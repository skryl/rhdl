# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'fileutils'
require 'tempfile'

require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../lib/rhdl/cli/tasks/import_task'
require_relative './verilator_wrapper_support'

RSpec.describe 'GameBoy imported design behavioral parity on Verilator', slow: true do
  include GameboyImportVerilatorWrapperSupport

  MAX_CYCLES = 100_000
  TRACE_COMPARE_LIMIT = 128
  DMG_BOOT_ROM_PATH = File.expand_path('../../../../examples/gameboy/software/roms/dmg_boot.bin', __dir__)
  VERILATOR_WARN_FLAGS = %w[
    -Wno-fatal
    -Wno-ASCRANGE
    -Wno-MULTIDRIVEN
    -Wno-PINMISSING
    -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC
    -Wno-UNOPTFLAT
    -Wno-CASEINCOMPLETE
  ].freeze

  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def export_tool
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL
    return tool if HdlToolchain.which(tool)

    nil
  end

  def require_export_tool!
    skip "#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL} not available for MLIR export" unless export_tool
  end

  def require_boot_rom!
    skip "DMG boot ROM not available: #{DMG_BOOT_ROM_PATH}" unless File.file?(DMG_BOOT_ROM_PATH)
    DMG_BOOT_ROM_PATH
  end

  def run_cmd!(cmd, chdir: nil)
    Tempfile.create('gameboy_import_stdout') do |stdout_file|
      Tempfile.create('gameboy_import_stderr') do |stderr_file|
        options = { out: stdout_file, err: stderr_file }
        options[:chdir] = chdir if chdir
        ok = system(*cmd, **options)
        return nil if ok

        stdout_file.rewind
        stderr_file.rewind
        detail = [stdout_file.read, stderr_file.read].join("\n").lines.first(120).join
        raise "Command failed: #{cmd.join(' ')}\n#{detail}"
      end
    end
  end

  def run_capture_cmd!(cmd, chdir: nil)
    stdout, stderr, status =
      if chdir
        Open3.capture3(*cmd, chdir: chdir)
      else
        Open3.capture3(*cmd)
      end
    return stdout if status.success?

    detail = [stdout, stderr].join("\n").lines.first(120).join
    raise "Command failed: #{cmd.join(' ')}\n#{detail}"
  end

  def diagnostic_summary(result)
    return '' unless result.respond_to?(:diagnostics)

    Array(result.diagnostics).map do |diag|
      if diag.respond_to?(:severity) && diag.respond_to?(:message)
        "[#{diag.severity}]#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
      else
        diag.to_s
      end
    end.join("\n")
  end

  def write_verilator_trace_harness(path)
    source = <<~CPP
      #include "Vgameboy.h"
      #include "verilated.h"
      #include <cstdint>
      #include <cstdio>
      #include <cstdlib>
      #include <fstream>
      #include <iterator>
      #include <vector>

      static std::vector<uint8_t> load_rom(const char* path) {
        std::ifstream in(path, std::ios::binary);
        if (!in) return std::vector<uint8_t>(1 << 16, 0);
        std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        if (bytes.empty()) bytes.resize(1 << 16, 0);
        if (bytes.size() < (1 << 16)) bytes.resize(1 << 16, 0);
        return bytes;
      }

      static uint8_t rom_read(const std::vector<uint8_t>& rom, uint16_t addr) {
        return rom[addr % rom.size()];
      }

      int main(int argc, char** argv) {
        Verilated::commandArgs(argc, argv);
        const char* rom_path = (argc > 1) ? argv[1] : "";
        const char* boot_rom_path = (argc > 2) ? argv[2] : "";
        int max_cycles = (argc > 3) ? std::atoi(argv[3]) : #{MAX_CYCLES};

        Vgameboy dut;
        auto rom = load_rom(rom_path);
        auto boot_rom = load_rom(boot_rom_path);

        auto tick_clock = [&]() {
          static uint32_t ce_phase = 0;
          dut.ce = (ce_phase == 0) ? 1 : 0;
          dut.ce_n = (ce_phase == 4) ? 1 : 0;
          dut.ce_2x = ((ce_phase & 0x3) == 0) ? 1 : 0;
          uint8_t boot_addr = dut.boot_rom_addr & 0xFF;
          dut.boot_rom_do = boot_rom[boot_addr];
          dut.clk_sys = 0;
          dut.eval();

          if (dut.cart_rd) {
            uint16_t addr =
              (static_cast<uint16_t>(dut.ext_bus_a15 & 0x1) << 15) |
              static_cast<uint16_t>(dut.ext_bus_addr & 0x7FFF);
            dut.cart_do = rom_read(rom, addr);
          }

          dut.eval();
          dut.clk_sys = 1;
          dut.eval();
          ce_phase = (ce_phase + 1) & 0x7;
        };

        auto run_machine_cycle = [&]() {
          for (int i = 0; i < 4; ++i) tick_clock();
        };

        dut.joystick = 0xFF;
        dut.is_gbc = 0;
        dut.is_sgb = 0;
        dut.boot_rom_do = 0;
        dut.reset = 1;
        for (int i = 0; i < 10; ++i) tick_clock();
        dut.reset = 0;
        for (int i = 0; i < 100; ++i) tick_clock();

        uint16_t last_addr = 0xFFFF;
        for (int i = 0; i < max_cycles; ++i) {
          run_machine_cycle();
          if (!dut.cart_rd) continue;

          uint16_t addr =
            (static_cast<uint16_t>(dut.ext_bus_a15 & 0x1) << 15) |
            static_cast<uint16_t>(dut.ext_bus_addr & 0x7FFF);
          if (addr == last_addr) continue;
          uint8_t opcode = rom_read(rom, addr);
          std::printf("%u,%u\\n", static_cast<unsigned>(addr), static_cast<unsigned>(opcode));
          last_addr = addr;
        }

        return 0;
      }
    CPP

    File.write(path, source)
  end

  def pack_trace_event(pc, opcode)
    ((pc.to_i & 0xFFFF_FFFF) << 8) | (opcode.to_i & 0xFF)
  end

  def unpack_trace_event(event)
    value = event.to_i
    [value >> 8, value & 0xFF]
  end

  def parse_trace(text)
    text.lines.filter_map do |line|
      match = line.strip.match(/\A(\d+),(\d+)\z/)
      next unless match

      pack_trace_event(match[1].to_i, match[2].to_i)
    end
  end

  def collect_verilator_trace(verilog_entry:, rom_path:, scratch_dir:)
    FileUtils.mkdir_p(scratch_dir)
    build_dir = File.join(scratch_dir, 'verilator_obj')
    wrapper = File.join(scratch_dir, 'gameboy.v')
    harness = File.join(scratch_dir, 'trace_main.cpp')
    profile = gb_wrapper_profile(verilog_entry)
    write_gameboy_wrapper(wrapper, profile: profile)
    write_verilator_trace_harness(harness)

    run_cmd!([
      'verilator',
      '--cc',
      wrapper,
      verilog_entry,
      '--top-module', gameboy_wrapper_top_module,
      '--Mdir', build_dir,
      '--public-flat-rw',
      *VERILATOR_WARN_FLAGS,
      '--exe',
      harness
    ])
    run_cmd!(['make', '-C', build_dir, '-f', 'Vgameboy.mk', 'Vgameboy'])

    parse_trace(run_capture_cmd!([File.join(build_dir, 'Vgameboy'), rom_path, require_boot_rom!, MAX_CYCLES.to_s]))
  end

  def convert_mlir_to_verilog(mlir_source, base_dir:, stem:)
    FileUtils.mkdir_p(base_dir)
    mlir_path = File.join(base_dir, "#{stem}.mlir")
    verilog_path = File.join(base_dir, "#{stem}.v")
    File.write(mlir_path, mlir_source)
    tool = export_tool

    result = RHDL::Codegen::CIRCT::Tooling.circt_mlir_to_verilog(
      mlir_path: mlir_path,
      out_path: verilog_path,
      tool: tool
    )
    expect(result[:success]).to be(true), "CIRCT->Verilog failed:\n#{result[:command]}\n#{result[:stderr]}"
    verilog_path
  end

  def overlay_verilog_for_verilator!(verilog_path:, pure_verilog_root:)
    task = RHDL::CLI::Tasks::ImportTask.new({})
    task.send(
      :overlay_generated_memory_modules!,
      normalized_verilog_path: verilog_path,
      pure_verilog_root: pure_verilog_root
    )
  end

  def export_raised_rhdl_verilog(source_mlir, scratch_dir:, pure_verilog_root:)
    raise_result = RHDL::Codegen.raise_circt_components(source_mlir, namespace: Module.new, top: 'gb')
    expect(raise_result.success?).to be(true), diagnostic_summary(raise_result)

    roundtrip_mlir = raise_result.components.keys.sort.map do |module_name|
      raise_result.components.fetch(module_name).to_ir(top_name: module_name)
    end.join("\n\n")
    verilog_path = convert_mlir_to_verilog(roundtrip_mlir, base_dir: scratch_dir, stem: 'raised_roundtrip')
    overlay_verilog_for_verilator!(verilog_path: verilog_path, pure_verilog_root: pure_verilog_root)
    verilog_path
  end

  def align_trace_prefix(lhs, rhs)
    a = Array(lhs)
    b = Array(rhs)
    return [a, b] if a.empty? || b.empty?

    first_match = nil
    a.each_with_index do |event_a, idx_a|
      idx_b = b.index(event_a)
      next unless idx_b

      first_match = [idx_a, idx_b]
      break
    end

    return [a, b] unless first_match

    [a.drop(first_match[0]), b.drop(first_match[1])]
  end

  def compare_trace_prefix(lhs, rhs, limit:)
    aligned_lhs, aligned_rhs = align_trace_prefix(lhs, rhs)
    compare_len = [aligned_lhs.length, aligned_rhs.length, limit].min
    return { compare_len: compare_len, mismatch: "trace shorter than #{limit} events after alignment" } if compare_len < limit

    compare_len.times do |idx|
      lhs_event = aligned_lhs[idx]
      rhs_event = aligned_rhs[idx]
      next if lhs_event == rhs_event

      return {
        compare_len: compare_len,
        mismatch: "index=#{idx} lhs=#{unpack_trace_event(lhs_event).inspect} rhs=#{unpack_trace_event(rhs_event).inspect}"
      }
    end

    { compare_len: compare_len, mismatch: nil }
  end

  def trace_sample(trace, limit: 12)
    Array(trace).first(limit).map { |event| unpack_trace_event(event) }
  end

  def expect_trace_match!(lhs_name:, lhs_trace:, rhs_name:, rhs_trace:)
    compare = compare_trace_prefix(lhs_trace, rhs_trace, limit: TRACE_COMPARE_LIMIT)
    return if compare[:mismatch].nil?

    raise RSpec::Expectations::ExpectationNotMetError,
          "Verilator parity mismatch between #{lhs_name} and #{rhs_name}:\n" \
          "  - compared events: #{compare[:compare_len]}\n" \
          "  - mismatch: #{compare[:mismatch]}\n" \
          "  - #{lhs_name} sample: #{trace_sample(lhs_trace).inspect}\n" \
          "  - #{rhs_name} sample: #{trace_sample(rhs_trace).inspect}"
  end

  it 'matches staged source Verilog, normalized imported Verilog, and Verilog regenerated from raised RHDL on Verilator', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_tool!('verilator')
    require_tool!('c++')
    require_export_tool!
    require_boot_rom!

    Dir.mktmpdir('gameboy_import_parity_out') do |out_dir|
      Dir.mktmpdir('gameboy_import_parity_ws') do |workspace|
        Dir.mktmpdir('gameboy_import_parity_run') do |scratch|
          rom_path = File.join(scratch, 'demo.gb')
          File.binwrite(rom_path, RHDL::Examples::GameBoy::Tasks::RunTask.create_demo_rom)

          importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            emit_runtime_json: false,
            strict: true,
            progress: ->(_msg) {}
          )
          import_result = importer.run
          expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")
          report = JSON.parse(File.read(import_result.report_path))
          mixed = report.fetch('mixed_import')
          pure_verilog_entry = mixed.fetch('pure_verilog_entry_path')
          pure_verilog_root = mixed.fetch('pure_verilog_root')
          normalized_verilog = mixed.fetch('normalized_verilog_path')
          source_mlir = File.read(import_result.mlir_path)
          expect(File.file?(pure_verilog_entry)).to be(true)
          expect(File.file?(normalized_verilog)).to be(true)
          raised_rhdl_verilog = export_raised_rhdl_verilog(
            source_mlir,
            scratch_dir: File.join(scratch, 'raised_rhdl'),
            pure_verilog_root: pure_verilog_root
          )
          expect(File.file?(raised_rhdl_verilog)).to be(true)

          reference_trace = collect_verilator_trace(
            verilog_entry: pure_verilog_entry,
            rom_path: rom_path,
            scratch_dir: File.join(scratch, 'reference')
          )
          normalized_trace = collect_verilator_trace(
            verilog_entry: normalized_verilog,
            rom_path: rom_path,
            scratch_dir: File.join(scratch, 'normalized')
          )
          raised_rhdl_trace = collect_verilator_trace(
            verilog_entry: raised_rhdl_verilog,
            rom_path: rom_path,
            scratch_dir: File.join(scratch, 'raised_rhdl_verilator')
          )

          expect(reference_trace.length).to be >= TRACE_COMPARE_LIMIT
          expect(normalized_trace.length).to be >= TRACE_COMPARE_LIMIT
          expect(raised_rhdl_trace.length).to be >= TRACE_COMPARE_LIMIT

          expect_trace_match!(
            lhs_name: 'staged source',
            lhs_trace: reference_trace,
            rhs_name: 'normalized import',
            rhs_trace: normalized_trace
          )
          expect_trace_match!(
            lhs_name: 'staged source',
            lhs_trace: reference_trace,
            rhs_name: 'raised RHDL roundtrip',
            rhs_trace: raised_rhdl_trace
          )
          expect_trace_match!(
            lhs_name: 'normalized import',
            lhs_trace: normalized_trace,
            rhs_name: 'raised RHDL roundtrip',
            rhs_trace: raised_rhdl_trace
          )
        end
      end
    end
  end
end
