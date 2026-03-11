# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'

RSpec.describe RHDL::Examples::AO486::IrRunner do
  include AO486SpecSupport::HeadlessImportRunnerHelper

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

  it 'drives deterministic reset-vector PC byte groups on the parity package', timeout: 240 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)
        reset_program = RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(:reset_smoke)

        reset_program.load_into(runtime)
        runtime.reset

        fetched = runtime.run_fetch_pc_groups(max_cycles: 24).first(3).map do |event|
          [event.pc, event.bytes]
        end

        expect(fetched).to eq(
          [
            [0xFFF0, [0x31, 0xC0, 0x40, 0x31]],
            [0xFFF4, [0xDB, 0x43, 0xF4, 0x00]],
            [0xFFF8, [0x00, 0x00, 0x00, 0x00]]
          ]
        )
      end
    end
  end

  it 'keeps an accepted fetch word alive long enough for decode_regs to latch it on the selected IR backend', timeout: 240 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    source = <<~ASM
      .intel_syntax noprefix
      .code16

      mov ax, 0x1234
      hlt
    ASM

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)
        bytes = RHDL::Examples::AO486::Import::CpuParityPrograms.assemble(source, label: 'decode_regs_latch_probe')

        runtime.load_bytes(RHDL::Examples::AO486::Import::CpuParityPrograms::RESET_VECTOR_PHYSICAL, bytes)
        runtime.reset

        saw_fetch_word = false
        saw_decoder_word = false

        8.times do |cycle|
          runtime.step(cycle)
          saw_fetch_word ||= (
            runtime.peek('pipeline_inst__decode_inst__decode_regs_inst__fetch_valid') == 4 &&
            runtime.peek('pipeline_inst__decode_inst__decode_regs_inst__fetch') == 0xF41234B8
          )
          saw_decoder_word ||= (runtime.peek('pipeline_inst__decode_inst__decode_regs_inst__decoder') != 0)
        end

        expect(saw_fetch_word).to be(true)
        expect(saw_decoder_word).to be(true)
      end
    end
  end

  it 'commits a simple aligned data write and exposes the success hlt on the selected IR backend', timeout: 240 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    source = <<~ASM
      .intel_syntax noprefix
      .code16

      xor ax, ax
      mov ds, ax
      mov ax, 0x1234
      mov [0x0200], ax
      hlt
    ASM

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)
        bytes = RHDL::Examples::AO486::Import::CpuParityPrograms.assemble(source, label: 'aligned_write_hlt_probe')

        runtime.load_bytes(RHDL::Examples::AO486::Import::CpuParityPrograms::RESET_VECTOR_PHYSICAL, bytes)
        runtime.reset

        saw_hlt = false

        128.times do |cycle|
          runtime.step(cycle)
          saw_hlt ||= (
            runtime.peek('trace_wr_hlt_in_progress') == 1 &&
            runtime.peek('trace_wr_ready') == 1
          )
          break if saw_hlt
        end

        expect(runtime.read_bytes(0x0200, 2)).to eq([0x34, 0x12])
        expect(saw_hlt).to be(true)
      end
    end
  end

  it 'matches the expected initial fetch windows for the benchmark parity programs on the selected IR backend', timeout: 240 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)

        RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each do |program|
          program.load_into(runtime)
          trace = runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

          expect(trace.first(program.initial_fetch_pc_groups.length)).to eq(program.initial_fetch_pc_groups), "program=#{program.name}"
        end
      end
    end
  end

  it 'matches the compact benchmark correctness prefixes on the selected IR backend', timeout: 240, slow: true do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)

        RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each do |program|
          program.load_into(runtime)
          trace = runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }
          expected = program.expected_fetch_pc_trace

          expect(trace.length).to be >= expected.length, "program=#{program.name}"
          expect(trace.first(expected.length)).to eq(expected), "program=#{program.name}"
        end
      end
    end
  end

  it 'reaches the expected final result registers and success hlt on the selected IR backend', timeout: 240, slow: true do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)

        RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each do |program|
          program.load_into(runtime)
          runtime.reset

          saw_hlt = false

          program.max_cycles.times do |cycle|
            runtime.step(cycle)
            saw_hlt ||= (
              runtime.peek('trace_wr_hlt_in_progress') == 1 &&
              runtime.peek('trace_wr_ready') == 1
            )
            break if saw_hlt
          end

          state = runtime.final_state_snapshot

          expect(saw_hlt).to be(true), "program=#{program.name}"
          expect(state.fetch('trace_wr_hlt_in_progress')).to eq(1), "program=#{program.name}"
          expect(state.fetch('trace_wr_ready')).to eq(1), "program=#{program.name}"
          program.expected_final_registers.each do |signal_name, expected_value|
            expect(state.fetch(signal_name)).to eq(expected_value), "program=#{program.name} signal=#{signal_name}"
          end
        end
      end
    end
  end

  it 'advances beyond the first aligned fetch window of a larger program on the selected IR backend', timeout: 240, slow: true do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(File.read(result.normalized_core_mlir_path), mode: :ir, sim: backend)
        program = RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(:prime_sieve)

        program.load_into(runtime)
        trace = runtime.run_fetch_pc_groups(max_cycles: 160)

        expect(trace.length).to be >= program.initial_fetch_pc_groups.length
        expect(trace.map(&:pc).max).to be >= 0x1000C
        expect(runtime.peek('memory_inst__prefetch_inst__limit')).to be > 0
        expect(runtime.peek('memory_inst__prefetch_inst__prefetch_address')).to be >= RHDL::Examples::AO486::Import::CpuParityPrograms::RESET_SEGMENT_BASE
        expect(runtime.peek('memory_inst__prefetch_inst__prefetch_address')).not_to eq(RHDL::Examples::AO486::Import::CpuParityPrograms::RESET_VECTOR_PHYSICAL)
      end
    end
  end

end
