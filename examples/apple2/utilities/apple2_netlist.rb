# frozen_string_literal: true

# Apple II Netlist Export and Runner
# Provides gate-level netlist simulation for the Apple2 HDL component
#
# Usage:
#   # Export netlist to JSON
#   Apple2Netlist.export('apple2.json')
#
#   # Get gate-level IR
#   ir = Apple2Netlist.gate_ir
#
#   # Create netlist runner for simulation
#   runner = RHDL::Apple2::NetlistRunner.new

require_relative '../hdl/apple2'
require_relative 'ps2_encoder'
require 'rhdl/codegen'

# Load MOS6502 library (needed for lower.rb constants)
begin
  mos6502_cpu_path = File.expand_path('../../mos6502/hdl/cpu', __dir__)
  require mos6502_cpu_path
rescue LoadError
  # MOS6502 library not available, continue without it
end

module RHDL
  module Apple2
    # Utility module for exporting Apple2 component to gate-level netlist
    module Apple2Netlist
      class << self
        # Export Apple2 component to gate-level IR
        def gate_ir
          apple2 = Apple2.new('apple2')
          RHDL::Codegen::Netlist::Lower.from_components([apple2], name: 'apple2')
        end

        # Export to JSON file
        def export(path)
          ir = gate_ir
          File.write(path, ir.to_json)
          puts "Exported Apple2 netlist to #{path}"
          puts "  Nets: #{ir.net_count}"
          puts "  Gates: #{ir.gates.length}"
          puts "  DFFs: #{ir.dffs.length}"
          ir
        end

        # Get stats about the netlist
        def stats
          ir = gate_ir
          {
            net_count: ir.net_count,
            gate_count: ir.gates.length,
            dff_count: ir.dffs.length,
            input_count: ir.inputs.length,
            output_count: ir.outputs.length,
            inputs: ir.inputs.keys,
            outputs: ir.outputs.keys
          }
        end
      end
    end

    # HDL-based runner using native Rust gate-level simulation
    class NetlistRunner
      attr_reader :sim, :ram, :ir

      # Text page constants
      TEXT_PAGE1_START = 0x0400
      TEXT_PAGE1_END = 0x07FF

      # Hi-res graphics pages (280x192, 8KB each)
      HIRES_PAGE1_START = 0x2000
      HIRES_PAGE1_END = 0x3FFF
      HIRES_PAGE2_START = 0x4000
      HIRES_PAGE2_END = 0x5FFF

      HIRES_WIDTH = 280   # pixels
      HIRES_HEIGHT = 192  # lines
      HIRES_BYTES_PER_LINE = 40  # 280 pixels / 7 bits per byte

      # Disk geometry constants
      TRACKS = 35
      SECTORS_PER_TRACK = 16
      BYTES_PER_SECTOR = 256
      TRACK_SIZE = SECTORS_PER_TRACK * BYTES_PER_SECTOR  # 4096 bytes
      DISK_SIZE = TRACKS * TRACK_SIZE                     # 143360 bytes
      TRACK_BYTES = 6448  # Nibblized track size

      # DOS 3.3 sector interleaving table
      DOS33_INTERLEAVE = [
        0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
        0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F
      ].freeze

      # Backend options:
      #   :interpret - Pure Rust interpreter (slowest, fastest startup)
      #   :jit       - Cranelift JIT (default, balanced)
      #   :compile   - Rustc compiled (fastest, slow startup)
      def initialize(backend: :jit, simd: :auto)
        @backend = backend
        @simd = simd

        backend_names = { interpret: "Interpreter", jit: "Cranelift JIT", compile: "Rustc Compiler" }
        puts "Initializing Apple2 netlist simulation (#{backend_names[backend] || backend})..."
        start_time = Time.now

        # Generate gate-level IR
        @ir = Apple2Netlist.gate_ir

        # Create the simulator wrapper based on backend selection
        # allow_fallback: false ensures we get an error if the native extension is missing
        @sim = case backend
               when :interpret
                 RHDL::Codegen::Netlist::NetlistInterpreterWrapper.new(@ir, lanes: 1, allow_fallback: false)
               when :jit
                 RHDL::Codegen::Netlist::NetlistJitWrapper.new(@ir, lanes: 1, allow_fallback: false)
               when :compile
                 RHDL::Codegen::Netlist::NetlistCompilerWrapper.new(@ir, simd: simd, lanes: 1, allow_fallback: false)
               else
                 raise ArgumentError, "Unknown backend: #{backend}. Valid: :interpret, :jit, :compile"
               end

        elapsed = Time.now - start_time
        puts "  Netlist loaded in #{elapsed.round(2)}s"
        puts "  Native backend: #{@sim.native? ? 'Rust' : 'Ruby (fallback)'}"
        puts "  Gates: #{@ir.gates.length}, DFFs: #{@ir.dffs.length}"
        if backend == :compile && @sim.respond_to?(:simd_mode)
          puts "  SIMD mode: #{@sim.simd_mode}"
        end

        @ram = Array.new(48 * 1024, 0)  # 48KB RAM
        @rom = Array.new(12 * 1024, 0)  # 12KB ROM (loaded separately)
        @cycles = 0
        @halted = false
        @text_page_dirty = false

        # PS/2 keyboard encoder for sending keys through the PS/2 protocol
        @ps2_encoder = PS2Encoder.new

        # Initialize and reset
        @sim.reset
        initialize_inputs
      end

      def native?
        @sim.native?
      end

      def simulator_type
        :"netlist_#{@backend}"
      end

      # Initialize all input signals to safe defaults
      def initialize_inputs
        poke_input(:clk_14m, 0)
        poke_input(:flash_clk, 0)
        poke_input(:reset, 0)
        poke_input(:ram_do, 0)
        poke_input(:pd, 0)
        poke_input(:ps2_clk, 1)   # PS/2 idle state is high
        poke_input(:ps2_data, 1)  # PS/2 idle state is high
        poke_input(:gameport, 0)
        poke_input(:pause, 0)
        @sim.evaluate
      end

      # Poke an input signal (handles port naming convention)
      def poke_input(name, value)
        @sim.poke("apple2.#{name}", value)
      end

      # Peek an output signal (handles port naming convention)
      # Converts multi-bit arrays to integers
      def peek_output(name)
        result = @sim.peek("apple2.#{name}")
        if result.is_a?(Array)
          # Convert array of bit values to integer (LSB first)
          result.each_with_index.reduce(0) { |acc, (bit, i)| acc | ((bit & 1) << i) }
        else
          result
        end
      end

      # Load ROM data
      def load_rom(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        bytes.each_with_index do |byte, i|
          @rom[i] = byte if i < @rom.size
        end
      end

      # Load data into RAM
      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        bytes.each_with_index do |byte, i|
          addr = base_addr + i
          @ram[addr] = byte if addr < @ram.size
        end
      end

      # Disk loading
      def load_disk(path_or_bytes, drive: 0)
        bytes = if path_or_bytes.is_a?(String)
                  File.binread(path_or_bytes).bytes
                else
                  path_or_bytes.is_a?(Array) ? path_or_bytes : path_or_bytes.bytes
                end

        if bytes.length != DISK_SIZE
          raise ArgumentError, "Invalid disk image size: #{bytes.length} (expected #{DISK_SIZE})"
        end

        # For now, just store disk data - disk controller support TBD
        @disk_loaded = true
        @disk_tracks = encode_disk(bytes)
        puts "Warning: Disk support in netlist mode is limited"
      end

      def disk_loaded?(drive: 0)
        @disk_loaded || false
      end

      # Reset the system
      def reset
        poke_input(:reset, 1)
        run_14m_cycles(14)  # Hold reset for a few cycles
        poke_input(:reset, 0)
        run_14m_cycles(14 * 10)  # Let system settle
        @cycles = 0
        @halted = false
      end

      # Run N CPU cycles (approximately)
      # Each CPU cycle is ~7 14MHz cycles
      def run_steps(steps)
        steps.times do
          run_cpu_cycle
        end
      end

      # Run a single CPU cycle
      def run_cpu_cycle
        # Run 14MHz cycles until we complete a CPU cycle
        14.times do
          run_14m_cycle
        end
        @cycles += 1
      end

      # Run a single 14MHz clock cycle
      def run_14m_cycle
        # Update PS/2 keyboard signals from encoder
        ps2_clk, ps2_data = @ps2_encoder.next_ps2_state
        poke_input(:ps2_clk, ps2_clk)
        poke_input(:ps2_data, ps2_data)

        # Falling edge
        poke_input(:clk_14m, 0)
        @sim.evaluate

        # Provide RAM/ROM data based on address
        ram_addr = peek_output(:ram_addr)
        if ram_addr >= 0xD000 && ram_addr <= 0xFFFF
          # ROM access
          rom_offset = ram_addr - 0xD000
          poke_input(:ram_do, @rom[rom_offset] || 0)
        elsif ram_addr < @ram.size
          # RAM access
          poke_input(:ram_do, @ram[ram_addr] || 0)
        else
          poke_input(:ram_do, 0)
        end
        @sim.evaluate

        # Rising edge - use tick for DFF state update
        poke_input(:clk_14m, 1)
        @sim.tick

        # Handle RAM writes
        ram_we = peek_output(:ram_we)
        if ram_we == 1
          write_addr = peek_output(:ram_addr)
          if write_addr < @ram.size
            data = peek_output(:d)
            @ram[write_addr] = data & 0xFF
            # Mark text page dirty
            if write_addr >= TEXT_PAGE1_START && write_addr <= TEXT_PAGE1_END
              @text_page_dirty = true
            end
          end
        end
      end

      # Run N 14MHz cycles
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

      # Read the text page as a 2D array of character codes
      def read_screen_array
        result = []
        24.times do |row|
          line = []
          base = text_line_address(row)
          40.times do |col|
            addr = base + col
            line << (@ram[addr] || 0)
          end
          result << line
        end
        result
      end

      # Read the text page as 24 lines of strings
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

      # Read hi-res graphics as raw bitmap (192 rows x 280 pixels)
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

      # Render hi-res screen using Unicode braille characters
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

      # Hi-res screen line address calculation
      def hires_line_address(row, base = HIRES_PAGE1_START)
        section = row / 64
        row_in_section = row % 64
        group = row_in_section / 8
        line_in_group = row_in_section % 8

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      # Get CPU state for debugging
      # Netlist mode uses fully flattened gate-level IR, so debug signals should work
      def cpu_state
        {
          pc: safe_peek(:pc_debug),
          a: safe_peek(:a_debug),
          x: safe_peek(:x_debug),
          y: safe_peek(:y_debug),
          sp: 0xFF,  # TODO: Add S register debug output
          p: 0,      # TODO: Add P register debug output
          cycles: @cycles,
          halted: @halted,
          simulator_type: simulator_type
        }
      end

      # Safely peek an output, returning 0 on error
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

      # Return dry-run information for testing without starting emulation
      # @return [Hash] Information about engine configuration and memory state
      def dry_run_info
        {
          mode: :netlist,
          simulator_type: simulator_type,
          native: native?,
          backend: @backend,
          cpu_state: cpu_state,
          memory_sample: memory_sample
        }
      end

      # Bus-like interface for compatibility
      def bus
        self
      end

      def tick(cycles)
        # No-op for netlist
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

      # Return a sample of memory for verification
      def memory_sample
        {
          zero_page: (0...256).map { |i| @ram[i] || 0 },
          stack: (0...256).map { |i| @ram[0x0100 + i] || 0 },
          text_page: (0...1024).map { |i| @ram[0x0400 + i] || 0 },
          program_area: (0...256).map { |i| @ram[0x0800 + i] || 0 },
          reset_vector: [read(0xFFFC), read(0xFFFD)]
        }
      end

      # Apple II text screen line address calculation
      def text_line_address(row)
        group = row / 8
        line_in_group = row % 8
        TEXT_PAGE1_START + (line_in_group * 0x80) + (group * 0x28)
      end

      # Encode a .dsk image to nibblized format for each track
      def encode_disk(bytes)
        tracks = []

        TRACKS.times do |track_num|
          track_data = []

          SECTORS_PER_TRACK.times do |phys_sector|
            log_sector = DOS33_INTERLEAVE[phys_sector]
            offset = (track_num * TRACK_SIZE) + (log_sector * BYTES_PER_SECTOR)
            sector_data = bytes[offset, BYTES_PER_SECTOR]
            track_data.concat(encode_sector(track_num, phys_sector, sector_data))
          end

          tracks << track_data
        end

        tracks
      end

      def encode_sector(track, sector, data)
        encoded = []

        # Gap 1 - self-sync bytes
        16.times { encoded << 0xFF }

        # Address field prologue: D5 AA 96
        encoded << 0xD5 << 0xAA << 0x96

        # Volume, track, sector, checksum (4-and-4 encoded)
        volume = 254
        checksum = volume ^ track ^ sector

        encoded.concat(encode_4and4(volume))
        encoded.concat(encode_4and4(track))
        encoded.concat(encode_4and4(sector))
        encoded.concat(encode_4and4(checksum))

        # Address field epilogue: DE AA EB
        encoded << 0xDE << 0xAA << 0xEB

        # Gap 2
        8.times { encoded << 0xFF }

        # Data field prologue: D5 AA AD
        encoded << 0xD5 << 0xAA << 0xAD

        # 6-and-2 encoding
        encoded.concat(encode_6and2(data || Array.new(256, 0)))

        # Data field epilogue: DE AA EB
        encoded << 0xDE << 0xAA << 0xEB

        # Gap 3
        16.times { encoded << 0xFF }

        encoded
      end

      def encode_4and4(byte)
        [
          ((byte >> 1) & 0x55) | 0xAA,
          (byte & 0x55) | 0xAA
        ]
      end

      def encode_6and2(data)
        translate = [
          0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
          0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
          0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
          0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
          0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
          0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
          0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
          0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
        ]

        buffer = Array.new(342, 0)

        86.times do |i|
          val = 0
          val |= ((data[i] || 0) & 0x01) << 1
          val |= ((data[i] || 0) & 0x02) >> 1
          val |= ((data[i + 86] || 0) & 0x01) << 3 if i + 86 < 256
          val |= ((data[i + 86] || 0) & 0x02) << 1 if i + 86 < 256
          val |= ((data[i + 172] || 0) & 0x01) << 5 if i + 172 < 256
          val |= ((data[i + 172] || 0) & 0x02) << 3 if i + 172 < 256
          buffer[i] = val
        end

        256.times do |i|
          buffer[86 + i] = (data[i] || 0) >> 2
        end

        encoded = []
        checksum = 0

        342.times do |i|
          val = buffer[i] ^ checksum
          checksum = buffer[i]
          encoded << translate[val & 0x3F]
        end

        encoded << translate[checksum & 0x3F]

        encoded
      end
    end

    # Stub for disk controller (reuse from harness)
    class DiskControllerStub
      def track
        0
      end

      def motor_on
        false
      end
    end

    # Stub for speaker (reuse from harness)
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
