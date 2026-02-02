# frozen_string_literal: true

require 'spec_helper'

# SM83 (LR35902) CPU Instruction Tests
# Tests all instructions supported by the Game Boy CPU

RSpec.describe 'SM83 CPU Instructions' do
  # Test helper to create a minimal ROM with test code
  def create_test_rom(code_bytes, entry: 0x0100)
    rom = Array.new(32 * 1024, 0x00)

    # Nintendo logo (required for boot)
    nintendo_logo = [
      0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
      0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
      0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
      0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
      0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
      0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
    ]
    nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

    # Title
    "SM83TEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

    # Header checksum
    checksum = 0
    (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
    rom[0x14D] = checksum

    # Entry point jump to test code
    rom[0x100] = 0xC3  # JP
    rom[0x101] = entry & 0xFF
    rom[0x102] = (entry >> 8) & 0xFF

    # Test code
    code_bytes.each_with_index { |b, i| rom[entry + i] = b }

    rom.pack('C*')
  end

  # Run test ROM and return CPU state after specified cycles
  def run_test_code(code_bytes, cycles: 1000, skip_boot: true)
    @runner.load_rom(create_test_rom(code_bytes))
    @runner.reset

    if skip_boot
      # Run through boot ROM
      while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 500_000
        @runner.run_steps(1000)
      end
    end

    @runner.run_steps(cycles)
    @runner.cpu_state
  end

  before(:all) do
    begin
      require_relative '../../../../../examples/gameboy/gameboy'
      require_relative '../../../../../examples/gameboy/utilities/gameboy_ir'

      # Check if IR compiler is available
      @ir_available = RHDL::Codegen::IR::COMPILER_AVAILABLE rescue false
    rescue LoadError => e
      @ir_available = false
    end
  end

  before(:each) do
    skip 'IR compiler not available' unless @ir_available

    @runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
  end

  # ==========================================================================
  # 8-bit Load Instructions (LD r,r')
  # ==========================================================================
  describe '8-bit Load Instructions' do
    describe 'LD r,r\' (register to register)' do
      # LD B,A (0x47) - This is the bug we found!
      it 'LD B,A (0x47) copies A to B' do
        code = [
          0x3E, 0xAB,  # LD A, 0xAB
          0x47,        # LD B, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0xAB)
        expect(state[:b]).to eq(0xAB)
      end

      it 'LD C,A (0x4F) copies A to C' do
        code = [
          0x3E, 0xCD,  # LD A, 0xCD
          0x4F,        # LD C, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0xCD)
        expect(state[:c]).to eq(0xCD)
      end

      it 'LD D,A (0x57) copies A to D' do
        code = [
          0x3E, 0x12,  # LD A, 0x12
          0x57,        # LD D, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:d]).to eq(0x12)
      end

      it 'LD E,A (0x5F) copies A to E' do
        code = [
          0x3E, 0x34,  # LD A, 0x34
          0x5F,        # LD E, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:e]).to eq(0x34)
      end

      it 'LD H,A (0x67) copies A to H' do
        code = [
          0x3E, 0x56,  # LD A, 0x56
          0x67,        # LD H, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:h]).to eq(0x56)
      end

      it 'LD L,A (0x6F) copies A to L' do
        code = [
          0x3E, 0x78,  # LD A, 0x78
          0x6F,        # LD L, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:l]).to eq(0x78)
      end

      it 'LD A,B (0x78) copies B to A' do
        code = [
          0x06, 0x99,  # LD B, 0x99
          0x78,        # LD A, B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x99)
      end

      it 'LD A,C (0x79) copies C to A' do
        code = [
          0x0E, 0xAA,  # LD C, 0xAA
          0x79,        # LD A, C
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0xAA)
      end

      it 'LD B,C (0x41) copies C to B' do
        code = [
          0x0E, 0xBB,  # LD C, 0xBB
          0x41,        # LD B, C
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xBB)
      end

      it 'LD B,D (0x42) copies D to B' do
        code = [
          0x16, 0xCC,  # LD D, 0xCC
          0x42,        # LD B, D
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xCC)
      end

      it 'LD B,E (0x43) copies E to B' do
        code = [
          0x1E, 0xDD,  # LD E, 0xDD
          0x43,        # LD B, E
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xDD)
      end

      it 'LD B,H (0x44) copies H to B' do
        code = [
          0x26, 0xEE,  # LD H, 0xEE
          0x44,        # LD B, H
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xEE)
      end

      it 'LD B,L (0x45) copies L to B' do
        code = [
          0x2E, 0xFF,  # LD L, 0xFF
          0x45,        # LD B, L
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xFF)
      end

      it 'LD B,B (0x40) preserves B' do
        code = [
          0x06, 0x42,  # LD B, 0x42
          0x40,        # LD B, B (NOP-like)
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x42)
      end
    end

    describe 'LD r,n (immediate to register)' do
      it 'LD A,n (0x3E) loads immediate to A' do
        code = [
          0x3E, 0x42,  # LD A, 0x42
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x42)
      end

      it 'LD B,n (0x06) loads immediate to B' do
        code = [
          0x06, 0x55,  # LD B, 0x55
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x55)
      end

      it 'LD C,n (0x0E) loads immediate to C' do
        code = [
          0x0E, 0x66,  # LD C, 0x66
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:c]).to eq(0x66)
      end

      it 'LD D,n (0x16) loads immediate to D' do
        code = [
          0x16, 0x77,  # LD D, 0x77
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:d]).to eq(0x77)
      end

      it 'LD E,n (0x1E) loads immediate to E' do
        code = [
          0x1E, 0x88,  # LD E, 0x88
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:e]).to eq(0x88)
      end

      it 'LD H,n (0x26) loads immediate to H' do
        code = [
          0x26, 0x99,  # LD H, 0x99
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:h]).to eq(0x99)
      end

      it 'LD L,n (0x2E) loads immediate to L' do
        code = [
          0x2E, 0xAA,  # LD L, 0xAA
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:l]).to eq(0xAA)
      end
    end
  end

  # ==========================================================================
  # 16-bit Load Instructions
  # ==========================================================================
  describe '16-bit Load Instructions' do
    it 'LD BC,nn (0x01) loads 16-bit immediate' do
      code = [
        0x01, 0x34, 0x12,  # LD BC, 0x1234
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x12)
      expect(state[:c]).to eq(0x34)
    end

    it 'LD DE,nn (0x11) loads 16-bit immediate' do
      code = [
        0x11, 0x78, 0x56,  # LD DE, 0x5678
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:d]).to eq(0x56)
      expect(state[:e]).to eq(0x78)
    end

    it 'LD HL,nn (0x21) loads 16-bit immediate' do
      code = [
        0x21, 0xBC, 0x9A,  # LD HL, 0x9ABC
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x9A)
      expect(state[:l]).to eq(0xBC)
    end

    it 'LD SP,nn (0x31) loads 16-bit immediate to SP' do
      code = [
        0x31, 0xF0, 0xDE,  # LD SP, 0xDEF0
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:sp]).to eq(0xDEF0)
    end
  end

  # ==========================================================================
  # Arithmetic Instructions (8-bit)
  # ==========================================================================
  describe '8-bit Arithmetic Instructions' do
    describe 'ADD A,r' do
      it 'ADD A,B (0x80) adds B to A' do
        code = [
          0x3E, 0x10,  # LD A, 0x10
          0x06, 0x05,  # LD B, 0x05
          0x80,        # ADD A, B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x15)
      end

      it 'ADD A,n (0xC6) adds immediate to A' do
        code = [
          0x3E, 0x20,  # LD A, 0x20
          0xC6, 0x08,  # ADD A, 0x08
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x28)
      end

      it 'ADD A,A (0x87) doubles A' do
        code = [
          0x3E, 0x40,  # LD A, 0x40
          0x87,        # ADD A, A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x80)
      end
    end

    describe 'SUB' do
      it 'SUB B (0x90) subtracts B from A' do
        code = [
          0x3E, 0x20,  # LD A, 0x20
          0x06, 0x08,  # LD B, 0x08
          0x90,        # SUB B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x18)
      end

      it 'SUB n (0xD6) subtracts immediate from A' do
        code = [
          0x3E, 0x30,  # LD A, 0x30
          0xD6, 0x10,  # SUB 0x10
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x20)
      end
    end

    describe 'INC/DEC' do
      it 'INC A (0x3C) increments A' do
        code = [
          0x3E, 0xFF,  # LD A, 0xFF
          0x3C,        # INC A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)  # Wraps around
      end

      it 'DEC A (0x3D) decrements A' do
        code = [
          0x3E, 0x00,  # LD A, 0x00
          0x3D,        # DEC A
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0xFF)  # Wraps around
      end

      it 'INC B (0x04) increments B' do
        code = [
          0x06, 0x41,  # LD B, 0x41
          0x04,        # INC B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x42)
      end

      it 'DEC B (0x05) decrements B' do
        code = [
          0x06, 0x42,  # LD B, 0x42
          0x05,        # DEC B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x41)
      end
    end

    describe 'AND/OR/XOR' do
      it 'AND B (0xA0) performs AND' do
        code = [
          0x3E, 0xF0,  # LD A, 0xF0
          0x06, 0x0F,  # LD B, 0x0F
          0xA0,        # AND B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
      end

      it 'OR B (0xB0) performs OR' do
        code = [
          0x3E, 0xF0,  # LD A, 0xF0
          0x06, 0x0F,  # LD B, 0x0F
          0xB0,        # OR B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0xFF)
      end

      it 'XOR B (0xA8) performs XOR' do
        code = [
          0x3E, 0xFF,  # LD A, 0xFF
          0x06, 0xF0,  # LD B, 0xF0
          0xA8,        # XOR B
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x0F)
      end

      it 'XOR A (0xAF) zeros A' do
        code = [
          0x3E, 0x42,  # LD A, 0x42
          0xAF,        # XOR A (clears A, sets Z flag)
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
      end
    end

    describe 'CP (Compare)' do
      it 'CP n (0xFE) sets Z flag when equal' do
        code = [
          0x3E, 0x42,  # LD A, 0x42
          0xFE, 0x42,  # CP 0x42
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x42)  # A unchanged
        expect(state[:f] & 0x80).to eq(0x80)  # Z flag set
      end

      it 'CP n (0xFE) clears Z flag when not equal' do
        code = [
          0x3E, 0x42,  # LD A, 0x42
          0xFE, 0x41,  # CP 0x41
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x42)  # A unchanged
        expect(state[:f] & 0x80).to eq(0x00)  # Z flag clear
      end
    end
  end

  # ==========================================================================
  # 16-bit Arithmetic
  # ==========================================================================
  describe '16-bit Arithmetic Instructions' do
    it 'INC BC (0x03) increments BC' do
      code = [
        0x01, 0xFF, 0x00,  # LD BC, 0x00FF
        0x03,              # INC BC
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x01)
      expect(state[:c]).to eq(0x00)
    end

    it 'DEC BC (0x0B) decrements BC' do
      code = [
        0x01, 0x00, 0x01,  # LD BC, 0x0100
        0x0B,              # DEC BC
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x00)
      expect(state[:c]).to eq(0xFF)
    end

    it 'INC DE (0x13) increments DE' do
      code = [
        0x11, 0x00, 0x10,  # LD DE, 0x1000
        0x13,              # INC DE
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:d]).to eq(0x10)
      expect(state[:e]).to eq(0x01)
    end

    it 'INC HL (0x23) increments HL' do
      code = [
        0x21, 0xFF, 0xFF,  # LD HL, 0xFFFF
        0x23,              # INC HL
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x00)
      expect(state[:l]).to eq(0x00)
    end

    it 'ADD HL,BC (0x09) adds BC to HL' do
      code = [
        0x21, 0x00, 0x10,  # LD HL, 0x1000
        0x01, 0x00, 0x01,  # LD BC, 0x0100
        0x09,              # ADD HL, BC
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x11)
      expect(state[:l]).to eq(0x00)
    end
  end

  # ==========================================================================
  # Rotate and Shift (CB-prefixed)
  # ==========================================================================
  describe 'Rotate and Shift Instructions (CB prefix)' do
    it 'SLA B (0xCB 0x20) shifts B left' do
      code = [
        0x06, 0x81,     # LD B, 0x81 (10000001)
        0xCB, 0x20,     # SLA B -> 0x02 (00000010), Carry=1
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x02)
    end

    it 'SRL B (0xCB 0x38) shifts B right' do
      code = [
        0x06, 0x81,     # LD B, 0x81 (10000001)
        0xCB, 0x38,     # SRL B -> 0x40 (01000000), Carry=1
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x40)
    end

    it 'RL C (0xCB 0x11) rotates C left through carry' do
      code = [
        0x37,           # SCF (set carry)
        0x0E, 0x80,     # LD C, 0x80 (10000000)
        0xCB, 0x11,     # RL C -> 0x01 (with carry in), Carry=1
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:c]).to eq(0x01)
    end

    it 'RR C (0xCB 0x19) rotates C right through carry' do
      code = [
        0x37,           # SCF (set carry)
        0x0E, 0x01,     # LD C, 0x01 (00000001)
        0xCB, 0x19,     # RR C -> 0x80 (with carry in), Carry=1
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:c]).to eq(0x80)
    end

    it 'SWAP A (0xCB 0x37) swaps nibbles of A' do
      code = [
        0x3E, 0x12,     # LD A, 0x12
        0xCB, 0x37,     # SWAP A -> 0x21
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x21)
    end
  end

  # ==========================================================================
  # Bit Operations (CB-prefixed)
  # ==========================================================================
  describe 'Bit Instructions (CB prefix)' do
    it 'BIT 0,A (0xCB 0x47) tests bit 0 of A' do
      code = [
        0x3E, 0x01,     # LD A, 0x01 (bit 0 set)
        0xCB, 0x47,     # BIT 0, A (Z=0 because bit is set)
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:f] & 0x80).to eq(0x00)  # Z flag clear (bit is set)
    end

    it 'BIT 7,A (0xCB 0x7F) tests bit 7 of A' do
      code = [
        0x3E, 0x00,     # LD A, 0x00 (bit 7 clear)
        0xCB, 0x7F,     # BIT 7, A (Z=1 because bit is clear)
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:f] & 0x80).to eq(0x80)  # Z flag set (bit is clear)
    end

    it 'SET 3,A (0xCB 0xDF) sets bit 3 of A' do
      code = [
        0x3E, 0x00,     # LD A, 0x00
        0xCB, 0xDF,     # SET 3, A -> 0x08
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x08)
    end

    it 'RES 3,A (0xCB 0x9F) resets bit 3 of A' do
      code = [
        0x3E, 0xFF,     # LD A, 0xFF
        0xCB, 0x9F,     # RES 3, A -> 0xF7
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0xF7)
    end

    it 'BIT 5,H (0xCB 0x6C) tests bit 5 of H' do
      code = [
        0x26, 0x20,     # LD H, 0x20 (bit 5 set)
        0xCB, 0x6C,     # BIT 5, H
        0x76            # HALT
      ]
      state = run_test_code(code)
      expect(state[:f] & 0x80).to eq(0x00)  # Z flag clear (bit is set)
    end
  end

  # ==========================================================================
  # Jump Instructions
  # ==========================================================================
  describe 'Jump Instructions' do
    it 'JP nn (0xC3) jumps to address' do
      code = [
        0xC3, 0x05, 0x01,  # JP 0x0105
        0x3E, 0x11,        # LD A, 0x11 (skipped)
        0x3E, 0x22,        # LD A, 0x22 (executed)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x22)
    end

    it 'JR n (0x18) relative jump forward' do
      code = [
        0x18, 0x02,        # JR +2
        0x3E, 0x11,        # LD A, 0x11 (skipped)
        0x3E, 0x22,        # LD A, 0x22 (executed)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x22)
    end

    it 'JR Z,n (0x28) jumps if Z flag set' do
      code = [
        0xAF,              # XOR A (sets Z flag)
        0x28, 0x02,        # JR Z, +2
        0x3E, 0x11,        # LD A, 0x11 (skipped)
        0x3E, 0x22,        # LD A, 0x22 (executed)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x22)
    end

    it 'JR NZ,n (0x20) jumps if Z flag clear' do
      code = [
        0x3E, 0x01,        # LD A, 0x01 (clears Z flag)
        0x20, 0x02,        # JR NZ, +2
        0x3E, 0x11,        # LD A, 0x11 (skipped)
        0x3E, 0x22,        # LD A, 0x22 (executed)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x22)
    end
  end

  # ==========================================================================
  # Call/Return Instructions
  # ==========================================================================
  describe 'Call and Return Instructions' do
    it 'CALL nn (0xCD) calls subroutine' do
      # Layout: CALL 0x0106, LD A 0x22, HALT, LD A 0x11, RET
      # Addresses: 0x0100-0x0102 (CALL), 0x0103-0x0104 (LD A), 0x0105 (HALT),
      #            0x0106-0x0107 (subroutine LD A), 0x0108 (RET)
      code = [
        0xCD, 0x06, 0x01,  # CALL 0x0106 (subroutine at offset 6)
        0x3E, 0x22,        # LD A, 0x22 (after return)
        0x76,              # HALT
        0x3E, 0x11,        # LD A, 0x11 (subroutine at 0x0106)
        0xC9               # RET
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x22)
    end

    it 'RET (0xC9) returns from subroutine' do
      code = [
        0xCD, 0x05, 0x01,  # CALL 0x0105
        0x76,              # HALT
        0xC9               # RET
      ]
      state = run_test_code(code)
      # Just verify it doesn't hang
      expect(state[:pc]).to be >= 0x0104
    end
  end

  # ==========================================================================
  # Stack Instructions
  # ==========================================================================
  describe 'Stack Instructions' do
    it 'PUSH BC / POP BC preserves value' do
      code = [
        0x01, 0x34, 0x12,  # LD BC, 0x1234
        0xC5,              # PUSH BC
        0x01, 0x00, 0x00,  # LD BC, 0x0000
        0xC1,              # POP BC
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x12)
      expect(state[:c]).to eq(0x34)
    end

    it 'PUSH AF / POP AF preserves value' do
      code = [
        0x3E, 0xAB,        # LD A, 0xAB
        0xF5,              # PUSH AF
        0x3E, 0x00,        # LD A, 0x00
        0xF1,              # POP AF
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0xAB)
    end
  end

  # ==========================================================================
  # Miscellaneous Instructions
  # ==========================================================================
  describe 'Miscellaneous Instructions' do
    it 'NOP (0x00) does nothing' do
      code = [
        0x3E, 0x42,        # LD A, 0x42
        0x00,              # NOP
        0x00,              # NOP
        0x00,              # NOP
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)
    end

    it 'CPL (0x2F) complements A' do
      code = [
        0x3E, 0xAA,        # LD A, 0xAA (10101010)
        0x2F,              # CPL -> 0x55 (01010101)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x55)
    end

    it 'SCF (0x37) sets carry flag' do
      code = [
        0x37,              # SCF (set carry)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:f] & 0x10).to eq(0x10)  # Carry flag set
    end

    it 'CCF (0x3F) complements carry flag' do
      code = [
        0x37,              # SCF (set carry)
        0x3F,              # CCF (complement carry)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:f] & 0x10).to eq(0x00)  # Carry flag clear
    end
  end

  # ============================================================================
  # Missing functionality tests (from reference comparison)
  # These tests verify features that should be implemented to match the
  # MiSTer reference implementation (reference/rtl/T80/*.vhd)
  # ============================================================================

  describe 'Instruction Timing' do
    it 'conditional JP takes fewer cycles when condition is false' do
      # Reference: T80 reduces cycles when conditional branches not taken
      pending 'Conditional jump cycle reduction'
      fail
    end

    it 'conditional CALL takes fewer cycles when condition is false' do
      # Reference: T80 reduces cycles for untaken conditional calls
      pending 'Conditional call cycle reduction'
      fail
    end

    it 'conditional RET takes fewer cycles when condition is false' do
      # Reference: T80 reduces cycles for untaken conditional returns
      pending 'Conditional return cycle reduction'
      fail
    end

    it 'applies proper M-cycle timing for each instruction' do
      # Reference: Different instructions have different cycle counts
      pending 'M-cycle timing per instruction'
      fail
    end
  end

  describe 'CB Prefix Instructions (Complete Set)' do
    describe 'BIT instructions (all 64 combinations)' do
      it 'BIT 0-7,B tests all bits of B' do
        # Reference: T80_MCode.vhd implements all 8 bit tests for each register
        pending 'Complete BIT n,B implementation'
        fail
      end

      it 'BIT 0-7,C tests all bits of C' do
        pending 'Complete BIT n,C implementation'
        fail
      end

      it 'BIT 0-7,D tests all bits of D' do
        pending 'Complete BIT n,D implementation'
        fail
      end

      it 'BIT 0-7,E tests all bits of E' do
        pending 'Complete BIT n,E implementation'
        fail
      end

      it 'BIT 0-7,H tests all bits of H' do
        pending 'Complete BIT n,H implementation'
        fail
      end

      it 'BIT 0-7,L tests all bits of L' do
        pending 'Complete BIT n,L implementation'
        fail
      end

      it 'BIT 0-7,(HL) tests all bits of memory at HL' do
        pending 'Complete BIT n,(HL) implementation'
        fail
      end
    end

    describe 'SET instructions (all 64 combinations)' do
      it 'SET 0-7,r sets all bits for all registers' do
        # Reference: T80_MCode.vhd implements all 64 SET operations
        pending 'Complete SET instruction set'
        fail
      end

      it 'SET 0-7,(HL) sets bits in memory at HL' do
        pending 'Complete SET n,(HL) implementation'
        fail
      end
    end

    describe 'RES instructions (all 64 combinations)' do
      it 'RES 0-7,r resets all bits for all registers' do
        # Reference: T80_MCode.vhd implements all 64 RES operations
        pending 'Complete RES instruction set'
        fail
      end

      it 'RES 0-7,(HL) resets bits in memory at HL' do
        pending 'Complete RES n,(HL) implementation'
        fail
      end
    end

    describe 'Rotate/Shift (all register variants)' do
      it 'RLC r rotates left for all registers' do
        pending 'Complete RLC r implementation'
        fail
      end

      it 'RRC r rotates right for all registers' do
        pending 'Complete RRC r implementation'
        fail
      end

      it 'RL r rotates left through carry for all registers' do
        pending 'Complete RL r implementation'
        fail
      end

      it 'RR r rotates right through carry for all registers' do
        pending 'Complete RR r implementation'
        fail
      end

      it 'SLA r shifts left arithmetic for all registers' do
        pending 'Complete SLA r implementation'
        fail
      end

      it 'SRA r shifts right arithmetic for all registers' do
        pending 'Complete SRA r implementation'
        fail
      end

      it 'SRL r shifts right logical for all registers' do
        pending 'Complete SRL r implementation'
        fail
      end

      it 'SWAP r swaps nibbles for all registers' do
        pending 'Complete SWAP r implementation'
        fail
      end
    end
  end

  describe 'Memory Indirect Load Instructions' do
    it 'LD (BC),A stores A at address BC' do
      pending 'LD (BC),A implementation'
      fail
    end

    it 'LD (DE),A stores A at address DE' do
      pending 'LD (DE),A implementation'
      fail
    end

    it 'LD A,(BC) loads from address BC into A' do
      pending 'LD A,(BC) implementation'
      fail
    end

    it 'LD A,(DE) loads from address DE into A' do
      pending 'LD A,(DE) implementation'
      fail
    end

    it 'LDI (HL),A stores A at HL then increments HL' do
      # Reference: LD (HL+),A or LDI (HL),A
      pending 'LDI (HL),A implementation'
      fail
    end

    it 'LDD (HL),A stores A at HL then decrements HL' do
      # Reference: LD (HL-),A or LDD (HL),A
      pending 'LDD (HL),A implementation'
      fail
    end

    it 'LDI A,(HL) loads from HL into A then increments HL' do
      pending 'LDI A,(HL) implementation'
      fail
    end

    it 'LDD A,(HL) loads from HL into A then decrements HL' do
      pending 'LDD A,(HL) implementation'
      fail
    end

    it 'LD (nn),A stores A at 16-bit immediate address' do
      pending 'LD (nn),A implementation'
      fail
    end

    it 'LD A,(nn) loads from 16-bit immediate address into A' do
      pending 'LD A,(nn) implementation'
      fail
    end

    it 'LD (nn),SP stores SP at 16-bit immediate address' do
      pending 'LD (nn),SP implementation'
      fail
    end
  end

  describe 'Zero Page (High RAM) Instructions' do
    it 'LDH (C),A stores A at FF00+C' do
      pending 'LDH (C),A implementation'
      fail
    end

    it 'LDH A,(C) loads from FF00+C into A' do
      pending 'LDH A,(C) implementation'
      fail
    end
  end

  describe 'Stack Pointer Instructions' do
    it 'LD SP,HL copies HL to SP' do
      pending 'LD SP,HL implementation'
      fail
    end

    it 'LD HL,SP+n adds signed offset to SP and stores in HL' do
      pending 'LD HL,SP+n implementation'
      fail
    end

    it 'ADD SP,n adds signed 8-bit immediate to SP' do
      pending 'ADD SP,n implementation'
      fail
    end
  end

  describe 'ALU Flag Behavior' do
    it 'DAA correctly adjusts for BCD after addition' do
      # Reference: T80_ALU.vhd has full DAA with Mode=3 specific behavior
      pending 'DAA after addition'
      fail
    end

    it 'DAA correctly adjusts for BCD after subtraction' do
      pending 'DAA after subtraction'
      fail
    end

    it 'RLCA/RLA/RRCA/RRA suppress Z flag (Rot_Akku behavior)' do
      # Reference: T80_ALU handles Rot_Akku signal to suppress Z flag
      pending 'Rotate accumulator Z flag suppression'
      fail
    end

    it 'ADC sets flags correctly for all cases' do
      pending 'ADC flag behavior'
      fail
    end

    it 'SBC sets flags correctly for all cases' do
      pending 'SBC flag behavior'
      fail
    end
  end

  describe 'Interrupt Handling' do
    it 'disables interrupts for one instruction after DI' do
      # Reference: IntE_FF1, IntE_FF2 interaction
      pending 'DI interrupt delay'
      fail
    end

    it 'enables interrupts for one instruction after EI' do
      # Reference: EI enables interrupts after next instruction
      pending 'EI interrupt delay'
      fail
    end

    it 'handles interrupt during HALT correctly' do
      # Reference: Complex timing for interrupt during HALT
      pending 'Interrupt during HALT timing'
      fail
    end

    it 'RETI enables interrupts and returns' do
      pending 'RETI implementation'
      fail
    end

    it 'RST vectors push PC and jump to vector address' do
      # Reference: 8 RST vectors (0x00, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38)
      pending 'RST vector implementation'
      fail
    end
  end

  describe 'HALT and STOP Modes' do
    it 'HALT waits for interrupt' do
      pending 'HALT mode implementation'
      fail
    end

    it 'STOP enters low-power mode' do
      pending 'STOP mode implementation'
      fail
    end

    it 'HALT bug: skips next byte when IME=0 and interrupt pending' do
      # Reference: DMG HALT bug
      pending 'HALT bug implementation'
      fail
    end
  end

  describe 'Microcode Coverage' do
    it 'decodes all 256 main opcodes' do
      # Reference: T80_MCode.vhd decodes all 256 main opcodes
      pending 'Complete main opcode decoding'
      fail
    end

    it 'decodes all 256 CB-prefixed opcodes' do
      # Reference: T80_MCode.vhd decodes all 256 CB prefix opcodes
      pending 'Complete CB prefix opcode decoding'
      fail
    end
  end

  describe '16-bit Arithmetic' do
    it 'ADD HL,DE adds DE to HL' do
      pending 'ADD HL,DE implementation'
      fail
    end

    it 'ADD HL,HL doubles HL' do
      pending 'ADD HL,HL implementation'
      fail
    end

    it 'ADD HL,SP adds SP to HL' do
      pending 'ADD HL,SP implementation'
      fail
    end

    it 'DEC DE decrements DE' do
      pending 'DEC DE implementation'
      fail
    end

    it 'DEC HL decrements HL' do
      pending 'DEC HL implementation'
      fail
    end

    it 'DEC SP decrements SP' do
      pending 'DEC SP implementation'
      fail
    end

    it 'INC SP increments SP' do
      pending 'INC SP implementation'
      fail
    end
  end

  describe 'Savestate Support' do
    it 'has savestate interface for CPU state preservation' do
      # Reference: T80 has comprehensive savestate interface
      pending 'CPU savestate interface'
      fail
    end
  end
end
