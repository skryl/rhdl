# frozen_string_literal: true

# Apple II FIRRTL/RTL Simulator Runner
# Provides RTL-level simulation for the Apple2 HDL component
#
# Usage:
#   runner = RHDL::Apple2::FirrtlRunner.new
#   runner.reset
#   runner.run_steps(100)

require_relative '../hdl/apple2'
require 'rhdl/codegen'
require 'rhdl/codegen/circt/sim/firrtl_native'

module RHDL
  module Apple2
    # Utility module for exporting Apple2 component to RTL IR
    module Apple2Firrtl
      class << self
        # Get the Behavior IR for the Apple2 component
        def behavior_ir
          Apple2.to_ir
        end

        # Convert to JSON format for the simulator
        def ir_json
          ir = behavior_ir
          RHDL::Codegen::CIRCT::IRToJson.convert(ir)
        end

        # Get stats about the IR
        def stats
          ir = behavior_ir
          {
            port_count: ir.ports.length,
            net_count: ir.nets.length,
            reg_count: ir.regs.length,
            assign_count: ir.assigns.length,
            process_count: ir.processes.length,
            inputs: ir.ports.select { |p| p.direction == :in }.map(&:name),
            outputs: ir.ports.select { |p| p.direction == :out }.map(&:name)
          }
        end
      end
    end

    # RTL-level runner using FIRRTL simulator
    class FirrtlRunner
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

      def initialize
        puts "Initializing Apple2 FIRRTL/RTL simulation..."
        start_time = Time.now

        # Generate RTL IR JSON
        @ir_json = Apple2Firrtl.ir_json

        # Create the simulator
        @sim = RHDL::Codegen::CIRCT::FirrtlSimWrapper.new(@ir_json)

        elapsed = Time.now - start_time
        puts "  IR loaded in #{elapsed.round(2)}s"
        puts "  Native backend: #{@sim.native? ? 'Rust' : 'Ruby (fallback)'}"
        puts "  Signals: #{@sim.signal_count}, Registers: #{@sim.reg_count}"

        @ram = Array.new(48 * 1024, 0)
        @rom = Array.new(12 * 1024, 0)
        @cycles = 0
        @halted = false
        @text_page_dirty = false
        @key_data = 0
        @key_ready = false

        @sim.reset
        initialize_inputs
      end

      def native?
        @sim.native?
      end

      def simulator_type
        :firrtl
      end

      def initialize_inputs
        poke_input('clk_14m', 0)
        poke_input('flash_clk', 0)
        poke_input('reset', 0)
        poke_input('ram_do', 0)
        poke_input('pd', 0)
        poke_input('k', 0)
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
        bytes.each_with_index do |byte, i|
          @rom[i] = byte if i < @rom.size
        end
      end

      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        bytes.each_with_index do |byte, i|
          addr = base_addr + i
          @ram[addr] = byte if addr < @ram.size
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
        puts "Warning: Disk support in FIRRTL mode is limited"
      end

      def disk_loaded?(drive: 0)
        @disk_loaded || false
      end

      def reset
        poke_input('reset', 1)
        run_14m_cycles(14)
        poke_input('reset', 0)
        run_14m_cycles(14 * 10)
        @cycles = 0
        @halted = false
      end

      def run_steps(steps)
        steps.times { run_cpu_cycle }
      end

      def run_cpu_cycle
        14.times { run_14m_cycle }
        @cycles += 1
      end

      def run_14m_cycle
        poke_input('k', @key_ready ? (@key_data | 0x80) : 0)

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

        # Check for keyboard strobe clear
        if peek_output('read_key') == 1
          @key_ready = false
        end
      end

      def run_14m_cycles(n)
        n.times { run_14m_cycle }
      end

      def inject_key(ascii)
        @key_data = ascii & 0x7F
        @key_ready = true
      end

      def key_ready?
        @key_ready
      end

      def clear_key
        @key_ready = false
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

      def hires_line_address(row, base = HIRES_PAGE1_START)
        section = row / 64
        row_in_section = row % 64
        group = row_in_section / 8
        line_in_group = row_in_section % 8

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      def cpu_state
        {
          pc: peek_output('pc_debug'),
          a: peek_output('a_debug'),
          x: peek_output('x_debug'),
          y: peek_output('y_debug'),
          sp: 0xFF,
          p: 0,
          cycles: @cycles,
          halted: @halted,
          simulator_type: :firrtl
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
        @speaker ||= SpeakerStub.new
      end

      def display_mode
        :text
      end

      def start_audio
        # No-op
      end

      def stop_audio
        # No-op
      end

      def read(addr)
        if addr < @ram.size
          @ram[addr]
        elsif addr >= 0xD000 && addr <= 0xFFFF
          @rom[addr - 0xD000] || 0
        else
          0
        end
      end

      def write(addr, value)
        if addr < @ram.size
          @ram[addr] = value & 0xFF
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

      class SpeakerStub
        def status
          "OFF"
        end

        def active?
          false
        end

        def toggle_count
          0
        end

        def samples_written
          0
        end
      end
    end
  end
end
