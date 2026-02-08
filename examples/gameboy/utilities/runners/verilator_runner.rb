# frozen_string_literal: true

# Game Boy Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the Gameboy HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface similar to the Rust IR runners.
#
# Usage:
#   runner = RHDL::ExamplesRHDL::Examples::GameBoy::VerilatorRunner.new
#   runner.load_rom(File.binread('game.gb'))
#   runner.reset
#   runner.run_steps(100)

require_relative '../../gameboy'
require_relative '../output/speaker'
require_relative '../renderers/lcd_renderer'
require_relative '../renderers/framebuffer_decoder'
require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'fiddle/import'

module RHDL
  module Examples
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
      ROM_BANK_SIZE = 0x4000
      CART_RAM_BANK_SIZE = 0x2000
      MBC1_CART_TYPES = [0x01, 0x02, 0x03].freeze

      # Build directory for Verilator output
      BUILD_DIR = File.expand_path('../../../../.verilator_build_gb', __dir__)
      VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
      OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')

      # Boot ROM path
      DMG_BOOT_ROM_PATH = File.expand_path('../../software/roms/dmg_boot.bin', __dir__)

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
        @decoded_framebuffer_rows = Array.new(SCREEN_HEIGHT) { Array.new(SCREEN_WIDTH, 0) }
        @decoded_frame_count = -1

        # Memory arrays
        @rom = Array.new(1024 * 1024, 0)  # 1MB max ROM
        @rom_len = 0
        @cart_type = 0x00
        @cart_ram = Array.new(128 * 1024, 0xFF)
        @cart_ram_len = 0
        @vram = Array.new(8192, 0)         # 8KB VRAM
        @wram = Array.new(8192, 0)         # 8KB WRAM
        @hram = Array.new(127, 0)          # 127 bytes HRAM
        @boot_rom = Array.new(256, 0)      # 256 bytes DMG boot ROM
        reset_mapper_state

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

        # Load boot ROM if available
        load_boot_rom if File.exist?(DMG_BOOT_ROM_PATH)
      end

      def native?
        true
      end

      def simulator_type
        :hdl_verilator
      end

      def dry_run_info
        {
          mode: :verilog,
          simulator_type: :hdl_verilator,
          native: true
        }
      end

      # Load ROM data
      # @param bytes [String, Array<Integer>] ROM bytes
      # @param base_addr [Integer] kept for API compatibility with other runners (ignored for GB carts)
      def load_rom(bytes, base_addr: 0)
        bytes = bytes.bytes if bytes.is_a?(String)
        @rom_len = [bytes.size, 1024 * 1024].min
        @cart_type = bytes.size > 0x147 ? bytes[0x147] : 0x00
        @cart_ram_len = [cart_ram_size_from_header(bytes.size > 0x149 ? bytes[0x149] : 0x00), @cart_ram.size].min
        @cart_ram.fill(0xFF)
        reset_mapper_state
        @rom = bytes.first(1024 * 1024)
        @rom.concat(Array.new(1024 * 1024 - @rom.size, 0))

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
        reset_mapper_state
        @cycles = 0
        @halted = false
        @screen_dirty = false
        @lcd_x = 0
        @lcd_y = 0
        @frame_count = 0
        @decoded_framebuffer_rows.each { |row| row.fill(0) } if @decoded_framebuffer_rows
        @decoded_frame_count = -1
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

        # Handle mapper writes and ROM reads
        addr = verilator_peek('ext_bus_addr')
        a15 = verilator_peek('ext_bus_a15')
        full_addr = ((a15 & 0x1) << 15) | (addr & 0x7FFF)

        cart_wr = verilator_peek('cart_wr')
        ram_addr = mapped_cart_ram_addr(full_addr)
        cart_oe = (full_addr <= ROM_BANK_N_END) || !ram_addr.nil?
        tick_open_bus(cart_oe)

        if cart_wr == 1
          data = verilator_peek('cart_di')
          if full_addr <= ROM_BANK_N_END
            mapper_write(full_addr, data)
          else
            @cart_ram[ram_addr] = data if ram_addr
          end
        end

        cart_rd = verilator_peek('cart_rd')
        data = if full_addr <= ROM_BANK_N_END
                 mapped_addr = mapped_rom_addr(full_addr)
                 mapped_addr < @rom_len ? (@rom[mapped_addr] || 0xFF) : 0xFF
               else
                 ram_addr ? (@cart_ram[ram_addr] || 0xFF) : @open_bus_data
               end

        @open_bus_data = data & 0xFF if cart_rd == 1
        # Keep cart data bus driven from the currently addressed source so fetch
        # bytes are valid as soon as `cart_rd` is asserted.
        verilator_poke('cart_do', data)
        verilator_eval

        # Rising edge
        verilator_poke('clk_sys', 1)
        verilator_eval

        # Capture LCD output
        lcd_clkena = verilator_peek('lcd_clkena')
        lcd_vsync = verilator_peek('lcd_vsync')
        lcd_data = verilator_peek('lcd_data_gb') & 0x3

        # Capture by hardware counters to avoid software raster drift.
        if lcd_clkena == 1
          pcnt = verilator_peek('gb_core__video_unit__pcnt')
          v_cnt = verilator_peek('gb_core__video_unit__v_cnt')
          if v_cnt < SCREEN_HEIGHT && pcnt < SCREEN_WIDTH
            x = pcnt
            @framebuffer[v_cnt][x] = lcd_data
            @lcd_x = x
            @lcd_y = v_cnt
            @screen_dirty = true
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
        # Prefer native framebuffer captured from live LCD pixel output.
        if @sim_ctx && @sim_read_framebuffer_fn
          @native_framebuffer_buffer ||= Fiddle::Pointer.malloc(SCREEN_WIDTH * SCREEN_HEIGHT)
          @sim_read_framebuffer_fn.call(@sim_ctx, @native_framebuffer_buffer)
          flat = @native_framebuffer_buffer.to_s(SCREEN_WIDTH * SCREEN_HEIGHT).bytes
          return FramebufferDecoder.flat_to_rows(flat)
        end

        return decode_framebuffer_from_memory if @sim_ctx

        @framebuffer
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
        renderer.render_braille(read_framebuffer)
      end

      def render_lcd_color(chars_wide: 80)
        renderer = LcdRenderer.new(chars_wide: chars_wide)
        renderer.render_color(read_framebuffer)
      end

      def cpu_state
        {
          pc: verilator_peek('debug_pc') || 0,
          a: verilator_peek('debug_acc') || 0,
          f: verilator_peek('debug_f') || 0,
          b: verilator_peek('debug_b') || 0,
          c: verilator_peek('debug_c') || 0,
          d: verilator_peek('debug_d') || 0,
          e: verilator_peek('debug_e') || 0,
          h: verilator_peek('debug_h') || 0,
          l: verilator_peek('debug_l') || 0,
          sp: verilator_peek('debug_sp') || 0,
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
          mapped_addr = mapped_rom_addr(addr)
          mapped_addr < @rom_len ? (@rom[mapped_addr] || 0xFF) : 0xFF
        elsif addr >= 0xA000 && addr <= 0xBFFF
          ram_addr = mapped_cart_ram_addr(addr)
          ram_addr ? (@cart_ram[ram_addr] || 0xFF) : @open_bus_data
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
        elsif addr >= 0xA000 && addr <= 0xBFFF
          ram_addr = mapped_cart_ram_addr(addr)
          @cart_ram[ram_addr] = value & 0xFF if ram_addr
        elsif addr >= WRAM_START && addr <= WRAM_END
          @wram[addr - WRAM_START] = value & 0xFF
        elsif addr >= HRAM_START && addr <= HRAM_END
          @hram[addr - HRAM_START] = value & 0xFF
        end
      end

      private

      def reset_mapper_state
        @mbc1_rom_bank_low5 = 1
        @mbc1_bank_high2 = 0
        @mbc1_mode = 0
        @mbc1_ram_enable = false
        @open_bus_data = 0
        @open_bus_cnt = 0
      end

      def mbc1_cart?
        MBC1_CART_TYPES.include?(@cart_type)
      end

      def mapper_write(addr, value)
        return unless mbc1_cart?

        value &= 0xFF
        case addr & 0x7FFF
        when 0x0000..0x1FFF
          @mbc1_ram_enable = (value & 0x0F) == 0x0A
        when 0x2000..0x3FFF
          bank = value & 0x1F
          @mbc1_rom_bank_low5 = bank.zero? ? 1 : bank
        when 0x4000..0x5FFF
          @mbc1_bank_high2 = value & 0x03
        when 0x6000..0x7FFF
          @mbc1_mode = value & 0x01
        end
      end

      def mapped_rom_addr(addr)
        addr &= 0x7FFF
        return 0 if @rom_len <= 0
        return addr % @rom_len unless mbc1_cart?

        rom_banks = [@rom_len / ROM_BANK_SIZE, 1].max
        bank_off = addr & 0x3FFF
        upper_window = (addr & 0x4000) != 0

        bank = if upper_window
                 low5 = @mbc1_rom_bank_low5.zero? ? 1 : @mbc1_rom_bank_low5
                 high2 = (@mbc1_bank_high2 << 5)
                 (low5 | high2) & 0x7F
               elsif @mbc1_mode != 0
                 (@mbc1_bank_high2 << 5) & 0x7F
               else
                 0
               end

        bank %= rom_banks
        bank = 1 if upper_window && rom_banks > 1 && bank.zero?
        ((bank * ROM_BANK_SIZE) + bank_off) % @rom_len
      end

      def mapped_cart_ram_addr(addr)
        return nil unless addr >= 0xA000 && addr <= 0xBFFF
        return nil if @cart_ram_len <= 0

        bank_off = addr & 0x1FFF
        if mbc1_cart?
          return nil unless @mbc1_ram_enable
          ram_banks = [@cart_ram_len / CART_RAM_BANK_SIZE, 1].max
          bank = @mbc1_mode.zero? ? 0 : (@mbc1_bank_high2 & 0x03)
          ((bank % ram_banks) * CART_RAM_BANK_SIZE + bank_off) % @cart_ram_len
        else
          bank_off % @cart_ram_len
        end
      end

      def tick_open_bus(cart_oe)
        if cart_oe
          @open_bus_cnt = 0
        elsif @open_bus_cnt < 0xFF
          @open_bus_cnt += 1
          @open_bus_data = 0xFF if @open_bus_cnt == 4
        end
      end

      def cart_ram_size_from_header(ram_size_code)
        case ram_size_code & 0xFF
        when 0x00 then 0
        when 0x01 then 2 * 1024
        when 0x02 then 8 * 1024
        when 0x03 then 32 * 1024
        when 0x04 then 128 * 1024
        when 0x05 then 64 * 1024
        else 0
        end
      end

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
        verilog_codegen = File.expand_path('../../../../lib/rhdl/codegen/verilog/verilog.rb', __dir__)
        hdl_glob = File.expand_path('../../hdl/**/*.rb', __dir__)
        hdl_deps = Dir.glob(hdl_glob)
        gameboy_top = File.expand_path('../../gameboy.rb', __dir__)
        export_deps = [__FILE__, verilog_codegen, gameboy_top, *hdl_deps].select { |p| File.exist?(p) }
        needs_export = !File.exist?(verilog_file) ||
                       export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

        if needs_export
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
        verilog_code = RHDL::Examples::GameBoy::Gameboy.to_verilog

        # Also export all subcomponents
        subcomponent_verilog = []
        [
          RHDL::Examples::GameBoy::SpeedControl,
          RHDL::Examples::GameBoy::GB,
          RHDL::Examples::GameBoy::SM83,
          RHDL::Examples::GameBoy::SM83_ALU,
          RHDL::Examples::GameBoy::SM83_Registers,
          RHDL::Examples::GameBoy::SM83_MCode,
          RHDL::Examples::GameBoy::Timer,
          RHDL::Examples::GameBoy::Video,
          RHDL::Examples::GameBoy::Sprites,
          RHDL::Examples::GameBoy::LCD,
          RHDL::Examples::GameBoy::Sound,
          RHDL::Examples::GameBoy::ChannelSquare,
          RHDL::Examples::GameBoy::ChannelWave,
          RHDL::Examples::GameBoy::ChannelNoise,
          RHDL::Examples::GameBoy::HDMA,
          RHDL::Examples::GameBoy::Link,
          RHDL::Examples::GameBoy::DPRAM,
          RHDL::Examples::GameBoy::DPRAM15,
          RHDL::Examples::GameBoy::DPRAM7,
          RHDL::Examples::GameBoy::SPRAM
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

        verilog
      end

      def create_cpp_wrapper(cpp_file, header_file)
        header_content = <<~HEADER
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
          unsigned char sim_read_wram(void* sim, unsigned int addr);
          unsigned char sim_read_zpram(void* sim, unsigned int addr);
          unsigned char sim_read_oam(void* sim, unsigned int addr);

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

        cpp_content = <<~CPP
          #include "Vgame_boy_gameboy.h"
          #include "Vgame_boy_gameboy___024root.h"  // For internal signal access
          #include "verilated.h"
          #include "sim_wrapper.h"
          #include <cstring>

          // Verilator runtime expects this symbol when linking libverilated.
          // Our simulation doesn't use SystemC time, so return 0.
          double sc_time_stamp() { return 0; }

	          struct SimContext {
	              Vgame_boy_gameboy* dut;
	              unsigned char rom[1048576];     // 1MB ROM
	              unsigned int rom_len;           // Actual ROM size
	              unsigned char cart_type;        // Cartridge type (header 0x147)
	              unsigned char cart_ram[131072]; // 128KB cart RAM max
	              unsigned int cart_ram_len;      // Actual cart RAM size from header (0x149)
	              unsigned char open_bus_data;
	              unsigned char open_bus_cnt;
	              unsigned char boot_rom[256];    // 256 byte DMG boot ROM
	              unsigned char oam[160];         // 160 byte OAM shadow (sprite decode)
	              unsigned char framebuffer[160 * 144];  // Framebuffer
	              unsigned int lcd_x;
	              unsigned int lcd_y;
	              unsigned char prev_lcd_clkena;
	              unsigned char prev_lcd_vsync;
	              unsigned char prev_dma_active;
	              unsigned long frame_count;
	              unsigned int clk_counter;       // System clock counter for CPU cycle estimation
	              unsigned char mbc1_rom_bank_low5;
	              unsigned char mbc1_bank_high2;
	              unsigned char mbc1_mode;
              unsigned char mbc1_ram_enable;
          };

          static inline bool is_mbc1_cart(unsigned char cart_type) {
              return cart_type == 0x01 || cart_type == 0x02 || cart_type == 0x03;
          }

          static inline unsigned int cart_ram_size_from_header(unsigned char ram_size_code) {
              switch (ram_size_code) {
                  case 0x00: return 0;
                  case 0x01: return 2 * 1024;
                  case 0x02: return 8 * 1024;
                  case 0x03: return 32 * 1024;
                  case 0x04: return 128 * 1024;
                  case 0x05: return 64 * 1024;
                  default: return 0;
              }
          }

          static inline void reset_mapper(SimContext* ctx) {
              ctx->mbc1_rom_bank_low5 = 1;
              ctx->mbc1_bank_high2 = 0;
              ctx->mbc1_mode = 0;
              ctx->mbc1_ram_enable = 0;
          }

          static inline void apply_mapper_write(SimContext* ctx, unsigned int full_addr, unsigned char data) {
              if (!is_mbc1_cart(ctx->cart_type)) {
                  return;
              }
              unsigned int addr = full_addr & 0x7FFF;
              if (addr <= 0x1FFF) {
                  ctx->mbc1_ram_enable = ((data & 0x0F) == 0x0A) ? 1 : 0;
              } else if (addr <= 0x3FFF) {
                  unsigned char bank = data & 0x1F;
                  if (bank == 0) bank = 1;
                  ctx->mbc1_rom_bank_low5 = bank;
              } else if (addr <= 0x5FFF) {
                  ctx->mbc1_bank_high2 = data & 0x03;
              } else if (addr <= 0x7FFF) {
                  ctx->mbc1_mode = data & 0x01;
              }
          }

          static inline unsigned int map_rom_addr(const SimContext* ctx, unsigned int full_addr) {
              if (ctx->rom_len == 0) {
                  return 0;
              }

              unsigned int addr = full_addr & 0x7FFF;
              if (!is_mbc1_cart(ctx->cart_type)) {
                  return addr % ctx->rom_len;
              }

              unsigned int rom_banks = ctx->rom_len / 0x4000;
              if (rom_banks == 0) rom_banks = 1;

              unsigned int bank_off = addr & 0x3FFF;
              bool upper_window = (addr & 0x4000) != 0;
              unsigned int bank;

              if (upper_window) {
                  unsigned int low5 = (ctx->mbc1_rom_bank_low5 == 0) ? 1 : ctx->mbc1_rom_bank_low5;
                  unsigned int high2 = (ctx->mbc1_bank_high2 << 5);
                  bank = (low5 | high2) & 0x7F;
              } else if (ctx->mbc1_mode != 0) {
                  bank = (ctx->mbc1_bank_high2 << 5) & 0x7F;
              } else {
                  bank = 0;
              }

              bank %= rom_banks;
              if (upper_window && rom_banks > 1 && bank == 0) {
                  bank = 1;
              }

              return ((bank * 0x4000) + bank_off) % ctx->rom_len;
          }

          static inline bool map_cart_ram_addr(const SimContext* ctx, unsigned int full_addr, unsigned int* out_addr) {
              if (ctx->cart_ram_len == 0 || out_addr == nullptr) {
                  return false;
              }

              const unsigned int a = full_addr & 0xFFFF;
              if (a < 0xA000 || a > 0xBFFF) {
                  return false;
              }

              const unsigned int bank_off = a & 0x1FFF;
              if (is_mbc1_cart(ctx->cart_type)) {
                  if (!ctx->mbc1_ram_enable) {
                      return false;
                  }
                  unsigned int ram_banks = ctx->cart_ram_len / 0x2000;
                  if (ram_banks == 0) ram_banks = 1;
                  const unsigned int bank = (ctx->mbc1_mode == 0) ? 0U : (static_cast<unsigned int>(ctx->mbc1_bank_high2) & 0x03U);
                  *out_addr = (((bank % ram_banks) * 0x2000) + bank_off) % ctx->cart_ram_len;
                  return true;
              }

              *out_addr = bank_off % ctx->cart_ram_len;
              return true;
          }

          static inline void tick_open_bus(SimContext* ctx, bool cart_oe) {
              if (cart_oe) {
                  ctx->open_bus_cnt = 0;
              } else if (ctx->open_bus_cnt != 0xFF) {
                  ctx->open_bus_cnt = static_cast<unsigned char>(ctx->open_bus_cnt + 1);
                  if (ctx->open_bus_cnt == 4) {
                      ctx->open_bus_data = 0xFF;
                  }
              }
          }

	          static inline unsigned char read_live_vram(const SimContext* ctx, unsigned int addr) {
	              const auto* root = ctx->dut->rootp;
	              return static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__vram0__DOT__mem[addr & 0x1FFF] & 0xFF
	              );
	          }

	          static inline unsigned char read_live_wram(const SimContext* ctx, unsigned int addr) {
	              const auto* root = ctx->dut->rootp;
	              return static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__wram__DOT__mem[addr & 0x7FFF] & 0xFF
	              );
	          }

	          static inline unsigned char read_live_zpram(const SimContext* ctx, unsigned int addr) {
	              const auto* root = ctx->dut->rootp;
	              return static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__zpram__DOT__mem[addr & 0x7F] & 0xFF
	              );
	          }

	          static inline unsigned char read_dma_source(const SimContext* ctx, unsigned int addr) {
	              const unsigned int a = addr & 0xFFFF;
	              if (a <= 0x7FFF) {
	                  unsigned int mapped = map_rom_addr(ctx, a);
	                  return (mapped < ctx->rom_len) ? ctx->rom[mapped] : 0xFF;
	              }
	              if (a >= 0xA000 && a <= 0xBFFF) {
	                  unsigned int ram_addr = 0;
	                  if (map_cart_ram_addr(ctx, a, &ram_addr)) {
	                      return ctx->cart_ram[ram_addr];
	                  }
	                  return 0xFF;
	              }
	              if (a >= 0x8000 && a <= 0x9FFF) return read_live_vram(ctx, a - 0x8000);
	              if (a >= 0xC000 && a <= 0xDFFF) return read_live_wram(ctx, a - 0xC000);
	              if (a >= 0xE000 && a <= 0xFDFF) return read_live_wram(ctx, a - 0xE000);
	              if (a >= 0xFF80 && a <= 0xFFFE) return read_live_zpram(ctx, a - 0xFF80);
	              return 0xFF;
	          }

	          static inline void sync_oam_dma_if_needed(SimContext* ctx) {
	              auto* root = ctx->dut->rootp;
	              const unsigned char dma_active = static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__dma_active & 0x1
	              );
	              if (dma_active && !ctx->prev_dma_active) {
	                  const unsigned int page = static_cast<unsigned int>(
	                      root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__dma_reg & 0xFF
	                  );
	                  for (unsigned int i = 0; i < 160; ++i) {
	                      ctx->oam[i] = read_dma_source(ctx, (page << 8) | i);
	                  }
	              }
	              ctx->prev_dma_active = dma_active;
	          }

	          struct SpriteCandidate {
	              int idx;
	              int sx;
	              int sy;
	              unsigned char tile;
	              unsigned char attr;
	          };

	          static inline void render_dmg_framebuffer(SimContext* ctx) {
	              auto* root = ctx->dut->rootp;

	              const unsigned char lcdc = static_cast<unsigned char>(
                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__lcdc & 0xFF
              );
              const unsigned char scx = static_cast<unsigned char>(
                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__scx & 0xFF
              );
              const unsigned char scy = static_cast<unsigned char>(
                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__scy & 0xFF
              );
	              const unsigned char bgp = static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__bgp & 0xFF
	              );
	              const unsigned char obp0 = static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__obp0 & 0xFF
	              );
	              const unsigned char obp1 = static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__obp1 & 0xFF
	              );
	              const unsigned char wx = static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__wx & 0xFF
	              );
	              const unsigned char wy = static_cast<unsigned char>(
	                  root->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__wy & 0xFF
	              );

	              const bool lcd_on = (lcdc & 0x80) != 0;
	              const bool bg_enable = (lcdc & 0x01) != 0;
	              const bool sprite_enable = (lcdc & 0x02) != 0;
	              const unsigned int sprite_height = (lcdc & 0x04) ? 16 : 8;
	              const bool win_enable = (lcdc & 0x20) != 0;
	              const bool unsigned_tiles = (lcdc & 0x10) != 0;
	              const unsigned int bg_map_base = (lcdc & 0x08) ? 0x1C00 : 0x1800;
	              const unsigned int win_map_base = (lcdc & 0x40) ? 0x1C00 : 0x1800;
	              const int win_x_start = static_cast<int>(wx) - 7;

              if (!lcd_on) {
	                  memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
	                  return;
	              }

	              unsigned char bg_raw[160 * 144];

	              for (unsigned int y = 0; y < 144; ++y) {
	                  const bool win_line_active = win_enable &&
	                                               (y >= static_cast<unsigned int>(wy)) &&
	                                               (win_x_start < 160);
	                  for (unsigned int x = 0; x < 160; ++x) {
	                      const unsigned int fb_idx = y * 160 + x;
	                      unsigned char raw = 0;
	                      unsigned char color = 0;
	                      if (bg_enable) {
	                          const bool use_window = win_line_active && (static_cast<int>(x) >= win_x_start);
	                          const unsigned int map_base = use_window ? win_map_base : bg_map_base;
	                          const unsigned int src_x = use_window
	                              ? static_cast<unsigned int>((static_cast<int>(x) - win_x_start) & 0xFF)
	                              : static_cast<unsigned int>((x + scx) & 0xFF);
                          const unsigned int src_y = use_window
                              ? static_cast<unsigned int>((static_cast<int>(y) - static_cast<int>(wy)) & 0xFF)
                              : static_cast<unsigned int>((y + scy) & 0xFF);

                          const unsigned int tile_row = (src_y >> 3) & 0x1F;
                          const unsigned int tile_col = (src_x >> 3) & 0x1F;
                          const unsigned int map_addr = map_base + tile_row * 32 + tile_col;
                          const unsigned char tile_num = read_live_vram(ctx, map_addr);
                          const unsigned int row_in_tile = src_y & 0x07;

                          unsigned int tile_addr;
                          if (unsigned_tiles) {
                              tile_addr = ((static_cast<unsigned int>(tile_num) << 4) +
                                           (row_in_tile << 1)) & 0x1FFF;
                          } else {
                              const int signed_tile = (tile_num < 0x80)
                                  ? static_cast<int>(tile_num)
                                  : static_cast<int>(tile_num) - 0x100;
                              tile_addr = static_cast<unsigned int>(
                                  (0x1000 + signed_tile * 16 + static_cast<int>(row_in_tile << 1)) & 0x1FFF
                              );
                          }

	                          const unsigned char lo = read_live_vram(ctx, tile_addr);
	                          const unsigned char hi = read_live_vram(ctx, (tile_addr + 1) & 0x1FFF);
	                          const unsigned int bit = 7 - (src_x & 0x07);
	                          raw = static_cast<unsigned char>(
	                              (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
	                          );
	                          color = static_cast<unsigned char>((bgp >> (raw * 2)) & 0x03);
	                      }
	                      bg_raw[fb_idx] = raw;
	                      ctx->framebuffer[fb_idx] = color;
	                  }
	              }

	              if (!sprite_enable) {
	                  return;
	              }

	              for (unsigned int y = 0; y < 144; ++y) {
	                  SpriteCandidate line[40];
	                  int count = 0;

	                  for (int i = 0; i < 40; ++i) {
	                      const int base = i * 4;
	                      const int sy = static_cast<int>(ctx->oam[base]) - 16;
	                      const int sx = static_cast<int>(ctx->oam[base + 1]) - 8;
	                      if (static_cast<int>(y) < sy || static_cast<int>(y) >= sy + static_cast<int>(sprite_height)) continue;
	                      if (sx <= -8 || sx >= 160) continue;
	                      line[count++] = SpriteCandidate{
	                          i,
	                          sx,
	                          sy,
	                          ctx->oam[base + 2],
	                          ctx->oam[base + 3]
	                      };
	                  }

	                  // DMG priority: lower X first, then lower OAM index.
	                  for (int i = 1; i < count; ++i) {
	                      SpriteCandidate key = line[i];
	                      int j = i - 1;
	                      while (j >= 0 &&
	                             (line[j].sx > key.sx ||
	                              (line[j].sx == key.sx && line[j].idx > key.idx))) {
	                          line[j + 1] = line[j];
	                          --j;
	                      }
	                      line[j + 1] = key;
	                  }

	                  const int limit = (count < 10) ? count : 10;

	                  // Draw low-priority first, then high-priority over it.
	                  for (int s = limit - 1; s >= 0; --s) {
	                      const SpriteCandidate& sp = line[s];
	                      int row = static_cast<int>(y) - sp.sy;
	                      const bool y_flip = (sp.attr & 0x40) != 0;
	                      const bool x_flip = (sp.attr & 0x20) != 0;
	                      const bool behind_bg = (sp.attr & 0x80) != 0;
	                      if (y_flip) row = static_cast<int>(sprite_height) - 1 - row;

	                      unsigned int tile_index = sp.tile;
	                      if (sprite_height == 16) {
	                          tile_index &= 0xFE;
	                          if (row >= 8) tile_index += 1;
	                      }
	                      const unsigned int row_in_tile = static_cast<unsigned int>(row & 0x07);
	                      const unsigned int tile_addr = ((tile_index << 4) + (row_in_tile << 1)) & 0x1FFF;
	                      const unsigned char lo = read_live_vram(ctx, tile_addr);
	                      const unsigned char hi = read_live_vram(ctx, (tile_addr + 1) & 0x1FFF);
	                      const unsigned char palette = (sp.attr & 0x10) ? obp1 : obp0;

	                      for (int col = 0; col < 8; ++col) {
	                          const int x = sp.sx + col;
	                          if (x < 0 || x >= 160) continue;
	                          const unsigned int bit = static_cast<unsigned int>(x_flip ? col : (7 - col));
	                          const unsigned char raw = static_cast<unsigned char>(
	                              (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
	                          );
	                          if (raw == 0) continue;
	                          const unsigned int fb_idx = y * 160 + static_cast<unsigned int>(x);
	                          if (behind_bg && bg_raw[fb_idx] != 0) continue;
	                          ctx->framebuffer[fb_idx] = static_cast<unsigned char>((palette >> (raw * 2)) & 0x03);
	                      }
	                  }
	              }
	          }

          extern "C" {

	          void* sim_create(void) {
	              const char* empty_args[] = {""};
	              Verilated::commandArgs(1, empty_args);
	              SimContext* ctx = new SimContext();
              ctx->dut = new Vgame_boy_gameboy();
              ctx->dut->clk_sys = 0;
              ctx->dut->reset = 0;
              ctx->dut->joystick = 0xFF;
              ctx->dut->is_gbc = 0;
              ctx->dut->is_sgb = 0;
              ctx->dut->cart_do = 0;
              memset(ctx->rom, 0, sizeof(ctx->rom));
	              ctx->rom_len = 0;
	              ctx->cart_type = 0x00;
	              memset(ctx->cart_ram, 0xFF, sizeof(ctx->cart_ram));
	              ctx->cart_ram_len = 0;
	              ctx->open_bus_data = 0;
	              ctx->open_bus_cnt = 0;
	              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
	              memset(ctx->oam, 0, sizeof(ctx->oam));
	              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
	              ctx->lcd_x = 0;
	              ctx->lcd_y = 0;
	              ctx->prev_lcd_clkena = 0;
	              ctx->prev_lcd_vsync = 0;
	              ctx->prev_dma_active = 0;
	              ctx->frame_count = 0;
	              ctx->clk_counter = 0;
	              reset_mapper(ctx);
	              return ctx;
	          }

          void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
          }

          void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              reset_mapper(ctx);
              ctx->open_bus_data = 0;
              ctx->open_bus_cnt = 0;
              ctx->dut->joystick = 0xFF;
              ctx->dut->is_gbc = 0;
              ctx->dut->is_sgb = 0;
              ctx->dut->cart_do = 0;
              // Hold reset high and clock a few times to properly reset sequential logic
              ctx->dut->reset = 1;
              for (int i = 0; i < 10; i++) {
                  ctx->dut->clk_sys = 0;
                  ctx->dut->eval();
                  ctx->dut->clk_sys = 1;
                  ctx->dut->eval();
              }
              // Release reset and clock to let the system initialize
              // IMPORTANT: Must provide boot ROM data during these cycles!
              ctx->dut->reset = 0;
              for (int i = 0; i < 100; i++) {
                  ctx->dut->clk_sys = 0;
                  ctx->dut->eval();

                  // Provide boot ROM data (same as in sim_run_cycles)
                  unsigned int boot_addr = ctx->dut->boot_rom_addr & 0xFF;
                  ctx->dut->boot_rom_do = ctx->boot_rom[boot_addr];

                  unsigned int addr = ctx->dut->ext_bus_addr;
                  unsigned int a15 = ctx->dut->ext_bus_a15;
                  unsigned int full_addr = ((a15 & 1U) << 15) | (addr & 0x7FFF);
                  unsigned int ram_addr = 0;
                  bool ram_valid = map_cart_ram_addr(ctx, full_addr, &ram_addr);
                  bool cart_oe = (full_addr <= 0x7FFF) || ram_valid;
                  tick_open_bus(ctx, cart_oe);

                  // Handle mapper writes
                  if (ctx->dut->cart_wr) {
                      unsigned char cart_di = static_cast<unsigned char>(ctx->dut->cart_di & 0xFF);
                      if (full_addr <= 0x7FFF) {
                          apply_mapper_write(ctx, full_addr, cart_di);
                      } else if (ram_valid) {
                          ctx->cart_ram[ram_addr] = cart_di;
                      }
                  }

                  unsigned char data = 0xFF;
                  if (full_addr <= 0x7FFF) {
                      unsigned int mapped_addr = map_rom_addr(ctx, full_addr);
                      data = (mapped_addr < ctx->rom_len) ? ctx->rom[mapped_addr] : 0xFF;
                  } else if (ram_valid) {
                      data = ctx->cart_ram[ram_addr];
                  } else {
                      data = ctx->open_bus_data;
                  }
                  if (ctx->dut->cart_rd) {
                      ctx->open_bus_data = data;
                  }
                  ctx->dut->cart_do = data;

                  ctx->dut->clk_sys = 1;
                  ctx->dut->eval();
              }

              ctx->lcd_x = 0;
	              ctx->lcd_y = 0;
	              ctx->frame_count = 0;
	              ctx->clk_counter = 0;  // Reset clock counter
	              ctx->prev_dma_active = 0;
	              memset(ctx->oam, 0, sizeof(ctx->oam));
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
              else if (strcmp(name, "debug_f") == 0) return ctx->dut->debug_f;
              else if (strcmp(name, "debug_b") == 0) return ctx->dut->debug_b;
              else if (strcmp(name, "debug_c") == 0) return ctx->dut->debug_c;
              else if (strcmp(name, "debug_d") == 0) return ctx->dut->debug_d;
              else if (strcmp(name, "debug_e") == 0) return ctx->dut->debug_e;
              else if (strcmp(name, "debug_h") == 0) return ctx->dut->debug_h;
              else if (strcmp(name, "debug_l") == 0) return ctx->dut->debug_l;
              else if (strcmp(name, "debug_sp") == 0) return ctx->dut->debug_sp;
              else if (strcmp(name, "debug_ir") == 0) return ctx->dut->debug_ir;
              else if (strcmp(name, "debug_save_alu") == 0) return ctx->dut->debug_save_alu;
              else if (strcmp(name, "debug_t_state") == 0) return ctx->dut->debug_t_state;
              else if (strcmp(name, "debug_m_cycle") == 0) return ctx->dut->debug_m_cycle;
              else if (strcmp(name, "debug_alu_flags") == 0) return ctx->dut->debug_alu_flags;
              else if (strcmp(name, "debug_clken") == 0) return ctx->dut->debug_clken;
              else if (strcmp(name, "debug_alu_op") == 0) return ctx->dut->debug_alu_op;
              else if (strcmp(name, "debug_bus_a") == 0) return ctx->dut->debug_bus_a;
              else if (strcmp(name, "debug_bus_b") == 0) return ctx->dut->debug_bus_b;
              else if (strcmp(name, "debug_alu_result") == 0) return ctx->dut->debug_alu_result;
              else if (strcmp(name, "debug_z_flag") == 0) return ctx->dut->debug_z_flag;
              else if (strcmp(name, "debug_bus_a_zero") == 0) return ctx->dut->debug_bus_a_zero;
              else if (strcmp(name, "debug_const_one") == 0) return ctx->dut->debug_const_one;
              else if (strcmp(name, "gb_core__video_unit__lcdc") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__lcdc;
              else if (strcmp(name, "gb_core__video_unit__scx") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__scx;
              else if (strcmp(name, "gb_core__video_unit__scy") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__scy;
              else if (strcmp(name, "gb_core__video_unit__bgp") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__bgp;
              else if (strcmp(name, "gb_core__video_unit__wx") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__wx;
              else if (strcmp(name, "gb_core__video_unit__wy") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__wy;
              else if (strcmp(name, "gb_core__video_unit__h_cnt") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__h_cnt;
              else if (strcmp(name, "gb_core__video_unit__h_div_cnt") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__h_div_cnt;
              else if (strcmp(name, "gb_core__video_unit__v_cnt") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__v_cnt;
              else if (strcmp(name, "gb_core__video_unit__pcnt") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__pcnt;
              else if (strcmp(name, "gb_core__video_unit__fetch_phase") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__fetch_phase;
              else if (strcmp(name, "gb_core__video_unit__tile_num") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__tile_num;
              else if (strcmp(name, "gb_core__video_unit__tile_data_lo") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__tile_data_lo;
              else if (strcmp(name, "gb_core__video_unit__tile_data_hi") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__tile_data_hi;
              else if (strcmp(name, "gb_core__video_unit__vblank") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__v_cnt >= 144;
              else if (strcmp(name, "gb_core__video_unit__oam_eval") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__oam_eval;
              else if (strcmp(name, "gb_core__video_unit__vram_rd") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit___05Fvram_rd;
              else if (strcmp(name, "gb_core__video_unit__dma_active") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__dma_active;
              else if (strcmp(name, "gb_core__video_unit__dma_cnt") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__dma_cnt;
              else if (strcmp(name, "gb_core__vram_addr_ppu") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__vram_addr_mux;
              else if (strcmp(name, "gb_core__vram_data_ppu") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__vram0___05Fq_a;
              else if (strcmp(name, "gb_core__wram__wren_b") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__wram__DOT__wren_b;
              else if (strcmp(name, "gb_core__wram__data_b") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__wram__DOT__data_b;
              else if (strcmp(name, "gb_core__wram__address_b") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__wram__DOT__address_b;
              else if (strcmp(name, "gb_core__wram_addr") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__wram_addr;
              else if (strcmp(name, "gb_core__cpu_di") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__cpu_di;
              else if (strcmp(name, "gb_core__if_r") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__if_r;
              else if (strcmp(name, "gb_core__ie_r") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__ie_r;
              else if (strcmp(name, "gb_core__joypad_irq") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__joypad_irq;
              else if (strcmp(name, "gb_core__irq_n") == 0) return ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__irq_n;
              // Internal signals not accessible - return estimated values
              else if (strcmp(name, "_clkdiv") == 0) return ctx->clk_counter & 7;  // Estimate clkdiv
              // Other internal signals not accessible
              return 0;
          }

          void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memset(ctx->rom, 0, sizeof(ctx->rom));
              ctx->rom_len = (len < sizeof(ctx->rom)) ? len : sizeof(ctx->rom);
              ctx->cart_type = (ctx->rom_len > 0x147) ? data[0x147] : 0x00;
              unsigned char ram_size = (ctx->rom_len > 0x149) ? data[0x149] : 0x00;
              ctx->cart_ram_len = cart_ram_size_from_header(ram_size);
              if (ctx->cart_ram_len > sizeof(ctx->cart_ram)) {
                  ctx->cart_ram_len = sizeof(ctx->cart_ram);
              }
              memset(ctx->cart_ram, 0xFF, sizeof(ctx->cart_ram));
              ctx->open_bus_data = 0;
              ctx->open_bus_cnt = 0;
              reset_mapper(ctx);
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
              if (addr < 8192) {
                  ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__vram0__DOT__mem[addr] = value;
              }
          }

          unsigned char sim_read_vram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < 8192) {
                  return read_live_vram(ctx, addr);
              }
              return 0;
          }

          unsigned char sim_read_wram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < 32768) {
                  return read_live_wram(ctx, addr);
              }
              return 0;
          }

          unsigned char sim_read_zpram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < 128) {
                  return read_live_zpram(ctx, addr);
              }
              return 0;
          }

          unsigned char sim_read_oam(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < 160) {
                  return ctx->oam[addr];
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

                  // Provide boot ROM data based on boot_rom_addr
                  unsigned int boot_addr = ctx->dut->boot_rom_addr & 0xFF;
                  ctx->dut->boot_rom_do = ctx->boot_rom[boot_addr];

                  unsigned int addr = ctx->dut->ext_bus_addr;
                  unsigned int a15 = ctx->dut->ext_bus_a15;
                  unsigned int full_addr = ((a15 & 1U) << 15) | (addr & 0x7FFF);
                  unsigned int ram_addr = 0;
                  bool ram_valid = map_cart_ram_addr(ctx, full_addr, &ram_addr);
                  bool cart_oe = (full_addr <= 0x7FFF) || ram_valid;
                  tick_open_bus(ctx, cart_oe);

                  // Handle mapper writes
                  if (ctx->dut->cart_wr) {
                      unsigned char cart_di = static_cast<unsigned char>(ctx->dut->cart_di & 0xFF);
                      if (full_addr <= 0x7FFF) {
                          apply_mapper_write(ctx, full_addr, cart_di);
                      } else if (ram_valid) {
                          ctx->cart_ram[ram_addr] = cart_di;
                      }
                  }

                  unsigned char data = 0xFF;
                  if (full_addr <= 0x7FFF) {
                      unsigned int mapped_addr = map_rom_addr(ctx, full_addr);
                      data = (mapped_addr < ctx->rom_len) ? ctx->rom[mapped_addr] : 0xFF;
                  } else if (ram_valid) {
                      data = ctx->cart_ram[ram_addr];
                  } else {
                      data = ctx->open_bus_data;
                  }
                  if (ctx->dut->cart_rd) {
                      ctx->open_bus_data = data;
                  }
                  ctx->dut->cart_do = data;
                  ctx->dut->eval();

	                  // Rising edge
	                  ctx->dut->clk_sys = 1;
	                  ctx->dut->eval();

	                  // Keep a software shadow of OAM by mirroring DMA copies.
	                  // Sprite RAM is not fully modeled in HDL yet, but ROMs use DMA heavily.
	                  sync_oam_dma_if_needed(ctx);

	                  // Count every system clock as a CPU cycle
	                  // SpeedControl outputs ce=1 always (no division), so CPU executes every clock
	                  ctx->clk_counter++;
	                  result->cycles_run++;

                  // Capture LCD output
                  unsigned char lcd_clkena = ctx->dut->lcd_clkena;
                  unsigned char lcd_vsync = ctx->dut->lcd_vsync;
                  unsigned char lcd_data = ctx->dut->lcd_data_gb & 0x3;

                  // Capture by hardware counters to avoid software raster drift.
                  if (lcd_clkena) {
                      const unsigned int pcnt = static_cast<unsigned int>(
                          ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__pcnt & 0xFF
                      );
                      const unsigned int v_cnt = static_cast<unsigned int>(
                          ctx->dut->rootp->game_boy_gameboy__DOT__gb_core__DOT__video_unit__DOT__v_cnt & 0xFF
                      );
                  if (v_cnt < 144 && pcnt < 160) {
                      const unsigned int x = pcnt;
                      ctx->framebuffer[v_cnt * 160 + x] = lcd_data;
                      ctx->lcd_x = static_cast<unsigned char>(x);
                      ctx->lcd_y = static_cast<unsigned char>(v_cnt);
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

        # On some platforms (notably macOS), Verilator's make output may not update the
        # requested shared library even if compilation succeeds. Ensure the dylib/so
        # is freshly linked from the static archives when needed.
        lib_vgameboy = File.join(OBJ_DIR, 'libVgame_boy_gameboy.a')
        lib_verilated = File.join(OBJ_DIR, 'libverilated.a')
        newest_input = [lib_vgameboy, lib_verilated].filter_map { |p| File.exist?(p) ? File.mtime(p) : nil }.max
        lib_mtime = File.exist?(lib_path) ? File.mtime(lib_path) : nil

        if lib_mtime.nil? || (!newest_input.nil? && lib_mtime < newest_input)
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

        @sim_read_wram_fn = Fiddle::Function.new(
          @lib['sim_read_wram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_CHAR
        )

        @sim_read_zpram_fn = Fiddle::Function.new(
          @lib['sim_read_zpram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_CHAR
        )

        @sim_read_oam_fn = Fiddle::Function.new(
          @lib['sim_read_oam'],
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
        @sim_read_vram_fn.call(@sim_ctx, addr) & 0xFF
      end

      def verilator_read_wram(addr)
        return 0 unless @sim_ctx
        @sim_read_wram_fn.call(@sim_ctx, addr) & 0xFF
      end

      def verilator_read_zpram(addr)
        return 0 unless @sim_ctx
        @sim_read_zpram_fn.call(@sim_ctx, addr) & 0xFF
      end

      def verilator_read_oam(addr)
        return 0 unless @sim_ctx && @sim_read_oam_fn
        @sim_read_oam_fn.call(@sim_ctx, addr) & 0xFF
      end

      def decode_framebuffer_from_memory
        frame_id = frame_count
        return @decoded_framebuffer_rows if frame_id == @decoded_frame_count

        lcdc = read_video_reg('lcdc')
        scx = read_video_reg('scx')
        scy = read_video_reg('scy')
        bgp = read_video_reg('bgp')
        obp0 = read_video_reg('obp0')
        obp1 = read_video_reg('obp1')
        wx = read_video_reg('wx')
        wy = read_video_reg('wy')

        vram = Array.new(8192) { |i| verilator_read_vram(i) }
        oam = Array.new(160) { |i| verilator_read_oam(i) }

        flat = FramebufferDecoder.decode_dmg_flat(
          vram: vram,
          oam: oam,
          lcdc: lcdc,
          scx: scx,
          scy: scy,
          bgp: bgp,
          obp0: obp0,
          obp1: obp1,
          wx: wx,
          wy: wy
        )

        @decoded_framebuffer_rows = FramebufferDecoder.flat_to_rows(flat)
        @decoded_frame_count = frame_id
        @decoded_framebuffer_rows
      rescue StandardError
        @decoded_framebuffer_rows
      end

      def read_video_reg(name)
        (verilator_peek("gb_core__video_unit__#{name}") || 0) & 0xFF
      end
      end
    end
  end
end
