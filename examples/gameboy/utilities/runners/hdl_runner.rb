# frozen_string_literal: true

# Game Boy HDL Runner
# Behavioral simulation of Game Boy hardware
# Note: Full HDL component integration pending signal naming fixes

require_relative '../output/speaker'
require_relative '../renderers/lcd_renderer'

module RHDL
  module Examples
    module GameBoy
      # HDL-based runner using behavioral Game Boy simulation
    # This is a simplified runner that models Game Boy behavior
    # without requiring the full HDL component hierarchy
    class HdlRunner
      attr_reader :ram

      # Screen dimensions
      SCREEN_WIDTH = 160
      SCREEN_HEIGHT = 144

      # Memory map
      ROM_BANK_0_START = 0x0000
      ROM_BANK_0_END = 0x3FFF
      ROM_BANK_N_START = 0x4000
      ROM_BANK_N_END = 0x7FFF
      VRAM_START = 0x8000
      VRAM_END = 0x9FFF
      CART_RAM_START = 0xA000
      CART_RAM_END = 0xBFFF
      WRAM_START = 0xC000
      WRAM_END = 0xDFFF
      OAM_START = 0xFE00
      OAM_END = 0xFE9F
      IO_START = 0xFF00
      IO_END = 0xFF7F
      HRAM_START = 0xFF80
      HRAM_END = 0xFFFE
      IE_REGISTER = 0xFFFF

      def initialize
        # Memory arrays
        @rom = []           # Cartridge ROM (up to 8MB)
        @cart_ram = []      # Cartridge RAM (up to 128KB)
        @vram = Array.new(8 * 1024, 0)  # 8KB VRAM
        @wram = Array.new(8 * 1024, 0)  # 8KB WRAM
        @oam = Array.new(160, 0)        # 160 bytes OAM
        @hram = Array.new(127, 0)       # 127 bytes HRAM
        @io_regs = Array.new(128, 0)    # I/O registers
        @ie_reg = 0                      # Interrupt Enable register

        @cycles = 0
        @halted = false
        @screen_dirty = false

        # CPU state (simplified - post-boot values)
        @pc = 0x0100  # Program counter starts at 0x0100 after boot
        @sp = 0xFFFE  # Stack pointer
        @a = 0x01     # Accumulator
        @f = 0xB0     # Flags
        @bc = 0x0013
        @de = 0x00D8
        @hl = 0x014D

        # Frame buffer (160x144 pixels, 2-bit color)
        @framebuffer = Array.new(SCREEN_HEIGHT) { Array.new(SCREEN_WIDTH, 0) }

        # Joypad state (active low)
        @joypad = 0xFF

        # Speaker audio simulation
        @speaker = Speaker.new
        @prev_audio = 0
      end

      # Load ROM data
      def load_rom(bytes, base_addr: 0)
        bytes = bytes.bytes if bytes.is_a?(String)
        @rom = bytes.dup
        puts "Loaded #{@rom.length} bytes ROM"
      end

      # Load data into RAM for testing
      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        bytes.each_with_index do |byte, i|
          addr = base_addr + i
          write(addr, byte)
        end
      end

      # Reset the system
      def reset
        # Reset CPU state to post-boot values
        @pc = 0x0100
        @sp = 0xFFFE
        @a = 0x01
        @f = 0xB0
        @bc = 0x0013
        @de = 0x00D8
        @hl = 0x014D
        @cycles = 0
        @halted = false

        # Initialize key I/O registers
        @io_regs[0x40 - 0x00] = 0x91  # LCDC - LCD enabled
        @io_regs[0x41 - 0x00] = 0x85  # STAT
        @io_regs[0x47 - 0x00] = 0xFC  # BGP palette
      end

      # Run N machine cycles (4.19 MHz)
      def run_steps(steps)
        steps.times do
          run_machine_cycle
        end
      end

      # Run a single machine cycle (4 T-states)
      def run_machine_cycle
        # Simplified - just increment cycle counter
        # In a full implementation, this would execute CPU instructions
        @cycles += 1

        # Update LY register (scanline)
        ly = (@cycles / 456) % 154
        @io_regs[0x44] = ly

        # Update STAT mode based on cycle within line
        cycle_in_line = @cycles % 456
        mode = if ly >= 144
                 1  # VBlank
               elsif cycle_in_line < 80
                 2  # OAM search
               elsif cycle_in_line < 252
                 3  # Drawing
               else
                 0  # HBlank
               end
        @io_regs[0x41] = (@io_regs[0x41] & 0xFC) | mode

        @screen_dirty = true if mode == 1 && cycle_in_line == 0
      end

      # Read from memory
      def read(addr)
        addr &= 0xFFFF

        case addr
        when ROM_BANK_0_START..ROM_BANK_0_END
          @rom[addr] || 0
        when ROM_BANK_N_START..ROM_BANK_N_END
          @rom[addr] || 0
        when VRAM_START..VRAM_END
          @vram[addr - VRAM_START] || 0
        when CART_RAM_START..CART_RAM_END
          @cart_ram[addr - CART_RAM_START] || 0
        when WRAM_START..WRAM_END
          @wram[addr - WRAM_START] || 0
        when 0xE000..0xFDFF
          # Echo RAM
          @wram[addr - 0xE000] || 0
        when OAM_START..OAM_END
          @oam[addr - OAM_START] || 0
        when 0xFEA0..0xFEFF
          0xFF  # Unusable
        when IO_START..IO_END
          read_io(addr)
        when HRAM_START..HRAM_END
          @hram[addr - HRAM_START] || 0
        when IE_REGISTER
          @ie_reg
        else
          0xFF
        end
      end

      # Write to memory
      def write(addr, value)
        addr &= 0xFFFF
        value &= 0xFF

        case addr
        when ROM_BANK_0_START..ROM_BANK_N_END
          # ROM writes ignored (mapper would handle)
        when VRAM_START..VRAM_END
          @vram[addr - VRAM_START] = value
          @screen_dirty = true
        when CART_RAM_START..CART_RAM_END
          @cart_ram[addr - CART_RAM_START] = value
        when WRAM_START..WRAM_END
          @wram[addr - WRAM_START] = value
        when 0xE000..0xFDFF
          @wram[addr - 0xE000] = value
        when OAM_START..OAM_END
          @oam[addr - OAM_START] = value
        when 0xFEA0..0xFEFF
          # Unusable
        when IO_START..IO_END
          write_io(addr, value)
        when HRAM_START..HRAM_END
          @hram[addr - HRAM_START] = value
        when IE_REGISTER
          @ie_reg = value
        end
      end

      # Read I/O register
      def read_io(addr)
        case addr
        when 0xFF00  # JOYP
          @joypad
        when 0xFF04  # DIV
          (@cycles >> 8) & 0xFF
        when 0xFF44  # LY
          (@cycles / 456) % 154
        else
          @io_regs[addr - IO_START] || 0
        end
      end

      # Write I/O register
      def write_io(addr, value)
        case addr
        when 0xFF00  # JOYP
          @io_regs[0] = value
        when 0xFF04  # DIV
          # DIV reset
          @io_regs[4] = 0
        when 0xFF46  # DMA
          source = value << 8
          160.times { |i| @oam[i] = read(source + i) }
        else
          @io_regs[addr - IO_START] = value
        end
      end

      # Inject a joypad key press
      def inject_key(button)
        @joypad &= ~(1 << button)
      end

      # Release a joypad key
      def release_key(button)
        @joypad |= (1 << button)
      end

      # Read the frame buffer
      def read_framebuffer
        @framebuffer
      end

      # Read screen as text representation
      def read_screen
        ly = (@cycles / 456) % 154
        ["Game Boy LCD", "LY: #{ly}", "Cycles: #{@cycles}"]
      end

      def screen_dirty?
        @screen_dirty
      end

      def clear_screen_dirty
        @screen_dirty = false
      end

      # Render screen using braille characters
      def render_lcd_braille(chars_wide: 80, invert: false)
        renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
        renderer.render_braille(read_framebuffer)
      end

      # Render screen using color half-block characters
      def render_lcd_color(chars_wide: 80, invert: false)
        renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
        renderer.render_color(read_framebuffer)
      end

      # Get CPU state
      def cpu_state
        {
          pc: @pc,
          a: @a,
          f: @f,
          bc: @bc,
          de: @de,
          hl: @hl,
          sp: @sp,
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

      def dry_run_info
        {
          mode: :hdl,
          simulator_type: :hdl_ruby,
          native: false
        }
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
      end
    end
  end
end
