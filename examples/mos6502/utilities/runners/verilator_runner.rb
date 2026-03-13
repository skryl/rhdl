# frozen_string_literal: true

# MOS 6502 Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the MOS6502 CPU HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface with batch cycle execution to avoid
# FFI overhead.
#
# Usage:
#   runner = RHDL::Examples::MOS6502::VerilogRunner.new
#   runner.load_program([0xA9, 0x42, 0x00], 0x8000)  # LDA #$42; BRK
#   runner.reset
#   runner.run_cycles(100)

require_relative '../../hdl/cpu'
require_relative '../../hdl/memory'
require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'
require 'rhdl/sim/native/verilog/verilator/runtime'
require_relative '../renderers/color_renderer'

module RHDL
  module Examples
    module MOS6502
      # Verilator-based runner for MOS 6502 simulation
      # Compiles RHDL Verilog export to native code via Verilator
      class VerilogRunner
    HIRES_PAGE1_START = 0x2000
    HIRES_PAGE1_END = 0x3FFF
    HIRES_PAGE2_START = 0x4000
    HIRES_PAGE2_END = 0x5FFF

    # Build directory for Verilator output
    BUILD_DIR = File.expand_path('../../.verilator_build', __dir__)
    VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
    OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')

    attr_reader :cycle_count, :sim

    ABI_INPUT_SIGNALS = [
      ['clk', 1],
      ['rst', 1],
      ['rdy', 1],
      ['irq', 1],
      ['nmi', 1],
      ['data_in', 8],
      ['ext_pc_load_en', 1],
      ['ext_pc_load_data', 16],
      ['ext_a_load_en', 1],
      ['ext_a_load_data', 8],
      ['ext_x_load_en', 1],
      ['ext_x_load_data', 8],
      ['ext_y_load_en', 1],
      ['ext_y_load_data', 8],
      ['ext_sp_load_en', 1],
      ['ext_sp_load_data', 8]
    ].freeze

    ABI_OUTPUT_SIGNALS = [
      ['addr', 16],
      ['data_out', 8],
      ['rw', 1],
      ['sync', 1],
      ['reg_a', 8],
      ['reg_x', 8],
      ['reg_y', 8],
      ['reg_sp', 8],
      ['reg_pc', 16],
      ['reg_p', 8],
      ['opcode', 8],
      ['state', 8],
      ['halted', 1],
      ['cycle_count', 32]
    ].freeze

    # Initialize the MOS 6502 Verilator runner
    def initialize
      check_verilator_available!

      puts "Initializing MOS6502 Verilator simulation..."
      start_time = Time.now

      # Build and load the Verilator simulation
      build_verilator_simulation

      elapsed = Time.now - start_time
      puts "  Verilator simulation built in #{elapsed.round(2)}s"

      @cycle_count = 0
      @halted = false

      # Memory array (64KB)
      @memory = Array.new(65536, 0)
    end

    def native?
      true
    end

    def simulator_type
      :hdl_verilator
    end

    def abi_signal_widths_by_name
      @abi_signal_widths_by_name ||= (ABI_INPUT_SIGNALS + ABI_OUTPUT_SIGNALS).to_h
    end

    def abi_signal_widths_by_idx
      @abi_signal_widths_by_idx ||= (ABI_INPUT_SIGNALS + ABI_OUTPUT_SIGNALS).map(&:last)
    end

    # Load a program into memory
    def load_program(bytes, addr = 0x8000)
      bytes = bytes.bytes if bytes.is_a?(String)
      bytes.each_with_index do |byte, i|
        write_memory(addr + i, byte)
      end
      # Set reset vector to point to program
      write_memory(0xFFFC, addr & 0xFF)
      write_memory(0xFFFD, (addr >> 8) & 0xFF)
    end

    # Load memory region
    def load_memory(bytes, base_addr)
      bytes = bytes.bytes if bytes.is_a?(String)
      bytes.each_with_index do |byte, i|
        write_memory(base_addr + i, byte)
      end
      @sim&.runner_load_memory(bytes, base_addr, false)
    end

    # Alias for HeadlessRunner compatibility
    def load_rom(bytes, base_addr: 0xD000)
      load_memory(bytes, base_addr)
    end

    # Alias for HeadlessRunner compatibility
    def load_ram(bytes, base_addr: 0x0000)
      load_memory(bytes, base_addr)
    end

    # Write a single byte to memory
    def write_memory(addr, byte)
      @memory[addr & 0xFFFF] = byte & 0xFF
      verilator_write_memory(addr, byte) if @sim
    end

    # Read a single byte from memory
    def read_memory(addr)
      addr = addr & 0xFFFF
      if @sim
        return @sim.runner_read_memory(addr, 1, mapped: false).fetch(0, 0).to_i & 0xFF
      end

      @memory[addr]
    end

    # Set reset vector
    def set_reset_vector(addr)
      write_memory(0xFFFC, addr & 0xFF)
      write_memory(0xFFFD, (addr >> 8) & 0xFF)
    end

    def reset
      reset_simulation
      @cycle_count = 0
      @halted = false
    end

    # Run N clock cycles using batch execution (avoids FFI overhead)
    def run_cycles(n)
      if @sim
        result = @sim.runner_run_cycles(n)
        @cycle_count += (result && result[:cycles_run]) || n
        @halted = verilator_peek('halted') == 1
      else
        # Fallback to per-cycle execution
        n.times { clock_cycle }
      end
    end

    # Alias for HeadlessRunner compatibility
    alias run_steps run_cycles

    # Run a single clock cycle
    def clock_cycle
      # Match examples/mos6502/hdl/harness.rb clock_cycle timing:
      # - Evaluate CPU at clk=0 (low phase) to produce addr/rw/data_out
      # - Provide data_in from memory for clk=1 (high phase)
      # - Commit writes on the rising edge using the low-phase data_out

      # Low phase
      verilator_poke('clk', 0)
      verilator_eval

      addr = verilator_peek('addr') & 0xFFFF
      rw = verilator_peek('rw')
      write_data = verilator_peek('data_out') & 0xFF

      # Combinational memory read (always present, even on write cycles)
      verilator_poke('data_in', @memory[addr] || 0)
      verilator_eval

      # High phase
      verilator_poke('clk', 1)
      verilator_eval

      # Commit write on rising edge
      if rw == 0
        @memory[addr] = write_data
        verilator_write_memory(addr, write_data) if @sim
      end

      @cycle_count += 1
      @halted = verilator_peek('halted') == 1
    end

    # Step one instruction (run until next FETCH state)
    def step
      cycles = 0
      max_cycles = 20
      prev_state = verilator_peek('state')

      loop do
        clock_cycle
        cycles += 1

        state = verilator_peek('state')
        # Instruction complete when we transition TO FETCH from another state
        break if state == 0 && prev_state != 0  # STATE_FETCH = 0

        prev_state = state
        break if cycles >= max_cycles || halted?
      end

      cycles
    end

    # Register accessors
    def a
      verilator_peek('reg_a')
    end

    def x
      verilator_peek('reg_x')
    end

    def y
      verilator_peek('reg_y')
    end

    def sp
      verilator_peek('reg_sp')
    end

    def pc
      verilator_peek('reg_pc')
    end

    def p
      verilator_peek('reg_p')
    end

    def opcode
      verilator_peek('opcode')
    end

    def state
      verilator_peek('state')
    end

    def halted?
      @halted
    end

    # Status flags
    def flag_n; (p >> 7) & 1; end
    def flag_v; (p >> 6) & 1; end
    def flag_b; (p >> 4) & 1; end
    def flag_d; (p >> 3) & 1; end
    def flag_i; (p >> 2) & 1; end
    def flag_z; (p >> 1) & 1; end
    def flag_c; p & 1; end

    def cpu_state
      {
        a: a,
        x: x,
        y: y,
        sp: sp,
        pc: pc,
        p: p,
        cycles: @cycle_count,
        halted: halted?,
        simulator_type: simulator_type
      }
    end

    def render_hires_color(chars_wide: 140, base_addr: HIRES_PAGE1_START)
      renderer = RHDL::Examples::MOS6502::ColorRenderer.new(chars_wide: chars_wide)

      if @sim
        page_end = base_addr + 0x2000 - 1
        hires_ram = Array.new(page_end + 1, 0)
        (base_addr..page_end).each do |addr|
          hires_ram[addr] = read_memory(addr)
        end
        return renderer.render(hires_ram, base_addr: base_addr)
      end

      renderer.render(@memory, base_addr: base_addr)
    end

    def status_string
      flags = ''
      flags += flag_n == 1 ? 'N' : 'n'
      flags += flag_v == 1 ? 'V' : 'v'
      flags += '-'
      flags += flag_b == 1 ? 'B' : 'b'
      flags += flag_d == 1 ? 'D' : 'd'
      flags += flag_i == 1 ? 'I' : 'i'
      flags += flag_z == 1 ? 'Z' : 'z'
      flags += flag_c == 1 ? 'C' : 'c'

      format("A:%02X X:%02X Y:%02X SP:%02X PC:%04X P:%02X [%s] Cycles:%d",
             a, x, y, sp, pc, p, flags, @cycle_count)
    end

    # Run N instructions using fast C++ batch execution
    # Returns array of [pc, opcode, sp] tuples
    def run_instructions_with_opcodes(n)
      return [] unless @sim && @sim_run_instructions_fn

      # Allocate buffers for results
      # Each opcode is packed as: (pc << 16) | (opcode << 8) | sp
      opcodes_buf = Fiddle::Pointer.malloc(n * 8)  # unsigned long = 8 bytes
      halted_buf = Fiddle::Pointer.malloc(4)       # unsigned int = 4 bytes

      count = @sim_run_instructions_fn.call(@sim.raw_context, n, opcodes_buf, n, halted_buf)
      @halted = halted_buf.to_s(4).unpack1('L') != 0

      # Unpack results
      results = []
      raw = opcodes_buf.to_s(count * 8)
      count.times do |i|
        packed = raw[i * 8, 8].unpack1('Q')
        pc = (packed >> 16) & 0xFFFF
        opcode = (packed >> 8) & 0xFF
        sp = packed & 0xFF
        results << [pc, opcode, sp]
      end

      results
    end

    private

    def verilog_simulator
      @verilog_simulator ||= RHDL::Codegen::Verilog::VerilogSimulator.new(
        backend: :verilator,
        build_dir: BUILD_DIR,
        library_basename: 'mos6502_sim',
        top_module: 'mos6502_cpu',
        verilator_prefix: 'Vmos6502_cpu',
        x_assign: '0',
        x_initial: 'unique'
      )
    end

    def check_verilator_available!
      verilog_simulator.ensure_backend_available!
    end

    def build_verilator_simulation
      verilog_simulator.prepare_build_dirs!

      # Export MOS6502 CPU to Verilog
      verilog_file = File.join(VERILOG_DIR, 'mos6502.v')
      verilog_codegen = File.expand_path('../../../../lib/rhdl/dsl/codegen.rb', __dir__)
      circt_codegen = File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__)
      export_deps = [__FILE__, verilog_codegen, circt_codegen].select { |p| File.exist?(p) }
      needs_export = !File.exist?(verilog_file) ||
                     export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

      if needs_export
        puts "  Exporting MOS6502 to Verilog..."
        export_verilog(verilog_file)
      end

      # Create C++ wrapper
      wrapper_file = File.join(VERILOG_DIR, 'sim_wrapper.cpp')
      header_file = File.join(VERILOG_DIR, 'sim_wrapper.h')
      create_cpp_wrapper(wrapper_file, header_file)

      # Check if we need to rebuild
      lib_file = shared_lib_path
      needs_build = !File.exist?(lib_file) ||
                    File.mtime(verilog_file) > File.mtime(lib_file) ||
                    File.mtime(wrapper_file) > File.mtime(lib_file)

      if needs_build
        puts "  Compiling with Verilator..."
        compile_verilator(verilog_file, wrapper_file)
      end

      # Load the shared library
      puts "  Loading Verilator simulation..."
      load_shared_library(lib_file)
    end

    def export_verilog(output_file)
      # Export CPU and all subcomponents
      all_verilog = []

      # Main CPU
      all_verilog << RHDL::Examples::MOS6502::CPU.to_verilog

      # Subcomponents
      [Registers, StatusRegister, ProgramCounter, StackPointer,
       InstructionRegister, AddressLatch, DataLatch, ControlUnit,
       ALU, InstructionDecoder, AddressGenerator, IndirectAddressCalc].each do |klass|
        begin
          all_verilog << klass.to_verilog
        rescue StandardError => e
          puts "    Warning: Could not export #{klass}: #{e.message}"
        end
      end

      File.write(output_file, all_verilog.join("\n\n"))
    end

    def create_cpp_wrapper(cpp_file, header_file)
      input_signal_names = ABI_INPUT_SIGNALS.map(&:first)
      output_signal_names = ABI_OUTPUT_SIGNALS.map(&:first)
      all_signal_names = input_signal_names + output_signal_names

      signal_id_lines = all_signal_names.each_with_index.map do |name, idx|
        "          SIGNAL_#{name.upcase.gsub(/[^A-Z0-9]+/, '_')} = #{idx}"
      end
      signal_name_lines = all_signal_names.map { |name| %("#{name}") }
      signal_width_lines = all_signal_names.map { |name| "#{abi_signal_widths_by_name.fetch(name)}u" }
      input_csv = input_signal_names.join(',')
      output_csv = output_signal_names.join(',')
      signal_peek_lines = {
        'addr' => 'ctx->dut->addr',
        'data_out' => 'ctx->dut->data_out',
        'rw' => 'ctx->dut->rw',
        'sync' => 'ctx->dut->sync',
        'reg_a' => 'ctx->dut->reg_a',
        'reg_x' => 'ctx->dut->reg_x',
        'reg_y' => 'ctx->dut->reg_y',
        'reg_sp' => 'ctx->dut->reg_sp',
        'reg_pc' => 'ctx->dut->reg_pc',
        'reg_p' => 'ctx->dut->reg_p',
        'opcode' => 'ctx->dut->opcode',
        'state' => 'ctx->dut->state',
        'halted' => 'ctx->dut->halted',
        'cycle_count' => 'ctx->dut->cycle_count'
      }.map do |name, expr|
        "          case SIGNAL_#{name.upcase.gsub(/[^A-Z0-9]+/, '_')}: return static_cast<unsigned int>(#{expr});"
      end
      signal_poke_lines = {
        'clk' => 'ctx->dut->clk',
        'rst' => 'ctx->dut->rst',
        'rdy' => 'ctx->dut->rdy',
        'irq' => 'ctx->dut->irq',
        'nmi' => 'ctx->dut->nmi',
        'data_in' => 'ctx->dut->data_in',
        'ext_pc_load_en' => 'ctx->dut->ext_pc_load_en',
        'ext_pc_load_data' => 'ctx->dut->ext_pc_load_data',
        'ext_a_load_en' => 'ctx->dut->ext_a_load_en',
        'ext_a_load_data' => 'ctx->dut->ext_a_load_data',
        'ext_x_load_en' => 'ctx->dut->ext_x_load_en',
        'ext_x_load_data' => 'ctx->dut->ext_x_load_data',
        'ext_y_load_en' => 'ctx->dut->ext_y_load_en',
        'ext_y_load_data' => 'ctx->dut->ext_y_load_data',
        'ext_sp_load_en' => 'ctx->dut->ext_sp_load_en',
        'ext_sp_load_data' => 'ctx->dut->ext_sp_load_data'
      }.map do |name, expr|
        "          case SIGNAL_#{name.upcase.gsub(/[^A-Z0-9]+/, '_')}: #{expr} = value; return 1;"
      end

      header_content = <<~HEADER
        #ifndef SIM_WRAPPER_H
        #define SIM_WRAPPER_H

        #include <stddef.h>

        #ifdef __cplusplus
        extern "C" {
        #endif

        void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** error_out);
        void* sim_create_legacy(void);
        void sim_destroy(void* sim);
        void sim_free_error(char* error);
        void sim_free_string(char* str);
        void* sim_wasm_alloc(size_t size);
        void sim_wasm_dealloc(void* ptr, size_t size);
        int sim_get_caps(const void* sim, unsigned int* caps_out);
        int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value);
        int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out);
        int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value);
        size_t sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, size_t out_len);
        int runner_get_caps(const void* sim, void* caps_out);
        size_t runner_mem(void* sim, unsigned int op, unsigned int space, size_t offset, void* data, size_t len, unsigned int flags);
        int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, void* result_out);
        int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1);
        unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0);
        void sim_reset(void* sim);
        void sim_eval(void* sim);
        void sim_poke(void* sim, const char* name, unsigned int value);
        unsigned int sim_peek(void* sim, const char* name);
        void sim_write_memory(void* sim, unsigned int addr, unsigned char value);
        unsigned char sim_read_memory(void* sim, unsigned int addr);
        void sim_run_cycles(void* sim, unsigned int n_cycles, unsigned int* halted_out);
        void sim_load_memory(void* sim, const unsigned char* data, unsigned int offset, unsigned int len);
        unsigned int sim_run_instructions_with_opcodes(void* sim, unsigned int n, unsigned long* opcodes_out, unsigned int capacity, unsigned int* halted_out);

        #ifdef __cplusplus
        }
        #endif

        #endif // SIM_WRAPPER_H
      HEADER

      cpp_content = <<~CPP
        #include "Vmos6502_cpu.h"
        #include "verilated.h"
        #include "sim_wrapper.h"
        #include <cstdlib>
        #include <cstring>

        double sc_time_stamp() { return 0; }

        static constexpr unsigned int SIM_CAP_SIGNAL_INDEX = 1u << 0;
        static constexpr unsigned int SIM_CAP_RUNNER = 1u << 6;

        static constexpr unsigned int SIM_SIGNAL_HAS = 0u;
        static constexpr unsigned int SIM_SIGNAL_GET_INDEX = 1u;
        static constexpr unsigned int SIM_SIGNAL_PEEK = 2u;
        static constexpr unsigned int SIM_SIGNAL_POKE = 3u;
        static constexpr unsigned int SIM_SIGNAL_PEEK_INDEX = 4u;
        static constexpr unsigned int SIM_SIGNAL_POKE_INDEX = 5u;

        static constexpr unsigned int SIM_EXEC_EVALUATE = 0u;
        static constexpr unsigned int SIM_EXEC_TICK = 1u;
        static constexpr unsigned int SIM_EXEC_TICK_FORCED = 2u;
        static constexpr unsigned int SIM_EXEC_RESET = 5u;
        static constexpr unsigned int SIM_EXEC_RUN_TICKS = 6u;
        static constexpr unsigned int SIM_EXEC_SIGNAL_COUNT = 7u;
        static constexpr unsigned int SIM_EXEC_REG_COUNT = 8u;

        static constexpr unsigned int SIM_BLOB_INPUT_NAMES = 0u;
        static constexpr unsigned int SIM_BLOB_OUTPUT_NAMES = 1u;

        static constexpr int RUNNER_KIND_MOS6502 = 2;
        static constexpr unsigned int RUNNER_MEM_OP_LOAD = 0u;
        static constexpr unsigned int RUNNER_MEM_OP_READ = 1u;
        static constexpr unsigned int RUNNER_MEM_OP_WRITE = 2u;
        static constexpr unsigned int RUNNER_MEM_SPACE_MAIN = 0u;
        static constexpr unsigned int RUNNER_MEM_SPACE_ROM = 1u;
        static constexpr unsigned int RUNNER_CONTROL_SET_RESET_VECTOR = 0u;
        static constexpr unsigned int RUNNER_PROBE_KIND = 0u;
        static constexpr unsigned int RUNNER_PROBE_IS_MODE = 1u;
        static constexpr unsigned int RUNNER_PROBE_SIGNAL = 9u;

        struct RunnerCaps {
          int kind;
          unsigned int mem_spaces;
          unsigned int control_ops;
          unsigned int probe_ops;
        };

        struct RunnerRunResult {
          int text_dirty;
          int key_cleared;
          unsigned int cycles_run;
          unsigned int speaker_toggles;
          unsigned int frames_completed;
        };

        enum SignalId {
#{signal_id_lines.join(",\n")}
        };

        static constexpr unsigned int SIGNAL_COUNT = #{all_signal_names.length}u;
        static const char* const kSignalNames[SIGNAL_COUNT] = {
#{signal_name_lines.map { |line| "          #{line}" }.join(",\n")}
        };
        static const unsigned int kSignalWidths[SIGNAL_COUNT] = {
#{signal_width_lines.map { |line| "          #{line}" }.join(",\n")}
        };
        static const char kInputNamesCsv[] = "#{input_csv}";
        static const char kOutputNamesCsv[] = "#{output_csv}";

        struct SimContext {
          Vmos6502_cpu* dut;
          unsigned char memory[65536];
        };

        static int signal_index_from_name(const char* name) {
          if (!name) return -1;
          for (unsigned int i = 0; i < SIGNAL_COUNT; ++i) {
            if (std::strcmp(name, kSignalNames[i]) == 0) return static_cast<int>(i);
          }
          return -1;
        }

        static unsigned int signal_peek_by_id(SimContext* ctx, SignalId id) {
          switch (id) {
#{signal_peek_lines.join("\n")}
          default:
            return 0;
          }
        }

        static int signal_poke_by_id(SimContext* ctx, SignalId id, unsigned int value) {
          switch (id) {
#{signal_poke_lines.join("\n")}
          default:
            return 0;
          }
        }

        static size_t copy_blob(unsigned char* out_ptr, size_t out_len, const char* text) {
          const size_t required = text ? std::strlen(text) : 0u;
          if (out_ptr && out_len && required) {
            const size_t copy_len = required < out_len ? required : out_len;
            std::memcpy(out_ptr, text, copy_len);
          }
          return required;
        }

        extern "C" {

        void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** error_out) {
          (void)json;
          (void)json_len;
          (void)sub_cycles;
          if (error_out) *error_out = nullptr;

          const char* empty_args[] = {""};
          Verilated::commandArgs(1, empty_args);

          SimContext* ctx = new SimContext();
          ctx->dut = new Vmos6502_cpu();
          std::memset(ctx->memory, 0, sizeof(ctx->memory));

          ctx->dut->clk = 0;
          ctx->dut->rst = 1;
          ctx->dut->rdy = 1;
          ctx->dut->irq = 1;
          ctx->dut->nmi = 1;
          ctx->dut->data_in = 0;
          ctx->dut->ext_pc_load_en = 0;
          ctx->dut->ext_pc_load_data = 0;
          ctx->dut->ext_a_load_en = 0;
          ctx->dut->ext_a_load_data = 0;
          ctx->dut->ext_x_load_en = 0;
          ctx->dut->ext_x_load_data = 0;
          ctx->dut->ext_y_load_en = 0;
          ctx->dut->ext_y_load_data = 0;
          ctx->dut->ext_sp_load_en = 0;
          ctx->dut->ext_sp_load_data = 0;
          ctx->dut->eval();

          ctx->memory[0xFFFC] = 0x00;
          ctx->memory[0xFFFD] = 0x80;

          return ctx;
        }

        void* sim_create_legacy(void) {
          return sim_create(nullptr, 0, 0, nullptr);
        }

        void sim_destroy(void* sim) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return;
          delete ctx->dut;
          delete ctx;
        }

        void sim_free_error(char* error) {
          if (error) std::free(error);
        }

        void sim_free_string(char* str) {
          if (str) std::free(str);
        }

        void* sim_wasm_alloc(size_t size) {
          return std::malloc(size > 0 ? size : 1);
        }

        void sim_wasm_dealloc(void* ptr, size_t size) {
          (void)size;
          std::free(ptr);
        }

        int sim_get_caps(const void* sim, unsigned int* caps_out) {
          if (!sim || !caps_out) return 0;
          *caps_out = SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER;
          return 1;
        }

        void sim_reset(void* sim) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return;

          ctx->dut->clk = 0;
          ctx->dut->rdy = 1;
          ctx->dut->irq = 1;
          ctx->dut->nmi = 1;
          ctx->dut->data_in = 0;
          ctx->dut->ext_pc_load_en = 0;
          ctx->dut->ext_pc_load_data = 0;
          ctx->dut->ext_a_load_en = 0;
          ctx->dut->ext_a_load_data = 0;
          ctx->dut->ext_x_load_en = 0;
          ctx->dut->ext_x_load_data = 0;
          ctx->dut->ext_y_load_en = 0;
          ctx->dut->ext_y_load_data = 0;
          ctx->dut->ext_sp_load_en = 0;
          ctx->dut->ext_sp_load_data = 0;

          auto clock_cycle = [&](unsigned int rst_val) {
            ctx->dut->rst = rst_val;
            ctx->dut->clk = 0;
            ctx->dut->eval();

            unsigned int addr = ctx->dut->addr;
            unsigned int rw = ctx->dut->rw;
            unsigned char write_data = ctx->dut->data_out & 0xFF;

            ctx->dut->data_in = ctx->memory[addr];
            ctx->dut->eval();

            ctx->dut->clk = 1;
            ctx->dut->eval();

            if (rw == 0) {
              ctx->memory[addr] = write_data;
            }
          };

          clock_cycle(1);
          for (int i = 0; i < 5; ++i) {
            clock_cycle(0);
          }

          unsigned int reset_lo = ctx->memory[0xFFFC];
          unsigned int reset_hi = ctx->memory[0xFFFD];
          unsigned int target_addr = (reset_hi << 8) | reset_lo;

          ctx->dut->rst = 0;
          ctx->dut->ext_pc_load_data = target_addr;
          ctx->dut->ext_pc_load_en = 1;
          ctx->dut->clk = 0;
          ctx->dut->eval();
          ctx->dut->data_in = ctx->memory[target_addr];
          ctx->dut->eval();
          ctx->dut->clk = 1;
          ctx->dut->eval();
          ctx->dut->ext_pc_load_en = 0;
          ctx->dut->eval();
        }

        void sim_eval(void* sim) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return;
          ctx->dut->eval();
        }

        void sim_poke(void* sim, const char* name, unsigned int value) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx || !name) return;
          int idx = signal_index_from_name(name);
          if (idx < 0) return;
          signal_poke_by_id(ctx, static_cast<SignalId>(idx), value);
        }

        unsigned int sim_peek(void* sim, const char* name) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx || !name) return 0;
          int idx = signal_index_from_name(name);
          return idx < 0 ? 0 : signal_peek_by_id(ctx, static_cast<SignalId>(idx));
        }

        int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) {
            if (out_value) *out_value = 0;
            return 0;
          }

          int resolved_idx = name ? signal_index_from_name(name) : static_cast<int>(idx);
          switch (op) {
          case SIM_SIGNAL_HAS:
            if (out_value) *out_value = resolved_idx >= 0 ? 1ul : 0ul;
            return 1;
          case SIM_SIGNAL_GET_INDEX:
            if (resolved_idx < 0) {
              if (out_value) *out_value = 0;
              return 0;
            }
            if (out_value) *out_value = static_cast<unsigned long>(resolved_idx);
            return 1;
          case SIM_SIGNAL_PEEK:
          case SIM_SIGNAL_PEEK_INDEX:
            if (resolved_idx < 0 || static_cast<unsigned int>(resolved_idx) >= SIGNAL_COUNT) {
              if (out_value) *out_value = 0;
              return 0;
            }
            if (out_value) *out_value = signal_peek_by_id(ctx, static_cast<SignalId>(resolved_idx));
            return 1;
          case SIM_SIGNAL_POKE:
          case SIM_SIGNAL_POKE_INDEX:
            if (resolved_idx < 0 || static_cast<unsigned int>(resolved_idx) >= SIGNAL_COUNT) {
              if (out_value) *out_value = 0;
              return 0;
            }
            if (out_value) *out_value = 1;
            return signal_poke_by_id(ctx, static_cast<SignalId>(resolved_idx), static_cast<unsigned int>(value));
          default:
            if (out_value) *out_value = 0;
            return 0;
          }
        }

        void sim_write_memory(void* sim, unsigned int addr, unsigned char value) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx || addr >= sizeof(ctx->memory)) return;
          ctx->memory[addr] = value;
        }

        unsigned char sim_read_memory(void* sim, unsigned int addr) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx || addr >= sizeof(ctx->memory)) return 0;
          return ctx->memory[addr];
        }

        void sim_run_cycles(void* sim, unsigned int n_cycles, unsigned int* halted_out) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return;
          if (halted_out) *halted_out = 0;

          for (unsigned int i = 0; i < n_cycles; ++i) {
            ctx->dut->clk = 0;
            ctx->dut->eval();

            unsigned int addr = ctx->dut->addr;
            unsigned int rw = ctx->dut->rw;
            unsigned char write_data = ctx->dut->data_out & 0xFF;

            ctx->dut->data_in = ctx->memory[addr];
            ctx->dut->eval();

            ctx->dut->clk = 1;
            ctx->dut->eval();

            if (rw == 0) {
              ctx->memory[addr] = write_data;
            }

            if (ctx->dut->halted) {
              if (halted_out) *halted_out = 1;
              break;
            }
          }
        }

        int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out) {
          (void)arg1;
          (void)error_out;
          if (out_value) *out_value = 0;

          switch (op) {
          case SIM_EXEC_EVALUATE:
            sim_eval(sim);
            return 1;
          case SIM_EXEC_TICK:
          case SIM_EXEC_TICK_FORCED: {
            unsigned int halted = 0;
            sim_run_cycles(sim, 1, &halted);
            if (out_value) *out_value = halted;
            return 1;
          }
          case SIM_EXEC_RESET:
            sim_reset(sim);
            return 1;
          case SIM_EXEC_RUN_TICKS: {
            unsigned int halted = 0;
            sim_run_cycles(sim, static_cast<unsigned int>(arg0), &halted);
            if (out_value) *out_value = halted;
            return 1;
          }
          case SIM_EXEC_SIGNAL_COUNT:
            if (out_value) *out_value = SIGNAL_COUNT;
            return 1;
          case SIM_EXEC_REG_COUNT:
            return 1;
          default:
            return 0;
          }
        }

        int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
          (void)sim;
          (void)op;
          (void)str_arg;
          if (out_value) *out_value = 0;
          return 0;
        }

        size_t sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, size_t out_len) {
          (void)sim;
          switch (op) {
          case SIM_BLOB_INPUT_NAMES:
            return copy_blob(out_ptr, out_len, kInputNamesCsv);
          case SIM_BLOB_OUTPUT_NAMES:
            return copy_blob(out_ptr, out_len, kOutputNamesCsv);
          default:
            return 0;
          }
        }

        void sim_load_memory(void* sim, const unsigned char* data, unsigned int offset, unsigned int len) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx || !data) return;
          for (unsigned int i = 0; i < len && (offset + i) < sizeof(ctx->memory); ++i) {
            ctx->memory[offset + i] = data[i];
          }
        }

        unsigned int sim_run_instructions_with_opcodes(void* sim, unsigned int n, unsigned long* opcodes_out, unsigned int capacity, unsigned int* halted_out) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return 0;
          if (halted_out) *halted_out = 0;

          unsigned int instruction_count = 0;
          unsigned int max_cycles = n * 10;
          unsigned int cycles = 0;
          unsigned int last_state = ctx->dut->state;
          const unsigned int STATE_DECODE = 0x02;

          while (instruction_count < n && cycles < max_cycles) {
            ctx->dut->clk = 0;
            ctx->dut->eval();

            unsigned int addr = ctx->dut->addr;
            unsigned int rw = ctx->dut->rw;
            unsigned char write_data = ctx->dut->data_out & 0xFF;

            ctx->dut->data_in = ctx->memory[addr];
            ctx->dut->eval();

            ctx->dut->clk = 1;
            ctx->dut->eval();
            cycles++;

            if (rw == 0) {
              ctx->memory[addr] = write_data;
            }

            unsigned int current_state = ctx->dut->state;
            if (current_state == STATE_DECODE && last_state != STATE_DECODE) {
              unsigned int opcode = ctx->dut->opcode & 0xFF;
              unsigned int pc = (ctx->dut->reg_pc - 1) & 0xFFFF;
              unsigned int sp = ctx->dut->reg_sp & 0xFF;
              if (instruction_count < capacity) {
                opcodes_out[instruction_count] = ((unsigned long)pc << 16) | ((unsigned long)opcode << 8) | sp;
              }
              instruction_count++;
            }
            last_state = current_state;

            if (ctx->dut->halted) {
              if (halted_out) *halted_out = 1;
              break;
            }
          }
          return instruction_count;
        }

        int runner_get_caps(const void* sim, void* caps_out) {
          if (!sim || !caps_out) return 0;
          RunnerCaps* caps = static_cast<RunnerCaps*>(caps_out);
          caps->kind = RUNNER_KIND_MOS6502;
          caps->mem_spaces = (1u << RUNNER_MEM_SPACE_MAIN) | (1u << RUNNER_MEM_SPACE_ROM);
          caps->control_ops = (1u << RUNNER_CONTROL_SET_RESET_VECTOR);
          caps->probe_ops = (1u << RUNNER_PROBE_KIND) | (1u << RUNNER_PROBE_IS_MODE) | (1u << RUNNER_PROBE_SIGNAL);
          return 1;
        }

        size_t runner_mem(void* sim, unsigned int op, unsigned int space, size_t offset, void* data, size_t len, unsigned int flags) {
          (void)flags;
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx || !data) return 0;
          if (space != RUNNER_MEM_SPACE_MAIN && space != RUNNER_MEM_SPACE_ROM) return 0;

          unsigned char* bytes = static_cast<unsigned char*>(data);
          switch (op) {
          case RUNNER_MEM_OP_LOAD:
          case RUNNER_MEM_OP_WRITE: {
            size_t written = 0;
            for (size_t i = 0; i < len && (offset + i) < sizeof(ctx->memory); ++i) {
              ctx->memory[offset + i] = bytes[i];
              written++;
            }
            return written;
          }
          case RUNNER_MEM_OP_READ: {
            size_t read = 0;
            for (size_t i = 0; i < len && (offset + i) < sizeof(ctx->memory); ++i) {
              bytes[i] = ctx->memory[offset + i];
              read++;
            }
            return read;
          }
          default:
            return 0;
          }
        }

        int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, void* result_out) {
          (void)key_data;
          (void)key_ready;
          (void)mode;

          unsigned int halted = 0;
          sim_run_cycles(sim, cycles, &halted);
          if (result_out) {
            RunnerRunResult* result = static_cast<RunnerRunResult*>(result_out);
            result->text_dirty = 0;
            result->key_cleared = 0;
            result->cycles_run = cycles;
            result->speaker_toggles = 0;
            result->frames_completed = 0;
          }
          return 1;
        }

        int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) {
          (void)arg1;
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return 0;

          switch (op) {
          case RUNNER_CONTROL_SET_RESET_VECTOR:
            ctx->memory[0xFFFC] = static_cast<unsigned char>(arg0 & 0xFFu);
            ctx->memory[0xFFFD] = static_cast<unsigned char>((arg0 >> 8) & 0xFFu);
            return 1;
          default:
            return 0;
          }
        }

        unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0) {
          SimContext* ctx = static_cast<SimContext*>(sim);
          if (!ctx) return 0;

          switch (op) {
          case RUNNER_PROBE_KIND:
            return RUNNER_KIND_MOS6502;
          case RUNNER_PROBE_IS_MODE:
            return 0;
          case RUNNER_PROBE_SIGNAL:
            return arg0 < SIGNAL_COUNT ? signal_peek_by_id(ctx, static_cast<SignalId>(arg0)) : 0;
          default:
            return 0;
          }
        }

        } // extern "C"
      CPP

      write_file_if_changed(header_file, header_content)
      write_file_if_changed(cpp_file, cpp_content)
    end

    def write_file_if_changed(path, content)
      verilog_simulator.write_file_if_changed(path, content)
    end

    def compile_verilator(verilog_file, wrapper_file)
      verilog_simulator.compile_backend(verilog_file: verilog_file, wrapper_file: wrapper_file)
    end

    def build_shared_library(_wrapper_file = nil)
      verilog_simulator.build_shared_library
    end

    def shared_lib_path
      verilog_simulator.shared_library_path
    end

    def load_shared_library(lib_path)
      verilog_simulator.load_library!(lib_path)
      @sim = RHDL::Sim::Native::Verilog::Verilator::Runtime.open(
        lib_path: lib_path,
        signal_widths_by_name: abi_signal_widths_by_name,
        signal_widths_by_idx: abi_signal_widths_by_idx,
        backend_label: 'MOS6502 Verilator'
      )
      ensure_runner_abi!(@sim, expected_kind: :mos6502, backend_label: 'MOS6502 Verilator')
      sim_lib = @sim.instance_variable_get(:@lib)
      @sim_run_instructions_fn = Fiddle::Function.new(
        sim_lib['sim_run_instructions_with_opcodes'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )
    end

    def reset_simulation
      @sim&.reset
    end

    def ensure_runner_abi!(sim, expected_kind:, backend_label:)
      unless sim.runner_supported?
        sim.close
        raise RuntimeError, "#{backend_label} shared library does not expose runner ABI"
      end

      actual_kind = sim.runner_kind
      return if actual_kind == expected_kind

      sim.close
      raise RuntimeError, "#{backend_label} shared library exposes runner kind #{actual_kind.inspect}, expected #{expected_kind.inspect}"
    end

    def verilator_poke(name, value)
      return unless @sim
      @sim.poke(name, value.to_i)
    end

    def verilator_peek(name)
      return 0 unless @sim
      @sim.peek(name)
    end

    def verilator_eval
      @sim&.evaluate
    end

    def verilator_write_memory(addr, value)
      return unless @sim
      @sim.runner_write_memory(addr, [value.to_i & 0xFF], mapped: false)
    end
      end
    end
  end
end
