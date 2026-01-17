# Apple ][-style memory bus with I/O page and soft switches

require_relative '../../lib/rhdl/hdl'

module MOS6502S
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

    attr_reader :speaker_toggles, :video

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
