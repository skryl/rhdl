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
require_relative './verilator_wrapper_support'

RSpec.describe 'GameBoy mixed import runtime parity (Verilator/Verilator/Verilator)', slow: true do
  include GameboyImportVerilatorWrapperSupport

  MAX_CYCLES = Integer(ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_MAX_CYCLES', '50000000'))
  VIDEO_SNAPSHOT_INTERVAL_CYCLES = Integer(
    ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_SNAPSHOT_CYCLES', [MAX_CYCLES / 20, 25_000].max.to_s)
  )
  PARITY_LEGS = %i[staged normalized raised].freeze
  NINTENDO_LOGO_HEADER_RANGE = (0x0104..0x0133)
  SCREEN_WIDTH = 160
  SCREEN_HEIGHT = 144
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

  def require_boot_rom!
    skip "DMG boot ROM not available: #{DMG_BOOT_ROM_PATH}" unless File.file?(DMG_BOOT_ROM_PATH)
    DMG_BOOT_ROM_PATH
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

  def parse_video_snapshots(text)
    text.to_s.lines.filter_map do |line|
      match = line.strip.match(/\AVIDEO_SNAPSHOT,(\d+),(\d+),(\d+),([0-9a-fA-F]+)\z/)
      next unless match

      {
        cycles: match[1].to_i,
        frame_count: match[2].to_i,
        nonzero_pixels: match[3].to_i,
        hash: match[4].downcase
      }
    end
  end

  def latest_video_snapshot(snapshots)
    Array(snapshots).last
  end

  def first_nonblank_video_snapshot(snapshots)
    Array(snapshots).find { |snapshot| snapshot[:nonzero_pixels].to_i.positive? }
  end

  def trace_reaches_nintendo_logo_header?(trace)
    Array(trace).any? do |event|
      pc, = unpack_trace_event(event)
      NINTENDO_LOGO_HEADER_RANGE.cover?(pc)
    end
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

  def enabled_verilator_legs
    @enabled_verilator_legs ||=
      begin
        raw = ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_LEGS', '').strip
        if raw.empty?
          PARITY_LEGS
        else
          legs = raw.split(',').map { |value| value.strip.downcase.to_sym }.reject(&:empty?)
          unknown = legs - PARITY_LEGS
          raise ArgumentError, "Unknown parity legs: #{unknown.join(', ')}" if unknown.any?

          legs
        end
      end
  end

  def parity_leg_enabled?(name)
    enabled_verilator_legs.include?(name.to_sym)
  end

  def speedcontrol_verilog_path(pure_verilog_root:)
    path = File.join(pure_verilog_root, 'generated_vhdl', 'speedcontrol.v')
    raise "Missing synthesized speedcontrol Verilog: #{path}" unless File.file?(path)

    path
  end

  def write_verilator_trace_harness(path, wrapper_uses_speedcontrol:)
    ce_state = wrapper_uses_speedcontrol ? '' : "        unsigned int ce_phase = 0;\n"
    ce_drive = if wrapper_uses_speedcontrol
                 ''
               else
                 <<~CPP.chomp
                   dut.ce = (ce_phase == 0u) ? 1u : 0u;
                   dut.ce_n = (ce_phase == 4u) ? 1u : 0u;
                   dut.ce_2x = ((ce_phase & 0x3u) == 0u) ? 1u : 0u;
                 CPP
               end
    ce_advance = wrapper_uses_speedcontrol ? '' : "          ce_phase = (ce_phase + 1u) & 0x7u;\n"
    ce_init = if wrapper_uses_speedcontrol
                ''
              else
                <<~CPP.chomp
                  dut.ce = 0;
                  dut.ce_n = 0;
                  dut.ce_2x = 0;
                CPP
              end

    source = <<~CPP
      #include "Vgameboy.h"
      #include "Vgameboy___024root.h"
      #include "verilated.h"
      #include <cstdint>
      #include <cstdio>
      #include <cstdlib>
      #include <fstream>
      #include <iterator>
      #include <cstring>
      #include <vector>

      static std::vector<uint8_t> load_bytes(const char* path, size_t min_size) {
        std::ifstream in(path, std::ios::binary);
        if (!in) return std::vector<uint8_t>(min_size, 0);
        std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        if (bytes.empty()) bytes.resize(min_size, 0);
        if (bytes.size() < min_size) bytes.resize(min_size, 0);
        return bytes;
      }

      static uint8_t rom_read(const std::vector<uint8_t>& rom, uint16_t addr) {
        return rom[addr % rom.size()];
      }

      struct CartState {
        uint8_t cart_type;
        uint8_t rom_size_code;
        uint8_t ram_size_code;
        uint16_t rom_bank_count;
        uint8_t mbc1_rom_bank_low5;
        uint8_t mbc1_bank_upper2;
        uint8_t mbc1_mode;
        uint8_t mbc1_ram_enabled;
        uint8_t cart_do_latched;
        uint8_t cart_oe_latched;
        unsigned int cart_read_pipeline[6];
        uint8_t cart_read_valid[6];
        unsigned int cart_last_full_addr;
        uint8_t cart_last_rd;
        unsigned int last_fetch_addr;
      };

      static uint16_t rom_bank_count(uint8_t rom_size_code) {
        switch (rom_size_code) {
          case 0x00: return 2;
          case 0x01: return 4;
          case 0x02: return 8;
          case 0x03: return 16;
          case 0x04: return 32;
          case 0x05: return 64;
          case 0x06: return 128;
          case 0x07: return 256;
          case 0x08: return 512;
          case 0x52: return 72;
          case 0x53: return 80;
          case 0x54: return 96;
          default: return 2;
        }
      }

      static bool mbc1_cart(uint8_t cart_type) {
        return cart_type == 0x01 || cart_type == 0x02 || cart_type == 0x03;
      }

      static void reset_cart_state(CartState& cart) {
        cart.mbc1_rom_bank_low5 = 1;
        cart.mbc1_bank_upper2 = 0;
        cart.mbc1_mode = 0;
        cart.mbc1_ram_enabled = 0;
        cart.cart_do_latched = 0xFF;
        cart.cart_oe_latched = 0;
        memset(cart.cart_read_pipeline, 0, sizeof(cart.cart_read_pipeline));
        memset(cart.cart_read_valid, 0, sizeof(cart.cart_read_valid));
        cart.cart_last_full_addr = 0u;
        cart.cart_last_rd = 0u;
        cart.last_fetch_addr = 0xFFFFu;
      }

      static uint8_t cart_read(const std::vector<uint8_t>& rom, const CartState& cart, uint16_t addr) {
        if (!mbc1_cart(cart.cart_type)) return rom_read(rom, addr);
        if (addr > 0x7FFF) return 0xFF;

        uint32_t bank = 0;
        if (addr <= 0x3FFF) {
          bank = cart.mbc1_mode ? ((cart.mbc1_bank_upper2 & 0x3u) << 5) : 0u;
        } else {
          uint32_t low = cart.mbc1_rom_bank_low5 & 0x1Fu;
          if (low == 0u) low = 1u;
          bank = ((cart.mbc1_bank_upper2 & 0x3u) << 5) | low;
        }
        uint32_t bank_count = cart.rom_bank_count ? cart.rom_bank_count : 1u;
        bank %= bank_count;
        uint32_t index = bank * 0x4000u + (addr & 0x3FFFu);
        return rom[index % rom.size()];
      }

      static uint8_t cart_output_enable(const CartState& cart, uint16_t addr) {
        if (addr <= 0x7FFF) return 1;
        if (mbc1_cart(cart.cart_type) && addr >= 0xA000 && addr <= 0xBFFF) return cart.mbc1_ram_enabled;
        return 0;
      }

      static void cart_write(CartState& cart, uint16_t addr, uint8_t value) {
        if (!mbc1_cart(cart.cart_type) || addr > 0x7FFF) return;

        if (addr <= 0x1FFF) {
          cart.mbc1_ram_enabled = (value & 0x0F) == 0x0A ? 1u : 0u;
        } else if (addr <= 0x3FFF) {
          uint8_t bank = value & 0x1F;
          cart.mbc1_rom_bank_low5 = bank == 0 ? 1 : bank;
        } else if (addr <= 0x5FFF) {
          cart.mbc1_bank_upper2 = value & 0x03;
        } else {
          cart.mbc1_mode = value & 0x01;
        }
      }

      static void cart_advance_read_pipeline(CartState& cart, const std::vector<uint8_t>& rom) {
        for (int i = 5; i > 0; --i) {
          cart.cart_read_pipeline[i] = cart.cart_read_pipeline[i - 1];
          cart.cart_read_valid[i] = cart.cart_read_valid[i - 1];
        }
        cart.cart_read_pipeline[0] = cart.cart_last_full_addr;
        cart.cart_read_valid[0] = cart.cart_last_rd;
        if (cart.cart_read_valid[5]) {
          cart.cart_do_latched = cart_read(rom, cart, cart.cart_read_pipeline[5]);
          cart.cart_oe_latched = cart_output_enable(cart, cart.cart_read_pipeline[5]);
        } else {
          cart.cart_oe_latched = 0;
        }
      }

      static void drive_inputs(Vgameboy& dut, CartState& cart, const std::vector<uint8_t>& rom, const std::vector<uint8_t>& boot_rom) {
        uint16_t cart_addr =
          (static_cast<uint16_t>(dut.ext_bus_a15 & 0x1) << 15) |
          static_cast<uint16_t>(dut.ext_bus_addr & 0x7FFF);
        cart.cart_last_full_addr = cart_addr;

        dut.cart_ram_size = cart.ram_size_code;
        uint8_t boot_addr = dut.boot_rom_addr & 0xFF;
        dut.boot_rom_do = boot_rom[boot_addr];

        if (dut.cart_wr) {
          cart_write(cart, cart_addr, dut.cart_di & 0xFF);
        }

        cart.cart_last_rd = dut.cart_rd ? 1u : 0u;
        cart.last_fetch_addr = cart_addr;

        dut.cart_oe = cart.cart_oe_latched;
        dut.cart_do = cart.cart_do_latched;
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
        const char* boot_rom_path = (argc > 2) ? argv[2] : "";
        int max_cycles = (argc > 3) ? std::atoi(argv[3]) : #{MAX_CYCLES};

        Vgameboy dut;
        auto rom = load_bytes(rom_path, 1 << 16);
        auto boot_rom = load_bytes(boot_rom_path, 256);
        CartState cart{};
        cart.cart_type = rom[0x147];
        cart.rom_size_code = rom[0x148];
        cart.ram_size_code = rom[0x149];
        cart.rom_bank_count = rom_bank_count(rom[0x148]);
        reset_cart_state(cart);
        std::vector<uint8_t> framebuffer(#{SCREEN_WIDTH} * #{SCREEN_HEIGHT}, 0);
        int lcd_x = 0;
        int lcd_y = 0;
        uint8_t prev_lcd_clkena = 0;
        uint8_t prev_lcd_vsync = 0;
        uint64_t frame_count = 0;
#{ce_state.chomp}
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
#{ce_drive.empty? ? '' : "          #{ce_drive.gsub("\n", "\n          ")}\n"}
          dut.clk_sys = 0;
          dut.eval();
          drive_inputs(dut, cart, rom, boot_rom);
          dut.eval();
#{ce_drive.empty? ? '' : "          #{ce_drive.gsub("\n", "\n          ")}\n"}
          dut.clk_sys = 1;
          dut.eval();
          drive_inputs(dut, cart, rom, boot_rom);
          dut.eval();
          capture_video();
          cart_advance_read_pipeline(cart, rom);
#{ce_advance.chomp}
        };

        dut.joystick = 0xFF;
        dut.is_gbc = 0;
        dut.is_sgb = 0;
#{ce_init.empty? ? '' : "        #{ce_init.gsub("\n", "\n        ")}\n"}
        dut.boot_rom_do = 0;
        dut.reset = 1;
        for (int i = 0; i < 10; ++i) tick_clock();
        dut.reset = 0;
        for (int i = 0; i < 100; ++i) tick_clock();

        uint16_t last_addr = 0xFFFF;
        for (int i = 0; i < max_cycles; ++i) {
          tick_clock();
          if (((i + 1) % #{VIDEO_SNAPSHOT_INTERVAL_CYCLES}) == 0) {
            emit_video_snapshot(i + 1);
          }
          if (!dut.cart_rd) continue;

          uint16_t addr =
            (static_cast<uint16_t>(dut.ext_bus_a15 & 0x1u) << 15) |
            (static_cast<uint16_t>(dut.ext_bus_addr & 0x7FFFu));
          if (addr == last_addr) continue;

          cart.last_fetch_addr = addr;
          uint8_t opcode = rom_read(rom, addr);
          std::printf("%u,%u\\n", static_cast<unsigned>(addr), static_cast<unsigned>(opcode));
          last_addr = addr;
        }

        if ((max_cycles % #{VIDEO_SNAPSHOT_INTERVAL_CYCLES}) != 0) emit_video_snapshot(max_cycles);

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

  def collect_verilator_trace(verilog_entry:, rom_path:, scratch_dir:, support_verilog_paths:, use_speedcontrol:)
    FileUtils.mkdir_p(scratch_dir)
    build_dir = File.join(scratch_dir, 'verilator_obj')
    wrapper = File.join(scratch_dir, 'gameboy.v')
    harness = File.join(scratch_dir, 'trace_main.cpp')
    profile = gb_wrapper_profile(verilog_entry)
    File.write(
      wrapper,
      gameboy_wrapper_source(
        profile: profile,
        use_speedcontrol: use_speedcontrol
      )
    )
    write_verilator_trace_harness(harness, wrapper_uses_speedcontrol: use_speedcontrol)

    run_cmd!([
      'verilator',
      '--cc',
      wrapper,
      *Array(support_verilog_paths).uniq,
      verilog_entry,
      '--top-module', gameboy_wrapper_top_module,
      '--Mdir', build_dir,
      '--public-flat-rw',
      *VERILATOR_WARN_FLAGS,
      '--exe',
      harness
    ])
    run_cmd!(['make', '-C', build_dir, '-f', 'Vgameboy.mk', 'Vgameboy'])

    output = run_capture_cmd!([File.join(build_dir, 'Vgameboy'), rom_path, require_boot_rom!, MAX_CYCLES.to_s])
    videos = parse_video_snapshots(output)
    {
      trace: normalize_trace(parse_trace(output)),
      video: latest_video_snapshot(videos),
      videos: videos
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
    require_export_tool! if parity_leg_enabled?(:raised)
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
            auto_stub_modules: :simulation_safe,
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
          raised_rhdl_verilog = nil
          if parity_leg_enabled?(:raised)
            source_mlir = File.read(import_result.mlir_path)
            raised_rhdl_verilog = export_raised_rhdl_verilog(
              source_mlir,
              scratch_dir: File.join(scratch, 'raised_rhdl'),
              pure_verilog_root: pure_verilog_root
            )
          end

          expect(File.file?(pure_verilog_entry)).to be(true)
          expect(File.file?(normalized_verilog)).to be(true)
          expect(File.file?(raised_rhdl_verilog)).to be(true) if raised_rhdl_verilog
          speedcontrol_verilog = speedcontrol_verilog_path(pure_verilog_root: pure_verilog_root)

          summary_lines = []
          failures = []
          summary_lines << 'Backend order: Verilator(staged source) -> Verilator(normalized import) -> Verilator(raised RHDL)'
          summary_lines << "Enabled legs: #{enabled_verilator_legs.join(', ')}"
          summary_lines << "Importer stubs: #{import_result.stub_modules.join(', ')}"
          summary_lines << "Staged source Verilog: #{pure_verilog_entry}"
          summary_lines << "Normalized imported Verilog: #{normalized_verilog}"
          summary_lines << "Raised-RHDL Verilog: #{raised_rhdl_verilog || '(skipped)'}"
          summary_lines << "Imported speedcontrol Verilog: #{speedcontrol_verilog}"

          importer = nil
          import_result = nil
          report = nil
          mixed = nil
          trim_ruby_heap!

          announce_parity_phase!('collecting staged-source Verilator trace')
          staged_trace = []
          staged_videos = []
          staged_video = nil
          staged_first_nonblank_video = nil
          if parity_leg_enabled?(:staged)
            staged = collect_verilator_trace(
              verilog_entry: pure_verilog_entry,
              rom_path: pop_rom_path,
              scratch_dir: File.join(scratch, 'staged_source'),
              support_verilog_paths: [],
              use_speedcontrol: true
            )
            staged_trace = staged.fetch(:trace)
            staged_videos = staged.fetch(:videos)
            staged_video = staged.fetch(:video)
            staged_first_nonblank_video = first_nonblank_video_snapshot(staged_videos)
            staged = nil
            if staged_trace.empty?
              failures << 'Staged-source Verilator trace is empty'
              summary_lines << 'Staged-source Verilator: empty trace'
            else
              summary_lines << "Staged-source Verilator: #{staged_trace.length} events"
            end
            unless trace_reaches_nintendo_logo_header?(staged_trace)
              failures << 'Staged-source Verilator trace never reaches Nintendo logo header range'
              summary_lines << 'Staged-source trace: missing Nintendo logo header access'
            end
            if staged_video
              summary_lines << "Staged-source video@#{staged_video[:cycles]}: frames=#{staged_video[:frame_count]} nonzero=#{staged_video[:nonzero_pixels]} hash=#{staged_video[:hash]}"
            else
              failures << 'Staged-source Verilator video snapshot is missing'
              summary_lines << 'Staged-source video: missing snapshot'
            end
            if staged_first_nonblank_video
              summary_lines << "Staged-source first nonblank video@#{staged_first_nonblank_video[:cycles]}: frames=#{staged_first_nonblank_video[:frame_count]} nonzero=#{staged_first_nonblank_video[:nonzero_pixels]} hash=#{staged_first_nonblank_video[:hash]}"
            else
              failures << 'Staged-source Verilator framebuffer never becomes nonblank'
              summary_lines << 'Staged-source video: framebuffer remained blank'
            end
          else
            summary_lines << 'Staged-source Verilator: skipped by RHDL_GAMEBOY_VERILATOR_PARITY_LEGS'
          end

          trim_ruby_heap!

          announce_parity_phase!('collecting normalized-import Verilator trace')
          normalized_trace = []
          normalized_videos = []
          normalized_video = nil
          normalized_first_nonblank_video = nil
          if parity_leg_enabled?(:normalized)
            normalized = collect_verilator_trace(
              verilog_entry: normalized_verilog,
              rom_path: pop_rom_path,
              scratch_dir: File.join(scratch, 'normalized_import'),
              support_verilog_paths: [speedcontrol_verilog],
              use_speedcontrol: true
            )
            normalized_trace = normalized.fetch(:trace)
            normalized_videos = normalized.fetch(:videos)
            normalized_video = normalized.fetch(:video)
            normalized_first_nonblank_video = first_nonblank_video_snapshot(normalized_videos)
            normalized = nil
            if normalized_trace.empty?
              failures << 'Normalized-import Verilator trace is empty'
              summary_lines << 'Normalized-import Verilator: empty trace'
            else
              summary_lines << "Normalized-import Verilator: #{normalized_trace.length} events"
            end
            unless trace_reaches_nintendo_logo_header?(normalized_trace)
              failures << 'Normalized-import Verilator trace never reaches Nintendo logo header range'
              summary_lines << 'Normalized-import trace: missing Nintendo logo header access'
            end
            if normalized_video
              summary_lines << "Normalized-import video@#{normalized_video[:cycles]}: frames=#{normalized_video[:frame_count]} nonzero=#{normalized_video[:nonzero_pixels]} hash=#{normalized_video[:hash]}"
            else
              failures << 'Normalized-import Verilator video snapshot is missing'
              summary_lines << 'Normalized-import video: missing snapshot'
            end
            if normalized_first_nonblank_video
              summary_lines << "Normalized-import first nonblank video@#{normalized_first_nonblank_video[:cycles]}: frames=#{normalized_first_nonblank_video[:frame_count]} nonzero=#{normalized_first_nonblank_video[:nonzero_pixels]} hash=#{normalized_first_nonblank_video[:hash]}"
            else
              failures << 'Normalized-import Verilator framebuffer never becomes nonblank'
              summary_lines << 'Normalized-import video: framebuffer remained blank'
            end
          else
            summary_lines << 'Normalized-import Verilator: skipped by RHDL_GAMEBOY_VERILATOR_PARITY_LEGS'
          end

          trim_ruby_heap!

          announce_parity_phase!('collecting raised-RHDL Verilator trace')
          raised_trace = []
          raised_videos = []
          raised_video = nil
          raised_first_nonblank_video = nil
          if parity_leg_enabled?(:raised)
            raised = collect_verilator_trace(
              verilog_entry: raised_rhdl_verilog,
              rom_path: pop_rom_path,
              scratch_dir: File.join(scratch, 'raised_rhdl_verilator'),
              support_verilog_paths: [speedcontrol_verilog],
              use_speedcontrol: true
            )
            raised_trace = raised.fetch(:trace)
            raised_videos = raised.fetch(:videos)
            raised_video = raised.fetch(:video)
            raised_first_nonblank_video = first_nonblank_video_snapshot(raised_videos)
            raised = nil
            if raised_trace.empty?
              failures << 'Raised-RHDL Verilator trace is empty'
              summary_lines << 'Raised-RHDL Verilator: empty trace'
            else
              summary_lines << "Raised-RHDL Verilator: #{raised_trace.length} events"
            end
            unless trace_reaches_nintendo_logo_header?(raised_trace)
              failures << 'Raised-RHDL Verilator trace never reaches Nintendo logo header range'
              summary_lines << 'Raised-RHDL trace: missing Nintendo logo header access'
            end
            if raised_video
              summary_lines << "Raised-RHDL video@#{raised_video[:cycles]}: frames=#{raised_video[:frame_count]} nonzero=#{raised_video[:nonzero_pixels]} hash=#{raised_video[:hash]}"
            else
              failures << 'Raised-RHDL Verilator video snapshot is missing'
              summary_lines << 'Raised-RHDL video: missing snapshot'
            end
            if raised_first_nonblank_video
              summary_lines << "Raised-RHDL first nonblank video@#{raised_first_nonblank_video[:cycles]}: frames=#{raised_first_nonblank_video[:frame_count]} nonzero=#{raised_first_nonblank_video[:nonzero_pixels]} hash=#{raised_first_nonblank_video[:hash]}"
            else
              failures << 'Raised-RHDL Verilator framebuffer never becomes nonblank'
              summary_lines << 'Raised-RHDL video: framebuffer remained blank'
            end
          else
            summary_lines << 'Raised-RHDL Verilator: skipped by RHDL_GAMEBOY_VERILATOR_PARITY_LEGS'
          end

          if parity_leg_enabled?(:staged) && parity_leg_enabled?(:normalized)
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
              lhs_video: staged_first_nonblank_video || staged_video,
              rhs_name: 'Normalized import',
              rhs_video: normalized_first_nonblank_video || normalized_video
            )
          end

          if parity_leg_enabled?(:staged) && parity_leg_enabled?(:raised)
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
              lhs_video: staged_first_nonblank_video || staged_video,
              rhs_name: 'Raised RHDL',
              rhs_video: raised_first_nonblank_video || raised_video
            )
          end

          if parity_leg_enabled?(:normalized) && parity_leg_enabled?(:raised)
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
              lhs_video: normalized_first_nonblank_video || normalized_video,
              rhs_name: 'Raised RHDL',
              rhs_video: raised_first_nonblank_video || raised_video
            )
          end

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
