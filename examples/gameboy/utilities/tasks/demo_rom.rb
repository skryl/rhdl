# frozen_string_literal: true

module RHDL
  module GameBoy
    module Tasks
      # Creates demo ROMs for testing the Game Boy emulator
      class DemoRom
        NINTENDO_LOGO = [
          0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
          0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
          0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
          0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
          0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
          0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
        ].freeze

        DEFAULT_TITLE = "RHDL TEST"
        ROM_SIZE = 32 * 1024

        attr_reader :title

        def initialize(title: DEFAULT_TITLE)
          @title = title
        end

        # Create a minimal Game Boy ROM that turns on the LCD and loops
        def create
          rom = Array.new(ROM_SIZE, 0)

          write_entry_point(rom)  # Must be before logo (shares 0x104)
          write_nintendo_logo(rom)
          write_title(rom)
          write_header_checksum(rom)
          write_main_program(rom)

          rom.pack('C*')
        end

        # Create ROM and return as byte array (not packed)
        def create_bytes
          rom = Array.new(ROM_SIZE, 0)

          write_entry_point(rom)  # Must be before logo (shares 0x104)
          write_nintendo_logo(rom)
          write_title(rom)
          write_header_checksum(rom)
          write_main_program(rom)

          rom
        end

        private

        def write_nintendo_logo(rom)
          NINTENDO_LOGO.each_with_index { |b, i| rom[0x104 + i] = b }
        end

        def write_title(rom)
          @title.bytes.each_with_index { |b, i| rom[0x134 + i] = b }
        end

        def write_header_checksum(rom)
          checksum = 0
          (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
          rom[0x14D] = checksum
        end

        def write_entry_point(rom)
          # Entry point at 0x100 - NOP NOP JP 0x150
          rom[0x100] = 0x00  # NOP
          rom[0x101] = 0x00  # NOP
          rom[0x102] = 0xC3  # JP
          rom[0x103] = 0x50  # addr low
          rom[0x104] = 0x01  # addr high (will be overwritten by logo)
        end

        def write_main_program(rom)
          pc = 0x150

          # Turn on LCD: LD A, $91; LDH ($40), A
          rom[pc] = 0x3E; pc += 1  # LD A, imm
          rom[pc] = 0x91; pc += 1  # $91 (LCD on)
          rom[pc] = 0xE0; pc += 1  # LDH (n), A
          rom[pc] = 0x40; pc += 1  # LCDC register

          # Infinite loop: NOP; JR -2
          loop_addr = pc
          rom[pc] = 0x00; pc += 1  # NOP
          rom[pc] = 0x18; pc += 1  # JR
          rom[pc] = (loop_addr - pc - 1) & 0xFF
        end
      end
    end
  end
end
