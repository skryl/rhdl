# frozen_string_literal: true

# Apple II Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the Apple2 HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface similar to the Rust IR runners.
#
# Usage:
#   runner = RHDL::Examples::Apple2::VerilogRunner.new(sub_cycles: 14)
#   runner.reset
#   runner.run_steps(100)

require_relative '../../hdl/apple2'
require_relative '../output/speaker'
require_relative '../renderers/color_renderer'
require_relative '../input/ps2_encoder'
require 'rhdl/sim/native/verilog/verilator/runtime'
require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'fiddle/import'

module RHDL
  module Examples
    module Apple2
      # Verilator-based runner for Apple II simulation
    # Compiles RHDL Verilog export to native code via Verilator
    class VerilogRunner
      # Text page constants
      TEXT_PAGE1_START = 0x0400
      TEXT_PAGE1_END = 0x07FF

      # Hi-res graphics pages
      HIRES_PAGE1_START = 0x2000
      HIRES_PAGE1_END = 0x3FFF
      HIRES_PAGE2_START = 0x4000
      HIRES_PAGE2_END = 0x5FFF
      HIRES_WIDTH = 280
      HIRES_HEIGHT = 192
      HIRES_BYTES_PER_LINE = 40

      # Build directory for Verilator output
      BUILD_DIR = File.expand_path('../../.verilator_build', __dir__)
      VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
      OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')
      INPUT_SIGNAL_WIDTHS = {
        'clk_14m' => 1,
        'flash_clk' => 1,
        'reset' => 1,
        'ram_do' => 8,
        'pd' => 8,
        'ps2_clk' => 1,
        'ps2_data' => 1,
        'gameport' => 8,
        'pause' => 1
      }.freeze
      OUTPUT_SIGNAL_WIDTHS = {
        'ram_addr' => 16,
        'ram_we' => 1,
        'd' => 8,
        'speaker' => 1,
        'video' => 1,
        'pc_debug' => 16,
        'a_debug' => 8,
        'x_debug' => 8,
        'y_debug' => 8,
        's_debug' => 8,
        'p_debug' => 8,
        'opcode_debug' => 8
      }.freeze
      SIGNAL_WIDTHS = INPUT_SIGNAL_WIDTHS.merge(OUTPUT_SIGNAL_WIDTHS).freeze

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
      end

      def native?
        true
      end

      def sim
        @sim
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

      def load_rom(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        # Keep Ruby copy for compatibility
        bytes.each_with_index do |byte, i|
          @rom[i] = byte if i < @rom.size
        end
        @sim&.runner_load_rom(bytes, base_addr)
      end

      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        # Keep Ruby copy for compatibility
        bytes.each_with_index do |byte, i|
          addr = base_addr + i
          @ram[addr] = byte if addr < @ram.size
        end
        @sim&.runner_write_memory(base_addr, bytes, mapped: false)
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
          @sim&.runner_load_rom([byte & 0xFF], addr)
        else
          # RAM area
          @ram[addr] = byte if addr < @ram.size
          @text_page_dirty = true if display_memory_addr?(addr)
          verilator_write_ram(addr, byte) if addr < @ram.size
        end
      end

      # Get current program counter
      def pc
        verilator_peek('pc_debug')
      end

      # Main entry point for running cycles
      def run_steps(steps)
        if @sim
          result = @sim.runner_run_cycles(steps)
          @text_page_dirty ||= result[:text_dirty]
          result[:speaker_toggles].times { @speaker.toggle }
          @cycles += result[:cycles_run]
        else
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
            if display_memory_addr?(write_addr)
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
            line << read_ram_byte(base + col)
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

      def read_hires_bitmap(base_addr: HIRES_PAGE1_START)
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base_addr)

          HIRES_BYTES_PER_LINE.times do |col|
            byte = read_ram_byte(line_addr + col)
            7.times do |bit|
              line << ((byte >> bit) & 1)
            end
          end

          bitmap << line
        end

        bitmap
      end

      def render_hires_braille(chars_wide: 80, invert: false, base_addr: HIRES_PAGE1_START)
        bitmap = read_hires_bitmap(base_addr: base_addr)

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

      def render_hires_color(chars_wide: 140, composite: false, base_addr: HIRES_PAGE1_START)
        renderer = ColorRenderer.new(chars_wide: chars_wide, composite: composite)

        if @sim
          page_end = base_addr + 0x2000 - 1
          hires_ram = Array.new(page_end + 1, 0)
          (base_addr..page_end).each do |addr|
            hires_ram[addr] = read_ram_byte(addr)
          end
          return renderer.render(hires_ram, base_addr: base_addr)
        end

        renderer.render(@ram, base_addr: base_addr)
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
        addr &= 0xFFFF
        if addr >= 0xD000
          return @rom[addr - 0xD000] || 0
        end

        read_ram_byte(addr)
      end

      def write(addr, value)
        # Use write_memory which handles both RAM and ROM addresses
        write_memory(addr, value & 0xFF)
      end

      private

      def verilog_simulator
        @verilog_simulator ||= RHDL::Codegen::Verilog::VerilogSimulator.new(
          backend: :verilator,
          build_dir: BUILD_DIR,
          library_basename: 'apple2_sim',
          top_module: 'apple2_apple2',
          verilator_prefix: 'Vapple2',
          x_assign: '0',
          x_initial: 'unique'
        )
      end

      def check_verilator_available!
        verilog_simulator.ensure_backend_available!
      end

      def build_verilator_simulation
        verilog_simulator.prepare_build_dirs!

        # Export Apple2 to Verilog
        verilog_file = File.join(VERILOG_DIR, 'apple2.v')
        verilog_codegen = File.expand_path('../../../../lib/rhdl/dsl/codegen.rb', __dir__)
        circt_codegen = File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__)
        export_deps = [__FILE__, verilog_codegen, circt_codegen].select { |p| File.exist?(p) }
        needs_export = !File.exist?(verilog_file) ||
                       export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

        if needs_export
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
        input_signal_names = INPUT_SIGNAL_WIDTHS.keys
        output_signal_names = OUTPUT_SIGNAL_WIDTHS.keys
        input_names_csv = input_signal_names.join(',')
        output_names_csv = output_signal_names.join(',')
        header_content = <<~HEADER
          #ifndef SIM_WRAPPER_H
          #define SIM_WRAPPER_H

          #ifdef __cplusplus
          extern "C" {
          #endif

          void* sim_create(const char* json, unsigned long json_len, unsigned int sub_cycles, char** err_out);
          void sim_destroy(void* sim);
          void sim_free_error(void* err);
          void sim_free_string(void* str);
          void* sim_wasm_alloc(unsigned int size);
          void sim_wasm_dealloc(void* ptr, unsigned int size);
          int sim_get_caps(const void* sim, unsigned int* caps_out);
          int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value);
          int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out);
          int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value);
          unsigned long sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, unsigned long out_len);
          int runner_get_caps(const void* sim, unsigned int* caps_out);
          unsigned long runner_mem(void* sim, unsigned int op, unsigned int space, unsigned long offset, unsigned char* data, unsigned long len, unsigned int flags);
          int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, void* result_out);
          int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1);
          unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0);
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

        cpp_content = <<~CPP
          #include "Vapple2.h"
          #include "Vapple2___024root.h"
          #include "verilated.h"
          #include "sim_wrapper.h"
          #include <cstring>

          // Verilator time stamp function (required by verilator runtime on some platforms)
          double sc_time_stamp() { return 0; }

          struct SimContext {
              Vapple2* dut;
              unsigned char ram[65536];  // 64KB RAM for Apple II
              unsigned char rom[12288];  // 12KB ROM
              unsigned char prev_speaker;
              unsigned int speaker_toggles;
              unsigned int sub_cycles;
              unsigned int text_dirty;
              unsigned int cycle_count;
          };

          static const char* k_input_signal_names[] = {
              #{input_signal_names.map { |name| %("#{name}") }.join(",\n              ")}
          };
          static const char* k_output_signal_names[] = {
              #{output_signal_names.map { |name| %("#{name}") }.join(",\n              ")}
          };
          static const char k_input_names_csv[] = "#{input_names_csv}";
          static const char k_output_names_csv[] = "#{output_names_csv}";
          static const unsigned int k_input_signal_count = #{input_signal_names.length}u;
          static const unsigned int k_output_signal_count = #{output_signal_names.length}u;

          static const unsigned int SIM_CAP_SIGNAL_INDEX = 1u << 0;
          static const unsigned int SIM_CAP_RUNNER = 1u << 6;
          static const unsigned int SIM_SIGNAL_HAS = 0u;
          static const unsigned int SIM_SIGNAL_GET_INDEX = 1u;
          static const unsigned int SIM_SIGNAL_PEEK = 2u;
          static const unsigned int SIM_SIGNAL_POKE = 3u;
          static const unsigned int SIM_SIGNAL_PEEK_INDEX = 4u;
          static const unsigned int SIM_SIGNAL_POKE_INDEX = 5u;
          static const unsigned int SIM_EXEC_EVALUATE = 0u;
          static const unsigned int SIM_EXEC_TICK = 1u;
          static const unsigned int SIM_EXEC_TICK_FORCED = 2u;
          static const unsigned int SIM_EXEC_SET_PREV_CLOCK = 3u;
          static const unsigned int SIM_EXEC_GET_CLOCK_LIST_IDX = 4u;
          static const unsigned int SIM_EXEC_RESET = 5u;
          static const unsigned int SIM_EXEC_RUN_TICKS = 6u;
          static const unsigned int SIM_EXEC_SIGNAL_COUNT = 7u;
          static const unsigned int SIM_EXEC_REG_COUNT = 8u;
          static const unsigned int SIM_EXEC_COMPILE = 9u;
          static const unsigned int SIM_EXEC_IS_COMPILED = 10u;
          static const unsigned int SIM_TRACE_START = 0u;
          static const unsigned int SIM_TRACE_START_STREAMING = 1u;
          static const unsigned int SIM_TRACE_STOP = 2u;
          static const unsigned int SIM_TRACE_ENABLED = 3u;
          static const unsigned int SIM_BLOB_INPUT_NAMES = 0u;
          static const unsigned int SIM_BLOB_OUTPUT_NAMES = 1u;
          static const unsigned int RUNNER_KIND_APPLE2 = 1u;
          static const unsigned int RUNNER_MEM_OP_LOAD = 0u;
          static const unsigned int RUNNER_MEM_OP_READ = 1u;
          static const unsigned int RUNNER_MEM_OP_WRITE = 2u;
          static const unsigned int RUNNER_MEM_SPACE_MAIN = 0u;
          static const unsigned int RUNNER_MEM_SPACE_ROM = 1u;
          static const unsigned int RUNNER_MEM_FLAG_MAPPED = 1u;
          static const unsigned int RUNNER_RUN_MODE_BASIC = 0u;
          static const unsigned int RUNNER_CONTROL_SET_RESET_VECTOR = 0u;
          static const unsigned int RUNNER_CONTROL_RESET_SPEAKER_TOGGLES = 1u;
          static const unsigned int RUNNER_PROBE_KIND = 0u;
          static const unsigned int RUNNER_PROBE_IS_MODE = 1u;
          static const unsigned int RUNNER_PROBE_SPEAKER_TOGGLES = 2u;
          static const unsigned int RUNNER_PROBE_SIGNAL = 9u;

          struct RunnerRunResult {
              int text_dirty;
              int key_cleared;
              unsigned int cycles_run;
              unsigned int speaker_toggles;
              unsigned int frames_completed;
          };

          static unsigned int total_signal_count() {
              return k_input_signal_count + k_output_signal_count;
          }

          static const char* signal_name_from_index(unsigned int idx) {
              if (idx < k_input_signal_count) return k_input_signal_names[idx];
              idx -= k_input_signal_count;
              if (idx < k_output_signal_count) return k_output_signal_names[idx];
              return nullptr;
          }

          static int signal_index_from_name(const char* name) {
              if (!name) return -1;
              for (unsigned int i = 0; i < k_input_signal_count; i++) {
                  if (std::strcmp(name, k_input_signal_names[i]) == 0) return static_cast<int>(i);
              }
              for (unsigned int i = 0; i < k_output_signal_count; i++) {
                  if (std::strcmp(name, k_output_signal_names[i]) == 0) {
                      return static_cast<int>(k_input_signal_count + i);
                  }
              }
              return -1;
          }

          static void write_out_ulong(unsigned long* out, unsigned long value) {
              if (out) *out = value;
          }

          extern "C" {

          void* sim_create(const char* json, unsigned long json_len, unsigned int sub_cycles, char** err_out) {
              (void)json;
              (void)json_len;
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);
              SimContext* ctx = new SimContext();
              ctx->dut = new Vapple2();
              memset(ctx->ram, 0, sizeof(ctx->ram));
              memset(ctx->rom, 0, sizeof(ctx->rom));
              ctx->prev_speaker = 0;
              ctx->speaker_toggles = 0;
              ctx->sub_cycles = (sub_cycles >= 1 && sub_cycles <= 14) ? sub_cycles : 14;
              ctx->text_dirty = 0;
              ctx->cycle_count = 0;
              if (err_out) *err_out = nullptr;

              // Initialize inputs to safe defaults
              ctx->dut->clk_14m = 0;
              ctx->dut->flash_clk = 0;
              ctx->dut->reset = 1;  // Start in reset
              ctx->dut->ram_do = 0;
              ctx->dut->pd = 0;
              ctx->dut->ps2_clk = 1;
              ctx->dut->ps2_data = 1;
              ctx->dut->gameport = 0;
              ctx->dut->pause = 0;

              // Run initial eval to trigger initial block execution
              ctx->dut->eval();

              return ctx;
          }

          void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
          }

          void sim_free_error(void* err) {
              (void)err;
          }

          void sim_free_string(void* str) {
              (void)str;
          }

          void* sim_wasm_alloc(unsigned int size) {
              return std::malloc(size > 0 ? size : 1);
          }

          void sim_wasm_dealloc(void* ptr, unsigned int size) {
              (void)size;
              std::free(ptr);
          }

          void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);

              // Match examples/apple2/utilities/runners/ruby_runner.rb reset sequence:
              //   1) reset=1 for 14x 14MHz cycles (1 CPU cycle)
              //   2) reset=0 for 140x 14MHz cycles (10 CPU cycles)
              //
              // Use the same memory-bridging/write-commit timing as sim_run_cycles.

              ctx->speaker_toggles = 0;

              auto run_14m_cycle = [&]() {
                  // Falling edge
                  ctx->dut->clk_14m = 0;
                  ctx->dut->eval();

                  // Provide RAM/ROM data based on system memory address bus.
                  // This keeps video fetches and CPU fetches coherent with the top-level design.
                  unsigned int ram_addr = ctx->dut->ram_addr & 0xFFFF;
                  if (ram_addr >= 0xD000 && ram_addr <= 0xFFFF) {
                      unsigned int rom_offset = ram_addr - 0xD000;
                      ctx->dut->ram_do = (rom_offset < sizeof(ctx->rom)) ? ctx->rom[rom_offset] : 0;
                  } else if (ram_addr >= 0xC000) {
                      ctx->dut->ram_do = 0;
                  } else {
                      ctx->dut->ram_do = ctx->ram[ram_addr];
                  }
                  ctx->dut->eval();

                  // Rising edge
                  ctx->dut->clk_14m = 1;
                  ctx->dut->eval();
                  // Ensure any derived-clock sequential logic (e.g. Q3-domain) runs in the same 14MHz tick
                  // to match the IR batched runner's deterministic tick ordering.
                  ctx->dut->eval();

                  // Handle RAM writes
                  if (ctx->dut->ram_we) {
                      unsigned int write_addr = ctx->dut->ram_addr & 0xFFFF;
                      if (write_addr < 0xC000) {
                          ctx->ram[write_addr] = ctx->dut->d & 0xFF;
                      }
                  }

                  // Track speaker toggles
                  unsigned char speaker = ctx->dut->speaker;
                  if (speaker != ctx->prev_speaker) {
                      ctx->speaker_toggles++;
                      ctx->prev_speaker = speaker;
                  }
              };

              ctx->dut->reset = 1;
              for (int i = 0; i < 14; i++) {
                  run_14m_cycle();
              }

              ctx->dut->reset = 0;
              for (int i = 0; i < 140; i++) {
                  run_14m_cycle();
              }
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

                  // Memory read - provide data from RAM or ROM based on system memory address bus
                  unsigned int ram_addr = ctx->dut->ram_addr & 0xFFFF;
                  if (ram_addr >= 0xD000 && ram_addr <= 0xFFFF) {
                      // ROM area
                      unsigned int rom_offset = ram_addr - 0xD000;
                      ctx->dut->ram_do = (rom_offset < sizeof(ctx->rom)) ? ctx->rom[rom_offset] : 0;
                  } else if (ram_addr >= 0xC000) {
                      ctx->dut->ram_do = 0;
                  } else {
                      ctx->dut->ram_do = ctx->ram[ram_addr];
                  }
                  ctx->dut->eval();

                  // Rising edge
                  ctx->dut->clk_14m = 1;
                  ctx->dut->eval();
                  // Ensure any derived-clock sequential logic (e.g. Q3-domain) runs in the same 14MHz tick
                  // to match the IR batched runner's deterministic tick ordering.
                  ctx->dut->eval();

                  // Handle RAM writes
                  if (ctx->dut->ram_we) {
                      unsigned int write_addr = ctx->dut->ram_addr & 0xFFFF;
                      if (write_addr < 0xC000) {
                          ctx->ram[write_addr] = ctx->dut->d & 0xFF;
                          // Mark display as dirty on text/graphics writes.
                          if ((write_addr >= 0x0400 && write_addr <= 0x07FF) ||
                              (write_addr >= 0x2000 && write_addr <= 0x5FFF)) {
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

          int sim_get_caps(const void* sim, unsigned int* caps_out) {
              if (!sim || !caps_out) return 0;
              *caps_out = SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER;
              return 1;
          }

          int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
              const int resolved_idx = name ? signal_index_from_name(name) : static_cast<int>(idx);
              const char* resolved_name = name ? name : signal_name_from_index(idx);

              switch (op) {
              case SIM_SIGNAL_HAS:
                  write_out_ulong(out_value, resolved_idx >= 0 ? 1UL : 0UL);
                  return resolved_idx >= 0 ? 1 : 0;
              case SIM_SIGNAL_GET_INDEX:
                  if (resolved_idx < 0) return 0;
                  write_out_ulong(out_value, static_cast<unsigned long>(resolved_idx));
                  return 1;
              case SIM_SIGNAL_PEEK:
              case SIM_SIGNAL_PEEK_INDEX:
                  if (resolved_idx < 0 || !resolved_name) return 0;
                  write_out_ulong(out_value, sim_peek(sim, resolved_name));
                  return 1;
              case SIM_SIGNAL_POKE:
              case SIM_SIGNAL_POKE_INDEX:
                  if (resolved_idx < 0 || !resolved_name) return 0;
                  sim_poke(sim, resolved_name, static_cast<unsigned int>(value));
                  write_out_ulong(out_value, value);
                  return 1;
              default:
                  return 0;
              }
          }

          int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out) {
              (void)arg1;
              (void)error_out;
              switch (op) {
              case SIM_EXEC_EVALUATE:
                  sim_eval(sim);
                  write_out_ulong(out_value, 1);
                  return 1;
              case SIM_EXEC_TICK:
              case SIM_EXEC_TICK_FORCED:
                  sim_run_cycles(sim, 1, nullptr);
                  write_out_ulong(out_value, 1);
                  return 1;
              case SIM_EXEC_SET_PREV_CLOCK:
                  write_out_ulong(out_value, 0);
                  return 1;
              case SIM_EXEC_GET_CLOCK_LIST_IDX:
                  return 0;
              case SIM_EXEC_RESET:
                  sim_reset(sim);
                  write_out_ulong(out_value, 1);
                  return 1;
              case SIM_EXEC_RUN_TICKS:
                  sim_run_cycles(sim, static_cast<unsigned int>(arg0), nullptr);
                  write_out_ulong(out_value, arg0);
                  return 1;
              case SIM_EXEC_SIGNAL_COUNT:
                  write_out_ulong(out_value, total_signal_count());
                  return 1;
              case SIM_EXEC_REG_COUNT:
                  write_out_ulong(out_value, 0);
                  return 1;
              case SIM_EXEC_COMPILE:
              case SIM_EXEC_IS_COMPILED:
                  return 0;
              default:
                  return 0;
              }
          }

          int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
              (void)sim;
              (void)str_arg;
              write_out_ulong(out_value, 0);
              return (op == SIM_TRACE_ENABLED) ? 1 : 0;
          }

          unsigned long sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, unsigned long out_len) {
              (void)sim;
              const char* data = nullptr;
              unsigned long len = 0;
              switch (op) {
              case SIM_BLOB_INPUT_NAMES:
                  data = k_input_names_csv;
                  len = sizeof(k_input_names_csv) - 1;
                  break;
              case SIM_BLOB_OUTPUT_NAMES:
                  data = k_output_names_csv;
                  len = sizeof(k_output_names_csv) - 1;
                  break;
              default:
                  return 0;
              }
              if (!out_ptr || out_len == 0) return len;
              const unsigned long copy_len = (len < out_len) ? len : out_len;
              std::memcpy(out_ptr, data, copy_len);
              return copy_len;
          }

          int runner_get_caps(const void* sim, unsigned int* caps_out) {
              if (!sim || !caps_out) return 0;
              caps_out[0] = RUNNER_KIND_APPLE2;
              caps_out[1] = (1u << RUNNER_MEM_SPACE_MAIN) | (1u << RUNNER_MEM_SPACE_ROM);
              caps_out[2] = (1u << RUNNER_CONTROL_SET_RESET_VECTOR) | (1u << RUNNER_CONTROL_RESET_SPEAKER_TOGGLES);
              caps_out[3] = (1u << RUNNER_PROBE_KIND) | (1u << RUNNER_PROBE_IS_MODE) |
                            (1u << RUNNER_PROBE_SPEAKER_TOGGLES) | (1u << RUNNER_PROBE_SIGNAL);
              return 1;
          }

          unsigned long runner_mem(void* sim, unsigned int op, unsigned int space, unsigned long offset, unsigned char* data, unsigned long len, unsigned int flags) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !data) return 0;

              unsigned char* mem = nullptr;
              unsigned long mem_size = 0;
              unsigned long mem_offset = offset;
              switch (space) {
              case RUNNER_MEM_SPACE_MAIN:
                  mem = ctx->ram;
                  mem_size = sizeof(ctx->ram);
                  break;
              case RUNNER_MEM_SPACE_ROM:
                  mem = ctx->rom;
                  mem_size = sizeof(ctx->rom);
                  mem_offset = (offset >= 0xD000 && offset <= 0xFFFF) ? (offset - 0xD000) : offset;
                  break;
              default:
                  return 0;
              }

              switch (op) {
              case RUNNER_MEM_OP_LOAD:
              case RUNNER_MEM_OP_WRITE: {
                  unsigned long count = 0;
                  for (unsigned long i = 0; i < len && (mem_offset + i) < mem_size; i++) {
                      mem[mem_offset + i] = data[i];
                      count++;
                  }
                  return count;
              }
              case RUNNER_MEM_OP_READ: {
                  if (space == RUNNER_MEM_SPACE_MAIN && (flags & RUNNER_MEM_FLAG_MAPPED)) {
                      for (unsigned long i = 0; i < len; i++) {
                          const unsigned long addr = (offset + i) & 0xFFFFul;
                          if (addr >= 0xD000ul) {
                              const unsigned long rom_offset = addr - 0xD000ul;
                              data[i] = (rom_offset < sizeof(ctx->rom)) ? ctx->rom[rom_offset] : 0;
                          } else if (addr >= 0xC000ul) {
                              data[i] = 0;
                          } else {
                              data[i] = (addr < sizeof(ctx->ram)) ? ctx->ram[addr] : 0;
                          }
                      }
                      return len;
                  }

                  unsigned long count = 0;
                  for (unsigned long i = 0; i < len && (mem_offset + i) < mem_size; i++) {
                      data[i] = mem[mem_offset + i];
                      count++;
                  }
                  return count;
              }
              default:
                  return 0;
              }
          }

          int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, void* result_out) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              (void)key_data;
              (void)key_ready;
              (void)mode;

              ctx->text_dirty = 0;
              ctx->speaker_toggles = 0;
              const unsigned int n_14m_cycles = cycles * ctx->sub_cycles;
              sim_run_cycles(sim, n_14m_cycles, &ctx->text_dirty);
              ctx->cycle_count += cycles;

              RunnerRunResult* result = static_cast<RunnerRunResult*>(result_out);
              if (result) {
                  result->text_dirty = ctx->text_dirty ? 1 : 0;
                  result->key_cleared = 0;
                  result->cycles_run = cycles;
                  result->speaker_toggles = ctx->speaker_toggles;
                  result->frames_completed = 0;
              }
              return 1;
          }

          int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              (void)arg1;
              switch (op) {
              case RUNNER_CONTROL_SET_RESET_VECTOR:
                  if (0x2FFD < sizeof(ctx->rom)) {
                      ctx->rom[0x2FFC] = arg0 & 0xFFu;
                      ctx->rom[0x2FFD] = (arg0 >> 8) & 0xFFu;
                  }
                  return 1;
              case RUNNER_CONTROL_RESET_SPEAKER_TOGGLES:
                  ctx->speaker_toggles = 0;
                  ctx->prev_speaker = static_cast<unsigned char>(ctx->dut->speaker) & 0x1u;
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
                  return RUNNER_KIND_APPLE2;
              case RUNNER_PROBE_IS_MODE:
                  return 0;
              case RUNNER_PROBE_SPEAKER_TOGGLES:
                  return ctx->speaker_toggles;
              case RUNNER_PROBE_SIGNAL: {
                  const char* signal_name = signal_name_from_index(arg0);
                  return signal_name ? sim_peek(sim, signal_name) : 0;
              }
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
        @sim = RHDL::Sim::Native::Verilog::Verilator::Runtime.open(
          lib_path: lib_path,
          config: { sub_cycles: @sub_cycles },
          sub_cycles: @sub_cycles,
          signal_widths_by_name: SIGNAL_WIDTHS,
          signal_widths_by_idx: SIGNAL_WIDTHS.values,
          backend_label: 'Apple2 Verilator'
        )
        ensure_runner_abi!(@sim, expected_kind: :apple2, backend_label: 'Apple2 Verilator')
      end

      def reset_simulation
        @sim&.reset
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

      def verilator_write_ram(addr, value)
        return unless @sim

        @sim.runner_write_memory(addr, [value.to_i & 0xFF], mapped: false)
      end

      def verilator_read_ram(addr)
        return 0 unless @sim

        @sim.runner_read_memory(addr, 1, mapped: false).fetch(0, 0).to_i & 0xFF
      end

      def read_ram_byte(addr)
        addr &= 0xFFFF
        return 0 unless addr < @ram.size

        if @sim
          return verilator_read_ram(addr)
        end

        @ram[addr] || 0
      end

      def display_memory_addr?(addr)
        (addr >= TEXT_PAGE1_START && addr <= TEXT_PAGE1_END) ||
          (addr >= HIRES_PAGE1_START && addr <= HIRES_PAGE2_END)
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
end
