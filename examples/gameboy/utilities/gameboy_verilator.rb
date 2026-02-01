# frozen_string_literal: true

# Game Boy Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the Gameboy HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface similar to the Rust IR runners.
#
# Usage:
#   runner = RHDL::GameBoy::VerilatorRunner.new
#   runner.load_rom(File.binread('game.gb'))
#   runner.reset
#   runner.run_steps(100)

require_relative '../gameboy'
require_relative 'speaker'
require_relative 'lcd_renderer'
require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'fiddle/import'

module RHDL
  module GameBoy
    # Verilator-based runner for Game Boy simulation
    # Compiles RHDL Verilog export to native code via Verilator
    class VerilatorRunner
      # Screen dimensions
      SCREEN_WIDTH = 160
      SCREEN_HEIGHT = 144

      # Memory map constants
      ROM_BANK_0_END = 0x3FFF
      ROM_BANK_N_END = 0x7FFF
      VRAM_START = 0x8000
      VRAM_END = 0x9FFF
      WRAM_START = 0xC000
      WRAM_END = 0xDFFF
      HRAM_START = 0xFF80
      HRAM_END = 0xFFFE

      # Build directory for Verilator output
      BUILD_DIR = File.expand_path('../../../.verilator_build_gb', __dir__)
      VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
      OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')

      # Boot ROM path
      DMG_BOOT_ROM_PATH = File.expand_path('../reference/BootROMs/bin/dmg_boot.bin', __dir__)

      # Initialize the Game Boy Verilator runner
      def initialize
        check_verilator_available!

        puts "Initializing Game Boy Verilator simulation..."
        start_time = Time.now

        # Build and load the Verilator simulation
        build_verilator_simulation

        elapsed = Time.now - start_time
        puts "  Verilator simulation built in #{elapsed.round(2)}s"

        @cycles = 0
        @halted = false
        @screen_dirty = false

        # Memory arrays
        @rom = Array.new(1024 * 1024, 0)  # 1MB max ROM
        @vram = Array.new(8192, 0)         # 8KB VRAM
        @wram = Array.new(8192, 0)         # 8KB WRAM
        @hram = Array.new(127, 0)          # 127 bytes HRAM
        @boot_rom = Array.new(256, 0)      # 256 bytes DMG boot ROM

        # Framebuffer (160x144 pixels, 2-bit grayscale)
        @framebuffer = Array.new(SCREEN_HEIGHT) { Array.new(SCREEN_WIDTH, 0) }

        # LCD state tracking
        @lcd_x = 0
        @lcd_y = 0
        @prev_lcd_clkena = 0
        @prev_lcd_vsync = 0
        @frame_count = 0

        # Speaker audio simulation
        @speaker = Speaker.new

        reset_simulation
      end

      def native?
        true
      end

      def simulator_type
        :hdl_verilator
      end

      # Load ROM data
      def load_rom(bytes)
        bytes = bytes.bytes if bytes.is_a?(String)
        @rom = bytes.dup
        @rom.concat(Array.new(1024 * 1024 - @rom.size, 0)) if @rom.size < 1024 * 1024

        # Bulk load into C++ side
        if @sim_load_rom_fn && @sim_ctx
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
        end

        puts "Loaded #{bytes.size} bytes ROM"
      end

      # Load boot ROM data
      def load_boot_rom(bytes = nil)
        if bytes.nil?
          if File.exist?(DMG_BOOT_ROM_PATH)
            bytes = File.binread(DMG_BOOT_ROM_PATH)
            puts "Loading default DMG boot ROM from #{DMG_BOOT_ROM_PATH}"
          else
            puts "Warning: DMG boot ROM not found at #{DMG_BOOT_ROM_PATH}"
            return
          end
        elsif bytes.is_a?(String) && File.exist?(bytes)
          bytes = File.binread(bytes)
        end

        bytes = bytes.bytes if bytes.is_a?(String)
        @boot_rom = bytes.dup
        @boot_rom.concat(Array.new(256 - @boot_rom.size, 0)) if @boot_rom.size < 256

        # Bulk load into C++ side
        if @sim_load_boot_rom_fn && @sim_ctx
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_boot_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
        end

        puts "Loaded #{bytes.size} bytes boot ROM"
        @boot_rom_loaded = true
      end

      def boot_rom_loaded?
        @boot_rom_loaded || false
      end

      def reset
        reset_simulation
        @cycles = 0
        @halted = false
        @screen_dirty = false
        @lcd_x = 0
        @lcd_y = 0
        @frame_count = 0
      end

      # Main entry point for running cycles
      def run_steps(steps)
        if @sim_run_cycles_fn
          # Use batch execution - run all cycles in C++
          result_ptr = Fiddle::Pointer.malloc(16)  # GbCycleResult struct
          @sim_run_cycles_fn.call(@sim_ctx, steps, result_ptr)
          # Unpack result: cycles_run (usize) + frames_completed (u32)
          values = result_ptr.to_s(16).unpack('QL')
          cycles_run = values[0]
          frames_completed = values[1]
          @cycles += cycles_run
          @screen_dirty = true if frames_completed > 0
          @frame_count += frames_completed
        else
          # Fallback to per-cycle Ruby execution
          steps.times { run_clock_cycle }
        end
      end

      # Run a single clock cycle
      def run_clock_cycle
        # Falling edge
        verilator_poke('clk_sys', 0)
        verilator_eval

        # Handle ROM read
        cart_rd = verilator_peek('cart_rd')
        if cart_rd == 1
          addr = verilator_peek('ext_bus_addr')
          a15 = verilator_peek('ext_bus_a15')
          full_addr = (a15 << 15) | addr
          verilator_poke('cart_do', @rom[full_addr] || 0)
        end
        verilator_eval

        # Rising edge
        verilator_poke('clk_sys', 1)
        verilator_eval

        # Capture LCD output
        lcd_clkena = verilator_peek('lcd_clkena')
        lcd_vsync = verilator_peek('lcd_vsync')
        lcd_data = verilator_peek('lcd_data_gb') & 0x3

        # Rising edge of lcd_clkena: capture pixel
        if lcd_clkena == 1 && @prev_lcd_clkena == 0
          if @lcd_x < SCREEN_WIDTH && @lcd_y < SCREEN_HEIGHT
            @framebuffer[@lcd_y][@lcd_x] = lcd_data
            @screen_dirty = true
          end
          @lcd_x += 1
          if @lcd_x >= SCREEN_WIDTH
            @lcd_x = 0
            @lcd_y += 1
          end
        end

        # Rising edge of lcd_vsync: end of frame
        if lcd_vsync == 1 && @prev_lcd_vsync == 0
          @lcd_x = 0
          @lcd_y = 0
          @frame_count += 1
        end

        @prev_lcd_clkena = lcd_clkena
        @prev_lcd_vsync = lcd_vsync
        @cycles += 1
      end

      # Inject a joypad button press
      def inject_key(button)
        current = verilator_peek('joystick') || 0xFF
        verilator_poke('joystick', current & ~(1 << button))
      end

      def release_key(button)
        current = verilator_peek('joystick') || 0xFF
        verilator_poke('joystick', current | (1 << button))
      end

      def read_framebuffer
        # Read framebuffer from C++ side
        if @sim_read_framebuffer_fn && @sim_ctx
          buffer = Fiddle::Pointer.malloc(160 * 144)
          @sim_read_framebuffer_fn.call(@sim_ctx, buffer)
          flat = buffer.to_s(160 * 144).bytes
          # Reshape to 2D array
          Array.new(SCREEN_HEIGHT) do |y|
            Array.new(SCREEN_WIDTH) do |x|
              flat[y * SCREEN_WIDTH + x]
            end
          end
        else
          @framebuffer
        end
      end

      def read_screen
        ly = (@cycles / 456) % 154
        ["Game Boy LCD (Verilator)", "LY: #{ly}", "Cycles: #{@cycles}"]
      end

      def screen_dirty?
        @screen_dirty
      end

      def clear_screen_dirty
        @screen_dirty = false
      end

      def render_lcd_braille(chars_wide: 40, invert: false)
        renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
        renderer.render_braille(@framebuffer)
      end

      def render_lcd_color(chars_wide: 80)
        renderer = LcdRenderer.new(chars_wide: chars_wide)
        renderer.render_color(@framebuffer)
      end

      def cpu_state
        {
          pc: verilator_peek('debug_pc') || 0,
          a: verilator_peek('debug_acc') || 0,
          f: 0,
          cycles: @cycles,
          halted: @halted,
          simulator_type: simulator_type
        }
      end

      def halted?
        @halted
      end

      def cycle_count
        @cycles
      end

      def frame_count
        @frame_count
      end

      def dry_run_info
        {
          mode: :verilog,
          simulator_type: simulator_type,
          native: native?,
          cpu_state: cpu_state,
          rom_size: @rom.compact.size
        }
      end

      def speaker
        @speaker
      end

      def start_audio
        @speaker.start
      end

      def stop_audio
        @speaker.stop
      end

      def read(addr)
        addr &= 0xFFFF

        if addr <= ROM_BANK_N_END
          @rom[addr] || 0
        elsif addr >= VRAM_START && addr <= VRAM_END
          @vram[addr - VRAM_START] || 0
        elsif addr >= WRAM_START && addr <= WRAM_END
          @wram[addr - WRAM_START] || 0
        elsif addr >= HRAM_START && addr <= HRAM_END
          @hram[addr - HRAM_START] || 0
        else
          0xFF
        end
      end

      def write(addr, value)
        addr &= 0xFFFF

        if addr >= VRAM_START && addr <= VRAM_END
          @vram[addr - VRAM_START] = value & 0xFF
          verilator_write_vram(addr - VRAM_START, value & 0xFF)
        elsif addr >= WRAM_START && addr <= WRAM_END
          @wram[addr - WRAM_START] = value & 0xFF
        elsif addr >= HRAM_START && addr <= HRAM_END
          @hram[addr - HRAM_START] = value & 0xFF
        end
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

        # Export Gameboy to Verilog
        verilog_file = File.join(VERILOG_DIR, 'gameboy.v')
        unless File.exist?(verilog_file) && File.mtime(verilog_file) > File.mtime(__FILE__)
          puts "  Exporting Gameboy to Verilog..."
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
        # Use the existing Verilog export infrastructure
        verilog_code = ::GameBoy::Gameboy.to_verilog

        # Also export all subcomponents
        subcomponent_verilog = []
        [
          ::GameBoy::SpeedControl,
          ::GameBoy::GB,
          ::GameBoy::SM83,
          ::GameBoy::SM83_ALU,
          ::GameBoy::SM83_Registers,
          ::GameBoy::SM83_MCode,
          ::GameBoy::Timer,
          ::GameBoy::Video,
          ::GameBoy::Sprites,
          ::GameBoy::LCD,
          ::GameBoy::Sound,
          ::GameBoy::ChannelSquare,
          ::GameBoy::ChannelWave,
          ::GameBoy::ChannelNoise,
          ::GameBoy::HDMA,
          ::GameBoy::Link,
          ::GameBoy::DPRAM,
          ::GameBoy::SPRAM
        ].each do |component_class|
          begin
            subcomponent_verilog << component_class.to_verilog
          rescue StandardError => e
            puts "    Warning: Could not export #{component_class}: #{e.message}"
          end
        end

        all_verilog = [verilog_code, *subcomponent_verilog].join("\n\n")

        # Post-process for Verilator compatibility
        all_verilog = make_verilator_compatible(all_verilog)

        File.write(output_file, all_verilog)
      end

      def make_verilator_compatible(verilog)
        # Add Verilator lint pragmas at the top
        pragmas = <<~PRAGMAS
          /* verilator lint_off IMPLICIT */
          /* verilator lint_off UNUSED */
          /* verilator lint_off UNDRIVEN */
          /* verilator lint_off PINMISSING */

        PRAGMAS

        verilog = pragmas + verilog

        # Replace true/false with 1'b1/1'b0
        verilog = verilog.gsub(/\(true\)/, "(1'b1)")
        verilog = verilog.gsub(/\(false\)/, "(1'b0)")
        verilog = verilog.gsub(/= true\b/, "= 1'b1")
        verilog = verilog.gsub(/= false\b/, "= 1'b0")

        # Remove default values from input declarations
        # Pattern: input name = value -> input name
        verilog = verilog.gsub(/^(\s*input\s+(?:\[[^\]]+\]\s+)?(\w+))\s*=\s*[^,;\n]+([,;])/) do
          "#{$1}#{$3}"
        end

        # Replace reduce_or(expr) with |expr
        verilog = verilog.gsub(/reduce_or\(([^)]+)\)/, '|\1')

        # Replace reduce_and(expr) with &expr
        verilog = verilog.gsub(/reduce_and\(([^)]+)\)/, '&\1')

        # Replace reduce_xor(expr) with ^expr
        verilog = verilog.gsub(/reduce_xor\(([^)]+)\)/, '^\1')

        # Remove parameter overrides that don't exist in module definitions
        # Pattern: game_boy_dpram #(.addr_width(N)) name -> game_boy_dpram name
        verilog = verilog.gsub(/game_boy_dpram\s+#\(\s*\.addr_width\(\d+\)\s*\)\s+(\w+)/, 'game_boy_dpram \1')
        verilog = verilog.gsub(/game_boy_spram\s+#\(\s*\.addr_width\(\d+\)\s*\)\s+(\w+)/, 'game_boy_spram \1')
        verilog = verilog.gsub(/game_boy_channel_square\s+#\(\s*\.has_sweep\([^)]+\)\s*\)\s+(\w+)/, 'game_boy_channel_square \1')

        # Fix unsized constants in concatenations: {0'd0, -> {1'b0,
        verilog = verilog.gsub(/\{0'd0,/, "{1'b0,")

        # Fix DPRAM outputs - they should be reg not wire since assigned in always blocks
        # Pattern: output [7:0] q_a, -> output reg [7:0] q_a,
        verilog = verilog.gsub(/output\s+(\[\d+:\d+\]\s+)(q_a|q_b)/, 'output reg \1\2')
        verilog = verilog.gsub(/output\s+(q_a|q_b)/, 'output reg \1')

        # Fix SPRAM outputs - data_out should be reg since assigned in always block
        verilog = verilog.gsub(/output\s+(\[\d+:\d+\]\s+)(data_out)(\s*[;)])/, 'output reg \1\2\3')
        verilog = verilog.gsub(/output\s+(data_out)(\s*[;)])/, 'output reg \1\2')

        verilog
      end

      def create_cpp_wrapper(cpp_file, header_file)
        # Create C++ header for FFI
        File.write(header_file, <<~HEADER)
          #ifndef SIM_WRAPPER_H
          #define SIM_WRAPPER_H

          #ifdef __cplusplus
          extern "C" {
          #endif

          // Lifecycle
          void* sim_create(void);
          void sim_destroy(void* sim);
          void sim_reset(void* sim);
          void sim_eval(void* sim);

          // Signal access
          void sim_poke(void* sim, const char* name, unsigned int value);
          unsigned int sim_peek(void* sim, const char* name);

          // Memory access
          void sim_load_rom(void* sim, const unsigned char* data, unsigned int len);
          void sim_load_boot_rom(void* sim, const unsigned char* data, unsigned int len);
          void sim_write_vram(void* sim, unsigned int addr, unsigned char value);
          unsigned char sim_read_vram(void* sim, unsigned int addr);

          // Framebuffer access
          void sim_read_framebuffer(void* sim, unsigned char* out_buffer);
          unsigned long sim_get_frame_count(void* sim);

          // Cycle result struct
          struct GbCycleResult {
              unsigned long cycles_run;
              unsigned int frames_completed;
          };

          // Batch execution
          void sim_run_cycles(void* sim, unsigned int n_cycles, struct GbCycleResult* result);

          #ifdef __cplusplus
          }
          #endif

          #endif // SIM_WRAPPER_H
        HEADER

        # Create C++ wrapper implementation
        File.write(cpp_file, <<~CPP)
          #include "Vgame_boy_gameboy.h"
          #include "Vgame_boy_gameboy___024root.h"  // For internal signal access
          #include "verilated.h"
          #include "sim_wrapper.h"
          #include <cstring>

          struct SimContext {
              Vgame_boy_gameboy* dut;
              unsigned char rom[1048576];     // 1MB ROM
              unsigned char boot_rom[256];    // 256 byte DMG boot ROM
              unsigned char vram[8192];       // 8KB VRAM
              unsigned char framebuffer[160 * 144];  // Framebuffer
              unsigned int lcd_x;
              unsigned int lcd_y;
              unsigned char prev_lcd_clkena;
              unsigned char prev_lcd_vsync;
              unsigned long frame_count;
              unsigned int clk_counter;       // System clock counter for CPU cycle estimation
          };

          extern "C" {

          void* sim_create(void) {
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);
              SimContext* ctx = new SimContext();
              ctx->dut = new Vgame_boy_gameboy();
              memset(ctx->rom, 0, sizeof(ctx->rom));
              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
              memset(ctx->vram, 0, sizeof(ctx->vram));
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0;
              ctx->lcd_y = 0;
              ctx->prev_lcd_clkena = 0;
              ctx->prev_lcd_vsync = 0;
              ctx->frame_count = 0;
              ctx->clk_counter = 0;
              return ctx;
          }

          void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
          }

          void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              // Hold reset high and clock a few times to properly reset sequential logic
              ctx->dut->reset = 1;
              for (int i = 0; i < 10; i++) {
                  ctx->dut->clk_sys = 0;
                  ctx->dut->eval();
                  ctx->dut->clk_sys = 1;
                  ctx->dut->eval();
              }
              // Release reset and clock to let the system initialize
              ctx->dut->reset = 0;
              for (int i = 0; i < 100; i++) {
                  ctx->dut->clk_sys = 0;
                  ctx->dut->eval();
                  ctx->dut->clk_sys = 1;
                  ctx->dut->eval();
              }

              // Note: boot_rom_enabled is internal and may not be accessible
              // The CPU will start executing from wherever it is after reset
              ctx->dut->eval();

              ctx->lcd_x = 0;
              ctx->lcd_y = 0;
              ctx->frame_count = 0;
              ctx->clk_counter = 0;  // Reset clock counter
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
          }

          void sim_eval(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->dut->eval();
          }

          void sim_poke(void* sim, const char* name, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (strcmp(name, "clk_sys") == 0) ctx->dut->clk_sys = value;
              else if (strcmp(name, "reset") == 0) ctx->dut->reset = value;
              else if (strcmp(name, "joystick") == 0) ctx->dut->joystick = value;
              else if (strcmp(name, "is_gbc") == 0) ctx->dut->is_gbc = value;
              else if (strcmp(name, "is_sgb") == 0) ctx->dut->is_sgb = value;
              else if (strcmp(name, "cart_do") == 0) ctx->dut->cart_do = value;
          }

          unsigned int sim_peek(void* sim, const char* name) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (strcmp(name, "ext_bus_addr") == 0) return ctx->dut->ext_bus_addr;
              else if (strcmp(name, "ext_bus_a15") == 0) return ctx->dut->ext_bus_a15;
              else if (strcmp(name, "cart_rd") == 0) return ctx->dut->cart_rd;
              else if (strcmp(name, "cart_wr") == 0) return ctx->dut->cart_wr;
              else if (strcmp(name, "cart_di") == 0) return ctx->dut->cart_di;
              else if (strcmp(name, "lcd_clkena") == 0) return ctx->dut->lcd_clkena;
              else if (strcmp(name, "lcd_data_gb") == 0) return ctx->dut->lcd_data_gb;
              else if (strcmp(name, "lcd_vsync") == 0) return ctx->dut->lcd_vsync;
              else if (strcmp(name, "lcd_on") == 0) return ctx->dut->lcd_on;
              else if (strcmp(name, "joystick") == 0) return ctx->dut->joystick;
              else if (strcmp(name, "debug_pc") == 0) return ctx->dut->debug_pc;
              else if (strcmp(name, "debug_acc") == 0) return ctx->dut->debug_acc;
              // Internal signals not accessible - return estimated values
              else if (strcmp(name, "_clkdiv") == 0) return ctx->clk_counter & 7;  // Estimate clkdiv
              // Other internal signals not accessible
              return 0;
          }

          void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len && i < sizeof(ctx->rom); i++) {
                  ctx->rom[i] = data[i];
              }
          }

          void sim_load_boot_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len && i < sizeof(ctx->boot_rom); i++) {
                  ctx->boot_rom[i] = data[i];
              }
          }

          void sim_write_vram(void* sim, unsigned int addr, unsigned char value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->vram)) {
                  ctx->vram[addr] = value;
              }
          }

          unsigned char sim_read_vram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->vram)) {
                  return ctx->vram[addr];
              }
              return 0;
          }

          void sim_read_framebuffer(void* sim, unsigned char* out_buffer) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memcpy(out_buffer, ctx->framebuffer, 160 * 144);
          }

          unsigned long sim_get_frame_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->frame_count;
          }

          // Batch cycle execution - runs until n_cycles CPU cycles completed
          // CPU cycles occur every 8 system clocks (SpeedControl divider)
          // This aligns with IR Compiler which counts effective CPU cycles
          void sim_run_cycles(void* sim, unsigned int n_cycles, struct GbCycleResult* result) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              result->cycles_run = 0;
              result->frames_completed = 0;

              while (result->cycles_run < n_cycles) {
                  // Falling edge
                  ctx->dut->clk_sys = 0;
                  ctx->dut->eval();

                  // Handle ROM read
                  if (ctx->dut->cart_rd) {
                      unsigned int addr = ctx->dut->ext_bus_addr;
                      unsigned int a15 = ctx->dut->ext_bus_a15;
                      unsigned int full_addr = (a15 << 15) | addr;
                      if (full_addr < sizeof(ctx->rom)) {
                          ctx->dut->cart_do = ctx->rom[full_addr];
                      }
                  }
                  ctx->dut->eval();

                  // Rising edge
                  ctx->dut->clk_sys = 1;
                  ctx->dut->eval();

                  // Count CPU cycles every 8 system clocks (SpeedControl divides by 8)
                  ctx->clk_counter++;
                  if ((ctx->clk_counter & 7) == 0) {
                      result->cycles_run++;
                  }

                  // Capture LCD output
                  unsigned char lcd_clkena = ctx->dut->lcd_clkena;
                  unsigned char lcd_vsync = ctx->dut->lcd_vsync;
                  unsigned char lcd_data = ctx->dut->lcd_data_gb & 0x3;

                  // Rising edge of lcd_clkena: capture pixel
                  if (lcd_clkena && !ctx->prev_lcd_clkena) {
                      if (ctx->lcd_x < 160 && ctx->lcd_y < 144) {
                          ctx->framebuffer[ctx->lcd_y * 160 + ctx->lcd_x] = lcd_data;
                      }
                      ctx->lcd_x++;
                      if (ctx->lcd_x >= 160) {
                          ctx->lcd_x = 0;
                          ctx->lcd_y++;
                      }
                  }

                  // Rising edge of lcd_vsync: end of frame
                  if (lcd_vsync && !ctx->prev_lcd_vsync) {
                      ctx->lcd_x = 0;
                      ctx->lcd_y = 0;
                      ctx->frame_count++;
                      result->frames_completed++;
                  }

                  ctx->prev_lcd_clkena = lcd_clkena;
                  ctx->prev_lcd_vsync = lcd_vsync;
              }
          }

          } // extern "C"
        CPP
      end

      def compile_verilator(verilog_file, wrapper_file)
        # Determine library suffix
        lib_suffix = case RbConfig::CONFIG['host_os']
                     when /darwin/ then 'dylib'
                     when /mswin|mingw/ then 'dll'
                     else 'so'
                     end

        lib_name = "libgameboy_sim.#{lib_suffix}"
        lib_path = File.join(OBJ_DIR, lib_name)

        # Verilate the design - top module is game_boy_gameboy
        verilate_cmd = [
          'verilator',
          '--cc',
          '--top-module', 'game_boy_gameboy',
          # Optimization flags
          '-O3',
          '--x-assign', 'fast',
          '--x-initial', 'fast',
          '--noassert',
          # Warning suppressions
          '-Wno-fatal',
          '-Wno-WIDTHEXPAND',
          '-Wno-WIDTHTRUNC',
          '-Wno-UNOPTFLAT',
          '-Wno-PINMISSING',
          # C++ compiler flags
          '-CFLAGS', '-fPIC -O3 -march=native',
          '-LDFLAGS', '-shared',
          '--Mdir', OBJ_DIR,
          '--prefix', 'Vgame_boy_gameboy',
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
          Dir.chdir(OBJ_DIR) do
            result = system('make', '-f', 'Vgame_boy_gameboy.mk', 'CXX=clang++', out: log, err: log)
            unless result
              raise "Verilator make failed. See #{log_file} for details."
            end
          end
        end

        unless File.exist?(lib_path)
          build_shared_library(wrapper_file)
        end
      end

      def build_shared_library(wrapper_file)
        lib_path = shared_lib_path
        lib_vgameboy = File.join(OBJ_DIR, 'libVgame_boy_gameboy.a')
        lib_verilated = File.join(OBJ_DIR, 'libverilated.a')

        link_cmd = if RbConfig::CONFIG['host_os'] =~ /darwin/
                     "clang++ -shared -dynamiclib -o #{lib_path} " \
                     "-Wl,-all_load #{lib_vgameboy} #{lib_verilated}"
                   else
                     "clang++ -shared -o #{lib_path} " \
                     "-Wl,--whole-archive #{lib_vgameboy} #{lib_verilated} -Wl,--no-whole-archive -latomic"
                   end

        system(link_cmd)
      end

      def shared_lib_path
        lib_suffix = case RbConfig::CONFIG['host_os']
                     when /darwin/ then 'dylib'
                     when /mswin|mingw/ then 'dll'
                     else 'so'
                     end
        File.join(OBJ_DIR, "libgameboy_sim.#{lib_suffix}")
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

        @sim_load_rom_fn = Fiddle::Function.new(
          @lib['sim_load_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_VOID
        )

        @sim_load_boot_rom_fn = Fiddle::Function.new(
          @lib['sim_load_boot_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_VOID
        )

        @sim_write_vram_fn = Fiddle::Function.new(
          @lib['sim_write_vram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
          Fiddle::TYPE_VOID
        )

        @sim_read_vram_fn = Fiddle::Function.new(
          @lib['sim_read_vram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_CHAR
        )

        @sim_read_framebuffer_fn = Fiddle::Function.new(
          @lib['sim_read_framebuffer'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        @sim_get_frame_count_fn = Fiddle::Function.new(
          @lib['sim_get_frame_count'],
          [Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_LONG
        )

        @sim_run_cycles_fn = Fiddle::Function.new(
          @lib['sim_run_cycles'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        # Create simulation context
        @sim_ctx = @sim_create.call
      end

      def reset_simulation
        @sim_reset&.call(@sim_ctx) if @sim_ctx
        initialize_inputs
      end

      def initialize_inputs
        return unless @sim_ctx

        verilator_poke('clk_sys', 0)
        verilator_poke('reset', 0)
        verilator_poke('joystick', 0xFF)  # All buttons released
        verilator_poke('is_gbc', 0)       # DMG mode
        verilator_poke('is_sgb', 0)       # Not SGB
        verilator_poke('cart_do', 0)
        verilator_eval
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

      def verilator_write_vram(addr, value)
        return unless @sim_ctx
        @sim_write_vram_fn.call(@sim_ctx, addr, value)
      end

      def verilator_read_vram(addr)
        return 0 unless @sim_ctx
        @sim_read_vram_fn.call(@sim_ctx, addr)
      end
    end
  end
end
