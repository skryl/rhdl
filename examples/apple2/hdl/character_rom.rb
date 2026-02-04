# frozen_string_literal: true

# Apple II Character ROM
# Based on Stephen A. Edwards' neoapple2 implementation
#
# 512 x 5-bit ROM containing character bitmaps
# Each character is 8 rows of 5 pixels
# Address format: char(5:0) & row(2:0) = 9 bits
# Output: 5 pixel bits per row

require 'rhdl/hdl'

module RHDL
  module Examples
    module Apple2
      class CharacterROM < RHDL::HDL::Component
      include RHDL::DSL::Memory

      input :clk
      input :addr, width: 9              # 512 locations
      output :dout, width: 5             # 5 bits per row

      # Character ROM data (from reference implementation)
      # Each entry is 5 bits representing one row of a character
      CHARACTER_DATA = [
        # Character 0 (@)
        0b01110, 0b10001, 0b10101, 0b11101, 0b01101, 0b00001, 0b11110, 0b00000,
        # Character 1 (A)
        0b00100, 0b01010, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b00000,
        # Character 2 (B)
        0b01111, 0b10001, 0b10001, 0b01111, 0b10001, 0b10001, 0b01111, 0b00000,
        # Character 3 (C)
        0b01110, 0b10001, 0b00001, 0b00001, 0b00001, 0b10001, 0b01110, 0b00000,
        # Character 4 (D)
        0b01111, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01111, 0b00000,
        # Character 5 (E)
        0b11111, 0b00001, 0b00001, 0b01111, 0b00001, 0b00001, 0b11111, 0b00000,
        # Character 6 (F)
        0b11111, 0b00001, 0b00001, 0b01111, 0b00001, 0b00001, 0b00001, 0b00000,
        # Character 7 (G)
        0b11110, 0b00001, 0b00001, 0b00001, 0b11001, 0b10001, 0b11110, 0b00000,
        # Character 8 (H)
        0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001, 0b00000,
        # Character 9 (I)
        0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110, 0b00000,
        # Character 10 (J)
        0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110, 0b00000,
        # Character 11 (K)
        0b10001, 0b01001, 0b00101, 0b00011, 0b00101, 0b01001, 0b10001, 0b00000,
        # Character 12 (L)
        0b00001, 0b00001, 0b00001, 0b00001, 0b00001, 0b00001, 0b11111, 0b00000,
        # Character 13 (M)
        0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001, 0b00000,
        # Character 14 (N)
        0b10001, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b10001, 0b00000,
        # Character 15 (O)
        0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110, 0b00000,
        # Character 16 (P)
        0b01111, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b00001, 0b00000,
        # Character 17 (Q)
        0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b01001, 0b10110, 0b00000,
        # Character 18 (R)
        0b01111, 0b10001, 0b10001, 0b01111, 0b00101, 0b01001, 0b10001, 0b00000,
        # Character 19 (S)
        0b01110, 0b10001, 0b00001, 0b01110, 0b10000, 0b10001, 0b01110, 0b00000,
        # Character 20 (T)
        0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000,
        # Character 21 (U)
        0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110, 0b00000,
        # Character 22 (V)
        0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100, 0b00000,
        # Character 23 (W)
        0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001, 0b00000,
        # Character 24 (X)
        0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001, 0b00000,
        # Character 25 (Y)
        0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000,
        # Character 26 (Z)
        0b11111, 0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b11111, 0b00000,
        # Character 27 ([)
        0b11111, 0b00011, 0b00011, 0b00011, 0b00011, 0b00011, 0b11111, 0b00000,
        # Character 28 (\)
        0b00000, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000, 0b00000,
        # Character 29 (])
        0b11111, 0b11000, 0b11000, 0b11000, 0b11000, 0b11000, 0b11111, 0b00000,
        # Character 30 (^)
        0b00000, 0b00000, 0b00100, 0b01010, 0b10001, 0b00000, 0b00000, 0b00000,
        # Character 31 (_)
        0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111, 0b00000,
        # Character 32 (space)
        0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000,
        # Character 33 (!)
        0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100, 0b00000,
        # Character 34 (")
        0b01010, 0b01010, 0b01010, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000,
        # Character 35 (#)
        0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010, 0b00000,
        # Character 36 ($)
        0b00100, 0b11110, 0b00101, 0b01110, 0b10100, 0b01111, 0b00100, 0b00000,
        # Character 37 (%)
        0b00011, 0b10011, 0b01000, 0b00100, 0b00010, 0b11001, 0b11000, 0b00000,
        # Character 38 (&)
        0b00010, 0b00101, 0b00101, 0b00010, 0b10101, 0b01001, 0b10110, 0b00000,
        # Character 39 (')
        0b00100, 0b00100, 0b00100, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000,
        # Character 40 (()
        0b00100, 0b00010, 0b00001, 0b00001, 0b00001, 0b00010, 0b00100, 0b00000,
        # Character 41 ())
        0b00100, 0b01000, 0b10000, 0b10000, 0b10000, 0b01000, 0b00100, 0b00000,
        # Character 42 (*)
        0b00100, 0b10101, 0b01110, 0b00100, 0b01110, 0b10101, 0b00100, 0b00000,
        # Character 43 (+)
        0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000, 0b00000,
        # Character 44 (,)
        0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100, 0b00010, 0b00000,
        # Character 45 (-)
        0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000, 0b00000,
        # Character 46 (.)
        0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00000,
        # Character 47 (/)
        0b00000, 0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b00000, 0b00000,
        # Character 48 (0)
        0b01110, 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b01110, 0b00000,
        # Character 49 (1)
        0b00100, 0b00110, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110, 0b00000,
        # Character 50 (2)
        0b01110, 0b10001, 0b10000, 0b01100, 0b00010, 0b00001, 0b11111, 0b00000,
        # Character 51 (3)
        0b11111, 0b10000, 0b01000, 0b01100, 0b10000, 0b10001, 0b01110, 0b00000,
        # Character 52 (4)
        0b01000, 0b01100, 0b01010, 0b01001, 0b11111, 0b01000, 0b01000, 0b00000,
        # Character 53 (5)
        0b11111, 0b00001, 0b01111, 0b10000, 0b10000, 0b10001, 0b01110, 0b00000,
        # Character 54 (6)
        0b11100, 0b00010, 0b00001, 0b01111, 0b10001, 0b10001, 0b01110, 0b00000,
        # Character 55 (7)
        0b11111, 0b10000, 0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00000,
        # Character 56 (8)
        0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110, 0b00000,
        # Character 57 (9)
        0b01110, 0b10001, 0b10001, 0b11110, 0b10000, 0b01000, 0b00111, 0b00000,
        # Character 58 (:)
        0b00000, 0b00000, 0b00100, 0b00000, 0b00100, 0b00000, 0b00000, 0b00000,
        # Character 59 (;)
        0b00000, 0b00000, 0b00100, 0b00000, 0b00100, 0b00100, 0b00010, 0b00000,
        # Character 60 (<)
        0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000, 0b00000,
        # Character 61 (=)
        0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000,
        # Character 62 (>)
        0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010, 0b00000,
        # Character 63 (?)
        0b01110, 0b10001, 0b01000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00000
      ].freeze

      # Define ROM array with initial data
      # Note: Using async_read for now; sync_read to be added to RHDL DSL
      memory :rom, depth: 512, width: 5, initial: CHARACTER_DATA

      # Asynchronous read (combinational)
      async_read :dout, from: :rom, addr: :addr
    end
  end
  end
end
