# frozen_string_literal: true

# MOS 6502 Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the MOS6502 CPU HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface with batch cycle execution to avoid
# FFI overhead.
#
# Usage:
#   runner = RHDL::Examples::MOS6502::VerilatorRunner.new
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

module RHDL
  module Examples
    module MOS6502
      # Verilator-based runner for MOS 6502 simulation
      # Compiles RHDL Verilog export to native code via Verilator
      class VerilatorRunner
    # Build directory for Verilator output
    BUILD_DIR = File.expand_path('../../../.verilator_build_6502', __dir__)
    VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
    OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')

    attr_reader :cycle_count

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
      # Bulk load into C++ side
      if @sim_load_memory_fn && @sim_ctx
        data_ptr = Fiddle::Pointer[bytes.pack('C*')]
        @sim_load_memory_fn.call(@sim_ctx, data_ptr, base_addr, bytes.size)
      end
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
      verilator_write_memory(addr, byte) if @sim_write_memory_fn && @sim_ctx
    end

    # Read a single byte from memory
    def read_memory(addr)
      addr = addr & 0xFFFF
      if @sim_read_memory_fn && @sim_ctx
        return @sim_read_memory_fn.call(@sim_ctx, addr) & 0xFF
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
      if @sim_run_cycles_fn && @sim_ctx
        halted_ptr = Fiddle::Pointer.malloc(4)
        @sim_run_cycles_fn.call(@sim_ctx, n, halted_ptr)
        halted_val = halted_ptr.to_s(4).unpack1('L')
        @halted = (halted_val != 0)
        @cycle_count += n
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
        verilator_write_memory(addr, write_data) if @sim_write_memory_fn && @sim_ctx
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
      return [] unless @sim_ctx && @sim_run_instructions_fn

      # Allocate buffers for results
      # Each opcode is packed as: (pc << 16) | (opcode << 8) | sp
      opcodes_buf = Fiddle::Pointer.malloc(n * 8)  # unsigned long = 8 bytes
      halted_buf = Fiddle::Pointer.malloc(4)       # unsigned int = 4 bytes

      count = @sim_run_instructions_fn.call(@sim_ctx, n, opcodes_buf, n, halted_buf)
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

    def check_verilator_available!
      verilator_path = ENV['PATH'].split(File::PATH_SEPARATOR).find do |path|
        File.executable?(File.join(path, 'verilator'))
      end

      unless verilator_path
        raise LoadError, <<~MSG
          Verilator not found in PATH.
          Install Verilator:
            Ubuntu/Debian: sudo apt-get install verilator
            macOS: brew install verilator
            Fedora: sudo dnf install verilator
        MSG
      end
    end

    def build_verilator_simulation
      FileUtils.mkdir_p(VERILOG_DIR)
      FileUtils.mkdir_p(OBJ_DIR)

      # Export MOS6502 CPU to Verilog
      verilog_file = File.join(VERILOG_DIR, 'mos6502.v')
      verilog_codegen = File.expand_path('../../../../lib/rhdl/codegen/verilog/verilog.rb', __dir__)
      export_deps = [__FILE__, verilog_codegen].select { |p| File.exist?(p) }
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
      header_content = <<~HEADER
        #ifndef SIM_WRAPPER_H
        #define SIM_WRAPPER_H

        #ifdef __cplusplus
        extern "C" {
        #endif

        void* sim_create(void);
        void sim_destroy(void* sim);
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
        #include <cstring>

        // Verilator time stamp function (required by verilator runtime on some platforms)
        double sc_time_stamp() { return 0; }

        struct SimContext {
            Vmos6502_cpu* dut;
            unsigned char memory[65536];  // 64KB memory
        };

        extern "C" {

        void* sim_create(void) {
            const char* empty_args[] = {""};
            Verilated::commandArgs(1, empty_args);
            SimContext* ctx = new SimContext();
            ctx->dut = new Vmos6502_cpu();
            memset(ctx->memory, 0, sizeof(ctx->memory));

            // Initialize inputs to safe defaults
            ctx->dut->clk = 0;
            ctx->dut->rst = 1;  // Start in reset
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

            // Run initial eval to trigger initial block execution
            ctx->dut->eval();

            return ctx;
        }

        void sim_destroy(void* sim) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            delete ctx->dut;
            delete ctx;
        }

        void sim_reset(void* sim) {
            SimContext* ctx = static_cast<SimContext*>(sim);

            // Match examples/mos6502/hdl/harness.rb reset sequence exactly:
            //   1) 1 cycle with rst=1
            //   2) 5 cycles with rst=0 (reach FETCH state)
            //   3) ext_pc_load_en cycle to load PC from reset vector and fetch first opcode

            // Initialize inputs to safe defaults
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

            // Low phase
            ctx->dut->clk = 0;
            ctx->dut->eval();

                unsigned int addr = ctx->dut->addr;
                unsigned int rw = ctx->dut->rw;
                unsigned char write_data = ctx->dut->data_out & 0xFF;

            // Provide memory data for the high phase (combinational read)
            ctx->dut->data_in = ctx->memory[addr];
            ctx->dut->eval();

            // High phase (posedge)
            ctx->dut->clk = 1;
            ctx->dut->eval();

                // Commit write on rising edge
                if (rw == 0) {
                    ctx->memory[addr] = write_data;
                }
            };

            // Pulse reset for 1 cycle
            clock_cycle(1);

            // Run 5 more cycles with reset released
            for (int i = 0; i < 5; i++) {
                clock_cycle(0);
            }

            // Load PC from reset vector
            unsigned int reset_lo = ctx->memory[0xFFFC];
            unsigned int reset_hi = ctx->memory[0xFFFD];
            unsigned int target_addr = (reset_hi << 8) | reset_lo;

            // Provide opcode from target address during the ext_pc_load cycle
            ctx->dut->rst = 0;
            ctx->dut->ext_pc_load_data = target_addr;
            ctx->dut->ext_pc_load_en = 1;

            // Low phase
            ctx->dut->clk = 0;
            ctx->dut->eval();

            // High phase: latch PC and fetch opcode
            ctx->dut->data_in = ctx->memory[target_addr];
            ctx->dut->eval();
            ctx->dut->clk = 1;
            ctx->dut->eval();

            // Clear external load enables
            ctx->dut->ext_pc_load_en = 0;
            ctx->dut->eval();
        }

        void sim_eval(void* sim) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            ctx->dut->eval();
        }

        void sim_poke(void* sim, const char* name, unsigned int value) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            if (strcmp(name, "clk") == 0) ctx->dut->clk = value;
            else if (strcmp(name, "rst") == 0) ctx->dut->rst = value;
            else if (strcmp(name, "rdy") == 0) ctx->dut->rdy = value;
            else if (strcmp(name, "irq") == 0) ctx->dut->irq = value;
            else if (strcmp(name, "nmi") == 0) ctx->dut->nmi = value;
            else if (strcmp(name, "data_in") == 0) ctx->dut->data_in = value;
            else if (strcmp(name, "ext_pc_load_en") == 0) ctx->dut->ext_pc_load_en = value;
            else if (strcmp(name, "ext_pc_load_data") == 0) ctx->dut->ext_pc_load_data = value;
            else if (strcmp(name, "ext_a_load_en") == 0) ctx->dut->ext_a_load_en = value;
            else if (strcmp(name, "ext_a_load_data") == 0) ctx->dut->ext_a_load_data = value;
            else if (strcmp(name, "ext_x_load_en") == 0) ctx->dut->ext_x_load_en = value;
            else if (strcmp(name, "ext_x_load_data") == 0) ctx->dut->ext_x_load_data = value;
            else if (strcmp(name, "ext_y_load_en") == 0) ctx->dut->ext_y_load_en = value;
            else if (strcmp(name, "ext_y_load_data") == 0) ctx->dut->ext_y_load_data = value;
            else if (strcmp(name, "ext_sp_load_en") == 0) ctx->dut->ext_sp_load_en = value;
            else if (strcmp(name, "ext_sp_load_data") == 0) ctx->dut->ext_sp_load_data = value;
        }

        unsigned int sim_peek(void* sim, const char* name) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            if (strcmp(name, "addr") == 0) return ctx->dut->addr;
            else if (strcmp(name, "data_out") == 0) return ctx->dut->data_out;
            else if (strcmp(name, "rw") == 0) return ctx->dut->rw;
            else if (strcmp(name, "sync") == 0) return ctx->dut->sync;
            else if (strcmp(name, "reg_a") == 0) return ctx->dut->reg_a;
            else if (strcmp(name, "reg_x") == 0) return ctx->dut->reg_x;
            else if (strcmp(name, "reg_y") == 0) return ctx->dut->reg_y;
            else if (strcmp(name, "reg_sp") == 0) return ctx->dut->reg_sp;
            else if (strcmp(name, "reg_pc") == 0) return ctx->dut->reg_pc;
            else if (strcmp(name, "reg_p") == 0) return ctx->dut->reg_p;
            else if (strcmp(name, "opcode") == 0) return ctx->dut->opcode;
            else if (strcmp(name, "state") == 0) return ctx->dut->state;
            else if (strcmp(name, "halted") == 0) return ctx->dut->halted;
            else if (strcmp(name, "cycle_count") == 0) return ctx->dut->cycle_count;
            return 0;
        }

        void sim_write_memory(void* sim, unsigned int addr, unsigned char value) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            if (addr < sizeof(ctx->memory)) {
                ctx->memory[addr] = value;
            }
        }

        unsigned char sim_read_memory(void* sim, unsigned int addr) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            if (addr < sizeof(ctx->memory)) {
                return ctx->memory[addr];
            }
            return 0;
        }

        // Batch cycle execution - runs N clock cycles without FFI overhead
        void sim_run_cycles(void* sim, unsigned int n_cycles, unsigned int* halted_out) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            *halted_out = 0;

            for (unsigned int i = 0; i < n_cycles; i++) {
                // Low phase: produce addr/rw/data_out
                ctx->dut->clk = 0;
                ctx->dut->eval();

                unsigned int addr = ctx->dut->addr;
                unsigned int rw = ctx->dut->rw;
                unsigned char write_data = ctx->dut->data_out & 0xFF;

                // Combinational read value provided to CPU during high phase
                ctx->dut->data_in = ctx->memory[addr];
                ctx->dut->eval();

                // High phase (posedge)
                ctx->dut->clk = 1;
                ctx->dut->eval();

                // Commit write on rising edge using low-phase data_out
                if (rw == 0) {
                    ctx->memory[addr] = write_data;
                }

                // Check halted
                if (ctx->dut->halted) {
                    *halted_out = 1;
                    break;
                }
            }
        }

        // Load memory in bulk (faster than individual writes)
        void sim_load_memory(void* sim, const unsigned char* data, unsigned int offset, unsigned int len) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            for (unsigned int i = 0; i < len && (offset + i) < sizeof(ctx->memory); i++) {
                ctx->memory[offset + i] = data[i];
            }
        }

        // Run until N instructions complete, capturing (pc, opcode, sp) for each
        // Each opcode_tuple is packed as: (pc << 16) | (opcode << 8) | sp
        // STATE_DECODE = 0x02
        unsigned int sim_run_instructions_with_opcodes(void* sim, unsigned int n, unsigned long* opcodes_out, unsigned int capacity, unsigned int* halted_out) {
            SimContext* ctx = static_cast<SimContext*>(sim);
            *halted_out = 0;
            unsigned int instruction_count = 0;
            unsigned int max_cycles = n * 10;  // Safety limit
            unsigned int cycles = 0;
            unsigned int last_state = ctx->dut->state;
            const unsigned int STATE_DECODE = 0x02;

            while (instruction_count < n && cycles < max_cycles) {
                // Low phase
                ctx->dut->clk = 0;
                ctx->dut->eval();

                unsigned int addr = ctx->dut->addr;
                unsigned int rw = ctx->dut->rw;
                unsigned char write_data = ctx->dut->data_out & 0xFF;

                // Provide memory data for high phase
                ctx->dut->data_in = ctx->memory[addr];
                ctx->dut->eval();

                // High phase (posedge)
                ctx->dut->clk = 1;
                ctx->dut->eval();
                cycles++;

                // Commit write on rising edge
                if (rw == 0) {
                    ctx->memory[addr] = write_data;
                }

                // Check for state transition to DECODE
                unsigned int current_state = ctx->dut->state;
                if (current_state == STATE_DECODE && last_state != STATE_DECODE) {
                    unsigned int opcode = ctx->dut->opcode & 0xFF;
                    unsigned int pc = (ctx->dut->reg_pc - 1) & 0xFFFF;  // PC points past opcode
                    unsigned int sp = ctx->dut->reg_sp & 0xFF;
                    if (instruction_count < capacity) {
                        opcodes_out[instruction_count] = ((unsigned long)pc << 16) | ((unsigned long)opcode << 8) | sp;
                    }
                    instruction_count++;
                }
                last_state = current_state;

                // Check halted
                if (ctx->dut->halted) {
                    *halted_out = 1;
                    break;
                }
            }
            return instruction_count;
        }

        } // extern "C"
      CPP

      write_file_if_changed(header_file, header_content)
      write_file_if_changed(cpp_file, cpp_content)
    end

    def write_file_if_changed(path, content)
      return if File.exist?(path) && File.read(path) == content
      File.write(path, content)
    end

    def compile_verilator(verilog_file, wrapper_file)
      # Determine library suffix
      lib_suffix = case RbConfig::CONFIG['host_os']
                   when /darwin/ then 'dylib'
                   when /mswin|mingw/ then 'dll'
                   else 'so'
                   end

      lib_name = "libmos6502_sim.#{lib_suffix}"
      lib_path = File.join(OBJ_DIR, lib_name)

      # Verilate the design - top module is mos6502_cpu
      # NOTE: --threads tested but 44x SLOWER due to sync overhead on sequential CPU
      verilate_cmd = [
        'verilator',
        '--cc',
        '--top-module', 'mos6502_cpu',
        # Optimization flags
        '-O3',                  # Maximum Verilator optimization
        '--x-assign', '0',      # Initialize X to 0 (required for proper simulation)
        '--x-initial', 'unique', # Proper initial block handling (required for timing generator)
        '--noassert',           # Disable assertions
        # Warning suppressions
        '-Wno-fatal',           # Continue despite warnings
        '-Wno-WIDTHEXPAND',     # Suppress width expansion warnings
        '-Wno-WIDTHTRUNC',      # Suppress width truncation warnings
        '-Wno-UNOPTFLAT',       # Suppress unoptimized flattening warnings
        '-Wno-PINMISSING',      # Suppress missing pin warnings
        # C++ compiler flags for performance
        '-CFLAGS', '-fPIC -O3 -march=native',
        '-LDFLAGS', '-shared',
        '--Mdir', OBJ_DIR,
        '--prefix', 'Vmos6502_cpu',
        '-o', lib_name,
        wrapper_file,
        verilog_file
      ]

      # Redirect build output to log file
      log_file = File.join(BUILD_DIR, 'build.log')
      File.open(log_file, 'w') do |log|
        Dir.chdir(VERILOG_DIR) do
          result = system(*verilate_cmd, out: log, err: log)
          unless result
            raise "Verilator compilation failed. See #{log_file} for details."
          end
        end

        # Build with clang++ for better optimization
        # Must pass CXX= on command line to override verilated.mk's hardcoded g++
        Dir.chdir(OBJ_DIR) do
          result = system('make', '-f', 'Vmos6502_cpu.mk', 'CXX=clang++', out: log, err: log)
          unless result
            raise "Verilator make failed. See #{log_file} for details."
          end
        end
      end

      # On some platforms (notably macOS), Verilator's make output may not update the
      # requested shared library even if compilation succeeds. Ensure the dylib/so
      # is freshly linked from the static archives when needed.
      lib_vcpu = File.join(OBJ_DIR, 'libVmos6502_cpu.a')
      lib_verilated = File.join(OBJ_DIR, 'libverilated.a')
      newest_input = [lib_vcpu, lib_verilated].filter_map { |p| File.exist?(p) ? File.mtime(p) : nil }.max
      lib_mtime = File.exist?(lib_path) ? File.mtime(lib_path) : nil

      if lib_mtime.nil? || (!newest_input.nil? && lib_mtime < newest_input)
        build_shared_library(wrapper_file)
      end
    end

    def build_shared_library(wrapper_file)
      # Link all object files and static libraries into shared library
      lib_path = shared_lib_path
      lib_vcpu = File.join(OBJ_DIR, 'libVmos6502_cpu.a')
      lib_verilated = File.join(OBJ_DIR, 'libverilated.a')

      # Use whole-archive to include all symbols from static libs
      # -latomic needed for clang++ on Linux
      link_cmd = if RbConfig::CONFIG['host_os'] =~ /darwin/
                   "clang++ -shared -dynamiclib -o #{lib_path} " \
                   "-Wl,-all_load #{lib_vcpu} #{lib_verilated}"
                 else
                   "clang++ -shared -o #{lib_path} " \
                   "-Wl,--whole-archive #{lib_vcpu} #{lib_verilated} -Wl,--no-whole-archive -latomic"
                 end

      unless system(link_cmd)
        raise "Failed to link Verilator shared library: #{lib_path}"
      end
    end

    def shared_lib_path
      lib_suffix = case RbConfig::CONFIG['host_os']
                   when /darwin/ then 'dylib'
                   when /mswin|mingw/ then 'dll'
                   else 'so'
                   end
      File.join(OBJ_DIR, "libmos6502_sim.#{lib_suffix}")
    end

    def load_shared_library(lib_path)
      unless File.exist?(lib_path)
        raise LoadError, "Verilator shared library not found: #{lib_path}"
      end

      @lib = Fiddle.dlopen(lib_path)

      # Bind FFI functions
      @sim_create = Fiddle::Function.new(
        @lib['sim_create'],
        [],
        Fiddle::TYPE_VOIDP
      )

      @sim_destroy = Fiddle::Function.new(
        @lib['sim_destroy'],
        [Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOID
      )

      @sim_reset = Fiddle::Function.new(
        @lib['sim_reset'],
        [Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOID
      )

      @sim_eval = Fiddle::Function.new(
        @lib['sim_eval'],
        [Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOID
      )

      @sim_poke = Fiddle::Function.new(
        @lib['sim_poke'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
        Fiddle::TYPE_VOID
      )

      @sim_peek = Fiddle::Function.new(
        @lib['sim_peek'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      @sim_write_memory_fn = Fiddle::Function.new(
        @lib['sim_write_memory'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
        Fiddle::TYPE_VOID
      )

      @sim_read_memory_fn = Fiddle::Function.new(
        @lib['sim_read_memory'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
        Fiddle::TYPE_CHAR
      )

      @sim_run_cycles_fn = Fiddle::Function.new(
        @lib['sim_run_cycles'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOID
      )

      @sim_load_memory_fn = Fiddle::Function.new(
        @lib['sim_load_memory'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
        Fiddle::TYPE_VOID
      )

      @sim_run_instructions_fn = Fiddle::Function.new(
        @lib['sim_run_instructions_with_opcodes'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      # Create simulation context
      @sim_ctx = @sim_create.call
    end

    def reset_simulation
      @sim_reset&.call(@sim_ctx) if @sim_ctx
    end

    def verilator_poke(name, value)
      return unless @sim_ctx
      @sim_poke.call(@sim_ctx, name, value.to_i)
    end

    def verilator_peek(name)
      return 0 unless @sim_ctx
      @sim_peek.call(@sim_ctx, name)
    end

    def verilator_eval
      return unless @sim_ctx
      @sim_eval.call(@sim_ctx)
    end

    def verilator_write_memory(addr, value)
      return unless @sim_ctx
      @sim_write_memory_fn.call(@sim_ctx, addr, value)
    end
      end
    end
  end
end
