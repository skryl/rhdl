# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'fileutils'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/runners/ir_runner'
require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative '../../../../lib/rhdl/cli/tasks/import_task'

RSpec.describe 'GameBoy mixed import runtime parity (Verilator/Arcilator/IR)', slow: true do
  MAX_CYCLES = 500_000
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

  def require_ir_compiler!
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  def skip_arcilator?
    ENV['RHDL_SKIP_ARCILATOR'] == '1'
  end

  def run_cmd!(cmd, chdir: nil)
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

      int main(int argc, char** argv) {
        Verilated::commandArgs(argc, argv);
        const char* rom_path = (argc > 1) ? argv[1] : "";
        int max_cycles = (argc > 2) ? std::atoi(argv[2]) : 200000;

        Vgb dut;
        auto* root = dut.rootp;
        auto rom = load_rom(rom_path);

        auto tick = [&]() {
          dut.ce = 1;
          dut.ce_n = 0;
          dut.ce_2x = 1;
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
        };

        dut.joystick = 0xFF;
        dut.cart_oe = 1;
        dut.reset = 1;
        for (int i = 0; i < 12; ++i) tick();
        dut.reset = 0;
        for (int i = 0; i < 4; ++i) tick();

        uint16_t last_pc = 0xFFFF;
        for (int i = 0; i < max_cycles; ++i) {
          tick();
          if ((root->gb__DOT__cpu_m1_n & 0x1) == 0) {
            uint16_t pc = static_cast<uint16_t>(root->gb__DOT__cpu_addr);
            if (pc != last_pc) {
              uint8_t opcode = rom_read(rom, pc);
              std::printf("%u,%u\\n", static_cast<unsigned>(pc), static_cast<unsigned>(opcode));
              last_pc = pc;
            }
          }
        }

        return 0;
      }
    CPP

    File.write(path, source)
  end

  def parse_trace(text)
    text.lines.filter_map do |line|
      match = line.strip.match(/\A(\d+),(\d+)\z/)
      next unless match

      [match[1].to_i, match[2].to_i]
    end
  end

  def normalize_trace(trace)
    Array(trace).drop_while { |(pc, _opcode)| pc.to_i.zero? }
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

    output = run_cmd!([File.join(build_dir, 'Vgb'), rom_path, MAX_CYCLES.to_s])
    normalize_trace(parse_trace(output))
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

  def collect_ir_trace(raised_hdl_dir:, rom_bytes:)
    with_env('RHDL_GAMEBOY_IMPORT_TOP' => 'gb') do
      runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile, hdl_dir: raised_hdl_dir)
      runner.load_rom(rom_bytes)
      runner.reset

      trace = []
      last_pc = nil
      use_fetch_trace = runner.signal_available?('cpu_m1_n') && runner.signal_available?('cpu_addr')
      MAX_CYCLES.times do
        runner.run_steps(1)
        if use_fetch_trace
          next unless (runner.safe_peek('cpu_m1_n') & 0x1).zero?

          pc = runner.safe_peek('cpu_addr').to_i & 0xFFFF
        else
          pc = runner.cpu_state.fetch(:pc).to_i & 0xFFFF
        end
        next if pc == last_pc

        trace << [pc, rom_bytes.getbyte(pc) || 0]
        last_pc = pc
      end

      normalize_trace(trace)
    end
  end

  def first_mismatch(lhs, rhs)
    limit = [lhs.length, rhs.length].min
    limit.times do |idx|
      next if lhs[idx] == rhs[idx]

      return "index=#{idx} lhs=#{lhs[idx].inspect} rhs=#{rhs[idx].inspect}"
    end

    return nil if lhs.length == rhs.length

    "length mismatch lhs=#{lhs.length} rhs=#{rhs.length}"
  end

  def arcilator_state_offset(states, *names)
    by_name = states.each_with_object({}) { |entry, acc| acc[entry.fetch('name')] = entry }
    names.each do |name|
      entry = by_name[name]
      return entry.fetch('offset') if entry
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

      int main(int argc, char** argv) {
        const char* rom_path = (argc > 1) ? argv[1] : "";
        int max_cycles = (argc > 2) ? std::atoi(argv[2]) : 200000;

        auto rom = load_rom(rom_path);
        std::vector<uint8_t> state(STATE_SIZE, 0);

        auto eval = [&]() { #{eval_symbol}(state.data()); };

        auto tick = [&]() {
          set_bit(state, OFF_CE, 1);
          set_bit(state, OFF_CE_N, 0);
          set_bit(state, OFF_CE_2X, 1);
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
        };

        set_u8(state, OFF_JOYSTICK, 0xFF);
        set_bit(state, OFF_CART_OE, 1);

        set_bit(state, OFF_RESET, 1);
        for (int i = 0; i < 12; ++i) tick();
        set_bit(state, OFF_RESET, 0);
        for (int i = 0; i < 4; ++i) tick();

        const bool has_fetch_signals = has(OFF_CPU_M1_N) && has(OFF_CPU_ADDR);
        uint16_t last_pc = 0xFFFF;

        for (int i = 0; i < max_cycles; ++i) {
          tick();
          bool fetch = has_fetch_signals ? (get_bit(state, OFF_CPU_M1_N) == 0) : (get_bit(state, OFF_CART_RD) == 1);
          if (!fetch) continue;

          uint16_t pc = has_fetch_signals ? get_u16(state, OFF_CPU_ADDR) :
            ((static_cast<uint16_t>(get_bit(state, OFF_EXT_BUS_A15)) << 15) | (get_u16(state, OFF_EXT_BUS_ADDR) & 0x7FFF));

          if (pc == last_pc) continue;
          uint8_t opcode = rom_read(rom, pc);
          std::printf("%u,%u\\n", static_cast<unsigned>(pc), static_cast<unsigned>(opcode));
          last_pc = pc;
        }

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
      clk_sys: arcilator_state_offset(states, 'clk_sys'),
      reset: arcilator_state_offset(states, 'reset'),
      ce: arcilator_state_offset(states, 'ce'),
      ce_n: arcilator_state_offset(states, 'ce_n'),
      ce_2x: arcilator_state_offset(states, 'ce_2x'),
      joystick: arcilator_state_offset(states, 'joystick'),
      cart_oe: arcilator_state_offset(states, 'cart_oe'),
      cart_do: arcilator_state_offset(states, 'cart_do'),
      cart_rd: arcilator_state_offset(states, 'cart_rd'),
      ext_bus_addr: arcilator_state_offset(states, 'ext_bus_addr'),
      ext_bus_a15: arcilator_state_offset(states, 'ext_bus_a15'),
      cpu_addr: arcilator_state_offset(states, 'cpu_addr', 'gb__DOT__cpu_addr', 'gb__cpu_addr'),
      cpu_m1_n: arcilator_state_offset(states, 'cpu_m1_n', 'gb__DOT__cpu_m1_n', 'gb__cpu_m1_n')
    }

    required = %i[clk_sys reset ce ce_n ce_2x joystick cart_oe cart_do cart_rd ext_bus_addr ext_bus_a15]
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
      run_cmd!(['llc', '-opaque-pointers=1', '-relocation-model=pic', '-filetype=obj', ll_path, '-o', obj_path])
      run_cmd!(['c++', '-std=c++17', '-O2', harness_path, obj_path, '-o', bin_path])
      output = run_cmd!([bin_path, rom_path, MAX_CYCLES.to_s])
      { trace: normalize_trace(parse_trace(output)), error: nil }
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
    %w[ghdl circt-verilog circt-opt verilator llc c++].each { |tool| require_tool!(tool) }
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
          workspace_normalized_verilog = mixed['workspace_normalized_verilog_path']
          pure_verilog_root = mixed.fetch('pure_verilog_root')
          expect(File.file?(pure_verilog_entry)).to be(true)
          expect(File.file?(normalized_verilog)).to be(true)
          expect(File.directory?(pure_verilog_root)).to be(true)
          expect(File.file?(workspace_normalized_verilog)).to be(true) if workspace_normalized_verilog

          pure_verilog_entry_text = File.read(pure_verilog_entry)
          expect(pure_verilog_entry_text).to include(pure_verilog_root)

          rom_path = pop_rom_path
          rom_bytes = File.binread(rom_path)

          summary_lines = []
          failures = []
          summary_lines << "Import strategy: #{import_result.strategy_used}"
          summary_lines << "Verilog source: normalized_verilog_path=#{normalized_verilog}"
          summary_lines << "Workspace Verilog source: workspace_normalized_verilog_path=#{workspace_normalized_verilog}" if workspace_normalized_verilog
          summary_lines << "Pure Verilog root: #{pure_verilog_root}"

          verilator_trace = collect_verilator_trace(
            staging_entry: normalized_verilog,
            rom_path: rom_path,
            scratch_dir: File.join(scratch, 'verilator')
          )
          if verilator_trace.empty?
            failures << 'Verilator trace is empty'
            summary_lines << 'Verilator: empty trace'
          else
            summary_lines << "Verilator: #{verilator_trace.length} events"
          end

          ir_trace = collect_ir_trace(raised_hdl_dir: out_dir, rom_bytes: rom_bytes)
          if ir_trace.empty?
            failures << 'Raised-RHDL IR trace is empty'
            summary_lines << 'IR compiler: empty trace'
          else
            summary_lines << "IR compiler: #{ir_trace.length} events"
          end

          vi_verilator_trace = verilator_trace
          vi_ir_trace = ir_trace
          vi_verilator_trace, vi_ir_trace = align_trace_prefix(vi_verilator_trace, vi_ir_trace)
          mismatch = first_mismatch(vi_verilator_trace, vi_ir_trace)
          if mismatch
            failures << "Verilator vs IR mismatch: #{mismatch}"
            summary_lines << "Verilator vs IR: mismatch (#{mismatch})"
          else
            summary_lines << 'Verilator vs IR: OK'
          end

          arcilator = if skip_arcilator?
                        { trace: nil, error: 'skipped via RHDL_SKIP_ARCILATOR=1' }
                      else
                        collect_arcilator_trace(
                          staging_entry: runtime_entry,
                          rom_path: rom_path,
                          scratch_dir: File.join(scratch, 'arcilator')
                        )
                      end

          if arcilator[:trace]
            arc_trace = arcilator.fetch(:trace)
            if arc_trace.empty?
              failures << 'Arcilator trace is empty'
              summary_lines << 'Arcilator: empty trace'
            else
              summary_lines << "Arcilator: #{arc_trace.length} events"
            end

            va_verilator_trace = verilator_trace
            va_arc_trace = arc_trace
            va_verilator_trace, va_arc_trace = align_trace_prefix(va_verilator_trace, va_arc_trace)
            mismatch_arc = first_mismatch(va_verilator_trace, va_arc_trace)
            if mismatch_arc
              failures << "Verilator vs Arcilator mismatch: #{mismatch_arc}"
              summary_lines << "Verilator vs Arcilator: mismatch (#{mismatch_arc})"
            else
              summary_lines << 'Verilator vs Arcilator: OK'
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
                  "  - Verilator: #{verilator_trace.first(20).inspect}\n" \
                  "  - IR: #{ir_trace.first(20).inspect}\n" \
                  "  - Arcilator: #{Array(arcilator[:trace]).first(20).inspect}"
          end
        end
      end
    end
  end
end
