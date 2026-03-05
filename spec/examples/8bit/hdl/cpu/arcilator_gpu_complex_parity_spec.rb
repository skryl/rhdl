# frozen_string_literal: true

require 'spec_helper'
require 'support/cpu_assembler'

RSpec.describe '8-bit CPU arcilator_gpu complex parity' do
  DISPLAY_START = 0x0800
  DISPLAY_LEN = 80 * 24

  def build_harness(sim)
    RHDL::HDL::CPU::FastHarness.new(nil, sim: sim)
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

  def compare_snapshots(compiler:, gpu:, regions:, label:)
    expect(gpu.halted).to eq(compiler.halted), "halted mismatch at #{label}"
    expect(gpu.acc).to eq(compiler.acc), "acc mismatch at #{label}"
    expect(gpu.pc).to eq(compiler.pc), "pc mismatch at #{label}"
    expect(gpu.sp).to eq(compiler.sp), "sp mismatch at #{label}"
    expect(gpu.state).to eq(compiler.state), "state mismatch at #{label}"
    expect(gpu.zero_flag).to eq(compiler.zero_flag), "zero_flag mismatch at #{label}"

    regions.each do |region|
      compiler_sig = checksum_region(compiler.memory, region.fetch(:start), region.fetch(:length))
      gpu_sig = checksum_region(gpu.memory, region.fetch(:start), region.fetch(:length))
      expect(gpu_sig).to eq(compiler_sig),
        "memory checksum mismatch at #{label} for 0x#{region.fetch(:start).to_s(16)}+#{region.fetch(:length)}"
    end
  end

  def run_checkpoint_parity(program_bytes:, start_pc:, checkpoints:, regions:, batch_size: 4096)
    compiler = build_harness(:compile)
    gpu = build_harness(:arcilator_gpu)

    bytes = Array(program_bytes).dup
    if start_pc.to_i.nonzero?
      # arcilator_gpu path currently cannot poke internal pc register directly
      # because arcilator state JSON does not expose that register by default.
      # Use an explicit reset-time trampoline so both backends start identically.
      bytes[0, 3] = [0xF9, ((start_pc >> 8) & 0xFF), (start_pc & 0xFF)] # JMP_LONG start_pc
      start_pc = 0
    end

    [compiler, gpu].each do |harness|
      harness.memory.load(bytes, 0)
      harness.pc = start_pc
    end

    last = 0
    checkpoints.each do |checkpoint|
      step = checkpoint - last
      raise ArgumentError, "checkpoints must be increasing (#{checkpoints.inspect})" if step <= 0

      compiler_ran = compiler.run_cycles(step, batch_size: batch_size)
      gpu_ran = gpu.run_cycles(step, batch_size: batch_size)
      expect(gpu_ran).to eq(compiler_ran), "cycle progress mismatch at checkpoint #{checkpoint}"

      compare_snapshots(
        compiler: compiler,
        gpu: gpu,
        regions: regions,
        label: "#{checkpoint} cycles"
      )

      last = checkpoint
    end
  end

  it 'matches compiler backend on conway glider 80x24 checkpoints', timeout: 180 do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    gpu_status = RHDL::HDL::CPU::FastHarness.arcilator_gpu_status
    expect(gpu_status[:ready]).to be(true), "arcilator_gpu backend unavailable: #{gpu_status.inspect}"

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
  end

  it 'matches compiler backend on mandelbrot 80x24 checkpoints', timeout: 180 do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    gpu_status = RHDL::HDL::CPU::FastHarness.arcilator_gpu_status
    expect(gpu_status[:ready]).to be(true), "arcilator_gpu backend unavailable: #{gpu_status.inspect}"

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
  end

  it 'matches compiler backend on long-running arithmetic loop checkpoints', timeout: 120 do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    gpu_status = RHDL::HDL::CPU::FastHarness.arcilator_gpu_status
    expect(gpu_status[:ready]).to be(true), "arcilator_gpu backend unavailable: #{gpu_status.inspect}"

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
  end
end
