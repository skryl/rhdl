# frozen_string_literal: true

# Apple II Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the Apple2 HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface similar to the Rust IR runners.
#
# Usage:
#   runner = RHDL::Apple2::VerilatorRunner.new(sub_cycles: 14)
#   runner.reset
#   runner.run_steps(100)

require_relative '../hdl/apple2'
require_relative 'speaker'
require_relative 'color_renderer'
require_relative 'ps2_encoder'
require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'fiddle/import'

module RHDL
  module Apple2
    # Verilator-based runner for Apple II simulation
    # Compiles RHDL Verilog export to native code via Verilator
    class VerilatorRunner
      # Text page constants
      TEXT_PAGE1_START = 0x0400
      TEXT_PAGE1_END = 0x07FF

      # Hi-res graphics pages
      HIRES_PAGE1_START = 0x2000
      HIRES_PAGE1_END = 0x3FFF
      HIRES_WIDTH = 280
      HIRES_HEIGHT = 192
      HIRES_BYTES_PER_LINE = 40

      # Build directory for Verilator output
      BUILD_DIR = File.expand_path('../../../.verilator_build', __dir__)
      VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
      OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')

      # Initialize the Apple II Verilator runner
      # @param sub_cycles [Integer] Sub-cycles per CPU cycle (1-14, default: 14)
      def initialize(sub_cycles: 14)
        @sub_cycles = sub_cycles.clamp(1, 14)

        check_verilator_available!

        puts "Initializing Apple2 Verilator simulation..."
        start_time = Time.now

        # Build and load the Verilator simulation
        build_verilator_simulation

        elapsed = Time.now - start_time
        puts "  Verilator simulation built in #{elapsed.round(2)}s"
        puts "  Sub-cycles: #{@sub_cycles} (#{@sub_cycles == 14 ? 'full accuracy' : 'fast mode'})"

        @cycles = 0
        @halted = false
        @text_page_dirty = false

        # Memory arrays
        @ram = Array.new(48 * 1024, 0)
        @rom = Array.new(12 * 1024, 0)

        # PS/2 keyboard encoder
        @ps2_encoder = PS2Encoder.new

        # Speaker audio simulation
        @speaker = Speaker.new
        @prev_speaker_state = 0
        @last_speaker_sync_time = nil

        reset_simulation
      end

      def native?
        true
      end

      def simulator_type
        :hdl_verilator
      end

      def load_rom(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        # Keep Ruby copy for compatibility
        bytes.each_with_index do |byte, i|
          @rom[i] = byte if i < @rom.size
        end
        # Bulk load into C++ side
        if @sim_load_rom_fn && @sim_ctx
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
        end
      end

      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        # Keep Ruby copy for compatibility
        bytes.each_with_index do |byte, i|
          addr = base_addr + i
          @ram[addr] = byte if addr < @ram.size
        end
        # Bulk load into C++ side
        if @sim_load_ram_fn && @sim_ctx
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_ram_fn.call(@sim_ctx, data_ptr, base_addr, bytes.size)
        end
      end

      def load_disk(path_or_bytes, drive: 0)
        puts "Warning: Disk support in Verilator mode is limited"
        @disk_loaded = true
      end

      def disk_loaded?(drive: 0)
        @disk_loaded || false
      end

      def reset
        reset_simulation
        @cycles = 0
        @halted = false
      end

      # Write a single byte to memory
      def write_memory(addr, byte)
        if addr >= 0xD000
          # ROM area
          offset = addr - 0xD000
          @rom[offset] = byte if offset < @rom.size
          # Also write to C++ ROM
          if @sim_write_rom_fn && @sim_ctx && offset < @rom.size
            @sim_write_rom_fn.call(@sim_ctx, offset, byte)
          end
        else
          # RAM area
          @ram[addr] = byte if addr < @ram.size
          verilator_write_ram(addr, byte) if addr < @ram.size
        end
      end

      # Get current program counter
      def pc
        verilator_peek('pc_debug')
      end

      # Main entry point for running cycles
      def run_steps(steps)
        if @sim_run_cycles_fn
          # Use batch execution - run all 14MHz cycles in C++
          n_14m_cycles = steps * @sub_cycles
          text_dirty_ptr = Fiddle::Pointer.malloc(4)  # 4 bytes for unsigned int
          speaker_toggles = @sim_run_cycles_fn.call(@sim_ctx, n_14m_cycles, text_dirty_ptr)
          text_dirty = text_dirty_ptr.to_s(4).unpack1('L') # unsigned int
          @text_page_dirty ||= (text_dirty != 0)
          speaker_toggles.times { @speaker.toggle }
          @cycles += steps
        else
          # Fallback to per-cycle Ruby execution
          steps.times { run_cpu_cycle }
        end
      end

      def run_cpu_cycle
        @sub_cycles.times { run_14m_cycle }
        @cycles += 1
      end

      # Run a single 14MHz cycle
      def run_14m_cycle
        # Update PS/2 keyboard signals
        ps2_clk, ps2_data = @ps2_encoder.next_ps2_state
        verilator_poke('ps2_clk', ps2_clk)
        verilator_poke('ps2_data', ps2_data)

        # Falling edge
        verilator_poke('clk_14m', 0)
        verilator_eval

        # Provide RAM/ROM data
        ram_addr = verilator_peek('ram_addr')
        if ram_addr >= 0xD000 && ram_addr <= 0xFFFF
          rom_offset = ram_addr - 0xD000
          verilator_poke('ram_do', @rom[rom_offset] || 0)
        elsif ram_addr < @ram.size
          verilator_poke('ram_do', @ram[ram_addr] || 0)
        else
          verilator_poke('ram_do', 0)
        end
        verilator_eval

        # Rising edge
        verilator_poke('clk_14m', 1)
        verilator_eval

        # Handle RAM writes
        ram_we = verilator_peek('ram_we')
        if ram_we == 1
          write_addr = verilator_peek('ram_addr')
          if write_addr < @ram.size
            data = verilator_peek('d')
            @ram[write_addr] = data & 0xFF
            if write_addr >= TEXT_PAGE1_START && write_addr <= TEXT_PAGE1_END
              @text_page_dirty = true
            end
          end
        end

        # Monitor speaker output
        speaker_state = verilator_peek('speaker')
        if speaker_state != @prev_speaker_state
          @speaker.toggle
          @prev_speaker_state = speaker_state
        end
      end

      # Inject a key through the PS/2 keyboard controller
      def inject_key(ascii)
        @ps2_encoder.queue_key(ascii)
      end

      def key_ready?
        @ps2_encoder.sending?
      end

      def clear_key
        @ps2_encoder.clear
      end

      def read_screen_array
        result = []
        24.times do |row|
          line = []
          base = text_line_address(row)
          40.times do |col|
            line << (@ram[base + col] || 0)
          end
          result << line
        end
        result
      end

      def read_screen
        read_screen_array.map do |line|
          line.map { |c| ((c & 0x7F) >= 0x20 ? (c & 0x7F).chr : ' ') }.join
        end
      end

      def screen_dirty?
        @text_page_dirty
      end

      def clear_screen_dirty
        @text_page_dirty = false
      end

      def read_hires_bitmap
        base = HIRES_PAGE1_START
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base)

          HIRES_BYTES_PER_LINE.times do |col|
            byte = @ram[line_addr + col] || 0
            7.times do |bit|
              line << ((byte >> bit) & 1)
            end
          end

          bitmap << line
        end

        bitmap
      end

      def render_hires_braille(chars_wide: 80, invert: false)
        bitmap = read_hires_bitmap

        chars_tall = (HIRES_HEIGHT / 4.0).ceil
        x_scale = HIRES_WIDTH.to_f / (chars_wide * 2)
        y_scale = HIRES_HEIGHT.to_f / (chars_tall * 4)

        dot_map = [
          [0x01, 0x08],
          [0x02, 0x10],
          [0x04, 0x20],
          [0x40, 0x80]
        ]

        lines = []
        chars_tall.times do |char_y|
          line = String.new
          chars_wide.times do |char_x|
            pattern = 0

            4.times do |dy|
              2.times do |dx|
                px = ((char_x * 2 + dx) * x_scale).to_i
                py = ((char_y * 4 + dy) * y_scale).to_i
                px = [px, HIRES_WIDTH - 1].min
                py = [py, HIRES_HEIGHT - 1].min

                pixel = bitmap[py][px]
                pixel = 1 - pixel if invert
                pattern |= dot_map[dy][dx] if pixel == 1
              end
            end

            line << (0x2800 + pattern).chr(Encoding::UTF_8)
          end
          lines << line
        end

        lines.join("\n")
      end

      def render_hires_color(chars_wide: 140)
        renderer = ColorRenderer.new(chars_wide: chars_wide)
        renderer.render(@ram, base_addr: HIRES_PAGE1_START)
      end

      def cpu_state
        {
          pc: verilator_peek('pc_debug'),
          a: verilator_peek('a_debug'),
          x: verilator_peek('x_debug'),
          y: verilator_peek('y_debug'),
          sp: 0xFF,
          p: 0,
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

      def dry_run_info
        {
          mode: :verilog,
          simulator_type: simulator_type,
          native: native?,
          cpu_state: cpu_state,
          memory_sample: memory_sample
        }
      end

      def bus
        self
      end

      def tick(cycles)
        # No-op
      end

      def disk_controller
        @disk_controller ||= DiskControllerStub.new
      end

      def speaker
        @speaker
      end

      def display_mode
        :text
      end

      def start_audio
        @speaker.start
      end

      def stop_audio
        @speaker.stop
      end

      def read(addr)
        if addr >= 0xD000 && addr <= 0xFFFF
          return @rom[addr - 0xD000] || 0
        end
        addr < @ram.size ? @ram[addr] : 0
      end

      def write(addr, value)
        if addr < @ram.size
          @ram[addr] = value & 0xFF
          verilator_write_ram(addr, value & 0xFF)
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

        # Export Apple2 to Verilog
        verilog_file = File.join(VERILOG_DIR, 'apple2.v')
        unless File.exist?(verilog_file) && File.mtime(verilog_file) > File.mtime(__FILE__)
          puts "  Exporting Apple2 to Verilog..."
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
                      File.mtime(wrapper_file) > File.mtime(lib_file) ||
                      File.mtime(__FILE__) > File.mtime(lib_file)

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
        verilog_code = Apple2.to_verilog

        # Also export all subcomponents (including nested ones)
        subcomponent_verilog = []
        # Main components
        [TimingGenerator, VideoGenerator, CharacterROM, SpeakerToggle,
         CPU6502, DiskII, DiskIIROM, Keyboard, PS2Controller].each do |component_class|
          begin
            subcomponent_verilog << component_class.to_verilog
          rescue StandardError => e
            puts "    Warning: Could not export #{component_class}: #{e.message}"
          end
        end

        all_verilog = [verilog_code, *subcomponent_verilog].join("\n\n")
        File.write(output_file, all_verilog)
      end

      def create_cpp_wrapper(cpp_file, header_file)
        # Create C++ header for FFI
        File.write(header_file, <<~HEADER)
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
          void sim_write_ram(void* sim, unsigned int addr, unsigned char value);
          unsigned char sim_read_ram(void* sim, unsigned int addr);

          #ifdef __cplusplus
          }
          #endif

          #endif // SIM_WRAPPER_H
        HEADER

        # Create C++ wrapper implementation
        File.write(cpp_file, <<~CPP)
          #include "Vapple2.h"
          #include "verilated.h"
          #include "sim_wrapper.h"
          #include <cstring>

          struct SimContext {
              Vapple2* dut;
              unsigned char ram[65536];  // 64KB RAM for Apple II
              unsigned char rom[12288];  // 12KB ROM
              unsigned char prev_speaker;
              unsigned int speaker_toggles;
          };

          extern "C" {

          void* sim_create(void) {
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);
              SimContext* ctx = new SimContext();
              ctx->dut = new Vapple2();
              memset(ctx->ram, 0, sizeof(ctx->ram));
              memset(ctx->rom, 0, sizeof(ctx->rom));
              ctx->prev_speaker = 0;
              ctx->speaker_toggles = 0;
              return ctx;
          }

          void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
          }

          void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->dut->reset = 1;
              ctx->dut->eval();
              ctx->dut->reset = 0;
              ctx->dut->eval();
          }

          void sim_eval(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->dut->eval();
          }

          void sim_poke(void* sim, const char* name, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (strcmp(name, "clk_14m") == 0) ctx->dut->clk_14m = value;
              else if (strcmp(name, "flash_clk") == 0) ctx->dut->flash_clk = value;
              else if (strcmp(name, "reset") == 0) ctx->dut->reset = value;
              else if (strcmp(name, "ram_do") == 0) ctx->dut->ram_do = value;
              else if (strcmp(name, "pd") == 0) ctx->dut->pd = value;
              else if (strcmp(name, "ps2_clk") == 0) ctx->dut->ps2_clk = value;
              else if (strcmp(name, "ps2_data") == 0) ctx->dut->ps2_data = value;
              else if (strcmp(name, "gameport") == 0) ctx->dut->gameport = value;
              else if (strcmp(name, "pause") == 0) ctx->dut->pause = value;
          }

          unsigned int sim_peek(void* sim, const char* name) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (strcmp(name, "ram_addr") == 0) return ctx->dut->ram_addr;
              else if (strcmp(name, "ram_we") == 0) return ctx->dut->ram_we;
              else if (strcmp(name, "d") == 0) return ctx->dut->d;
              else if (strcmp(name, "video") == 0) return ctx->dut->video;
              else if (strcmp(name, "speaker") == 0) return ctx->dut->speaker;
              else if (strcmp(name, "pc_debug") == 0) return ctx->dut->pc_debug;
              else if (strcmp(name, "opcode_debug") == 0) return ctx->dut->opcode_debug;
              else if (strcmp(name, "a_debug") == 0) return ctx->dut->a_debug;
              else if (strcmp(name, "x_debug") == 0) return ctx->dut->x_debug;
              else if (strcmp(name, "y_debug") == 0) return ctx->dut->y_debug;
              else if (strcmp(name, "s_debug") == 0) return ctx->dut->s_debug;
              else if (strcmp(name, "p_debug") == 0) return ctx->dut->p_debug;
              return 0;
          }

          void sim_write_ram(void* sim, unsigned int addr, unsigned char value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->ram)) {
                  ctx->ram[addr] = value;
              }
          }

          unsigned char sim_read_ram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->ram)) {
                  return ctx->ram[addr];
              }
              return 0;
          }

          void sim_write_rom(void* sim, unsigned int offset, unsigned char value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (offset < sizeof(ctx->rom)) {
                  ctx->rom[offset] = value;
              }
          }

          // Batch cycle execution - runs N 14MHz cycles without FFI overhead
          // Returns number of speaker toggles since last call
          // text_dirty_out is set to 1 if text page was written
          unsigned int sim_run_cycles(void* sim, unsigned int n_cycles, unsigned int* text_dirty_out) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              *text_dirty_out = 0;

              for (unsigned int i = 0; i < n_cycles; i++) {
                  // Falling edge
                  ctx->dut->clk_14m = 0;
                  ctx->dut->eval();

                  // Memory read - provide data from RAM or ROM
                  unsigned int ram_addr = ctx->dut->ram_addr;
                  if (ram_addr >= 0xD000 && ram_addr <= 0xFFFF) {
                      // ROM area
                      unsigned int rom_offset = ram_addr - 0xD000;
                      ctx->dut->ram_do = (rom_offset < sizeof(ctx->rom)) ? ctx->rom[rom_offset] : 0;
                  } else if (ram_addr < sizeof(ctx->ram)) {
                      ctx->dut->ram_do = ctx->ram[ram_addr];
                  } else {
                      ctx->dut->ram_do = 0;
                  }
                  ctx->dut->eval();

                  // Rising edge
                  ctx->dut->clk_14m = 1;
                  ctx->dut->eval();

                  // Handle RAM writes
                  if (ctx->dut->ram_we) {
                      unsigned int write_addr = ctx->dut->ram_addr;
                      if (write_addr < sizeof(ctx->ram)) {
                          ctx->ram[write_addr] = ctx->dut->d & 0xFF;
                          // Check text page ($0400-$07FF)
                          if (write_addr >= 0x0400 && write_addr <= 0x07FF) {
                              *text_dirty_out = 1;
                          }
                      }
                  }

                  // Track speaker toggles
                  unsigned char speaker = ctx->dut->speaker;
                  if (speaker != ctx->prev_speaker) {
                      ctx->speaker_toggles++;
                      ctx->prev_speaker = speaker;
                  }
              }

              unsigned int toggles = ctx->speaker_toggles;
              ctx->speaker_toggles = 0;
              return toggles;
          }

          // Load memory in bulk (faster than individual writes)
          void sim_load_ram(void* sim, const unsigned char* data, unsigned int offset, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len && (offset + i) < sizeof(ctx->ram); i++) {
                  ctx->ram[offset + i] = data[i];
              }
          }

          void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len && i < sizeof(ctx->rom); i++) {
                  ctx->rom[i] = data[i];
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

        lib_name = "libapple2_sim.#{lib_suffix}"
        lib_path = File.join(OBJ_DIR, lib_name)

        # Verilate the design - top module is apple2_apple2
        # Don't use --build so we can control the C++ compiler
        # NOTE: --threads tested but 44x SLOWER due to sync overhead on sequential CPU
        verilate_cmd = [
          'verilator',
          '--cc',
          '--top-module', 'apple2_apple2',
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
          '--prefix', 'Vapple2',
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
            result = system('make', '-f', 'Vapple2.mk', 'CXX=clang++', out: log, err: log)
            unless result
              raise "Verilator make failed. See #{log_file} for details."
            end
          end
        end

        unless File.exist?(lib_path)
          # Try alternative build approach - build object files then link
          build_shared_library(wrapper_file)
        end
      end

      def build_shared_library(wrapper_file)
        # Link all object files and static libraries into shared library
        lib_path = shared_lib_path
        lib_vapple2 = File.join(OBJ_DIR, 'libVapple2.a')
        lib_verilated = File.join(OBJ_DIR, 'libverilated.a')

        # Use whole-archive to include all symbols from static libs
        # -latomic needed for clang++ on Linux
        link_cmd = if RbConfig::CONFIG['host_os'] =~ /darwin/
                     "clang++ -shared -dynamiclib -o #{lib_path} " \
                     "-Wl,-all_load #{lib_vapple2} #{lib_verilated}"
                   else
                     "clang++ -shared -o #{lib_path} " \
                     "-Wl,--whole-archive #{lib_vapple2} #{lib_verilated} -Wl,--no-whole-archive -latomic"
                   end

        system(link_cmd)
      end

      def shared_lib_path
        lib_suffix = case RbConfig::CONFIG['host_os']
                     when /darwin/ then 'dylib'
                     when /mswin|mingw/ then 'dll'
                     else 'so'
                     end
        File.join(OBJ_DIR, "libapple2_sim.#{lib_suffix}")
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

        @sim_write_ram_fn = Fiddle::Function.new(
          @lib['sim_write_ram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
          Fiddle::TYPE_VOID
        )

        @sim_read_ram_fn = Fiddle::Function.new(
          @lib['sim_read_ram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_CHAR
        )

        @sim_write_rom_fn = Fiddle::Function.new(
          @lib['sim_write_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
          Fiddle::TYPE_VOID
        )

        @sim_run_cycles_fn = Fiddle::Function.new(
          @lib['sim_run_cycles'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @sim_load_ram_fn = Fiddle::Function.new(
          @lib['sim_load_ram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
          Fiddle::TYPE_VOID
        )

        @sim_load_rom_fn = Fiddle::Function.new(
          @lib['sim_load_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
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

        verilator_poke('clk_14m', 0)
        verilator_poke('flash_clk', 0)
        verilator_poke('reset', 0)
        verilator_poke('ram_do', 0)
        verilator_poke('pd', 0)
        verilator_poke('ps2_clk', 1)
        verilator_poke('ps2_data', 1)
        verilator_poke('gameport', 0)
        verilator_poke('pause', 0)
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

      def verilator_write_ram(addr, value)
        return unless @sim_ctx
        @sim_write_ram_fn.call(@sim_ctx, addr, value)
      end

      def verilator_read_ram(addr)
        return 0 unless @sim_ctx
        @sim_read_ram_fn.call(@sim_ctx, addr)
      end

      def text_line_address(row)
        group = row / 8
        line_in_group = row % 8
        TEXT_PAGE1_START + (line_in_group * 0x80) + (group * 0x28)
      end

      def hires_line_address(row, base = HIRES_PAGE1_START)
        section = row / 64
        row_in_section = row % 64
        group = row_in_section / 8
        line_in_group = row_in_section % 8

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      def memory_sample
        {
          zero_page: (0...256).map { |i| read(i) },
          stack: (0...256).map { |i| read(0x0100 + i) },
          text_page: (0...1024).map { |i| read(0x0400 + i) },
          program_area: (0...256).map { |i| read(0x0800 + i) },
          reset_vector: [read(0xFFFC), read(0xFFFD)]
        }
      end

      # Stub class for disk controller
      class DiskControllerStub
        def track
          0
        end

        def motor_on
          false
        end
      end
    end
  end
end
