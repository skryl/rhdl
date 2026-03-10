# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'fileutils'
require 'tempfile'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative '../../../../lib/rhdl/cli/tasks/import_task'

RSpec.describe 'GameBoy mixed import runtime parity (Verilator/Verilator/Verilator)', slow: true do
  MAX_CYCLES = 500_000
  VIDEO_PARITY_CYCLES = 100_000
  SCREEN_WIDTH = 160
  SCREEN_HEIGHT = 144
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
    root = RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT
    qip = RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH
    skip 'GameBoy reference tree not available' unless Dir.exist?(root)
    skip 'GameBoy files.qip not available' unless File.file?(qip)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def require_pop_rom!
    path = File.expand_path('../../../../examples/gameboy/software/roms/pop.gb', __dir__)
    skip "POP ROM not available: #{path}" unless File.file?(path)
    path
  end

  def export_tool
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL
    return tool if HdlToolchain.which(tool)

    nil
  end

  def require_export_tool!
    skip "#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL} not available for MLIR export" unless export_tool
  end

  def framebuffer_hash(framebuffer)
    hash = 0xcbf29ce484222325
    Array(framebuffer).flatten.each do |value|
      hash ^= (value.to_i & 0xFF)
      hash = (hash * 0x100000001b3) & 0xFFFF_FFFF_FFFF_FFFF
    end
    format('%016x', hash)
  end

  def framebuffer_nonzero_pixels(framebuffer)
    Array(framebuffer).sum { |row| Array(row).count { |pixel| pixel.to_i != 0 } }
  end

  def parse_video_snapshot(text)
    text.to_s.lines.reverse_each do |line|
      match = line.strip.match(/\AVIDEO_SNAPSHOT,(\d+),(\d+),(\d+),([0-9a-fA-F]+)\z/)
      next unless match

      return {
        cycles: match[1].to_i,
        frame_count: match[2].to_i,
        nonzero_pixels: match[3].to_i,
        hash: match[4].downcase
      }
    end
    nil
  end

  def first_video_mismatch(lhs, rhs)
    return 'missing lhs video snapshot' if lhs.nil?
    return 'missing rhs video snapshot' if rhs.nil?

    %i[cycles frame_count nonzero_pixels hash].each do |key|
      next if lhs[key] == rhs[key]

      return "#{key} mismatch lhs=#{lhs[key].inspect} rhs=#{rhs[key].inspect}"
    end

    nil
  end

  def record_trace_comparison!(summary_lines:, failures:, lhs_name:, lhs_trace:, rhs_name:, rhs_trace:)
    compare = compare_trace_prefix(lhs_trace, rhs_trace)
    if compare[:mismatch]
      failures << "#{lhs_name} vs #{rhs_name} mismatch: #{compare[:mismatch]}"
      summary_lines << "#{lhs_name} vs #{rhs_name}: mismatch (#{compare[:mismatch]})"
    else
      summary_lines << "#{lhs_name} vs #{rhs_name}: OK on first #{compare[:compare_len]} events"
    end
  end

  def record_video_comparison!(summary_lines:, failures:, lhs_name:, lhs_video:, rhs_name:, rhs_video:)
    mismatch = first_video_mismatch(lhs_video, rhs_video)
    if mismatch
      failures << "#{lhs_name} vs #{rhs_name} video mismatch: #{mismatch}"
      summary_lines << "#{lhs_name} vs #{rhs_name} video: mismatch (#{mismatch})"
    else
      summary_lines << "#{lhs_name} vs #{rhs_name} video: OK"
    end
  end

  def announce_parity_phase!(label)
    return unless ENV['RHDL_IMPORT_PARITY_PROGRESS'] == '1'

    warn("[gameboy/import/runtime_parity_3way_verilator] #{label}")
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

  def trim_ruby_heap!
    GC.start(full_mark: true, immediate_sweep: true)
    GC.compact if GC.respond_to?(:compact)
  end

  def write_verilator_trace_harness(path)
    source = <<~CPP
      #include "Vgb.h"
      #include "Vgb___024root.h"
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

      static uint64_t framebuffer_hash(const std::vector<uint8_t>& framebuffer) {
        uint64_t hash = 0xcbf29ce484222325ULL;
        for (uint8_t pixel : framebuffer) {
          hash ^= static_cast<uint64_t>(pixel);
          hash *= 0x100000001b3ULL;
        }
        return hash;
      }

      static uint32_t framebuffer_nonzero(const std::vector<uint8_t>& framebuffer) {
        uint32_t count = 0;
        for (uint8_t pixel : framebuffer) {
          if (pixel != 0) ++count;
        }
        return count;
      }

      int main(int argc, char** argv) {
        Verilated::commandArgs(argc, argv);
        const char* rom_path = (argc > 1) ? argv[1] : "";
        int max_cycles = (argc > 2) ? std::atoi(argv[2]) : #{MAX_CYCLES};

        Vgb dut;
        auto rom = load_rom(rom_path);
        std::vector<uint8_t> framebuffer(#{SCREEN_WIDTH} * #{SCREEN_HEIGHT}, 0);
        int lcd_x = 0;
        int lcd_y = 0;
        uint8_t prev_lcd_clkena = 0;
        uint8_t prev_lcd_vsync = 0;
        uint64_t frame_count = 0;
        bool video_emitted = false;

        auto capture_video = [&]() {
          uint8_t lcd_clkena = dut.lcd_clkena & 0x1;
          uint8_t lcd_vsync = dut.lcd_vsync & 0x1;
          uint8_t lcd_data = dut.lcd_data_gb & 0x3;

          if (lcd_clkena == 1 && prev_lcd_clkena == 0) {
            if (lcd_x < #{SCREEN_WIDTH} && lcd_y < #{SCREEN_HEIGHT}) {
              framebuffer[(lcd_y * #{SCREEN_WIDTH}) + lcd_x] = lcd_data;
            }
            lcd_x += 1;
            if (lcd_x >= #{SCREEN_WIDTH}) {
              lcd_x = 0;
              lcd_y += 1;
            }
          }

          if (lcd_vsync == 1 && prev_lcd_vsync == 0) {
            lcd_x = 0;
            lcd_y = 0;
            frame_count += 1;
          }

          prev_lcd_clkena = lcd_clkena;
          prev_lcd_vsync = lcd_vsync;
        };

        auto emit_video_snapshot = [&](int cycles_run) {
          std::printf(
            "VIDEO_SNAPSHOT,%d,%llu,%u,%016llx\\n",
            cycles_run,
            static_cast<unsigned long long>(frame_count),
            framebuffer_nonzero(framebuffer),
            static_cast<unsigned long long>(framebuffer_hash(framebuffer))
          );
        };

        auto tick_clock = [&]() {
          static uint32_t ce_phase = 0;
          dut.ce = (ce_phase == 0) ? 1 : 0;
          dut.ce_n = (ce_phase == 4) ? 1 : 0;
          dut.ce_2x = ((ce_phase & 0x3) == 0) ? 1 : 0;
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
          capture_video();
          ce_phase = (ce_phase + 1) & 0x7;
        };

        auto run_machine_cycle = [&]() {
          for (int i = 0; i < 4; ++i) tick_clock();
        };

        dut.joystick = 0xFF;
        dut.cart_oe = 1;
        dut.reset = 1;
        for (int i = 0; i < 10; ++i) tick_clock();
        dut.reset = 0;
        for (int i = 0; i < 100; ++i) tick_clock();

        uint16_t last_addr = 0xFFFF;
        for (int i = 0; i < max_cycles; ++i) {
          run_machine_cycle();
          if (!video_emitted && (i + 1) == #{VIDEO_PARITY_CYCLES}) {
            emit_video_snapshot(i + 1);
            video_emitted = true;
          }
          if (!dut.cart_rd) continue;

          uint16_t addr =
            (static_cast<uint16_t>(dut.ext_bus_a15 & 0x1) << 15) |
            static_cast<uint16_t>(dut.ext_bus_addr & 0x7FFF);
          if (addr == last_addr) continue;

          uint8_t opcode = rom_read(rom, addr);
          std::printf("%u,%u\\n", static_cast<unsigned>(addr), static_cast<unsigned>(opcode));
          last_addr = addr;
        }

        if (!video_emitted) emit_video_snapshot(max_cycles);

        return 0;
      }
    CPP

    File.write(path, source)
  end

  def parse_trace(text)
    text.lines.filter_map do |line|
      match = line.strip.match(/\A(\d+),(\d+)\z/)
      next unless match

      pack_trace_event(match[1].to_i, match[2].to_i)
    end
  end

  def pack_trace_event(pc, opcode)
    ((pc.to_i & 0xFFFF_FFFF) << 8) | (opcode.to_i & 0xFF)
  end

  def unpack_trace_event(event)
    value = event.to_i
    [value >> 8, value & 0xFF]
  end

  def trace_event_pc(event)
    event.to_i >> 8
  end

  def normalize_trace(trace)
    events = Array(trace)
    trimmed = events.drop_while { |event| trace_event_pc(event).zero? }
    trimmed.empty? ? events : trimmed
  end

  def align_trace_prefix_offsets(lhs, rhs)
    a = Array(lhs)
    b = Array(rhs)
    return [0, 0] if a.empty? || b.empty?

    rhs_indices = {}
    b.each_with_index { |event, idx| rhs_indices[event] ||= idx }

    a.each_with_index do |event_a, idx_a|
      idx_b = rhs_indices[event_a]
      return [idx_a, idx_b] unless idx_b.nil?
    end

    [0, 0]
  end

  def compare_trace_prefix(lhs, rhs)
    start_lhs, start_rhs = align_trace_prefix_offsets(lhs, rhs)
    compare_len = [
      Array(lhs).length - start_lhs,
      Array(rhs).length - start_rhs
    ].min
    mismatch = first_mismatch_with_offsets(lhs, rhs, start_lhs: start_lhs, start_rhs: start_rhs)
    {
      start_lhs: start_lhs,
      start_rhs: start_rhs,
      compare_len: compare_len,
      mismatch: mismatch
    }
  end

  def first_mismatch_with_offsets(lhs, rhs, start_lhs:, start_rhs:)
    limit = [
      lhs.length - start_lhs,
      rhs.length - start_rhs
    ].min
    limit.times do |idx|
      lhs_event = lhs[start_lhs + idx]
      rhs_event = rhs[start_rhs + idx]
      next if lhs_event == rhs_event

      return "index=#{idx} lhs=#{unpack_trace_event(lhs_event).inspect} rhs=#{unpack_trace_event(rhs_event).inspect}"
    end

    lhs_remaining = lhs.length - start_lhs
    rhs_remaining = rhs.length - start_rhs
    return nil if lhs_remaining == rhs_remaining

    "length mismatch lhs=#{lhs_remaining} rhs=#{rhs_remaining}"
  end

  def trace_sample(trace, start: 0, limit: 20)
    Array(trace).drop(start).first(limit).map { |event| unpack_trace_event(event) }
  end

  def collect_verilator_trace(verilog_entry:, rom_path:, scratch_dir:)
    FileUtils.mkdir_p(scratch_dir)
    build_dir = File.join(scratch_dir, 'verilator_obj')
    harness = File.join(scratch_dir, 'trace_main.cpp')
    write_verilator_trace_harness(harness)

    run_cmd!([
      'verilator',
      '--cc',
      verilog_entry,
      '--top-module', 'gb',
      '--Mdir', build_dir,
      '--public-flat-rw',
      *VERILATOR_WARN_FLAGS,
      '--exe',
      harness
    ])
    run_cmd!(['make', '-C', build_dir, '-f', 'Vgb.mk', 'Vgb'])

    output = run_capture_cmd!([File.join(build_dir, 'Vgb'), rom_path, MAX_CYCLES.to_s])
    {
      trace: normalize_trace(parse_trace(output)),
      video: parse_video_snapshot(output)
    }
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

  it 'matches PC/opcode progression and video snapshot across staged source, normalized import, and raised-RHDL Verilog', timeout: 3600 do
    require_reference_tree!
    %w[ghdl circt-verilog verilator c++].each { |tool| require_tool!(tool) }
    require_export_tool!
    pop_rom_path = require_pop_rom!

    Dir.mktmpdir('gameboy_runtime_parity_verilator_out') do |out_dir|
      Dir.mktmpdir('gameboy_runtime_parity_verilator_ws') do |workspace|
        Dir.mktmpdir('gameboy_runtime_parity_verilator_run') do |scratch|
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
          expect(File.file?(import_result.report_path)).to be(true)

          report = JSON.parse(File.read(import_result.report_path))
          mixed = report.fetch('mixed_import')
          pure_verilog_entry = mixed.fetch('pure_verilog_entry_path')
          normalized_verilog = mixed.fetch('normalized_verilog_path')
          pure_verilog_root = mixed.fetch('pure_verilog_root')
          source_mlir = File.read(import_result.mlir_path)
          raised_rhdl_verilog = export_raised_rhdl_verilog(
            source_mlir,
            scratch_dir: File.join(scratch, 'raised_rhdl'),
            pure_verilog_root: pure_verilog_root
          )

          expect(File.file?(pure_verilog_entry)).to be(true)
          expect(File.file?(normalized_verilog)).to be(true)
          expect(File.file?(raised_rhdl_verilog)).to be(true)

          summary_lines = []
          failures = []
          summary_lines << 'Backend order: Verilator(staged source) -> Verilator(normalized import) -> Verilator(raised RHDL)'
          summary_lines << "Staged source Verilog: #{pure_verilog_entry}"
          summary_lines << "Normalized imported Verilog: #{normalized_verilog}"
          summary_lines << "Raised-RHDL Verilog: #{raised_rhdl_verilog}"

          importer = nil
          import_result = nil
          report = nil
          mixed = nil
          source_mlir = nil
          trim_ruby_heap!

          announce_parity_phase!('collecting staged-source Verilator trace')
          staged = collect_verilator_trace(
            verilog_entry: pure_verilog_entry,
            rom_path: pop_rom_path,
            scratch_dir: File.join(scratch, 'staged_source')
          )
          staged_trace = staged.fetch(:trace)
          staged_video = staged.fetch(:video)
          staged = nil
          if staged_trace.empty?
            failures << 'Staged-source Verilator trace is empty'
            summary_lines << 'Staged-source Verilator: empty trace'
          else
            summary_lines << "Staged-source Verilator: #{staged_trace.length} events"
          end
          if staged_video
            summary_lines << "Staged-source video@#{staged_video[:cycles]}: frames=#{staged_video[:frame_count]} nonzero=#{staged_video[:nonzero_pixels]} hash=#{staged_video[:hash]}"
          else
            failures << 'Staged-source Verilator video snapshot is missing'
            summary_lines << 'Staged-source video: missing snapshot'
          end

          trim_ruby_heap!

          announce_parity_phase!('collecting normalized-import Verilator trace')
          normalized = collect_verilator_trace(
            verilog_entry: normalized_verilog,
            rom_path: pop_rom_path,
            scratch_dir: File.join(scratch, 'normalized_import')
          )
          normalized_trace = normalized.fetch(:trace)
          normalized_video = normalized.fetch(:video)
          normalized = nil
          if normalized_trace.empty?
            failures << 'Normalized-import Verilator trace is empty'
            summary_lines << 'Normalized-import Verilator: empty trace'
          else
            summary_lines << "Normalized-import Verilator: #{normalized_trace.length} events"
          end
          if normalized_video
            summary_lines << "Normalized-import video@#{normalized_video[:cycles]}: frames=#{normalized_video[:frame_count]} nonzero=#{normalized_video[:nonzero_pixels]} hash=#{normalized_video[:hash]}"
          else
            failures << 'Normalized-import Verilator video snapshot is missing'
            summary_lines << 'Normalized-import video: missing snapshot'
          end

          trim_ruby_heap!

          announce_parity_phase!('collecting raised-RHDL Verilator trace')
          raised = collect_verilator_trace(
            verilog_entry: raised_rhdl_verilog,
            rom_path: pop_rom_path,
            scratch_dir: File.join(scratch, 'raised_rhdl_verilator')
          )
          raised_trace = raised.fetch(:trace)
          raised_video = raised.fetch(:video)
          raised = nil
          if raised_trace.empty?
            failures << 'Raised-RHDL Verilator trace is empty'
            summary_lines << 'Raised-RHDL Verilator: empty trace'
          else
            summary_lines << "Raised-RHDL Verilator: #{raised_trace.length} events"
          end
          if raised_video
            summary_lines << "Raised-RHDL video@#{raised_video[:cycles]}: frames=#{raised_video[:frame_count]} nonzero=#{raised_video[:nonzero_pixels]} hash=#{raised_video[:hash]}"
          else
            failures << 'Raised-RHDL Verilator video snapshot is missing'
            summary_lines << 'Raised-RHDL video: missing snapshot'
          end

          record_trace_comparison!(
            summary_lines: summary_lines,
            failures: failures,
            lhs_name: 'Staged source',
            lhs_trace: staged_trace,
            rhs_name: 'Normalized import',
            rhs_trace: normalized_trace
          )
          record_video_comparison!(
            summary_lines: summary_lines,
            failures: failures,
            lhs_name: 'Staged source',
            lhs_video: staged_video,
            rhs_name: 'Normalized import',
            rhs_video: normalized_video
          )

          record_trace_comparison!(
            summary_lines: summary_lines,
            failures: failures,
            lhs_name: 'Staged source',
            lhs_trace: staged_trace,
            rhs_name: 'Raised RHDL',
            rhs_trace: raised_trace
          )
          record_video_comparison!(
            summary_lines: summary_lines,
            failures: failures,
            lhs_name: 'Staged source',
            lhs_video: staged_video,
            rhs_name: 'Raised RHDL',
            rhs_video: raised_video
          )

          record_trace_comparison!(
            summary_lines: summary_lines,
            failures: failures,
            lhs_name: 'Normalized import',
            lhs_trace: normalized_trace,
            rhs_name: 'Raised RHDL',
            rhs_trace: raised_trace
          )
          record_video_comparison!(
            summary_lines: summary_lines,
            failures: failures,
            lhs_name: 'Normalized import',
            lhs_video: normalized_video,
            rhs_name: 'Raised RHDL',
            rhs_video: raised_video
          )

          if failures.any?
            raise RSpec::Expectations::ExpectationNotMetError,
                  "Runtime parity summary:\n" \
                  "#{summary_lines.map { |line| "  - #{line}" }.join("\n")}\n" \
                  "Failures:\n" \
                  "#{failures.map { |line| "  - #{line}" }.join("\n")}\n" \
                  "Sample traces:\n" \
                  "  - Staged source: #{trace_sample(staged_trace).inspect}\n" \
                  "  - Normalized import: #{trace_sample(normalized_trace).inspect}\n" \
                  "  - Raised RHDL: #{trace_sample(raised_trace).inspect}"
          end
        end
      end
    end
  end
end
