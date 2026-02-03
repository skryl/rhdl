# frozen_string_literal: true

# Apple II Demo Program Generator
# Creates a simple demo program that clears the screen and echoes keyboard input

module RHDL
  module Apple2
    module Tasks
      # Generates a simple demo program for Apple II
      # Clears screen, prints "HDL READY", and echoes typed characters
      class DemoProgram
        def self.create
          new.generate
        end

        def generate
          asm = []
          cursor_lo = 0x00
          cursor_hi = 0x01

          # Initialize cursor
          asm << 0xA9 << 0x00        # LDA #$00
          asm << 0x85 << cursor_lo   # STA $00
          asm << 0xA9 << 0x04        # LDA #$04
          asm << 0x85 << cursor_hi   # STA $01

          # Clear screen
          asm << 0xA0 << 0x00        # LDY #$00
          asm << 0xA9 << 0xA0        # LDA #$A0 (space)
          # CLEAR_LOOP:
          asm << 0x91 << cursor_lo   # STA ($00),Y
          asm << 0xC8                # INY
          asm << 0xD0 << 0xFB        # BNE CLEAR_LOOP
          asm << 0xE6 << cursor_hi   # INC $01
          asm << 0xA5 << cursor_hi   # LDA $01
          asm << 0xC9 << 0x08        # CMP #$08
          asm << 0xD0 << 0xF3        # BNE CLEAR_LOOP

          # Reset cursor
          asm << 0xA9 << 0x00        # LDA #$00
          asm << 0x85 << cursor_lo   # STA $00
          asm << 0xA9 << 0x04        # LDA #$04
          asm << 0x85 << cursor_hi   # STA $01

          # Print "HDL READY"
          "HDL READY\r".each_byte do |b|
            b = b | 0x80
            asm << 0xA9 << b         # LDA #char
            asm << 0xA0 << 0x00      # LDY #$00
            asm << 0x91 << cursor_lo # STA ($00),Y
            asm << 0xE6 << cursor_lo # INC $00
          end

          # Main loop: read keyboard
          main_loop = asm.length
          asm << 0xAD << 0x00 << 0xC0  # LDA $C000
          asm << 0x10 << 0xFB          # BPL (wait for key)
          asm << 0x8D << 0x10 << 0xC0  # STA $C010 (clear strobe)
          asm << 0x09 << 0x80          # ORA #$80
          asm << 0xA0 << 0x00          # LDY #$00
          asm << 0x91 << cursor_lo     # STA ($00),Y
          asm << 0xE6 << cursor_lo     # INC $00
          asm << 0x4C                  # JMP main_loop
          asm << (main_loop & 0xFF) << (((main_loop >> 8) + 0x08) & 0xFF)

          asm
        end
      end
    end
  end
end
