# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_arcilator_runtime'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_runtime'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_verilator_runtime'

RSpec.describe 'AO486 CPU parity runtime across IR, Verilator, and Arcilator' do
  include AO486SpecSupport::HeadlessImportRunnerHelper

  def flatten_step_trace(trace)
    trace.flat_map do |event|
      Array(event.bytes).each_with_index.map { |byte, idx| [event.eip + idx, byte] }
    end
  end

  def normalize_memory(memory)
    memory.to_h.sort.to_h
  end

  def benchmark_result(program, runner)
    stats = runner.last_run_stats
    raise "missing headless-runner benchmark stats for #{runner.backend} #{program.name}" if stats.nil?

    stats.merge(program_name: program.name, backend_name: runner.backend)
  end

  def print_benchmark_summary(results)
    puts
    puts 'AO486 three-way complex-program throughput (cyc/s)'
    results.group_by { |result| result.fetch(:program_name) }.sort_by { |program_name, _| program_name.to_s }.each do |program_name, program_results|
      program_line = program_results.sort_by { |result| result.fetch(:backend_name).to_s }.map do |result|
        "#{result.fetch(:backend_name)}=#{format('%.2f', result.fetch(:cycles_per_second))}"
      end.join('  ')
      puts "  #{program_name}: #{program_line}"
    end
  end

  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def require_program_assembler!
    skip 'llvm-mc not available' unless HdlToolchain.which('llvm-mc')
    skip 'llvm-objcopy not available' unless HdlToolchain.which('llvm-objcopy')
  end

  def require_arcilator_toolchain!
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
    return if (HdlToolchain.which('clang') || HdlToolchain.which('llc')) && HdlToolchain.which('c++')
    return if HdlToolchain.which('lli') && HdlToolchain.which('llvm-link') && HdlToolchain.which('clang++')

    skip 'Neither clang/llc+c++ nor lli/llvm-link/clang++ is available for the Arcilator harness'
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::CpuImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: false
    ).run
  end

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.cpu_runtime_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

    backend
  end

  it 'matches the selected IR backend, Verilator, and Arcilator on the named parity programs for the parity package', timeout: 600 do
    require_import_tool!
    require_program_assembler!
    require_arcilator_toolchain!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_verilator_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_verilator_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)

        ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)

        Dir.mktmpdir('ao486_cpu_parity_verilator_build') do |build_dir|
          verilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :verilog,
            work_dir: File.join(build_dir, 'verilator')
          )
          arcilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :circt,
            work_dir: File.join(build_dir, 'arcilator')
          )

          RHDL::Examples::AO486::Import::CpuParityPrograms.all_programs.each do |program|
            program.load_into(ir_runtime)
            ir_trace = ir_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(verilator_runtime)
            verilator_trace = verilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(arcilator_runtime)
            arcilator_trace = arcilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            prefix = program.initial_fetch_pc_groups
            expect(ir_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(verilator_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(arcilator_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(verilator_trace).to eq(ir_trace), "program=#{program.name}"
            expect(arcilator_trace).to eq(ir_trace), "program=#{program.name}"
          end
        end
      end
    end
  end

  it 'matches the selected IR backend, Verilator, and Arcilator on the current write-trace EIP+bytes sequence for reset_smoke', timeout: 600 do
    require_import_tool!
    require_program_assembler!
    require_arcilator_toolchain!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_step_verilator_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_step_verilator_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        program = RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(:reset_smoke)

        ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)
        program.load_into(ir_runtime)
        ir_trace = ir_runtime.run(max_cycles: program.max_cycles).map { |event| [event.eip, event.bytes] }
        expect(ir_trace).not_to be_empty

        Dir.mktmpdir('ao486_cpu_step_verilator_build') do |build_dir|
          verilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :verilog,
            work_dir: File.join(build_dir, 'verilator')
          )
          program.load_into(verilator_runtime)
          verilator_trace = verilator_runtime.run_step_trace(max_cycles: program.max_cycles).map { |event| [event.eip, event.bytes] }
          expect(verilator_trace).not_to be_empty

          arcilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :circt,
            work_dir: File.join(build_dir, 'arcilator')
          )
          program.load_into(arcilator_runtime)
          arcilator_trace = arcilator_runtime.run_step_trace(max_cycles: program.max_cycles).map { |event| [event.eip, event.bytes] }
          expect(arcilator_trace).not_to be_empty

          expect(verilator_trace).to eq(ir_trace)
          expect(arcilator_trace).to eq(ir_trace)
        end
      end
    end
  end

  it 'matches the selected IR backend, Verilator, and Arcilator on the flattened write-trace PC byte stream for the named parity programs', timeout: 600 do
    require_import_tool!
    require_program_assembler!
    require_arcilator_toolchain!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    parity_programs = RHDL::Examples::AO486::Import::CpuParityPrograms.all_programs

    Dir.mktmpdir('ao486_cpu_step_byte_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_step_byte_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)

        Dir.mktmpdir('ao486_cpu_step_byte_build') do |build_dir|
          verilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :verilog,
            work_dir: File.join(build_dir, 'verilator')
          )
          arcilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :circt,
            work_dir: File.join(build_dir, 'arcilator')
          )

          parity_programs.each do |program|
            program.load_into(ir_runtime)
            ir_trace = flatten_step_trace(ir_runtime.run(max_cycles: program.max_cycles))
            expect(ir_trace).not_to be_empty, "program=#{program.name}"

            program.load_into(verilator_runtime)
            verilator_trace = flatten_step_trace(verilator_runtime.run_step_trace(max_cycles: program.max_cycles))
            expect(verilator_trace).not_to be_empty, "program=#{program.name}"

            program.load_into(arcilator_runtime)
            arcilator_trace = flatten_step_trace(arcilator_runtime.run_step_trace(max_cycles: program.max_cycles))
            expect(arcilator_trace).not_to be_empty, "program=#{program.name}"

            expect(verilator_trace).to eq(ir_trace), "program=#{program.name}"
            expect(arcilator_trace).to eq(ir_trace), "program=#{program.name}"
          end
        end
      end
    end
  end

  it 'matches the selected IR backend, Verilator, and Arcilator on the final memory image for the compact benchmark set', timeout: 600, noisy_output: true do
    require_import_tool!
    require_program_assembler!
    require_arcilator_toolchain!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    benchmark_programs = RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs
    benchmark_results = []

    begin
      Dir.mktmpdir('ao486_cpu_memory_out') do |out_dir|
        Dir.mktmpdir('ao486_cpu_memory_ws') do |workspace|
          result = run_importer(out_dir: out_dir, workspace: workspace)
          cleaned_mlir = File.read(result.normalized_core_mlir_path)
          ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)

          Dir.mktmpdir('ao486_cpu_memory_build') do |build_dir|
            verilator_runtime = build_ao486_import_headless_runner(
              cleaned_mlir,
              mode: :verilog,
              work_dir: File.join(build_dir, 'verilator')
            )
            arcilator_runtime = build_ao486_import_headless_runner(
              cleaned_mlir,
              mode: :circt,
              work_dir: File.join(build_dir, 'arcilator')
            )

            benchmark_programs.each do |program|
              program.load_into(ir_runtime)
              ir_runtime.run(max_cycles: program.max_cycles)
              benchmark_results << benchmark_result(program, ir_runtime)
              ir_memory = normalize_memory(ir_runtime.memory)

              program.load_into(verilator_runtime)
              verilator_runtime.run_final_state(max_cycles: program.max_cycles)
              benchmark_results << benchmark_result(program, verilator_runtime)
              verilator_memory = normalize_memory(verilator_runtime.memory)

              program.load_into(arcilator_runtime)
              arcilator_runtime.run_final_state(max_cycles: program.max_cycles)
              benchmark_results << benchmark_result(program, arcilator_runtime)
              arcilator_memory = normalize_memory(arcilator_runtime.memory)

              expect(verilator_memory).to eq(ir_memory), "program=#{program.name}"
              expect(arcilator_memory).to eq(ir_memory), "program=#{program.name}"
            end
          end
        end
      end
    ensure
      print_benchmark_summary(benchmark_results) unless benchmark_results.empty?
    end
  end
end
