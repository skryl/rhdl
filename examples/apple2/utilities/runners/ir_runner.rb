# frozen_string_literal: true

# Apple II IR Simulator Runner
# High-performance IR-level simulation using batched Rust execution
#
# Usage:
#   runner = RHDL::Apple2::IrSimulatorRunner.new(backend: :interpret)
#   runner = RHDL::Apple2::IrSimulatorRunner.new(backend: :jit)
#   runner = RHDL::Apple2::IrSimulatorRunner.new(backend: :compile)
#   runner.reset
#   runner.run_steps(100)

require_relative '../../hdl/apple2'
require_relative '../output/speaker'
require_relative '../renderers/color_renderer'
require_relative '../input/ps2_encoder'
require 'rhdl/codegen'
require 'rhdl/codegen/ir/sim/ir_interpreter'

module RHDL
  module Apple2
    # High-performance IR-level runner using batched Rust execution
    class IrSimulatorRunner
      attr_reader :sim, :ir_json

      # Text page constants
      TEXT_PAGE1_START = 0x0400
      TEXT_PAGE1_END = 0x07FF

      # Hi-res graphics pages
      HIRES_PAGE1_START = 0x2000
      HIRES_PAGE1_END = 0x3FFF
      HIRES_WIDTH = 280
      HIRES_HEIGHT = 192
      HIRES_BYTES_PER_LINE = 40

      # Disk geometry constants
      TRACKS = 35
      SECTORS_PER_TRACK = 16
      BYTES_PER_SECTOR = 256
      TRACK_SIZE = SECTORS_PER_TRACK * BYTES_PER_SECTOR
      DISK_SIZE = TRACKS * TRACK_SIZE

      DOS33_INTERLEAVE = [
        0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
        0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F
      ].freeze

      # Initialize the Apple II IR runner
      # @param backend [Symbol] :interpret, :jit, or :compile
      # @param sub_cycles [Integer] Sub-cycles per CPU cycle (1-14, default: 14)
      #   - 14: Full timing accuracy (~0.4M cycles/sec)
      #   - 7: Good accuracy, ~2x faster (~0.7M cycles/sec)
      #   - 2: Minimal accuracy, ~7x faster (~3M cycles/sec)
      def initialize(backend: :interpret, sub_cycles: 14)
        backend_names = { interpret: "Interpreter", jit: "JIT", compile: "Compiler" }
        puts "Initializing Apple2 IR simulation [#{backend_names[backend]}]..."
        start_time = Time.now

        # Generate IR JSON from Apple2 component
        ir = Apple2.to_flat_ir
        @ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
        @backend = backend
        @sub_cycles = sub_cycles.clamp(1, 14)

        # Create the simulator based on backend choice
        # All wrappers require native Rust extensions - will raise LoadError if unavailable
        @sim = case backend
               when :interpret
                 RHDL::Codegen::IR::IrInterpreterWrapper.new(@ir_json, allow_fallback: false, sub_cycles: @sub_cycles)
               when :jit
                 require 'rhdl/codegen/ir/sim/ir_jit'
                 RHDL::Codegen::IR::IrJitWrapper.new(@ir_json, allow_fallback: false, sub_cycles: @sub_cycles)
               when :compile
                 require 'rhdl/codegen/ir/sim/ir_compiler'
                 RHDL::Codegen::IR::IrCompilerWrapper.new(@ir_json, allow_fallback: false, sub_cycles: @sub_cycles)
               else
                 raise ArgumentError, "Unknown backend: #{backend}. Use :interpret, :jit, or :compile"
               end

        elapsed = Time.now - start_time
        puts "  IR loaded in #{elapsed.round(2)}s"
        puts "  Native backend: #{@sim.native? ? 'Rust (optimized)' : 'Ruby (fallback)'}"
        puts "  Signals: #{@sim.signal_count}, Registers: #{@sim.reg_count}"
        puts "  Sub-cycles: #{@sub_cycles} (#{@sub_cycles == 14 ? 'full accuracy' : 'fast mode'})"

        @cycles = 0
        @halted = false
        @text_page_dirty = false

        # PS/2 keyboard encoder for sending keys through the PS/2 protocol
        @ps2_encoder = PS2Encoder.new

        @use_batched = @sim.native? && @sim.respond_to?(:apple2_run_cpu_cycles)

        # Speaker audio simulation
        @speaker = Speaker.new
        @prev_speaker_state = 0
        @last_speaker_sync_time = nil

        if @use_batched
          puts "  Batched execution: enabled (minimal FFI overhead)"
        end

        @sim.reset
        initialize_inputs unless @use_batched
      end

      def native?
        @sim.native?
      end

      def simulator_type
        @sim.simulator_type
      end

      def initialize_inputs
        return if @use_batched
        poke_input('clk_14m', 0)
        poke_input('flash_clk', 0)
        poke_input('reset', 0)
        poke_input('ram_do', 0)
        poke_input('pd', 0)
        poke_input('ps2_clk', 1)   # PS/2 idle state is high
        poke_input('ps2_data', 1)  # PS/2 idle state is high
        poke_input('gameport', 0)
        poke_input('pause', 0)
        @sim.evaluate
      end

      def poke_input(name, value)
        @sim.poke(name, value)
      end

      def peek_output(name)
        @sim.peek(name)
      end

      def load_rom(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)

        # Always store ROM locally for read() access
        @rom ||= Array.new(12 * 1024, 0)
        bytes.each_with_index do |byte, i|
          @rom[i] = byte if i < @rom.size
        end

        if @use_batched
          # Also load into Rust memory for simulation
          @sim.apple2_load_rom(bytes)
        end
      end

      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)

        if @use_batched
          # Load directly into Rust memory
          @sim.apple2_load_ram(bytes, base_addr)
        else
          # Fallback: store locally
          @ram ||= Array.new(48 * 1024, 0)
          bytes.each_with_index do |byte, i|
            addr = base_addr + i
            @ram[addr] = byte if addr < @ram.size
          end
        end
      end

      def load_disk(path_or_bytes, drive: 0)
        bytes = if path_or_bytes.is_a?(String)
                  File.binread(path_or_bytes).bytes
                else
                  path_or_bytes.is_a?(Array) ? path_or_bytes : path_or_bytes.bytes
                end

        if bytes.length != DISK_SIZE
          raise ArgumentError, "Invalid disk image size: #{bytes.length} (expected #{DISK_SIZE})"
        end

        @disk_loaded = true
        puts "Warning: Disk support in IR mode is limited"
      end

      def disk_loaded?(drive: 0)
        @disk_loaded || false
      end

      def reset
        if @use_batched
          # Use batched reset sequence
          poke_input('reset', 1)
          @sim.apple2_run_cpu_cycles(1, 0, false)
          poke_input('reset', 0)
          @sim.apple2_run_cpu_cycles(10, 0, false)
        else
          poke_input('reset', 1)
          run_14m_cycles(14)
          poke_input('reset', 0)
          run_14m_cycles(14 * 10)
        end
        @cycles = 0
        @halted = false
      end

      # Main entry point for running cycles - uses batched execution when available
      def run_steps(steps)
        if @use_batched
          run_steps_batched(steps)
        else
          steps.times { run_cpu_cycle }
        end
      end

      # Batched execution - runs many cycles with single FFI call
      # Note: PS/2 keyboard support in batched mode is limited.
      # The Rust backend uses direct keyboard injection for performance.
      def run_steps_batched(steps)
        # For batched mode, we extract pending key from PS2 encoder and send directly
        # This is a workaround until the Rust backend supports PS2 protocol
        key_data = 0
        key_ready = false
        if @ps2_encoder.sending?
          # Drain the PS2 queue - batched mode uses direct injection
          @ps2_encoder.clear
          # Note: In batched mode, key injection happens at Rust level
          # PS2 protocol is not fully simulated
        end

        result = @sim.apple2_run_cpu_cycles(steps, key_data, key_ready)

        @cycles += result[:cycles_run]
        @text_page_dirty = true if result[:text_dirty]

        # Process speaker toggles for audio generation with proper timing
        if result[:speaker_toggles] && result[:speaker_toggles] > 0
          now = Time.now
          elapsed = @last_speaker_sync_time ? (now - @last_speaker_sync_time) : 0.033  # Default ~30fps
          @last_speaker_sync_time = now
          @speaker.sync_toggles(result[:speaker_toggles], elapsed)
        end
      end

      def run_cpu_cycle
        if @use_batched
          run_steps_batched(1)
        else
          14.times { run_14m_cycle }
          @cycles += 1
        end
      end

      # Fallback: individual 14MHz cycle (only used without batching)
      def run_14m_cycle
        @ram ||= Array.new(48 * 1024, 0)
        @rom ||= Array.new(12 * 1024, 0)

        # Update PS/2 keyboard signals from encoder
        ps2_clk, ps2_data = @ps2_encoder.next_ps2_state
        poke_input('ps2_clk', ps2_clk)
        poke_input('ps2_data', ps2_data)

        # Falling edge
        poke_input('clk_14m', 0)
        @sim.evaluate

        # Provide RAM/ROM data
        ram_addr = peek_output('ram_addr')
        if ram_addr >= 0xD000 && ram_addr <= 0xFFFF
          rom_offset = ram_addr - 0xD000
          poke_input('ram_do', @rom[rom_offset] || 0)
        elsif ram_addr < @ram.size
          poke_input('ram_do', @ram[ram_addr] || 0)
        else
          poke_input('ram_do', 0)
        end
        @sim.evaluate

        # Rising edge
        poke_input('clk_14m', 1)
        @sim.tick

        # Handle RAM writes
        ram_we = peek_output('ram_we')
        if ram_we == 1
          write_addr = peek_output('ram_addr')
          if write_addr < @ram.size
            data = peek_output('d')
            @ram[write_addr] = data & 0xFF
            if write_addr >= TEXT_PAGE1_START && write_addr <= TEXT_PAGE1_END
              @text_page_dirty = true
            end
          end
        end

        # Monitor speaker output for state changes
        speaker_state = safe_peek('speaker')
        if speaker_state != @prev_speaker_state
          @speaker.toggle
          @prev_speaker_state = speaker_state
        end
      end

      def run_14m_cycles(n)
        n.times { run_14m_cycle }
      end

      # Inject a key through the PS/2 keyboard controller
      # This queues the key for transmission via the PS/2 protocol
      def inject_key(ascii)
        @ps2_encoder.queue_key(ascii)
      end

      # Check if there's a key being transmitted
      def key_ready?
        @ps2_encoder.sending?
      end

      def clear_key
        @ps2_encoder.clear
      end

      def read_screen_array
        if @use_batched
          read_screen_array_batched
        else
          read_screen_array_fallback
        end
      end

      def read_screen_array_batched
        result = []
        24.times do |row|
          base = text_line_address(row)
          line_data = @sim.apple2_read_ram(base, 40)
          result << line_data.to_a
        end
        result
      end

      def read_screen_array_fallback
        @ram ||= Array.new(48 * 1024, 0)
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
        if @use_batched
          read_hires_bitmap_batched
        else
          read_hires_bitmap_fallback
        end
      end

      def read_hires_bitmap_batched
        bitmap = []
        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, HIRES_PAGE1_START)
          line_bytes = @sim.apple2_read_ram(line_addr, HIRES_BYTES_PER_LINE).to_a

          line_bytes.each do |byte|
            7.times do |bit|
              line << ((byte >> bit) & 1)
            end
          end

          bitmap << line
        end
        bitmap
      end

      def read_hires_bitmap_fallback
        @ram ||= Array.new(48 * 1024, 0)
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

      # Render hi-res screen with NTSC artifact colors
      # chars_wide: target width in characters (default 140)
      def render_hires_color(chars_wide: 140)
        if @use_batched
          render_hires_color_batched(chars_wide)
        else
          render_hires_color_fallback(chars_wide)
        end
      end

      def render_hires_color_batched(chars_wide)
        # Build a RAM array with hi-res page data from Rust backend
        # ColorRenderer needs the full address space since it uses hires_line_address()
        hires_ram = Array.new(HIRES_PAGE1_END + 1, 0)

        # Read hi-res page data from Rust backend
        # The hi-res page is 8KB at $2000-$3FFF
        hires_data = @sim.apple2_read_ram(HIRES_PAGE1_START, HIRES_PAGE1_END - HIRES_PAGE1_START + 1).to_a
        hires_data.each_with_index { |b, i| hires_ram[HIRES_PAGE1_START + i] = b }

        renderer = ColorRenderer.new(chars_wide: chars_wide)
        renderer.render(hires_ram, base_addr: HIRES_PAGE1_START)
      end

      def render_hires_color_fallback(chars_wide)
        @ram ||= Array.new(48 * 1024, 0)
        renderer = ColorRenderer.new(chars_wide: chars_wide)
        renderer.render(@ram, base_addr: HIRES_PAGE1_START)
      end

      def hires_line_address(row, base = HIRES_PAGE1_START)
        section = row / 64
        row_in_section = row % 64
        group = row_in_section / 8
        line_in_group = row_in_section % 8

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      def cpu_state
        # With flattened IR, debug signals from subcomponents should be available
        {
          pc: safe_peek('pc_debug'),
          a: safe_peek('a_debug'),
          x: safe_peek('x_debug'),
          y: safe_peek('y_debug'),
          sp: 0xFF,
          p: 0,
          cycles: @cycles,
          halted: @halted,
          simulator_type: simulator_type
        }
      end

      # Safely peek a signal, returning 0 if not available
      def safe_peek(name)
        peek_output(name)
      rescue StandardError
        0
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
        # ROM addresses ($D000-$FFFF) are always read from local @rom storage
        if addr >= 0xD000 && addr <= 0xFFFF
          @rom ||= Array.new(12 * 1024, 0)
          return @rom[addr - 0xD000] || 0
        end

        # RAM addresses use batched Rust backend when available
        if @use_batched
          data = @sim.apple2_read_ram(addr, 1)
          data[0] || 0
        else
          @ram ||= Array.new(48 * 1024, 0)
          addr < @ram.size ? @ram[addr] : 0
        end
      end

      def write(addr, value)
        if @use_batched
          @sim.apple2_write_ram(addr, [value & 0xFF])
        else
          @ram ||= Array.new(48 * 1024, 0)
          if addr < @ram.size
            @ram[addr] = value & 0xFF
          end
        end
      end

      private

      def text_line_address(row)
        group = row / 8
        line_in_group = row % 8
        TEXT_PAGE1_START + (line_in_group * 0x80) + (group * 0x28)
      end

      # Reuse stubs from netlist runner
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
