# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'fileutils'
require 'etc'
require 'tempfile'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/import/ir_runner'
require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative '../../../../lib/rhdl/cli/tasks/import_task'

RSpec.describe 'GameBoy mixed import runtime parity (Verilator/Arcilator/IR)', slow: true do
  MAX_CYCLES = 500_000
  IR_TRACE_CYCLES = 100_000
  VIDEO_PARITY_CYCLES = IR_TRACE_CYCLES
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

  def require_llvm_codegen_tool!
    return if llvm_lli_available?
    return if HdlToolchain.which('clang')
    return if HdlToolchain.which('llc')

    skip 'Neither lli/llvm-link nor clang/llc is available'
  end

  def require_pop_rom!
    path = File.expand_path('../../../../examples/gameboy/software/roms/pop.gb', __dir__)
    skip "POP ROM not available: #{path}" unless File.file?(path)
    path
  end

  def require_ir_compiler!
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
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

  def build_video_snapshot(framebuffer:, frame_count:, cycles:)
    {
      cycles: cycles.to_i,
      frame_count: frame_count.to_i,
      nonzero_pixels: framebuffer_nonzero_pixels(framebuffer),
      hash: framebuffer_hash(framebuffer)
    }
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

  def skip_arcilator?
    ENV['RHDL_SKIP_ARCILATOR'] == '1'
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

  def trim_ruby_heap!
    GC.start(full_mark: true, immediate_sweep: true)
    GC.compact if GC.respond_to?(:compact)
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

  def compile_llvm_ir_object!(ll_path:, obj_path:)
    if HdlToolchain.which('clang')
      run_cmd!(['clang', '-c', '-O0', '-fPIC', ll_path, '-o', obj_path])
    else
      run_cmd!(['llc', '-filetype=obj', '-O0', '-relocation-model=pic', ll_path, '-o', obj_path])
    end
  end

  def llvm_lli_available?
    HdlToolchain.which('lli') && HdlToolchain.which('llvm-link') && HdlToolchain.which('clang++')
  end

  def run_llvm_ir_harness!(ll_path:, harness_path:, obj_path:, bin_path:, rom_path:, max_cycles:)
    if llvm_lli_available?
      harness_ll_path = harness_path.sub(/\.cpp\z/, '.harness.ll')
      linked_bc_path = harness_path.sub(/\.cpp\z/, '.bc')
      compile_threads = [Etc.nprocessors, 8].compact.min

      run_cmd!(['clang++', '-std=c++17', '-O0', '-S', '-emit-llvm', harness_path, '-o', harness_ll_path])
      run_cmd!(['llvm-link', ll_path, harness_ll_path, '-o', linked_bc_path])
      stdout, stderr, status = Open3.capture3(
        'lli',
        '--jit-kind=orc-lazy',
        "--compile-threads=#{compile_threads}",
        '-O0',
        linked_bc_path,
        rom_path,
        max_cycles.to_s
      )
      return stdout if status.success?

      detail = [stdout, stderr].join("\n").lines.first(120).join
      raise "Command failed: lli --jit-kind=orc-lazy --compile-threads=#{compile_threads} -O0 #{linked_bc_path} #{rom_path} #{max_cycles}\n#{detail}"
    end

    compile_llvm_ir_object!(ll_path: ll_path, obj_path: obj_path)
    run_cmd!(['c++', '-std=c++17', '-O0', harness_path, obj_path, '-o', bin_path])
    stdout, stderr, status = Open3.capture3(bin_path, rom_path, max_cycles.to_s)
    return stdout if status.success?

    detail = [stdout, stderr].join("\n").lines.first(120).join
    raise "Command failed: #{bin_path} #{rom_path} #{max_cycles}\n#{detail}"
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
        int max_cycles = (argc > 2) ? std::atoi(argv[2]) : 200000;

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

        uint16_t last_pc = 0xFFFF;
        for (int i = 0; i < max_cycles; ++i) {
          run_machine_cycle();
          if (!video_emitted && (i + 1) == #{VIDEO_PARITY_CYCLES}) {
            emit_video_snapshot(i + 1);
            video_emitted = true;
          }
          const bool fetch = (dut.rootp->gb__DOT___cpu_M1_n == 0);
          if (fetch) {
            uint16_t pc = static_cast<uint16_t>(dut.rootp->gb__DOT___cpu_A);
            if (pc == last_pc) continue;
            uint8_t opcode = rom_read(rom, pc);
            std::printf("%u,%u\\n", static_cast<unsigned>(pc), static_cast<unsigned>(opcode));
            last_pc = pc;
          }
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

  def collect_verilator_trace(staging_entry:, rom_path:, scratch_dir:)
    FileUtils.mkdir_p(scratch_dir)
    build_dir = File.join(scratch_dir, 'verilator_obj')
    harness = File.join(scratch_dir, 'trace_main.cpp')
    write_verilator_trace_harness(harness)

    run_cmd!([
      'verilator',
      '--cc',
      staging_entry,
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

  def with_env(temp)
    previous = {}
    temp.each do |key, value|
      previous[key] = ENV[key]
      ENV[key] = value
    end
    yield
  ensure
    temp.each_key do |key|
      if previous[key].nil?
        ENV.delete(key)
      else
        ENV[key] = previous[key]
      end
    end
  end

  def collect_ir_trace(mlir_path: nil, runtime_json_path: nil, rom_bytes:)
    runner_args = {
      top: 'gb',
      backend: :compiler
    }
    if runtime_json_path
      runner_args[:runtime_json] = File.read(runtime_json_path)
    else
      runner_args[:mlir] = File.read(mlir_path)
    end
    runner = RHDL::Examples::GameBoy::Import::IrRunner.new(**runner_args)
    begin
      runner.load_rom(rom_bytes)
      runner.reset

      cpu_addr_candidates = %w[cpu_A_16 cpu__A cpu_addr]
      cpu_fetch_candidates = %w[cpu_M1_n_1 cpu__M1_n cpu_m1_n]
      bus_addr_candidates = %w[ext_bus_addr]
      bus_a15_candidates = %w[ext_bus_a15]
      cart_rd_candidates = %w[cart_rd]
      use_cpu_fetch =
        runner.signal_available?(cpu_addr_candidates) &&
        runner.signal_available?(cpu_fetch_candidates)
      cpu_addr_idx = runner.signal_index(cpu_addr_candidates)
      cpu_fetch_idx = runner.signal_index(cpu_fetch_candidates)
      bus_addr_idx = runner.signal_index(bus_addr_candidates)
      bus_a15_idx = runner.signal_index(bus_a15_candidates)
      cart_rd_idx = runner.signal_index(cart_rd_candidates)

      trace = []
      last_pc = nil
      IR_TRACE_CYCLES.times do
        runner.run_steps(1)
        pc =
          if use_cpu_fetch
            next unless (runner.peek_index(cpu_fetch_idx) & 0x1).zero?

            runner.peek_index(cpu_addr_idx).to_i & 0xFFFF
          else
            next unless (runner.peek_index(cart_rd_idx) & 0x1) == 1

            bus_addr = runner.peek_index(bus_addr_idx).to_i & 0x7FFF
            a15 = runner.peek_index(bus_a15_idx).to_i & 0x1
            (a15 << 15) | bus_addr
          end
        next if pc == last_pc

        trace << pack_trace_event(pc, rom_bytes.getbyte(pc) || 0)
        last_pc = pc
      end

      {
        trace: normalize_trace(trace),
        video: build_video_snapshot(
          framebuffer: runner.read_framebuffer,
          frame_count: runner.frame_count,
          cycles: IR_TRACE_CYCLES
        )
      }
    ensure
      runner.close if runner.respond_to?(:close)
    end
  end

  def first_mismatch(lhs, rhs)
    first_mismatch_with_offsets(lhs, rhs, start_lhs: 0, start_rhs: 0)
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
    limit = [lhs.length, rhs.length].min
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

  def arcilator_state_offset(states, *names, preferred_type: nil)
    by_name = states.each_with_object({}) do |entry, acc|
      (acc[entry.fetch('name')] ||= []) << entry
    end
    names.each do |name|
      entries = by_name[name]
      next unless entries

      preferred_entry = preferred_type && entries.find { |entry| entry['type'] == preferred_type }
      return (preferred_entry || entries.last).fetch('offset')
    end

    states.each do |entry|
      entry_name = entry.fetch('name').to_s
      return entry.fetch('offset') if names.any? { |name| entry_name.end_with?(name) || entry_name.include?(name) }
    end

    nil
  end

  def write_arcilator_trace_harness(path:, module_name:, state_size:, offsets:)
    eval_symbol = "#{module_name}_eval"

    source = <<~CPP
      #include <cstdint>
      #include <cstdio>
      #include <cstdlib>
      #include <cstring>
      #include <fstream>
      #include <iterator>
      #include <vector>

      extern "C" void #{eval_symbol}(void* state);

      static constexpr int STATE_SIZE = #{state_size};
      static constexpr int OFF_CLK_SYS = #{offsets[:clk_sys] || -1};
      static constexpr int OFF_RESET = #{offsets[:reset] || -1};
      static constexpr int OFF_CE = #{offsets[:ce] || -1};
      static constexpr int OFF_CE_N = #{offsets[:ce_n] || -1};
      static constexpr int OFF_CE_2X = #{offsets[:ce_2x] || -1};
      static constexpr int OFF_JOYSTICK = #{offsets[:joystick] || -1};
      static constexpr int OFF_CART_OE = #{offsets[:cart_oe] || -1};
      static constexpr int OFF_CART_DO = #{offsets[:cart_do] || -1};
      static constexpr int OFF_CART_RD = #{offsets[:cart_rd] || -1};
      static constexpr int OFF_EXT_BUS_ADDR = #{offsets[:ext_bus_addr] || -1};
      static constexpr int OFF_EXT_BUS_A15 = #{offsets[:ext_bus_a15] || -1};
      static constexpr int OFF_CPU_ADDR = #{offsets[:cpu_addr] || -1};
      static constexpr int OFF_CPU_M1_N = #{offsets[:cpu_m1_n] || -1};
      static constexpr int OFF_LCD_CLKENA = #{offsets[:lcd_clkena] || -1};
      static constexpr int OFF_LCD_DATA_GB = #{offsets[:lcd_data_gb] || -1};
      static constexpr int OFF_LCD_VSYNC = #{offsets[:lcd_vsync] || -1};

      static std::vector<uint8_t> load_rom(const char* path) {
        std::ifstream in(path, std::ios::binary);
        if (!in) return std::vector<uint8_t>(1 << 16, 0);
        std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        if (bytes.empty()) bytes.resize(1 << 16, 0);
        if (bytes.size() < (1 << 16)) bytes.resize(1 << 16, 0);
        return bytes;
      }

      static inline uint8_t rom_read(const std::vector<uint8_t>& rom, uint16_t addr) {
        return rom[addr % rom.size()];
      }

      static inline bool has(int off) {
        return off >= 0;
      }

      static inline void set_bit(std::vector<uint8_t>& state, int off, uint8_t v) {
        if (has(off)) state[off] = v & 0x1;
      }

      static inline void set_u8(std::vector<uint8_t>& state, int off, uint8_t v) {
        if (has(off)) state[off] = v;
      }

      static inline uint8_t get_u8(const std::vector<uint8_t>& state, int off) {
        return has(off) ? state[off] : 0;
      }

      static inline uint16_t get_u16(const std::vector<uint8_t>& state, int off) {
        if (!has(off)) return 0;
        uint16_t v = 0;
        std::memcpy(&v, &state[off], sizeof(uint16_t));
        return v;
      }

      static inline uint8_t get_bit(const std::vector<uint8_t>& state, int off) {
        return get_u8(state, off) & 0x1;
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
        const char* rom_path = (argc > 1) ? argv[1] : "";
        int max_cycles = (argc > 2) ? std::atoi(argv[2]) : 200000;

        auto rom = load_rom(rom_path);
        std::vector<uint8_t> state(STATE_SIZE, 0);
        std::vector<uint8_t> framebuffer(#{SCREEN_WIDTH} * #{SCREEN_HEIGHT}, 0);
        int lcd_x = 0;
        int lcd_y = 0;
        uint8_t prev_lcd_clkena = 0;
        uint8_t prev_lcd_vsync = 0;
        uint64_t frame_count = 0;
        bool video_emitted = false;

        auto eval = [&]() { #{eval_symbol}(state.data()); };

        auto capture_video = [&]() {
          if (!has(OFF_LCD_CLKENA) || !has(OFF_LCD_DATA_GB) || !has(OFF_LCD_VSYNC)) return;

          uint8_t lcd_clkena = get_bit(state, OFF_LCD_CLKENA);
          uint8_t lcd_vsync = get_bit(state, OFF_LCD_VSYNC);
          uint8_t lcd_data = get_u8(state, OFF_LCD_DATA_GB) & 0x3;

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
          set_bit(state, OFF_CE, (ce_phase == 0) ? 1 : 0);
          set_bit(state, OFF_CE_N, (ce_phase == 4) ? 1 : 0);
          set_bit(state, OFF_CE_2X, ((ce_phase & 0x3) == 0) ? 1 : 0);
          set_bit(state, OFF_CLK_SYS, 0);
          eval();

          if (get_bit(state, OFF_CART_RD)) {
            uint16_t bus_addr = get_u16(state, OFF_EXT_BUS_ADDR) & 0x7FFF;
            uint16_t full_addr = (static_cast<uint16_t>(get_bit(state, OFF_EXT_BUS_A15)) << 15) | bus_addr;
            set_u8(state, OFF_CART_DO, rom_read(rom, full_addr));
          }

          eval();
          set_bit(state, OFF_CLK_SYS, 1);
          eval();
          capture_video();
          ce_phase = (ce_phase + 1) & 0x7;
        };

        auto run_machine_cycle = [&]() {
          for (int i = 0; i < 4; ++i) tick_clock();
        };

        set_u8(state, OFF_JOYSTICK, 0xFF);
        set_bit(state, OFF_CART_OE, 1);

        set_bit(state, OFF_RESET, 1);
        for (int i = 0; i < 10; ++i) tick_clock();
        set_bit(state, OFF_RESET, 0);
        for (int i = 0; i < 100; ++i) tick_clock();

        const bool has_fetch_signals = has(OFF_CPU_M1_N) && has(OFF_CPU_ADDR);
        uint16_t last_pc = 0xFFFF;

        for (int i = 0; i < max_cycles; ++i) {
          run_machine_cycle();
          if (!video_emitted && (i + 1) == #{VIDEO_PARITY_CYCLES}) {
            emit_video_snapshot(i + 1);
            video_emitted = true;
          }
          bool fetch = has_fetch_signals ? (get_bit(state, OFF_CPU_M1_N) == 0) : (get_bit(state, OFF_CART_RD) == 1);
          if (!fetch) continue;

          uint16_t pc = has_fetch_signals ? get_u16(state, OFF_CPU_ADDR) :
            ((static_cast<uint16_t>(get_bit(state, OFF_EXT_BUS_A15)) << 15) | (get_u16(state, OFF_EXT_BUS_ADDR) & 0x7FFF));

          if (pc == last_pc) continue;
          uint8_t opcode = rom_read(rom, pc);
          std::printf("%u,%u\\n", static_cast<unsigned>(pc), static_cast<unsigned>(opcode));
          last_pc = pc;
        }

        if (!video_emitted) emit_video_snapshot(max_cycles);

        return 0;
      }
    CPP

    File.write(path, source)
  end

  def try_collect_arcilator_trace(mlir_path:, rom_path:, scratch_dir:)
    FileUtils.mkdir_p(scratch_dir)
    state_path = File.join(scratch_dir, 'gb_state.json')
    ll_path = File.join(scratch_dir, 'gb_arc.ll')
    obj_path = File.join(scratch_dir, 'gb_arc.o')
    harness_path = File.join(scratch_dir, 'gb_arc_trace.cpp')
    bin_path = File.join(scratch_dir, 'gb_arc_trace')

    begin
      run_cmd!([
        'arcilator',
        mlir_path,
        '--observe-ports',
        '--observe-wires',
        '--observe-registers',
        '--split-funcs-threshold=2000',
        "--state-file=#{state_path}",
        '-o', ll_path
      ])
    rescue StandardError => e
      return { trace: nil, error: "Arcilator compile failed for #{mlir_path}: #{e.message}" }
    end

    state = JSON.parse(File.read(state_path))
    mod = state.find { |entry| entry['name'].to_s == 'gb' } || state.first
    return { trace: nil, error: 'Arcilator state file missing module entries' } unless mod

    states = Array(mod['states'])
    offsets = {
      clk_sys: arcilator_state_offset(states, 'clk_sys', preferred_type: 'input'),
      reset: arcilator_state_offset(states, 'reset', preferred_type: 'input'),
      ce: arcilator_state_offset(states, 'ce', preferred_type: 'input'),
      ce_n: arcilator_state_offset(states, 'ce_n', preferred_type: 'input'),
      ce_2x: arcilator_state_offset(states, 'ce_2x', preferred_type: 'input'),
      joystick: arcilator_state_offset(states, 'joystick', preferred_type: 'input'),
      cart_oe: arcilator_state_offset(states, 'cart_oe', preferred_type: 'input'),
      cart_do: arcilator_state_offset(states, 'cart_do', preferred_type: 'input'),
      cart_rd: arcilator_state_offset(states, 'cart_rd', preferred_type: 'output'),
      ext_bus_addr: arcilator_state_offset(states, 'ext_bus_addr', preferred_type: 'output'),
      ext_bus_a15: arcilator_state_offset(states, 'ext_bus_a15', preferred_type: 'output'),
      lcd_clkena: arcilator_state_offset(states, 'lcd_clkena', preferred_type: 'output'),
      lcd_data_gb: arcilator_state_offset(states, 'lcd_data_gb', preferred_type: 'output'),
      lcd_vsync: arcilator_state_offset(states, 'lcd_vsync', preferred_type: 'output'),
      cpu_addr: arcilator_state_offset(states, 'cpu/A', 'cpu/u0/a', 'cpu_A', 'cpu__A', 'gb__DOT___cpu_A', 'gb__cpu_A'),
      cpu_m1_n: arcilator_state_offset(states, 'cpu/M1_n', 'cpu/u0/m1_n', 'cpu_M1_n', 'cpu__M1_n', 'gb__DOT___cpu_M1_n', 'gb__cpu_M1_n')
    }

    required = %i[clk_sys reset ce ce_n ce_2x joystick cart_oe cart_do cart_rd ext_bus_addr ext_bus_a15 lcd_clkena lcd_data_gb lcd_vsync]
    missing = required.select { |key| offsets[key].nil? }
    unless missing.empty?
      return { trace: nil, error: "Arcilator state layout missing required signals: #{missing.join(', ')}" }
    end

    write_arcilator_trace_harness(
      path: harness_path,
      module_name: mod.fetch('name'),
      state_size: mod.fetch('numStateBytes').to_i,
      offsets: offsets
    )

    begin
      output = run_llvm_ir_harness!(
        ll_path: ll_path,
        harness_path: harness_path,
        obj_path: obj_path,
        bin_path: bin_path,
        rom_path: rom_path,
        max_cycles: MAX_CYCLES
      )
      {
        trace: normalize_trace(parse_trace(output)),
        video: parse_video_snapshot(output),
        error: nil
      }
    rescue StandardError => e
      { trace: nil, error: "Arcilator runtime build/execute failed: #{e.message}" }
    end
  end

  def build_arc_mlir_from_pure_verilog(staging_entry:, scratch_dir:)
    FileUtils.mkdir_p(scratch_dir)
    result = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_verilog(
      verilog_path: staging_entry,
      work_dir: scratch_dir
    )
    return [result.fetch(:arc_mlir_path), nil] if result[:success]

    error_lines = []
    error_lines << "Pure Verilog -> CIRCT ARC lowering failed"
    if result[:import] && !result[:import][:success]
      error_lines << "import: #{result[:import][:stderr]}"
    elsif result[:normalize] && !result[:normalize][:success]
      error_lines << "normalize: #{result[:normalize][:stderr]}"
    elsif result[:arc] && !result[:arc][:success]
      error_lines << "arc: #{result[:arc][:stderr]}"
    end
    unsupported = Array(result[:unsupported_modules]).first(10)
    unless unsupported.empty?
      error_lines << "unsupported modules:"
      unsupported.each do |entry|
        error_lines << "  - #{entry.fetch('module')}: #{entry.fetch('reason')}"
      end
    end

    [nil, error_lines.join("\n")]
  end

  def collect_arcilator_trace(staging_entry:, rom_path:, scratch_dir:)
    arc_mlir, lower_error = build_arc_mlir_from_pure_verilog(
      staging_entry: staging_entry,
      scratch_dir: File.join(scratch_dir, 'lower')
    )
    return { trace: nil, error: lower_error } unless arc_mlir

    try_collect_arcilator_trace(
      mlir_path: arc_mlir,
      rom_path: rom_path,
      scratch_dir: File.join(scratch_dir, 'run')
    )
  end

  it 'matches PC/opcode progression across pure Verilog, CIRCT, and raised RHDL', timeout: 3600 do
    require_reference_tree!
    %w[ghdl circt-verilog circt-opt verilator c++].each { |tool| require_tool!(tool) }
    require_llvm_codegen_tool!
    require_tool!('arcilator') unless skip_arcilator?
    require_ir_compiler!
    pop_rom_path = require_pop_rom!

    Dir.mktmpdir('gameboy_runtime_parity_out') do |out_dir|
      Dir.mktmpdir('gameboy_runtime_parity_ws') do |workspace|
        Dir.mktmpdir('gameboy_runtime_parity_run') do |scratch|
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
          expect(import_result.strategy_used).to eq(:mixed)

          report = JSON.parse(File.read(import_result.report_path))
          mixed = report.fetch('mixed_import')
          pure_verilog_entry = mixed.fetch('pure_verilog_entry_path')
          normalized_verilog = mixed.fetch('normalized_verilog_path')
          imported_mlir_path = import_result.mlir_path
          workspace_normalized_verilog = mixed['workspace_normalized_verilog_path']
          pure_verilog_root = mixed.fetch('pure_verilog_root')
          expect(File.file?(pure_verilog_entry)).to be(true)
          expect(File.file?(normalized_verilog)).to be(true)
          expect(File.file?(imported_mlir_path)).to be(true)
          expect(File.directory?(pure_verilog_root)).to be(true)
          expect(File.file?(workspace_normalized_verilog)).to be(true) if workspace_normalized_verilog

          pure_verilog_entry_text = File.read(pure_verilog_entry)
          expect(pure_verilog_entry_text).to include(pure_verilog_root)

          rom_path = pop_rom_path
          rom_bytes = File.binread(rom_path)
          import_strategy = import_result.strategy_used

          summary_lines = []
          failures = []
          summary_lines << "Import strategy: #{import_strategy}"
          summary_lines << "Verilog source: normalized_verilog_path=#{normalized_verilog}"
          summary_lines << "Imported MLIR: #{imported_mlir_path}"
          summary_lines << "Workspace Verilog source: workspace_normalized_verilog_path=#{workspace_normalized_verilog}" if workspace_normalized_verilog
          summary_lines << "Pure Verilog root: #{pure_verilog_root}"

          importer = nil
          import_result = nil
          report = nil
          mixed = nil
          pure_verilog_entry_text = nil
          trim_ruby_heap!

          verilator = collect_verilator_trace(
            staging_entry: normalized_verilog,
            rom_path: rom_path,
            scratch_dir: File.join(scratch, 'verilator')
          )
          verilator_trace = verilator.fetch(:trace)
          verilator_video = verilator.fetch(:video)
          verilator = nil
          if verilator_trace.empty?
            failures << 'Verilator trace is empty'
            summary_lines << 'Verilator: empty trace'
          else
            summary_lines << "Verilator: #{verilator_trace.length} events"
          end
          if verilator_video
            summary_lines << "Verilator video@#{verilator_video[:cycles]}: frames=#{verilator_video[:frame_count]} nonzero=#{verilator_video[:nonzero_pixels]} hash=#{verilator_video[:hash]}"
          else
            failures << 'Verilator video snapshot is missing'
            summary_lines << 'Verilator video: missing snapshot'
          end

          ir = collect_ir_trace(mlir_path: imported_mlir_path, rom_bytes: rom_bytes)
          ir_trace = ir.fetch(:trace)
          ir_video = ir.fetch(:video)
          ir = nil
          trim_ruby_heap!
          if ir_trace.empty?
            failures << 'Raised-RHDL IR trace is empty'
            summary_lines << 'IR compiler: empty trace'
          else
            summary_lines << "IR compiler: #{ir_trace.length} events"
            summary_lines << "IR compiler cycle cap: #{IR_TRACE_CYCLES}" if IR_TRACE_CYCLES < MAX_CYCLES
          end
          summary_lines << "IR compiler video@#{ir_video[:cycles]}: frames=#{ir_video[:frame_count]} nonzero=#{ir_video[:nonzero_pixels]} hash=#{ir_video[:hash]}"

          vi_compare = compare_trace_prefix(verilator_trace, ir_trace)
          if vi_compare[:mismatch]
            failures << "Verilator vs IR mismatch: #{vi_compare[:mismatch]}"
            summary_lines << "Verilator vs IR: mismatch (#{vi_compare[:mismatch]})"
          else
            summary_lines << "Verilator vs IR: OK on first #{vi_compare[:compare_len]} events"
          end

          video_mismatch = first_video_mismatch(verilator_video, ir_video)
          if video_mismatch
            failures << "Verilator vs IR video mismatch: #{video_mismatch}"
            summary_lines << "Verilator vs IR video: mismatch (#{video_mismatch})"
          else
            summary_lines << 'Verilator vs IR video: OK'
          end

          arcilator = if skip_arcilator?
                        { trace: nil, video: nil, error: 'skipped via RHDL_SKIP_ARCILATOR=1' }
                      else
                        collect_arcilator_trace(
                          staging_entry: normalized_verilog,
                          rom_path: rom_path,
                          scratch_dir: File.join(scratch, 'arcilator')
                        )
                      end

          if arcilator[:trace]
            arc_trace = arcilator.fetch(:trace)
            arc_video = arcilator.fetch(:video)
            if arc_trace.empty?
              failures << 'Arcilator trace is empty'
              summary_lines << 'Arcilator: empty trace'
            else
              summary_lines << "Arcilator: #{arc_trace.length} events"
            end
            if arc_video
              summary_lines << "Arcilator video@#{arc_video[:cycles]}: frames=#{arc_video[:frame_count]} nonzero=#{arc_video[:nonzero_pixels]} hash=#{arc_video[:hash]}"
            else
              failures << 'Arcilator video snapshot is missing'
              summary_lines << 'Arcilator video: missing snapshot'
            end

            va_compare = compare_trace_prefix(verilator_trace, arc_trace)
            if va_compare[:mismatch]
              failures << "Verilator vs Arcilator mismatch: #{va_compare[:mismatch]}"
              summary_lines << "Verilator vs Arcilator: mismatch (#{va_compare[:mismatch]})"
            else
              summary_lines << "Verilator vs Arcilator: OK on first #{va_compare[:compare_len]} events"
            end

            video_mismatch_arc = first_video_mismatch(verilator_video, arc_video)
            if video_mismatch_arc
              failures << "Verilator vs Arcilator video mismatch: #{video_mismatch_arc}"
              summary_lines << "Verilator vs Arcilator video: mismatch (#{video_mismatch_arc})"
            else
              summary_lines << 'Verilator vs Arcilator video: OK'
            end
          else
            summary_lines << "Arcilator unavailable: #{arcilator[:error]}"
          end

          if failures.any?
            raise RSpec::Expectations::ExpectationNotMetError,
                  "Runtime parity summary:\n" \
                  "#{summary_lines.map { |line| "  - #{line}" }.join("\n")}\n" \
                  "Failures:\n" \
                  "#{failures.map { |line| "  - #{line}" }.join("\n")}\n" \
                  "Sample traces:\n" \
                  "  - Verilator: #{trace_sample(verilator_trace).inspect}\n" \
                  "  - IR: #{trace_sample(ir_trace).inspect}\n" \
                  "  - Arcilator: #{trace_sample(arcilator[:trace]).inspect}"
          end
        end
      end
    end
  end
end
