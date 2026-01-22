# frozen_string_literal: true

# Apple II HDL Harness
# Wraps the Apple2 HDL component for use in emulation

require_relative '../hdl/apple2'
require_relative 'speaker'

module RHDL
  module Apple2
    # HDL-based runner using cycle-accurate Apple2 simulation
    class Runner
      attr_reader :apple2, :ram

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

      def initialize
        @apple2 = Apple2.new('apple2')
        @ram = Array.new(48 * 1024, 0)  # 48KB RAM
        @cycles = 0
        @halted = false
        @text_page_dirty = false
        @key_data = 0
        @key_ready = false

        # Initialize system inputs
        @apple2.set_input(:clk_14m, 0)
        @apple2.set_input(:flash_clk, 0)
        @apple2.set_input(:reset, 0)
        @apple2.set_input(:ram_do, 0)
        @apple2.set_input(:pd, 0)
        @apple2.set_input(:k, 0)
        @apple2.set_input(:gameport, 0)
        @apple2.set_input(:pause, 0)

        # Track Q3 for cycle counting
        @prev_q3 = 0

        # Speaker audio simulation
        @speaker = Speaker.new
        @prev_speaker_state = 0
      end

      # Load ROM data into the Apple2 component
      def load_rom(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        @apple2.load_rom(bytes)
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

        # Load disk boot ROM
        load_disk_boot_rom

        # Convert DSK to nibblized tracks and load each track
        @disk_tracks = encode_disk(bytes)
        @disk_loaded = true
        @current_track = 0

        # Load initial track (track 0)
        load_track_to_controller(0)
      end

      def disk_loaded?(drive: 0)
        @disk_loaded || false
      end

      def load_disk_boot_rom
        boot_rom_path = File.expand_path('../software/roms/disk2_boot.bin', __dir__)
        if File.exist?(boot_rom_path)
          rom_data = File.binread(boot_rom_path).bytes
          @apple2.load_disk_boot_rom(rom_data)
        else
          warn "Disk II boot ROM not found at #{boot_rom_path}"
        end
      end

      def load_track_to_controller(track_num)
        return unless @disk_tracks && track_num < @disk_tracks.length
        track_data = @disk_tracks[track_num]
        @apple2.load_disk_track(track_num, track_data)
      end

      # Reset the system
      def reset
        @apple2.set_input(:reset, 1)
        run_14m_cycles(14)  # Hold reset for a few cycles
        @apple2.set_input(:reset, 0)
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
        # Run 14MHz cycles until we see a Q3 rising edge with enable
        14.times do
          run_14m_cycle
        end
        @cycles += 1
      end

      # Run a single 14MHz clock cycle
      def run_14m_cycle
        # Update keyboard input
        @apple2.set_input(:k, @key_ready ? (@key_data | 0x80) : 0)

        # Falling edge
        @apple2.set_input(:clk_14m, 0)
        @apple2.propagate

        # Provide RAM data
        ram_addr = @apple2.get_output(:ram_addr)
        if ram_addr < @ram.size
          @apple2.set_input(:ram_do, @ram[ram_addr])
        end
        @apple2.propagate

        # Rising edge
        @apple2.set_input(:clk_14m, 1)
        @apple2.propagate

        # Handle RAM writes
        ram_we = @apple2.get_output(:ram_we)
        if ram_we == 1
          write_addr = @apple2.get_output(:ram_addr)
          if write_addr < @ram.size
            @ram[write_addr] = @apple2.get_output(:d)
            # Mark text page dirty
            if write_addr >= TEXT_PAGE1_START && write_addr <= TEXT_PAGE1_END
              @text_page_dirty = true
            end
          end
        end

        # Check for keyboard strobe clear
        if @apple2.get_output(:read_key) == 1
          @key_ready = false
        end

        # Monitor speaker output for state changes
        speaker_state = @apple2.get_output(:speaker)
        if speaker_state != @prev_speaker_state
          @speaker.toggle
          @prev_speaker_state = speaker_state
        end
      end

      # Run N 14MHz cycles
      def run_14m_cycles(n)
        n.times { run_14m_cycle }
      end

      # Inject a key into the keyboard buffer
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
      # Returns 2D array of 0/1 values
      def read_hires_bitmap
        base = HIRES_PAGE1_START  # Always use page 1 for now
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base)

          HIRES_BYTES_PER_LINE.times do |col|
            byte = @ram[line_addr + col] || 0
            # Each byte has 7 pixels (bit 7 is color/palette select)
            7.times do |bit|
              line << ((byte >> bit) & 1)
            end
          end

          bitmap << line
        end

        bitmap
      end

      # Render hi-res screen using Unicode braille characters (2x4 dots per char)
      # This gives much higher resolution than ASCII art
      # chars_wide: target width in characters (default 80)
      def render_hires_braille(chars_wide: 80, invert: false)
        bitmap = read_hires_bitmap

        # Braille characters are 2 dots wide x 4 dots tall
        chars_tall = (HIRES_HEIGHT / 4.0).ceil

        # Scale factors
        x_scale = HIRES_WIDTH.to_f / (chars_wide * 2)
        y_scale = HIRES_HEIGHT.to_f / (chars_tall * 4)

        # Braille dot positions (Unicode mapping):
        # Dot 1 (0x01) Dot 4 (0x08)
        # Dot 2 (0x02) Dot 5 (0x10)
        # Dot 3 (0x04) Dot 6 (0x20)
        # Dot 7 (0x40) Dot 8 (0x80)
        dot_map = [
          [0x01, 0x08],  # row 0
          [0x02, 0x10],  # row 1
          [0x04, 0x20],  # row 2
          [0x40, 0x80]   # row 3
        ]

        lines = []
        chars_tall.times do |char_y|
          line = String.new
          chars_wide.times do |char_x|
            pattern = 0

            # Sample 2x4 grid for this braille character
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

            # Unicode braille starts at U+2800
            line << (0x2800 + pattern).chr(Encoding::UTF_8)
          end
          lines << line
        end

        lines.join("\n")
      end

      # Hi-res screen line address calculation (Apple II interleaved layout)
      def hires_line_address(row, base = HIRES_PAGE1_START)
        # row 0-191
        # Each group of 8 consecutive rows is separated by 0x400 bytes
        # Groups of 8 lines within a section are 0x80 apart
        # Sections (0-63, 64-127, 128-191) are 0x28 apart

        section = row / 64           # 0, 1, or 2
        row_in_section = row % 64
        group = row_in_section / 8   # 0-7
        line_in_group = row_in_section % 8  # 0-7

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      # Get CPU state for debugging
      def cpu_state
        {
          pc: @apple2.get_output(:pc_debug),
          a: @apple2.get_output(:a_debug),
          x: @apple2.get_output(:x_debug),
          y: @apple2.get_output(:y_debug),
          sp: 0xFF,  # TODO: Add S register debug output
          p: 0,      # TODO: Add P register debug output
          cycles: @cycles,
          halted: @halted,
          simulator_type: :hdl_ruby
        }
      end

      def halted?
        @halted
      end

      def cycle_count
        @cycles
      end

      def simulator_type
        :hdl_ruby
      end

      def native?
        false
      end

      # Bus-like interface for compatibility
      def bus
        self
      end

      # Stub methods for compatibility with Apple2Terminal
      def tick(cycles)
        # No-op for HDL
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
        if addr < @ram.size
          @ram[addr]
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

      # Apple II text screen line address calculation
      # The text screen uses an interleaved memory layout
      def text_line_address(row)
        # Apple II text page memory layout (base $0400)
        # Lines are interleaved in groups of 8
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

      # Encode a single sector with address field, gaps, and data field
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

      # 4-and-4 encoding for address field
      def encode_4and4(byte)
        [
          ((byte >> 1) & 0x55) | 0xAA,
          (byte & 0x55) | 0xAA
        ]
      end

      # 6-and-2 encoding for data field
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

        # Extract 2-bit values
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

        # Store 6-bit values
        256.times do |i|
          buffer[86 + i] = (data[i] || 0) >> 2
        end

        # XOR encode and translate
        encoded = []
        checksum = 0

        342.times do |i|
          val = buffer[i] ^ checksum
          checksum = buffer[i]
          encoded << translate[val & 0x3F]
        end

        # Append checksum
        encoded << translate[checksum & 0x3F]

        encoded
      end
    end

    # Stub for disk controller (not yet implemented)
    class DiskControllerStub
      def track
        0
      end

      def motor_on
        false
      end
    end

    # Stub for speaker (not yet implemented)
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
