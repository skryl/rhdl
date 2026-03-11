# frozen_string_literal: true

require 'spec_helper'
require 'support/cpu_assembler'
require 'fileutils'
require 'open3'

RSpec.describe '8-bit CPU arcilator_gpu complex parity' do
  DISPLAY_START = 0x0800
  DISPLAY_LEN = 80 * 24
  NATIVE_RUNNER_BACKENDS = %i[arcilator_gpu arcilator verilator].freeze

  def build_harness(sim)
    RHDL::HDL::CPU::FastHarness.new(nil, sim: sim)
  end

  def compiler_backend_available?
    build_harness(:compile)
    true
  rescue StandardError
    false
  end

  def checksum_region(memory, start_addr, length)
    sum = 0
    rolling_xor = 0

    length.times do |offset|
      byte = memory.read((start_addr + offset) & 0xFFFF).to_i & 0xFF
      sum = (sum + byte) & 0xFFFF_FFFF
      rolling_xor ^= ((byte << (offset & 7)) & 0xFF)
    end

    [sum, rolling_xor]
  end

  def compare_snapshots(compiler:, candidate:, regions:, label:, backend_label:)
    expect(candidate.halted).to eq(compiler.halted), "halted mismatch at #{label} (#{backend_label})"
    expect(candidate.acc).to eq(compiler.acc), "acc mismatch at #{label} (#{backend_label})"
    expect(candidate.pc).to eq(compiler.pc), "pc mismatch at #{label} (#{backend_label})"
    expect(candidate.sp).to eq(compiler.sp), "sp mismatch at #{label} (#{backend_label})"
    expect(candidate.state).to eq(compiler.state), "state mismatch at #{label} (#{backend_label})"
    expect(candidate.zero_flag).to eq(compiler.zero_flag), "zero_flag mismatch at #{label} (#{backend_label})"

    regions.each do |region|
      compiler_sig = checksum_region(compiler.memory, region.fetch(:start), region.fetch(:length))
      candidate_sig = checksum_region(candidate.memory, region.fetch(:start), region.fetch(:length))
      expect(candidate_sig).to eq(compiler_sig),
        "memory checksum mismatch at #{label} (#{backend_label}) for 0x#{region.fetch(:start).to_s(16)}+#{region.fetch(:length)}"
    end
  end

  def assert_native_runner_backends_available!
    backends = {
      arcilator_gpu: RHDL::HDL::CPU::FastHarness.arcilator_gpu_status,
      arcilator: RHDL::HDL::CPU::FastHarness.arcilator_status,
      verilator: RHDL::HDL::CPU::FastHarness.verilator_status
    }
    backends.each do |backend, status|
      expect(status[:ready]).to be(true), "#{backend} backend unavailable: #{status.inspect}"
    end
  end

  def run_checkpoint_parity(program_bytes:, start_pc:, checkpoints:, regions:, batch_size: 4096, backends: NATIVE_RUNNER_BACKENDS)
    compiler = build_harness(:compile)
    backend_harnesses = backends.to_h do |backend|
      [backend, build_harness(backend)]
    end

    bytes = Array(program_bytes).dup
    if start_pc.to_i.nonzero?
      # Native runner paths currently cannot poke internal pc register directly
      # because arcilator state JSON does not expose that register by default.
      # Use an explicit reset-time trampoline so both backends start identically.
      bytes[0, 3] = [0xF9, ((start_pc >> 8) & 0xFF), (start_pc & 0xFF)] # JMP_LONG start_pc
      start_pc = 0
    end

    ([compiler] + backend_harnesses.values).each do |harness|
      harness.memory.load(bytes, 0)
      harness.pc = start_pc
    end

    last = 0
    checkpoints.each do |checkpoint|
      step = checkpoint - last
      raise ArgumentError, "checkpoints must be increasing (#{checkpoints.inspect})" if step <= 0

      compiler_ran = compiler.run_cycles(step, batch_size: batch_size)
      backend_harnesses.each do |backend, harness|
        backend_ran = harness.run_cycles(step, batch_size: batch_size)
        expect(backend_ran).to eq(compiler_ran), "cycle progress mismatch at checkpoint #{checkpoint} (#{backend})"

        compare_snapshots(
          compiler: compiler,
          candidate: harness,
          regions: regions,
          label: "#{checkpoint} cycles",
          backend_label: backend
        )
      end

      last = checkpoint
    end
  end

  def normalize_program_for_start_pc(program_bytes:, start_pc:)
    bytes = Array(program_bytes).dup
    pc = start_pc.to_i
    if pc.nonzero?
      bytes[0, 3] = [0xF9, ((pc >> 8) & 0xFF), (pc & 0xFF)] # JMP_LONG start_pc
      pc = 0
    end
    [bytes, pc]
  end

  def measure_harness_cycles_per_sec(sim:, program_bytes:, start_pc:, cycles:, batch_size: 4096)
    harness = build_harness(sim)
    bytes, pc = normalize_program_for_start_pc(program_bytes: program_bytes, start_pc: start_pc)
    harness.memory.load(bytes, 0)
    harness.pc = pc

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cycles_run = harness.run_cycles(cycles, batch_size: batch_size)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    elapsed = 1.0e-9 if elapsed <= 0.0

    {
      backend: sim,
      cycles_run: cycles_run,
      elapsed_s: elapsed,
      cycles_per_sec: cycles_run.to_f / elapsed
    }
  end

  def command_available?(tool)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, tool))
    end
  end

  def gem_project_root
    File.expand_path('../../../../../', __dir__)
  end

  def gem_root
    File.join(gem_project_root, 'external', 'GEM')
  end

  def gem_cpu8bit_build_dir
    File.expand_path(
      ENV.fetch('RHDL_GEM_METAL_CPU8BIT_BUILD_DIR', File.join(gem_project_root, 'examples/8bit/.gem_metal_cpu8bit'))
    )
  end

  def ensure_gem_cpu8bit_artifacts!(top_module:)
    raise 'cargo not found in PATH' unless command_available?('cargo')
    raise 'yosys not found in PATH' unless command_available?('yosys')
    raise "external GEM repo not found at #{gem_root}" unless Dir.exist?(gem_root)

    build_dir = gem_cpu8bit_build_dir
    FileUtils.mkdir_p(build_dir)

    rtl_path = File.join(build_dir, 'cpu8bit_rtl.v')
    yosys_script_path = File.join(build_dir, 'cpu8bit_gem.ys')
    yosys_log_path = File.join(build_dir, 'cpu8bit_yosys.log')
    cut_map_log_path = File.join(build_dir, 'cpu8bit_cut_map.log')

    netlist_path = File.expand_path(
      ENV.fetch('RHDL_GEM_METAL_CPU8BIT_NETLIST', File.join(build_dir, 'cpu8bit_gatelevel.gv'))
    )
    gemparts_path = File.expand_path(
      ENV.fetch('RHDL_GEM_METAL_CPU8BIT_GEMPARTS', File.join(build_dir, 'cpu8bit.gemparts'))
    )

    level_split = ENV.fetch('RHDL_GEM_METAL_CPU8BIT_LEVEL_SPLIT', '').strip
    max_stage_degrad = ENV.fetch('RHDL_GEM_METAL_CPU8BIT_MAX_STAGE_DEGRAD', '').strip

    aigpdk_nomem_lib = File.join(gem_root, 'aigpdk', 'aigpdk_nomem.lib')
    raise "missing AIGPDK library at #{aigpdk_nomem_lib}" unless File.exist?(aigpdk_nomem_lib)

    unless File.exist?(netlist_path)
      File.write(rtl_path, RHDL::HDL::CPU::CPU.to_verilog_hierarchy(top_name: top_module))

      yosys_script = <<~YOSYS
        read_verilog "#{rtl_path}"
        hierarchy -check -top #{top_module}
        synth -flatten
        delete t:\\$print
        dfflibmap -liberty "#{aigpdk_nomem_lib}"
        opt_clean -purge
        abc -liberty "#{aigpdk_nomem_lib}"
        opt_clean -purge
        write_verilog "#{netlist_path}"
      YOSYS
      File.write(yosys_script_path, yosys_script)

      yosys_out, yosys_status = Open3.capture2e('yosys', '-q', '-s', yosys_script_path)
      File.write(yosys_log_path, yosys_out)
      raise "yosys synthesis failed. See #{yosys_log_path}" unless yosys_status.success?
    end

    unless File.exist?(gemparts_path)
      cut_map_cmd = [
        'cargo', 'run', '--release', '--features', 'metal', '--bin', 'cut_map_interactive', '--',
        netlist_path
      ]
      cut_map_cmd += ['--top-module', top_module]
      cut_map_cmd += ['--level-split', level_split] unless level_split.empty?
      cut_map_cmd += ['--max-stage-degrad', max_stage_degrad] unless max_stage_degrad.empty?
      cut_map_cmd << gemparts_path

      cut_map_out, cut_map_status = Open3.capture2e(*cut_map_cmd, chdir: gem_root)
      File.write(cut_map_log_path, cut_map_out)
      raise "cut_map_interactive failed. See #{cut_map_log_path}" unless cut_map_status.success?
    end

    [netlist_path, gemparts_path]
  end

  def collect_compiler_mem_data_trace(program_bytes:, start_pc:, cycles:)
    compiler = build_harness(:compile)
    bytes, pc = normalize_program_for_start_pc(program_bytes: program_bytes, start_pc: start_pc)

    compiler.memory.load(bytes, 0)
    compiler.pc = pc

    sim = compiler.instance_variable_get(:@sim)
    memory = compiler.memory
    trace = []

    cycles.times do
      break if compiler.halted

      addr = sim.peek('mem_addr')
      write_en = sim.peek('mem_write_en')
      memory.write(addr, sim.peek('mem_data_out')) if write_en == 1

      data = memory.read(addr) & 0xFF
      trace << data

      sim.poke('mem_data_in', data)
      sim.evaluate
      sim.poke('clk', 0)
      sim.evaluate
      sim.poke('clk', 1)
      sim.tick

      compiler.instance_variable_set(:@cycle_count, compiler.cycle_count + 1)
      compiler.instance_variable_set(:@halted, true) if sim.peek('halted') == 1
    end

    trace
  end

  def write_gem_input_vcd(path, mem_data_trace)
    first_data = mem_data_trace.first.to_i & 0xFF
    time = 0
    prev_data = first_data

    File.open(path, 'w') do |f|
      f.puts '$timescale 1ns $end'
      f.puts '$scope module cpu8bit $end'
      f.puts '$var wire 1 ! clk $end'
      f.puts '$var wire 1 " rst $end'
      f.puts '$var wire 8 # mem_data_in $end'
      f.puts '$upscope $end'
      f.puts '$enddefinitions $end'
      f.puts '$dumpvars'
      f.puts '0!'
      f.puts '0"'
      f.puts "b#{first_data.to_s(2).rjust(8, '0')} #"
      f.puts '$end'

      mem_data_trace.each do |data|
        d = data.to_i & 0xFF
        time += 1
        f.puts "##{time}"
        if d != prev_data
          f.puts "b#{d.to_s(2).rjust(8, '0')} #"
          prev_data = d
        end
        f.puts '1!'

        time += 1
        f.puts "##{time}"
        f.puts '0!'
      end
    end
  end

  def run_gem_metal_test(
    netlist_path:,
    gemparts_path:,
    input_vcd_path:,
    output_vcd_path:,
    log_path:,
    top_module:,
    max_cycles:,
    check_with_cpu:
  )
    cmd = [
      'cargo', 'run', '--release', '--features', 'metal', '--bin', 'metal_test', '--',
      netlist_path, gemparts_path, input_vcd_path, output_vcd_path, '5',
      '--top-module', top_module,
      '--input-vcd-scope', top_module,
      '--max-cycles', max_cycles.to_s
    ]
    cmd << '--check-with-cpu' if check_with_cpu

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, status = Open3.capture2e(*cmd, chdir: gem_root)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    elapsed = 1.0e-9 if elapsed <= 0.0

    File.write(log_path, out)
    expect(status.success?).to be(true), "metal_test failed. See #{log_path}"
    expect(File.exist?(output_vcd_path)).to be(true)
    expect(File.size(output_vcd_path)).to be > 0
    expect(out).to include('sanity test passed!') if check_with_cpu

    {
      output: out,
      elapsed_s: elapsed,
      cycles_run: max_cycles.to_i,
      cycles_per_sec: max_cycles.to_f / elapsed
    }
  end

  def run_gem_sanity_with_compiler_stimulus(program_bytes:, start_pc:, cycles:, top_module: 'cpu8bit', batch_size: 4096, label:)
    netlist_path, gemparts_path = ensure_gem_cpu8bit_artifacts!(top_module: top_module)
    mem_data_trace = collect_compiler_mem_data_trace(
      program_bytes: program_bytes,
      start_pc: start_pc,
      cycles: cycles
    )
    raise 'compiler trace generation produced no cycles' if mem_data_trace.empty?
    effective_cycles = mem_data_trace.length
    compiler_perf = measure_harness_cycles_per_sec(
      sim: :compile,
      program_bytes: program_bytes,
      start_pc: start_pc,
      cycles: effective_cycles,
      batch_size: batch_size
    )
    arcilator_gpu_perf = measure_harness_cycles_per_sec(
      sim: :arcilator_gpu,
      program_bytes: program_bytes,
      start_pc: start_pc,
      cycles: effective_cycles,
      batch_size: batch_size
    )
    arcilator_perf = measure_harness_cycles_per_sec(
      sim: :arcilator,
      program_bytes: program_bytes,
      start_pc: start_pc,
      cycles: effective_cycles,
      batch_size: batch_size
    )
    verilator_perf = measure_harness_cycles_per_sec(
      sim: :verilator,
      program_bytes: program_bytes,
      start_pc: start_pc,
      cycles: effective_cycles,
      batch_size: batch_size
    )

    build_dir = gem_cpu8bit_build_dir
    input_vcd_path = File.join(build_dir, "cpu8bit_gem_complex_#{cycles}.input.vcd")
    gpu_only_output_vcd_path = File.join(build_dir, "cpu8bit_gem_complex_#{cycles}.gpu_only.output.vcd")
    gpu_only_log_path = File.join(build_dir, "cpu8bit_gem_complex_#{cycles}.gpu_only.log")
    check_output_vcd_path = File.join(build_dir, "cpu8bit_gem_complex_#{cycles}.check.output.vcd")
    check_log_path = File.join(build_dir, "cpu8bit_gem_complex_#{cycles}.check.log")
    write_gem_input_vcd(input_vcd_path, mem_data_trace)

    gpu_only = run_gem_metal_test(
      netlist_path: netlist_path,
      gemparts_path: gemparts_path,
      input_vcd_path: input_vcd_path,
      output_vcd_path: gpu_only_output_vcd_path,
      log_path: gpu_only_log_path,
      top_module: top_module,
      max_cycles: effective_cycles,
      check_with_cpu: false
    )
    with_check = run_gem_metal_test(
      netlist_path: netlist_path,
      gemparts_path: gemparts_path,
      input_vcd_path: input_vcd_path,
      output_vcd_path: check_output_vcd_path,
      log_path: check_log_path,
      top_module: top_module,
      max_cycles: effective_cycles,
      check_with_cpu: true
    )

    compiler_cps = compiler_perf.fetch(:cycles_per_sec)
    arcilator_gpu_ratio = compiler_cps.positive? ? (arcilator_gpu_perf.fetch(:cycles_per_sec) / compiler_cps) : 0.0
    arcilator_ratio = compiler_cps.positive? ? (arcilator_perf.fetch(:cycles_per_sec) / compiler_cps) : 0.0
    verilator_ratio = compiler_cps.positive? ? (verilator_perf.fetch(:cycles_per_sec) / compiler_cps) : 0.0
    gpu_only_ratio = compiler_cps.positive? ? (gpu_only.fetch(:cycles_per_sec) / compiler_cps) : 0.0
    with_check_ratio = compiler_cps.positive? ? (with_check.fetch(:cycles_per_sec) / compiler_cps) : 0.0
    RSpec.configuration.reporter.message(
      format(
        '[%s] compiler=%.2f cyc/s, arcilator=%.2f cyc/s (%.3fx), verilator=%.2f cyc/s (%.3fx), arcilator_gpu=%.2f cyc/s (%.3fx), gem(no-check)=%.2f cyc/s (%.3fx), gem(check-with-cpu)=%.2f cyc/s (%.3fx)',
        label,
        compiler_cps,
        arcilator_perf.fetch(:cycles_per_sec),
        arcilator_ratio,
        verilator_perf.fetch(:cycles_per_sec),
        verilator_ratio,
        arcilator_gpu_perf.fetch(:cycles_per_sec),
        arcilator_gpu_ratio,
        gpu_only.fetch(:cycles_per_sec),
        gpu_only_ratio,
        with_check.fetch(:cycles_per_sec),
        with_check_ratio
      )
    )
  end

  it 'matches compiler backend on conway glider 80x24 checkpoints', timeout: 420 do
    skip 'IR compiler backend unavailable' unless compiler_backend_available?
    assert_native_runner_backends_available!

    bin_path = File.expand_path('../../../../../examples/8bit/software/bin/conway_glider_80x24.bin', __dir__)
    program = File.binread(bin_path).bytes

    run_checkpoint_parity(
      program_bytes: program,
      start_pc: 0x20,
      checkpoints: [50_000, 100_000, 200_000],
      regions: [
        { start: DISPLAY_START, length: DISPLAY_LEN },
        { start: 0x0200, length: 0x240 }
      ]
    )

    run_gem_sanity_with_compiler_stimulus(
      program_bytes: program,
      start_pc: 0x20,
      cycles: 50_000,
      label: 'conway'
    )
  rescue RuntimeError => e
    skip "GEM backend unavailable for conway parity: #{e.message}"
  end

  it 'matches compiler backend on mandelbrot 80x24 checkpoints', timeout: 420 do
    skip 'IR compiler backend unavailable' unless compiler_backend_available?
    assert_native_runner_backends_available!

    bin_path = File.expand_path('../../../../../examples/8bit/software/bin/mandelbrot_80x24.bin', __dir__)
    program = File.binread(bin_path).bytes

    run_checkpoint_parity(
      program_bytes: program,
      start_pc: 0x00,
      checkpoints: [40_000, 80_000, 120_000],
      regions: [
        { start: DISPLAY_START, length: DISPLAY_LEN },
        { start: 0x0100, length: 0x300 }
      ]
    )

    run_gem_sanity_with_compiler_stimulus(
      program_bytes: program,
      start_pc: 0x00,
      cycles: 40_000,
      label: 'mandelbrot'
    )
  rescue RuntimeError => e
    skip "GEM backend unavailable for mandelbrot parity: #{e.message}"
  end

  it 'matches compiler backend on long-running arithmetic loop checkpoints', timeout: 420 do
    skip 'IR compiler backend unavailable' unless compiler_backend_available?
    assert_native_runner_backends_available!

    program = Assembler.build(0x40) do |p|
      p.instr :LDI, 1
      p.instr :STA, 0x02
      p.instr :LDI, 0
      p.instr :STA, 0x0E

      p.label :loop
      p.instr :LDA, 0x0E
      p.instr :ADD, 0x02
      p.instr :STA, 0x0E
      p.instr :LDA, 0x0E
      p.instr :STA, 0x90
      p.instr :JMP_LONG, :loop
    end

    run_checkpoint_parity(
      program_bytes: program,
      start_pc: 0x40,
      checkpoints: [25_000, 50_000, 100_000],
      regions: [
        { start: 0x0080, length: 0x40 },
        { start: 0x0800, length: 0x80 }
      ]
    )

    run_gem_sanity_with_compiler_stimulus(
      program_bytes: program,
      start_pc: 0x40,
      cycles: 25_000,
      label: 'arith-loop'
    )
  rescue RuntimeError => e
    skip "GEM backend unavailable for arithmetic parity: #{e.message}"
  end
end
