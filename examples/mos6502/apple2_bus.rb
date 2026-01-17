# Apple ][-style memory bus with I/O page and soft switches

require_relative '../../lib/rhdl/hdl'

module MOS6502
  class Apple2Bus < RHDL::HDL::SimComponent
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

    attr_reader :speaker_toggles, :video, :key_ready

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
      @text_page_dirty = false
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

    def soft_switch_accessed?(addr)
      @soft_switch_access[addr & 0xFFFF] > 0
    end

    def text_page_written?
      (TEXT_PAGE1_START..TEXT_PAGE1_END).any? { |addr| @memory[addr] != 0 }
    end

    # Check if text page has been modified since last clear
    def text_page_dirty?
      @text_page_dirty
    end

    # Clear the dirty flag after rendering
    def clear_text_page_dirty
      @text_page_dirty = false
    end

    # Read the entire text page as a 24x40 array of characters
    # Apple II text page has a peculiar memory layout
    def read_text_page
      lines = Array.new(24) { Array.new(40, 0x20) }

      # Apple II text page memory layout:
      # Line groups are interleaved with 128-byte spacing
      # Group 0: lines 0, 8, 16 at offsets 0x000, 0x080, 0x100
      # Group 1: lines 1, 9, 17 at offsets 0x028, 0x0A8, 0x128
      # etc.
      base_offsets = [0x000, 0x080, 0x100]
      line_offsets = [0x00, 0x28, 0x50, 0x78, 0xA0, 0xC8, 0xF0, 0x118]

      8.times do |group|
        3.times do |section|
          line_num = group + (section * 8)
          next if line_num >= 24

          addr = TEXT_PAGE1_START + line_offsets[group] + base_offsets[section]
          40.times do |col|
            byte = @memory[addr + col]
            # Convert Apple II character to ASCII (handle inverse/flash)
            char = byte & 0x7F
            char = 0x20 if char < 0x20 # Control chars to space
            lines[line_num][col] = char
          end
        end
      end

      lines
    end

    # Read text page as a string (24 lines of 40 chars)
    def read_text_page_string
      read_text_page.map { |line| line.pack('C*') }.join("\n")
    end

    # Clear the keyboard ready flag (for polling)
    def clear_key
      @key_ready = false
    end

    private

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

      # Track text page writes for dirty flag
      if addr >= TEXT_PAGE1_START && addr <= TEXT_PAGE1_END
        @text_page_dirty = true
      end
    end

    def io_page?(addr)
      addr >= IO_PAGE_START && addr <= IO_PAGE_END
    end

    def handle_io(direction, addr, value)
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
