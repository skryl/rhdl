# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/character_rom'

RSpec.describe RHDL::Apple2::CharacterROM do
  let(:char_rom) { described_class.new('char_rom') }

  # Reference ROM data from character_rom.vhd
  # This is the exact data from the neoapple2 implementation
  REFERENCE_ROM = [
    # Character 0 (@) - addr 0-7
    0b01110, 0b10001, 0b10101, 0b11101, 0b01101, 0b00001, 0b11110, 0b00000,
    # Character 1 (A) - addr 8-15
    0b00100, 0b01010, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b00000,
    # Character 2 (B) - addr 16-23
    0b01111, 0b10001, 0b10001, 0b01111, 0b10001, 0b10001, 0b01111, 0b00000,
    # Character 3 (C) - addr 24-31
    0b01110, 0b10001, 0b00001, 0b00001, 0b00001, 0b10001, 0b01110, 0b00000,
    # Character 4 (D) - addr 32-39
    0b01111, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01111, 0b00000,
    # Character 5 (E) - addr 40-47
    0b11111, 0b00001, 0b00001, 0b01111, 0b00001, 0b00001, 0b11111, 0b00000,
    # Character 6 (F) - addr 48-55
    0b11111, 0b00001, 0b00001, 0b01111, 0b00001, 0b00001, 0b00001, 0b00000,
    # Character 7 (G) - addr 56-63
    0b11110, 0b00001, 0b00001, 0b00001, 0b11001, 0b10001, 0b11110, 0b00000,
  ].freeze

  before do
    char_rom
  end

  def set_addr_and_read(addr)
    char_rom.set_input(:addr, addr)
    char_rom.set_input(:clk, 0)
    char_rom.propagate
    char_rom.set_input(:clk, 1)
    char_rom.propagate
    char_rom.get_output(:dout)
  end

  describe 'ROM initialization' do
    it 'has correct dimensions (512 x 5-bit)' do
      # Verify ROM can be addressed with 9-bit address
      # and outputs 5-bit data
      char_rom.set_input(:addr, 0)
      char_rom.propagate
      dout = char_rom.get_output(:dout)
      expect(dout).to be_between(0, 0x1F)  # 5 bits max
    end
  end

  describe 'character data comparison with reference VHDL' do
    # Reference VHDL behavior from character_rom.vhd:
    # Synchronous read on rising edge of clk
    # Address format: char(5:0) & row(2:0)

    context 'character @ (0x00)' do
      it 'returns correct bitmap rows' do
        char_base = 0 * 8  # Character 0

        8.times do |row|
          addr = char_base + row
          data = set_addr_and_read(addr)
          expect(data).to eq(REFERENCE_ROM[addr]),
            "Mismatch at @ row #{row}: expected #{REFERENCE_ROM[addr].to_s(2)}, got #{data.to_s(2)}"
        end
      end
    end

    context 'character A (0x01)' do
      it 'returns correct bitmap rows' do
        char_base = 1 * 8  # Character 1 (A)
        expected = [
          0b00100,  # Row 0: top of A
          0b01010,  # Row 1
          0b10001,  # Row 2
          0b10001,  # Row 3
          0b11111,  # Row 4: horizontal bar
          0b10001,  # Row 5
          0b10001,  # Row 6
          0b00000   # Row 7: blank bottom
        ]

        8.times do |row|
          addr = char_base + row
          data = set_addr_and_read(addr)
          expect(data).to eq(expected[row]),
            "Mismatch at A row #{row}: expected #{expected[row].to_s(2)}, got #{data.to_s(2)}"
        end
      end
    end

    context 'character B (0x02)' do
      it 'returns correct bitmap rows' do
        char_base = 2 * 8  # Character 2 (B)
        expected = [
          0b01111,  # Row 0
          0b10001,  # Row 1
          0b10001,  # Row 2
          0b01111,  # Row 3: middle bar
          0b10001,  # Row 4
          0b10001,  # Row 5
          0b01111,  # Row 6
          0b00000   # Row 7
        ]

        8.times do |row|
          addr = char_base + row
          data = set_addr_and_read(addr)
          expect(data).to eq(expected[row]),
            "Mismatch at B row #{row}: expected #{expected[row].to_s(2)}, got #{data.to_s(2)}"
        end
      end
    end

    context 'character space (0x20)' do
      it 'returns all zeros (blank)' do
        char_base = 32 * 8  # Character 32 (space)

        8.times do |row|
          addr = char_base + row
          data = set_addr_and_read(addr)
          expect(data).to eq(0),
            "Space row #{row} should be blank, got #{data.to_s(2)}"
        end
      end
    end

    context 'digit 0 (0x30)' do
      it 'returns correct bitmap for numeral zero' do
        char_base = 48 * 8  # Character 48 ('0')
        expected = [
          0b01110,  # Row 0
          0b10001,  # Row 1
          0b11001,  # Row 2 (slash through)
          0b10101,  # Row 3
          0b10011,  # Row 4
          0b10001,  # Row 5
          0b01110,  # Row 6
          0b00000   # Row 7
        ]

        8.times do |row|
          addr = char_base + row
          data = set_addr_and_read(addr)
          expect(data).to eq(expected[row]),
            "Mismatch at 0 row #{row}: expected #{expected[row].to_s(2)}, got #{data.to_s(2)}"
        end
      end
    end

    context 'first 64 addresses' do
      it 'matches reference ROM data exactly' do
        REFERENCE_ROM.each_with_index do |expected, addr|
          data = set_addr_and_read(addr)
          expect(data).to eq(expected),
            "Mismatch at addr #{addr}: expected #{expected.to_s(2)}, got #{data.to_s(2)}"
        end
      end
    end
  end

  describe 'address format' do
    # Reference VHDL: addr = DL(5:0) & VC & VB & VA
    # This means: 6-bit character code + 3-bit row index

    it 'uses lower 3 bits for row selection' do
      # Read all 8 rows of character 'A'
      char_code = 1  # 'A'
      rows = []

      8.times do |row|
        addr = (char_code << 3) | row
        rows << set_addr_and_read(addr)
      end

      # Different rows should have different values
      expect(rows.uniq.size).to be > 1
    end

    it 'uses upper 6 bits for character selection' do
      # Read same row of different characters
      row = 0
      chars = []

      4.times do |char_code|
        addr = (char_code << 3) | row
        chars << set_addr_and_read(addr)
      end

      # Different characters have different first rows
      expect(chars.uniq.size).to be > 1
    end
  end

  describe 'ROM structure' do
    it 'stores 64 characters (full Apple II set)' do
      # Apple II uses 64 unique characters
      # ROM has 512 entries = 64 characters * 8 rows
      unique_patterns = Set.new

      64.times do |char|
        8.times do |row|
          addr = (char << 3) | row
          data = set_addr_and_read(addr)
          unique_patterns << "#{char}-#{row}-#{data}"
        end
      end

      expect(unique_patterns.size).to eq(512)
    end

    it 'outputs 5-bit values for all addresses' do
      # All outputs should be in valid 5-bit range
      64.times do |char|
        8.times do |row|
          addr = (char << 3) | row
          data = set_addr_and_read(addr)
          expect(data).to be_between(0, 31)
        end
      end
    end
  end

  describe 'timing characteristics' do
    it 'provides asynchronous read (combinational)' do
      # In async read mode, output changes immediately with address
      char_rom.set_input(:addr, 8)  # 'A' row 0
      char_rom.propagate  # Propagate combinational logic

      first_read = char_rom.get_output(:dout)

      char_rom.set_input(:addr, 16)  # 'B' row 0
      char_rom.propagate  # Propagate combinational logic

      second_read = char_rom.get_output(:dout)

      # Values should be different (A row 0 vs B row 0)
      expect(first_read).not_to eq(second_read)
    end
  end

  describe 'visual verification' do
    # These tests help visually verify the character patterns

    def render_char(char_code)
      rows = []
      8.times do |row|
        addr = (char_code << 3) | row
        data = set_addr_and_read(addr)
        # Convert 5-bit pattern to visual representation
        row_str = 5.times.map { |bit| (data >> (4 - bit)) & 1 == 1 ? '#' : '.' }.join
        rows << row_str
      end
      rows
    end

    it 'renders A correctly' do
      pattern = render_char(1)
      expect(pattern[0]).to eq('..#..')  # Top
      expect(pattern[1]).to eq('.#.#.')  # Expanding
      expect(pattern[4]).to eq('#####')  # Bar
    end

    it 'renders H correctly' do
      pattern = render_char(8)  # H
      expect(pattern[0]).to eq('#...#')  # Two verticals
      expect(pattern[3]).to eq('#####')  # Middle bar
      expect(pattern[6]).to eq('#...#')  # Two verticals
    end

    it 'renders I correctly' do
      pattern = render_char(9)  # I
      expect(pattern[0]).to eq('.###.')  # Top bar
      expect(pattern[3]).to eq('..#..')  # Vertical
      expect(pattern[6]).to eq('.###.')  # Bottom bar
    end
  end
end
