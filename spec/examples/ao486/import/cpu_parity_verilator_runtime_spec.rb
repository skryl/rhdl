# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_runtime'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_verilator_runtime'

RSpec.describe RHDL::Examples::AO486::Import::CpuParityVerilatorRuntime do
  def flatten_step_trace(trace)
    trace.flat_map do |event|
      Array(event.bytes).each_with_index.map { |byte, idx| [event.eip + idx, byte] }
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

  it 'matches the selected IR backend on the named parity programs for the parity package', timeout: 600 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_verilator_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_verilator_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)

        ir_runtime = RHDL::Examples::AO486::Import::CpuParityRuntime.build_from_cleaned_mlir(cleaned_mlir, backend: backend)

        Dir.mktmpdir('ao486_cpu_parity_verilator_build') do |build_dir|
          verilator_runtime = described_class.build_from_cleaned_mlir(cleaned_mlir, work_dir: build_dir)

          RHDL::Examples::AO486::Import::CpuParityPrograms.all_programs.each do |program|
            program.load_into(ir_runtime)
            ir_trace = ir_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(verilator_runtime)
            verilator_trace = verilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            prefix = program.initial_fetch_pc_groups
            expect(ir_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(verilator_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(verilator_trace).to eq(ir_trace), "program=#{program.name}"
          end
        end
      end
    end
  end

  it 'matches the selected IR backend on the current write-trace EIP+bytes sequence for reset_smoke', timeout: 600 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_step_verilator_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_step_verilator_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        program = RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(:reset_smoke)

        ir_runtime = RHDL::Examples::AO486::Import::CpuParityRuntime.build_from_cleaned_mlir(cleaned_mlir, backend: backend)
        program.load_into(ir_runtime)
        ir_trace = ir_runtime.run(max_cycles: program.max_cycles).map { |event| [event.eip, event.bytes] }
        expect(ir_trace).not_to be_empty

        Dir.mktmpdir('ao486_cpu_step_verilator_build') do |build_dir|
          verilator_runtime = described_class.build_from_cleaned_mlir(cleaned_mlir, work_dir: build_dir)
          program.load_into(verilator_runtime)
          verilator_trace = verilator_runtime.run_step_trace(max_cycles: program.max_cycles).map { |event| [event.eip, event.bytes] }
          expect(verilator_trace).not_to be_empty

          expect(verilator_trace).to eq(ir_trace)
        end
      end
    end
  end

  it 'matches the selected IR backend on the flattened write-trace PC byte stream for the currently stable parity programs', timeout: 600 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    stable_programs = %i[reset_smoke prime_sieve game_of_life].map do |name|
      RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(name)
    end

    Dir.mktmpdir('ao486_cpu_step_byte_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_step_byte_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        ir_runtime = RHDL::Examples::AO486::Import::CpuParityRuntime.build_from_cleaned_mlir(cleaned_mlir, backend: backend)

        Dir.mktmpdir('ao486_cpu_step_byte_build') do |build_dir|
          verilator_runtime = described_class.build_from_cleaned_mlir(cleaned_mlir, work_dir: build_dir)

          stable_programs.each do |program|
            program.load_into(ir_runtime)
            ir_trace = flatten_step_trace(ir_runtime.run(max_cycles: program.max_cycles))
            expect(ir_trace).not_to be_empty, "program=#{program.name}"

            program.load_into(verilator_runtime)
            verilator_trace = flatten_step_trace(verilator_runtime.run_step_trace(max_cycles: program.max_cycles))
            expect(verilator_trace).not_to be_empty, "program=#{program.name}"

            expect(verilator_trace).to eq(ir_trace), "program=#{program.name}"
          end
        end
      end
    end
  end

end
