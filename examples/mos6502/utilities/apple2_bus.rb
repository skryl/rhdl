# Apple ][-style memory bus with I/O page and soft switches

require_relative '../../../lib/rhdl/hdl'
require_relative 'disk2'

module MOS6502
  class Apple2Bus < RHDL::HDL::Component
    IO_PAGE_START = 0xC000
    IO_PAGE_END = 0xC0FF

    TEXT_PAGE1_START = 0x0400
    TEXT_PAGE1_END = 0x07FF

    ROM_START = 0xF800
    ROM_END = 0xFFFF

    SOFT_SWITCHES = {
      0xC050 => [:text, false], # GRAPHICS
      0xC051 => [:text, true],  # TEXT
      0xC052 => [:mixed, false],
      0xC053 => [:mixed, true],
      0xC054 => [:page2, false],
      0xC055 => [:page2, true],
      0xC056 => [:hires, false],
      0xC057 => [:hires, true]
    }.freeze

    attr_reader :speaker_toggles, :video, :disk_controller

    def initialize(name = nil)
      @memory = Array.new(0x10000, 0)
      @rom_mask = Array.new(0x10000, false)
      @prev_clk = 0
      @key_ready = false
      @key_value = 0
      @speaker_toggles = 0
      @video = {
        text: true,
        mixed: false,
        page2: false,
        hires: false
      }
      @soft_switch_access = Hash.new(0)
      @disk_controller = Disk2.new
      super(name)
    end

    def setup_ports
      input :clk
      input :addr, width: 16
      input :data_in, width: 8
      input :rw
      input :cs

      output :data_out, width: 8
    end

    def rising_edge?
      prev = @prev_clk
      @prev_clk = in_val(:clk)
      prev == 0 && @prev_clk == 1
    end

    def propagate
      addr = in_val(:addr) & 0xFFFF
      cs = in_val(:cs)
      rw = in_val(:rw)

      if cs == 1
        if rising_edge? && rw == 0
          handle_write(addr, in_val(:data_in))
        end

        out_set(:data_out, handle_read(addr))
      else
        out_set(:data_out, 0)
      end
    end

    def read(addr)
      handle_read(addr & 0xFFFF)
    end

    def write(addr, data)
      handle_write(addr & 0xFFFF, data)
    end

    def load_rom(bytes, base_addr:)
      to_bytes(bytes).each_with_index do |byte, i|
        addr = (base_addr + i) & 0xFFFF
        @memory[addr] = byte & 0xFF
        @rom_mask[addr] = true
      end
    end

    def load_ram(bytes, base_addr:)
      to_bytes(bytes).each_with_index do |byte, i|
        addr = (base_addr + i) & 0xFFFF
        @memory[addr] = byte & 0xFF
        @rom_mask[addr] = false
      end
    end

    def reset_vector
      low = @memory[0xFFFC]
      high = @memory[0xFFFD]
      (high << 8) | low
    end

    def inject_key(ascii)
      @key_value = ascii & 0x7F
      @key_ready = true
    end

    # Load a disk image into the specified drive
    def load_disk(path_or_bytes, drive: 0)
      @disk_controller.load_disk(path_or_bytes, drive: drive)
    end

    # Check if a disk is loaded
    def disk_loaded?(drive: 0)
      @disk_controller.disk_loaded?(drive: drive)
    end

    # Eject disk from drive
    def eject_disk(drive: 0)
      @disk_controller.eject_disk(drive: drive)
    end

    def soft_switch_accessed?(addr)
      @soft_switch_access[addr & 0xFFFF] > 0
    end

    def text_page_written?
      (TEXT_PAGE1_START..TEXT_PAGE1_END).any? { |addr| @memory[addr] != 0 }
    end

    # Read the text page as a 2D array of character codes (24 rows x 40 columns)
    def read_text_page
      result = []
      24.times do |row|
        line = []
        base = text_line_address(row)
        40.times do |col|
          line << @memory[base + col]
        end
        result << line
      end
      result
    end

    # Read the text page as 24 lines of strings
    def read_text_page_string
      read_text_page.map do |line|
        line.map { |c| ((c & 0x7F) >= 0x20 ? (c & 0x7F).chr : ' ') }.join
      end
    end

    # Check if the screen has been modified
    def text_page_dirty?
      @text_page_dirty ||= false
    end

    # Clear the screen dirty flag
    def clear_text_page_dirty
      @text_page_dirty = false
    end

    # Mark the screen as dirty
    def mark_text_page_dirty
      @text_page_dirty = true
    end

    # Get the key ready state
    def key_ready
      @key_ready
    end

    # Clear the key ready flag
    def clear_key
      @key_ready = false
    end

    private

    # Apple II text page has a non-linear layout
    def text_line_address(row)
      base = TEXT_PAGE1_START
      # Apple II screen memory layout: interleaved in groups of 8
      group = row / 8
      offset = row % 8
      base + (offset * 0x80) + (group * 0x28)
    end

    def handle_read(addr)
      if io_page?(addr)
        return handle_io(:read, addr, 0)
      end

      @memory[addr]
    end

    def handle_write(addr, value)
      if io_page?(addr)
        handle_io(:write, addr, value)
        return
      end

      return if @rom_mask[addr]

      @memory[addr] = value & 0xFF

      # Mark text page dirty if writing to text area
      if addr >= TEXT_PAGE1_START && addr <= TEXT_PAGE1_END
        @text_page_dirty = true
      end
    end

    def io_page?(addr)
      addr >= IO_PAGE_START && addr <= IO_PAGE_END
    end

    def handle_io(direction, addr, value)
      # Check Disk II controller first (slot 6: $C0E0-$C0EF)
      if @disk_controller.handles_address?(addr)
        return @disk_controller.access(addr, value, write: direction == :write)
      end

      case addr
      when 0xC000
        @key_ready ? (@key_value | 0x80) : 0x00
      when 0xC010
        @key_ready = false
        0x00
      when 0xC030
        @speaker_toggles += 1
        0x00
      else
        if SOFT_SWITCHES.key?(addr)
          setting, state = SOFT_SWITCHES[addr]
          @video[setting] = state
          @soft_switch_access[addr] += 1
        end
        0x00
      end
    end

    def to_bytes(source)
      return source.bytes if source.is_a?(String)

      source
    end
  end
end
