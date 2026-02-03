# frozen_string_literal: true

# Demo program generator for MOS6502 terminal emulator

module MOS6502
  module Tasks
    class DemoProgram
      def self.create
        new.generate
      end

      # Simple 6502 program that:
      # 1. Clears screen
      # 2. Prints "APPLE ][ READY" message
      # 3. Echoes keyboard input to screen
      def generate
        asm = []

        # ORG $0800
        # Zero page variables
        cursor_lo = 0x00
        cursor_hi = 0x01

        # INIT: Set up cursor at start of text page
        asm << 0xA9 << 0x00        # LDA #$00
        asm << 0x85 << cursor_lo   # STA $00 (cursor low)
        asm << 0xA9 << 0x04        # LDA #$04
        asm << 0x85 << cursor_hi   # STA $01 (cursor high)

        # Clear text page
        asm << 0xA0 << 0x00        # LDY #$00
        asm << 0xA9 << 0xA0        # LDA #$A0 (space with high bit set)
        # CLEAR_LOOP:
        clear_loop = asm.length
        asm << 0x91 << cursor_lo   # STA ($00),Y
        asm << 0xC8                # INY
        asm << 0xD0 << 0xFB        # BNE CLEAR_LOOP (-5)
        asm << 0xE6 << cursor_hi   # INC $01
        asm << 0xA5 << cursor_hi   # LDA $01
        asm << 0xC9 << 0x08        # CMP #$08
        asm << 0xD0 << 0xF3        # BNE CLEAR_LOOP (-13)

        # Reset cursor to start
        asm << 0xA9 << 0x00        # LDA #$00
        asm << 0x85 << cursor_lo   # STA $00
        asm << 0xA9 << 0x04        # LDA #$04
        asm << 0x85 << cursor_hi   # STA $01

        # Print "READY" message
        message = "APPLE ][ READY\r"
        message.each_byte do |b|
          b = b | 0x80 # Set high bit for Apple II normal video
          asm << 0xA9 << b         # LDA #char
          asm << 0x20              # JSR PRINT_CHAR (we'll fill in address)
          print_char_addr = asm.length + 40 # Approximate offset
          asm << (print_char_addr & 0xFF) << ((print_char_addr >> 8) & 0xFF)
        end

        # Main loop: read keyboard and echo
        # MAIN_LOOP:
        main_loop = asm.length
        asm << 0xAD << 0x00 << 0xC0  # LDA $C000 (read keyboard)
        asm << 0x10 << 0xFB          # BPL MAIN_LOOP (wait for key)
        asm << 0x8D << 0x10 << 0xC0  # STA $C010 (clear strobe)
        asm << 0x29 << 0x7F          # AND #$7F (mask high bit)
        asm << 0xC9 << 0x0D          # CMP #$0D (carriage return?)
        asm << 0xF0 << 0x10          # BEQ NEW_LINE
        asm << 0x09 << 0x80          # ORA #$80 (set high bit for display)
        asm << 0x20                  # JSR PRINT_CHAR
        print_char_offset = asm.length
        asm << 0x00 << 0x00          # (placeholder)
        jmp_main = asm.length
        asm << 0x4C                  # JMP MAIN_LOOP
        asm << (main_loop & 0xFF) << (((main_loop >> 8) + 0x08) & 0xFF)

        # NEW_LINE: Handle carriage return
        new_line = asm.length
        # Move cursor to next line
        asm << 0x18                  # CLC
        asm << 0xA5 << cursor_lo     # LDA $00
        asm << 0x69 << 0x28          # ADC #$28 (40 columns)
        asm << 0x85 << cursor_lo     # STA $00
        asm << 0xA5 << cursor_hi     # LDA $01
        asm << 0x69 << 0x00          # ADC #$00
        asm << 0x85 << cursor_hi     # STA $01
        # Check for screen wrap
        asm << 0xC9 << 0x08          # CMP #$08
        asm << 0x90 << 0x04          # BCC NO_WRAP
        asm << 0xA9 << 0x04          # LDA #$04
        asm << 0x85 << cursor_hi     # STA $01
        # NO_WRAP:
        asm << 0x4C                  # JMP MAIN_LOOP
        asm << (main_loop & 0xFF) << (((main_loop >> 8) + 0x08) & 0xFF)

        # PRINT_CHAR: Print character in A to screen
        print_char = asm.length
        asm << 0xA0 << 0x00          # LDY #$00
        asm << 0x91 << cursor_lo     # STA ($00),Y
        asm << 0xE6 << cursor_lo     # INC $00
        asm << 0xD0 << 0x02          # BNE NO_CARRY
        asm << 0xE6 << cursor_hi     # INC $01
        # NO_CARRY:
        asm << 0x60                  # RTS

        # Fix up JSR addresses
        print_char_addr_full = 0x0800 + print_char
        asm[print_char_offset] = print_char_addr_full & 0xFF
        asm[print_char_offset + 1] = (print_char_addr_full >> 8) & 0xFF

        # Fix up JSRs in message printing
        idx = 0
        while idx < main_loop
          if asm[idx] == 0x20 # JSR
            asm[idx + 1] = print_char_addr_full & 0xFF
            asm[idx + 2] = (print_char_addr_full >> 8) & 0xFF
            idx += 3
          else
            idx += 1
          end
        end

        # Fix up NEW_LINE branch offset
        new_line_offset = new_line - (jmp_main - 2)
        # The BEQ after CMP #$0D needs to jump to NEW_LINE
        beq_offset_idx = main_loop + 11 # Position of BEQ operand
        asm[beq_offset_idx] = (new_line - (beq_offset_idx + 1)) & 0xFF

        asm
      end
    end
  end
end
