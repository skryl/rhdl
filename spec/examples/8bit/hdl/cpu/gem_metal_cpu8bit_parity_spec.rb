# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require_relative '../../../../../examples/8bit/hdl/cpu/cpu'

RSpec.describe '8-bit CPU GEM Metal parity (Yosys -> GEM)', timeout: 300 do
  def command_available?(tool)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, tool))
    end
  end

  def run_cmd!(cmd, chdir:, log_path:, step:)
    out, status = Open3.capture2e(*cmd, chdir: chdir)
    File.write(log_path, out)
    expect(status.success?).to be(true), "#{step} failed (exit #{status.exitstatus}). Log: #{log_path}"
    out
  end

  def write_input_vcd(path, cycles:)
    cycles = [cycles.to_i, 1].max
    time = 0
    rst = 1
    clk = 0

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
      f.puts '1"'
      f.puts 'b00000000 #'
      f.puts '$end'

      cycles.times do |i|
        time += 1
        f.puts "##{time}"
        f.puts '1!'

        if i.zero?
          time += 1
          f.puts "##{time}"
          f.puts '0!'
          rst = 0
          f.puts "#{rst}\""
          next
        end

        time += 1
        f.puts "##{time}"
        f.puts '0!'
      end
    end
  end

  it 'runs GEM Metal parity checks on the same Yosys path as gem_metal_cpu8bit' do
    skip 'cargo not found in PATH' unless command_available?('cargo')
    skip 'yosys not found in PATH' unless command_available?('yosys')

    project_root = File.expand_path('../../../../../', __dir__)
    gem_root = File.join(project_root, 'external', 'GEM')
    skip "external GEM repo not found at #{gem_root}" unless Dir.exist?(gem_root)

    top_module = ENV.fetch('RHDL_GEM_METAL_CPU8BIT_TOP', 'cpu8bit')
    build_dir = File.expand_path(
      ENV.fetch('RHDL_GEM_METAL_CPU8BIT_BUILD_DIR', File.join(project_root, 'examples/8bit/.gem_metal_cpu8bit'))
    )
    FileUtils.mkdir_p(build_dir)

    rtl_path = File.join(build_dir, 'cpu8bit_rtl.v')
    yosys_script_path = File.join(build_dir, 'cpu8bit_gem.ys')
    yosys_log_path = File.join(build_dir, 'cpu8bit_yosys.log')
    cut_map_log_path = File.join(build_dir, 'cpu8bit_cut_map.log')
    metal_dummy_log_path = File.join(build_dir, 'cpu8bit_metal_dummy.log')
    metal_parity_log_path = File.join(build_dir, 'cpu8bit_metal_parity.log')

    netlist_path = File.expand_path(
      ENV.fetch('RHDL_GEM_METAL_CPU8BIT_NETLIST', File.join(build_dir, 'cpu8bit_gatelevel.gv'))
    )
    gemparts_path = File.expand_path(
      ENV.fetch('RHDL_GEM_METAL_CPU8BIT_GEMPARTS', File.join(build_dir, 'cpu8bit.gemparts'))
    )

    level_split = ENV.fetch('RHDL_GEM_METAL_CPU8BIT_LEVEL_SPLIT', '').strip
    max_stage_degrad = ENV.fetch('RHDL_GEM_METAL_CPU8BIT_MAX_STAGE_DEGRAD', '').strip

    aigpdk_nomem_lib = File.join(gem_root, 'aigpdk', 'aigpdk_nomem.lib')
    skip "missing AIGPDK library at #{aigpdk_nomem_lib}" unless File.exist?(aigpdk_nomem_lib)

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

      run_cmd!(
        ['yosys', '-q', '-s', yosys_script_path],
        chdir: project_root,
        log_path: yosys_log_path,
        step: 'yosys synthesis'
      )
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

      run_cmd!(
        cut_map_cmd,
        chdir: gem_root,
        log_path: cut_map_log_path,
        step: 'cut_map_interactive'
      )
    end

    expect(File.exist?(netlist_path)).to be(true), "missing netlist at #{netlist_path}"
    expect(File.exist?(gemparts_path)).to be(true), "missing gemparts at #{gemparts_path}"

    # Run the same benchmark path used by gem_metal_cpu8bit.
    dummy_out = run_cmd!(
      [
        'cargo', 'run', '--release', '--features', 'metal', '--bin', 'metal_dummy_test', '--',
        netlist_path, gemparts_path, '5', '256'
      ],
      chdir: gem_root,
      log_path: metal_dummy_log_path,
      step: 'metal_dummy_test'
    )
    expect(dummy_out).to include('metal_dummy_test: logical_dispatches=')

    # Parity check on the same netlist/partitions (GPU path must match GEM CPU execution).
    input_vcd_path = File.join(build_dir, 'cpu8bit_gem_input.vcd')
    output_vcd_path = File.join(build_dir, 'cpu8bit_gem_output.vcd')
    write_input_vcd(input_vcd_path, cycles: 64)

    parity_out = run_cmd!(
      [
        'cargo', 'run', '--release', '--features', 'metal', '--bin', 'metal_test', '--',
        netlist_path, gemparts_path, input_vcd_path, output_vcd_path, '5',
        '--top-module', top_module,
        '--input-vcd-scope', top_module,
        '--check-with-cpu',
        '--max-cycles', '64'
      ],
      chdir: gem_root,
      log_path: metal_parity_log_path,
      step: 'metal_test parity'
    )

    expect(parity_out).to include('sanity test passed!')
    expect(File.exist?(output_vcd_path)).to be(true)
    expect(File.size(output_vcd_path)).to be > 0
  end
end
