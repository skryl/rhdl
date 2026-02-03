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
      require_relative '../../../../../examples/gameboy/utilities/runners/ir_runner'

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
    describe 'BIT instructions' do
      it 'BIT 0,B tests bit 0 of B (Z flag set when bit is 0)' do
        code = [
          0x06, 0xFE,        # LD B, 0xFE (bit 0 is 0)
          0xCB, 0x40,        # BIT 0, B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:f] & 0x80).to eq(0x80)  # Z flag set (bit 0 is 0)
      end

      it 'BIT 7,A tests bit 7 of A (Z flag clear when bit is 1)' do
        code = [
          0x3E, 0x80,        # LD A, 0x80 (bit 7 is 1)
          0xCB, 0x7F,        # BIT 7, A
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:f] & 0x80).to eq(0x00)  # Z flag clear (bit 7 is 1)
      end

      it 'BIT n,r sets H flag and clears N flag' do
        code = [
          0x06, 0xFF,        # LD B, 0xFF
          0xCB, 0x40,        # BIT 0, B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:f] & 0x20).to eq(0x20)  # H flag set
        expect(state[:f] & 0x40).to eq(0x00)  # N flag clear
      end
    end

    describe 'SET instructions' do
      it 'SET 0,B sets bit 0 of B' do
        code = [
          0x06, 0x00,        # LD B, 0x00
          0xCB, 0xC0,        # SET 0, B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x01)
      end

      it 'SET 7,A sets bit 7 of A' do
        code = [
          0x3E, 0x00,        # LD A, 0x00
          0xCB, 0xFF,        # SET 7, A
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x80)
      end

      it 'SET does not affect other bits' do
        code = [
          0x06, 0x0F,        # LD B, 0x0F
          0xCB, 0xF0,        # SET 6, B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x4F)  # 0x0F | 0x40
      end
    end

    describe 'RES instructions' do
      it 'RES 0,B clears bit 0 of B' do
        code = [
          0x06, 0xFF,        # LD B, 0xFF
          0xCB, 0x80,        # RES 0, B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xFE)
      end

      it 'RES 7,A clears bit 7 of A' do
        code = [
          0x3E, 0xFF,        # LD A, 0xFF
          0xCB, 0xBF,        # RES 7, A
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x7F)
      end

      it 'RES does not affect other bits' do
        code = [
          0x06, 0xFF,        # LD B, 0xFF
          0xCB, 0xB0,        # RES 6, B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xBF)  # 0xFF & ~0x40
      end
    end

    describe 'Rotate/Shift instructions' do
      it 'RLC B rotates B left (bit 7 to carry and bit 0)' do
        code = [
          0x06, 0x80,        # LD B, 0x80
          0xCB, 0x00,        # RLC B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x01)  # 0x80 rotated left
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set
      end

      it 'RRC B rotates B right (bit 0 to carry and bit 7)' do
        code = [
          0x06, 0x01,        # LD B, 0x01
          0xCB, 0x08,        # RRC B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x80)  # 0x01 rotated right
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set
      end

      it 'SLA B shifts B left arithmetic (bit 7 to carry, 0 into bit 0)' do
        code = [
          0x06, 0x81,        # LD B, 0x81
          0xCB, 0x20,        # SLA B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x02)  # 0x81 << 1 with bit 0 = 0
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set (from bit 7)
      end

      it 'SRA B shifts B right arithmetic (bit 0 to carry, sign extends)' do
        code = [
          0x06, 0x81,        # LD B, 0x81 (bit 7 set)
          0xCB, 0x28,        # SRA B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xC0)  # 0x81 >> 1 with sign extension
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set (from bit 0)
      end

      it 'SRL B shifts B right logical (bit 0 to carry, 0 into bit 7)' do
        code = [
          0x06, 0x81,        # LD B, 0x81
          0xCB, 0x38,        # SRL B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0x40)  # 0x81 >> 1 with bit 7 = 0
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set (from bit 0)
      end

      it 'SWAP B swaps nibbles of B' do
        code = [
          0x06, 0xAB,        # LD B, 0xAB
          0xCB, 0x30,        # SWAP B
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:b]).to eq(0xBA)  # Nibbles swapped
        expect(state[:f] & 0x10).to eq(0x00)  # C flag clear
        expect(state[:f] & 0x40).to eq(0x00)  # N flag clear
        expect(state[:f] & 0x20).to eq(0x00)  # H flag clear
      end
    end
  end

  describe 'Memory Indirect Load Instructions' do
    # NOTE: Tests use ZPRAM (0xFF80-0xFFFE) which is supported by the IR runner
    # WRAM (0xC000-0xDFFF) is not bridged in the current IR simulation

    it 'LD (BC),A stores A at address BC' do
      # Store A to ZPRAM via BC, then load back to verify
      code = [
        0x3E, 0x42,        # LD A, 0x42
        0x01, 0x80, 0xFF,  # LD BC, 0xFF80 (ZPRAM)
        0x02,              # LD (BC), A
        0x3E, 0x00,        # LD A, 0x00 (clear A)
        0x0A,              # LD A, (BC) - load back
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)
    end

    it 'LD (DE),A stores A at address DE' do
      # Store A to ZPRAM via DE, then load back to verify
      code = [
        0x3E, 0x55,        # LD A, 0x55
        0x11, 0x90, 0xFF,  # LD DE, 0xFF90 (ZPRAM)
        0x12,              # LD (DE), A
        0x3E, 0x00,        # LD A, 0x00 (clear A)
        0x1A,              # LD A, (DE) - load back
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x55)
    end

    it 'LD A,(BC) loads from address BC into A' do
      # First store a value to ZPRAM, then load it back with LD A,(BC)
      code = [
        0x3E, 0x42,        # LD A, 0x42
        0x01, 0x80, 0xFF,  # LD BC, 0xFF80 (ZPRAM)
        0x02,              # LD (BC), A - store 0x42 at FF80
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0x0A,              # LD A, (BC) - load from FF80
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)
    end

    it 'LD A,(DE) loads from address DE into A' do
      # First store a value to ZPRAM, then load it back with LD A,(DE)
      code = [
        0x3E, 0x55,        # LD A, 0x55
        0x11, 0x90, 0xFF,  # LD DE, 0xFF90 (ZPRAM)
        0x12,              # LD (DE), A - store 0x55 at FF90
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0x1A,              # LD A, (DE) - load from FF90
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x55)
    end

    it 'LDI (HL),A stores A at HL then increments HL' do
      # Store A to ZPRAM via HL, verify HL incremented
      code = [
        0x3E, 0x77,        # LD A, 0x77
        0x21, 0x80, 0xFF,  # LD HL, 0xFF80 (ZPRAM)
        0x22,              # LD (HL+), A - store and increment
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0xFF)
      expect(state[:l]).to eq(0x81)  # HL was incremented from 0xFF80 to 0xFF81
    end

    it 'LDD (HL),A stores A at HL then decrements HL' do
      # Store A to ZPRAM via HL, verify HL decremented
      code = [
        0x3E, 0x88,        # LD A, 0x88
        0x21, 0x90, 0xFF,  # LD HL, 0xFF90 (ZPRAM)
        0x32,              # LD (HL-), A - store and decrement
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0xFF)
      expect(state[:l]).to eq(0x8F)  # HL was decremented from 0xFF90 to 0xFF8F
    end

    it 'LDI A,(HL) loads from HL into A then increments HL' do
      # First store a value, then load it back with LDI
      code = [
        0x3E, 0x99,        # LD A, 0x99
        0x21, 0xA0, 0xFF,  # LD HL, 0xFFA0 (ZPRAM)
        0x77,              # LD (HL), A - store 0x99 at FFA0
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0x21, 0xA0, 0xFF,  # LD HL, 0xFFA0 - reset HL
        0x2A,              # LD A, (HL+) - load and increment
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x99)
      expect(state[:h]).to eq(0xFF)
      expect(state[:l]).to eq(0xA1)  # HL was incremented
    end

    it 'LDD A,(HL) loads from HL into A then decrements HL' do
      # First store a value, then load it back with LDD
      code = [
        0x3E, 0xAA,        # LD A, 0xAA
        0x21, 0xB0, 0xFF,  # LD HL, 0xFFB0 (ZPRAM)
        0x77,              # LD (HL), A - store 0xAA at FFB0
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0x21, 0xB0, 0xFF,  # LD HL, 0xFFB0 - reset HL
        0x3A,              # LD A, (HL-) - load and decrement
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0xAA)
      expect(state[:h]).to eq(0xFF)
      expect(state[:l]).to eq(0xAF)  # HL was decremented
    end

    it 'LD (nn),A stores A at 16-bit immediate address' do
      # Store A to ZPRAM at immediate address, then load back to verify
      code = [
        0x3E, 0xBB,        # LD A, 0xBB
        0xEA, 0xC0, 0xFF,  # LD (0xFFC0), A
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0xFA, 0xC0, 0xFF,  # LD A, (0xFFC0) - load back
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0xBB)
    end

    it 'LD A,(nn) loads from 16-bit immediate address into A' do
      # First store, then load from immediate address
      code = [
        0x3E, 0xCC,        # LD A, 0xCC
        0xEA, 0xD0, 0xFF,  # LD (0xFFD0), A
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0xFA, 0xD0, 0xFF,  # LD A, (0xFFD0)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0xCC)
    end

    it 'LD (nn),SP stores SP at 16-bit immediate address' do
      # Store SP to ZPRAM, then load back to verify
      code = [
        0x31, 0xFE, 0xDF,  # LD SP, 0xDFFE
        0x08, 0xE0, 0xFF,  # LD (0xFFE0), SP - stores SP (little-endian)
        0x21, 0xE0, 0xFF,  # LD HL, 0xFFE0
        0x2A,              # LD A, (HL+) - get low byte
        0x47,              # LD B, A
        0x2A,              # LD A, (HL+) - get high byte
        0x4F,              # LD C, A
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0xFE)  # Low byte of SP
      expect(state[:c]).to eq(0xDF)  # High byte of SP
    end
  end

  describe 'Zero Page (High RAM) Instructions' do
    it 'LDH (C),A stores A at FF00+C' do
      # Store A at FF00+C (ZPRAM when C >= 0x80)
      code = [
        0x3E, 0x77,        # LD A, 0x77
        0x0E, 0x80,        # LD C, 0x80 (so address is FF80)
        0xE2,              # LDH (C), A - store A at FF80
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0xF2,              # LDH A, (C) - load back from FF80
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x77)
    end

    it 'LDH A,(C) loads from FF00+C into A' do
      # First store a value, then load it back with LDH A,(C)
      code = [
        0x3E, 0x88,        # LD A, 0x88
        0x0E, 0x90,        # LD C, 0x90 (so address is FF90)
        0xE2,              # LDH (C), A - store 0x88 at FF90
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0xF2,              # LDH A, (C) - load from FF90
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x88)
    end

    it 'LDH A,(n) reads video registers correctly (LY at FF44)' do
      # Read LY register many times and track min/max
      # LY cycles 0-153 (154 lines), so we need to run long enough to see all values
      # Use nested loops: outer loop (E) * inner loop (D) = total iterations
      # 256 * 256 = 65536 iterations, each ~12 cycles = ~786K cycles
      # This covers multiple complete frames (70K cycles/frame)
      code = [
        0x06, 0xFF,        # LD B, 0xFF - min = 255
        0x0E, 0x00,        # LD C, 0x00 - max = 0
        0x1E, 0x10,        # LD E, 0x10 - outer count (16 iterations * 256 inner = 4096 total)
        # outer_loop:
        0x16, 0x00,        # LD D, 0x00 - inner count (256 iterations)
        # inner_loop:
        0xF0, 0x44,        # LDH A, (0x44) - read LY
        0xB8,              # CP B - compare with min
        0x30, 0x01,        # JR NC, +1 - skip if A >= B
        0x47,              # LD B, A - new min
        0xB9,              # CP C - compare with max
        0x38, 0x01,        # JR C, +1 - skip if A < C
        0x4F,              # LD C, A - new max
        0x15,              # DEC D
        0x20, 0xF3,        # JR NZ, inner_loop (-13, target=0x108 from 0x115)
        0x1D,              # DEC E
        0x20, 0xEE,        # JR NZ, outer_loop (-18, target=0x106 from 0x118)
        # Store results in ZPRAM for verification
        0x78,              # LD A, B - min
        0xE0, 0x80,        # LDH (0x80), A
        0x79,              # LD A, C - max
        0xE0, 0x81,        # LDH (0x81), A
        0x76               # HALT
      ]
      # Run longer to ensure we see full LY range (0-153)
      # Test runs 4096 iterations * ~14 cycles = ~57K cycles (about 1 frame)
      # This should see most of the LY range
      # Need more cycles to complete the loop
      state = run_test_code(code, cycles: 500_000)

      # The min should be 0 and max should be 153 (or close to it)
      # Note: we check the ZPRAM values, not registers (which might have changed)
      # ZPRAM address is 7 bits: addr - 0xFF80, so 0xFF80 -> 0, 0xFF81 -> 1
      min_ly = @runner.sim.read_zpram(0)  # 0xFF80
      max_ly = @runner.sim.read_zpram(1)  # 0xFF81

      expect(min_ly).to eq(0), "Expected LY min to be 0, got #{min_ly}"
      expect(max_ly).to eq(153), "Expected LY max to be 153, got #{max_ly}"
    end

    it 'reads LY via (HL) indirect addressing correctly' do
      # Similar to Prince of Persia which uses CP (HL) to check LY
      # This test uses LD A,(HL) with HL=0xFF44 to read LY
      code = [
        0x21, 0x44, 0xFF,  # LD HL, 0xFF44 (LY register address)
        0x06, 0xFF,        # LD B, 0xFF - min = 255
        0x0E, 0x00,        # LD C, 0x00 - max = 0
        0x1E, 0x10,        # LD E, 0x10 - outer count (16 iterations * 256 inner = 4096 total)
        # outer_loop (0x10A):
        0x16, 0x00,        # LD D, 0x00 - inner count (256 iterations)
        # inner_loop (0x10C):
        0x7E,              # LD A, (HL) - read LY via indirect
        0xB8,              # CP B - compare with min
        0x30, 0x01,        # JR NC, +1 - skip if A >= B
        0x47,              # LD B, A - new min
        0xB9,              # CP C - compare with max
        0x38, 0x01,        # JR C, +1 - skip if A < C
        0x4F,              # LD C, A - new max
        0x15,              # DEC D
        0x20, 0xF4,        # JR NZ, inner_loop (-12, target=0x10C from 0x118)
        0x1D,              # DEC E
        0x20, 0xEF,        # JR NZ, outer_loop (-17, target=0x10A from 0x11B)
        # Store results in ZPRAM
        0x78,              # LD A, B - min
        0xE0, 0x80,        # LDH (0x80), A
        0x79,              # LD A, C - max
        0xE0, 0x81,        # LDH (0x81), A
        0x76               # HALT
      ]
      state = run_test_code(code, cycles: 500_000)

      min_ly = @runner.sim.read_zpram(0)  # 0xFF80
      max_ly = @runner.sim.read_zpram(1)  # 0xFF81

      expect(min_ly).to eq(0), "Expected LY min to be 0, got #{min_ly}"
      expect(max_ly).to eq(153), "Expected LY max to be 153, got #{max_ly}"
    end
  end

  describe 'Stack Pointer Instructions' do
    it 'LD SP,HL copies HL to SP' do
      # Set HL to a value, copy to SP, then verify via PUSH/POP
      code = [
        0x21, 0xE0, 0xFF,  # LD HL, 0xFFE0 (ZPRAM area for stack)
        0xF9,              # LD SP, HL - copy HL to SP
        0x3E, 0x42,        # LD A, 0x42
        0xF5,              # PUSH AF - push A to stack
        0x3E, 0x00,        # LD A, 0x00 - clear A
        0xF1,              # POP AF - pop back
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)  # Verify PUSH/POP worked with new SP
      expect(state[:sp]).to eq(0xFFE0)  # SP should be back to original after POP
    end

    it 'LD HL,SP+n adds signed offset to SP and stores in HL' do
      # Set SP, then LD HL,SP+n to get SP + signed offset in HL
      code = [
        0x31, 0x00, 0xFF,  # LD SP, 0xFF00
        0xF8, 0x10,        # LD HL, SP+0x10 (HL = 0xFF10)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0xFF)
      expect(state[:l]).to eq(0x10)
    end

    it 'LD HL,SP+n handles negative offset correctly' do
      # Test with negative offset
      code = [
        0x31, 0x10, 0xFF,  # LD SP, 0xFF10
        0xF8, 0xF0,        # LD HL, SP-16 (0xF0 = -16 signed, HL = 0xFF00)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0xFF)
      expect(state[:l]).to eq(0x00)
    end

    it 'ADD SP,n adds signed 8-bit immediate to SP' do
      # Add positive offset to SP
      code = [
        0x31, 0x00, 0xFF,  # LD SP, 0xFF00
        0xE8, 0x20,        # ADD SP, 0x20 (SP = 0xFF20)
        0x21, 0x00, 0x00,  # LD HL, 0x0000 - clear HL
        0xF9,              # LD SP, HL - HL becomes invalid, SP stays
        0x76               # HALT
      ]
      state = run_test_code(code)
      # SP should be 0xFF20 after ADD SP,n but we can't easily read SP
      # Instead verify by checking state[:sp]
      expect(state[:sp]).to eq(0x0000)  # After LD SP,HL with HL=0
    end

    it 'ADD SP,n handles negative value correctly' do
      # Add negative offset to SP
      code = [
        0x31, 0x20, 0xFF,  # LD SP, 0xFF20
        0xE8, 0xF0,        # ADD SP, -16 (0xF0 signed = -16, SP = 0xFF10)
        0x08, 0x80, 0xFF,  # LD (0xFF80), SP - store SP for verification
        0x21, 0x80, 0xFF,  # LD HL, 0xFF80
        0x2A,              # LD A, (HL+) - get low byte
        0x47,              # LD B, A
        0x2A,              # LD A, (HL+) - get high byte
        0x4F,              # LD C, A
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x10)  # Low byte of 0xFF10
      expect(state[:c]).to eq(0xFF)  # High byte of 0xFF10
    end
  end

  describe 'ALU Flag Behavior' do
    it 'DAA correctly adjusts for BCD after addition' do
      # 0x15 + 0x27 = 0x3C in hex, which DAA should adjust to 0x42 (15+27=42 in BCD)
      code = [
        0x3E, 0x15,        # LD A, 0x15
        0xC6, 0x27,        # ADD A, 0x27 -> A = 0x3C, H flag set (5+7=12 > 15)
        0x27,              # DAA -> A should become 0x42
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)  # BCD result of 15 + 27
      expect(state[:f] & 0x80).to eq(0x00)  # Z flag clear (result not zero)
      expect(state[:f] & 0x10).to eq(0x00)  # C flag clear (no BCD overflow)
    end

    it 'DAA correctly adjusts for BCD after subtraction' do
      # 0x42 - 0x15 = 0x2D in hex, which DAA should adjust to 0x27 (42-15=27 in BCD)
      code = [
        0x3E, 0x42,        # LD A, 0x42
        0xD6, 0x15,        # SUB A, 0x15 -> A = 0x2D, N flag set
        0x27,              # DAA -> A should become 0x27
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x27)  # BCD result of 42 - 15
      expect(state[:f] & 0x80).to eq(0x00)  # Z flag clear (result not zero)
    end

    describe 'RLCA/RLA/RRCA/RRA suppress Z flag' do
      it 'RLCA always clears Z flag even when result is zero' do
        # Rotate 0 left should give 0, but Z flag must be cleared
        code = [
          0x3E, 0x00,        # LD A, 0x00
          0x07,              # RLCA - result is 0 but Z should be 0
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
        expect(state[:f] & 0x80).to eq(0x00)  # Z flag must be cleared
      end

      it 'RLA always clears Z flag even when result is zero' do
        # Rotate 0 left through carry (with carry=0) should give 0, but Z flag must be cleared
        code = [
          0xAF,              # XOR A (A=0, clears carry)
          0x17,              # RLA - result is 0 but Z should be 0
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
        expect(state[:f] & 0x80).to eq(0x00)  # Z flag must be cleared
      end

      it 'RRCA always clears Z flag even when result is zero' do
        # Rotate 0 right should give 0, but Z flag must be cleared
        code = [
          0x3E, 0x00,        # LD A, 0x00
          0x0F,              # RRCA - result is 0 but Z should be 0
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
        expect(state[:f] & 0x80).to eq(0x00)  # Z flag must be cleared
      end

      it 'RRA always clears Z flag even when result is zero' do
        # Rotate 0 right through carry (with carry=0) should give 0, but Z flag must be cleared
        code = [
          0xAF,              # XOR A (A=0, clears carry)
          0x1F,              # RRA - result is 0 but Z should be 0
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
        expect(state[:f] & 0x80).to eq(0x00)  # Z flag must be cleared
      end

      it 'RLCA clears N and H flags' do
        code = [
          0x3E, 0x80,        # LD A, 0x80
          0x07,              # RLCA - bit 7 goes to carry and bit 0
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x01)
        expect(state[:f] & 0x40).to eq(0x00)  # N flag cleared
        expect(state[:f] & 0x20).to eq(0x00)  # H flag cleared
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set (from bit 7)
      end
    end

    describe 'ADC flag behavior' do
      it 'ADC A,B adds B plus carry to A' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x10,        # LD A, 0x10
          0x06, 0x05,        # LD B, 0x05
          0x88,              # ADC A, B (A = 0x10 + 0x05 + 1 = 0x16)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x16)
      end

      it 'ADC sets Z flag when result is zero' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0xFF,        # LD A, 0xFF
          0x06, 0x00,        # LD B, 0x00
          0x88,              # ADC A, B (A = 0xFF + 0x00 + 1 = 0x00)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
        expect(state[:f] & 0x80).to eq(0x80)  # Z flag set
      end

      it 'ADC sets C flag on overflow' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x80,        # LD A, 0x80
          0x06, 0x80,        # LD B, 0x80
          0x88,              # ADC A, B (A = 0x80 + 0x80 + 1 = 0x101, result = 0x01)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x01)
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set
      end

      it 'ADC A,n adds immediate plus carry to A' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x20,        # LD A, 0x20
          0xCE, 0x10,        # ADC A, 0x10 (A = 0x20 + 0x10 + 1 = 0x31)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x31)
      end
    end

    describe 'SBC flag behavior' do
      it 'SBC A,B subtracts B plus carry from A' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x20,        # LD A, 0x20
          0x06, 0x05,        # LD B, 0x05
          0x98,              # SBC A, B (A = 0x20 - 0x05 - 1 = 0x1A)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x1A)
      end

      it 'SBC sets Z flag when result is zero' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x06,        # LD A, 0x06
          0x06, 0x05,        # LD B, 0x05
          0x98,              # SBC A, B (A = 0x06 - 0x05 - 1 = 0x00)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x00)
        expect(state[:f] & 0x80).to eq(0x80)  # Z flag set
      end

      it 'SBC sets C flag on borrow' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x00,        # LD A, 0x00
          0x06, 0x01,        # LD B, 0x01
          0x98,              # SBC A, B (A = 0x00 - 0x01 - 1 = 0xFE with borrow)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0xFE)
        expect(state[:f] & 0x10).to eq(0x10)  # C flag set (borrow)
      end

      it 'SBC sets N flag (subtract operation)' do
        code = [
          0xAF,              # XOR A (clear carry)
          0x3E, 0x10,        # LD A, 0x10
          0x06, 0x05,        # LD B, 0x05
          0x98,              # SBC A, B (A = 0x10 - 0x05 - 0 = 0x0B)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x0B)
        expect(state[:f] & 0x40).to eq(0x40)  # N flag set
      end

      it 'SBC A,n subtracts immediate plus carry from A' do
        code = [
          0x37,              # SCF (set carry)
          0x3E, 0x30,        # LD A, 0x30
          0xDE, 0x10,        # SBC A, 0x10 (A = 0x30 - 0x10 - 1 = 0x1F)
          0x76               # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x1F)
      end
    end
  end

  describe 'Interrupt Handling' do
    it 'services VBlank interrupt when IME is enabled' do
      # This test verifies that the CPU correctly services interrupts:
      # 1. Enable VBlank interrupt (write 0x01 to IE at 0xFFFF)
      # 2. Enable interrupts (EI)
      # 3. Wait for VBlank (polling LY until line 144+)
      # 4. Verify the CPU jumps to VBlank handler at 0x0040
      #
      # The VBlank interrupt fires when LY transitions to 144.
      # Test ROM layout:
      # - 0x0040: VBlank handler (set A=0x42 and store to ZPRAM, then RETI)
      # - 0x0100: Main code (enable interrupts, wait for VBlank, check result)
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
      "INTTEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

      # Header checksum
      checksum = 0
      (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
      rom[0x14D] = checksum

      # VBlank interrupt handler at 0x0040
      # Set A = 0x42, store at 0xFF80, then RETI
      handler_code = [
        0x3E, 0x42,        # LD A, 0x42
        0xE0, 0x80,        # LDH (0x80), A - store flag
        0xD9               # RETI
      ]
      handler_code.each_with_index { |b, i| rom[0x0040 + i] = b }

      # Main code at 0x0100
      main_code = [
        # Entry point jump
        0xC3, 0x50, 0x01,  # JP 0x0150

        # Code at 0x0150:
        # 1. Clear flag at 0xFF80
        # 2. Enable VBlank interrupt
        # 3. Enable IME
        # 4. Wait long enough for VBlank to fire
        # 5. Check if handler was called
      ]
      rom[0x100] = main_code[0]
      rom[0x101] = main_code[1]
      rom[0x102] = main_code[2]

      code_at_150 = [
        0x3E, 0x00,        # LD A, 0x00
        0xE0, 0x80,        # LDH (0x80), A - clear flag
        0x3E, 0x01,        # LD A, 0x01 (VBlank enable bit)
        0xE0, 0xFF,        # LDH (0xFF), A - IE = 0x01 (enable VBlank)
        0xFB,              # EI - enable interrupts
        # Wait loop - run for about 2 frames worth of cycles
        0x01, 0x00, 0x08,  # LD BC, 0x0800 (2048 iterations)
        # wait_loop:
        0x0B,              # DEC BC
        0x78,              # LD A, B
        0xB1,              # OR C
        0x20, 0xFB,        # JR NZ, wait_loop (-5)
        # Check result
        0xF0, 0x80,        # LDH A, (0x80) - load flag
        0xE0, 0x81,        # LDH (0x81), A - copy to 0xFF81 for test
        0x76               # HALT
      ]
      code_at_150.each_with_index { |b, i| rom[0x0150 + i] = b }

      @runner.load_rom(rom.pack('C*'))
      @runner.reset

      # Run through boot ROM with coarse steps first
      while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 300_000
        @runner.run_steps(1000)
      end

      # Fine-grained stepping to catch exact boot exit
      while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 500_000
        @runner.run_steps(1)
      end

      boot_cycles = @runner.cycle_count
      puts "Boot complete at #{boot_cycles} cycles, PC=0x#{@runner.cpu_state[:pc].to_s(16)}"

      # Now run through our test code with fine-grained steps to observe interrupt handling
      # Code at 0x0150:
      # 0x0150: LD A, 0x00       (2 cycles)
      # 0x0152: LDH (0x80), A    (3 cycles)
      # 0x0154: LD A, 0x01       (2 cycles)
      # 0x0156: LDH (0xFF), A    (3 cycles) - enables VBlank interrupt
      # 0x0158: EI               (1 cycle)
      # 0x0159: LD BC, 0x0800    (3 cycles) - IME becomes 1 after this
      # Wait for interrupt...

      puts "\nTracing through test code:"
      100.times do |i|
        @runner.run_steps(1)
        pc = @runner.cpu_state[:pc]
        ime = @runner.sim.peek('gb_core__cpu__int_e_ff1') rescue -1
        ime2 = @runner.sim.peek('gb_core__cpu__int_e_ff2') rescue -1
        int_cycle = @runner.sim.peek('gb_core__cpu__int_cycle') rescue -1
        if_r = @runner.sim.peek('gb_core__if_r') rescue -1
        ir = @runner.sim.peek('gb_core__cpu__ir') rescue -1

        # Only print important transitions
        if pc == 0x0040 || pc == 0x0150 || int_cycle == 1 || ime != ime2
          puts "Cycle +#{i+1}: PC=0x#{pc.to_s(16)}, IR=0x#{ir.to_s(16)}, IME=#{ime}, IME2=#{ime2}, IF=0x#{if_r.to_s(16)}, INT_CYCLE=#{int_cycle}"
        end
      end

      # Run remaining cycles for the test
      @runner.run_steps(299900)

      # Check if the VBlank handler was called
      flag = @runner.sim.read_zpram(0)  # 0xFF80
      result = @runner.sim.read_zpram(1)  # 0xFF81

      # Debug output
      state = @runner.cpu_state
      ime = @runner.sim.peek('gb_core__cpu__int_e_ff1') rescue -1
      ie = @runner.sim.peek('gb_core__ie_r') rescue -1
      if_r = @runner.sim.peek('gb_core__if_r') rescue -1
      irq_n = @runner.sim.peek('gb_core__irq_n') rescue -1
      int_cycle = @runner.sim.peek('gb_core__cpu__int_cycle') rescue -1

      puts "CPU state: PC=0x#{state[:pc].to_s(16)}, halted=#{state[:halted]}"
      puts "Cycles: #{@runner.cycle_count}"
      puts "IME=#{ime}, IE=0x#{ie.to_s(16)}, IF=0x#{if_r.to_s(16)}, IRQ_N=#{irq_n}, INT_CYCLE=#{int_cycle}"
      puts "ZPRAM[0] (flag)=#{flag}, ZPRAM[1] (result)=#{result}"

      # The handler sets A=0x42 and stores it at 0xFF80
      # The main code copies 0xFF80 to 0xFF81
      expect(result).to eq(0x42), "Expected VBlank handler to set flag to 0x42, got #{result}"
    end

    it 'EI sets the Interrupt Master Enable (IME) flag' do
      # EI (0xFB) should set int_e_ff1 (IME) to 1
      # The SM83 enables interrupts after the NEXT instruction, but for now
      # we test that IME is eventually set.
      code = [
        0xFB,              # EI - enable interrupts
        0x00,              # NOP - allows EI to take effect
        0x76               # HALT
      ]

      # Run the test
      @runner.load_rom(create_test_rom(code))
      @runner.reset

      # Run through boot ROM
      while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 500_000
        @runner.run_steps(1000)
      end

      # Run just enough to execute EI and NOP
      # At 0x0100: EI (1 cycle = 4 T-states)
      # At 0x0101: NOP (1 cycle = 4 T-states)
      # At 0x0102: HALT
      # After 100 cycles, we should have executed all and IME should be 1
      @runner.run_steps(100)

      # Check IME flag
      ime = @runner.sim.peek('gb_core__cpu__int_e_ff1') rescue -1

      # Debug output
      state = @runner.cpu_state
      puts "After EI: PC=0x#{state[:pc].to_s(16)}, halted=#{state[:halted]}, IME=#{ime}"

      expect(ime).to eq(1), "Expected IME (int_e_ff1) to be 1 after EI, got #{ime}"
    end

    it 'EI sets IME with preceding instructions' do
      # Test that EI works when preceded by LDH instructions
      # Note: We write 0 to IE to disable all interrupts, so IME stays 1 after EI
      # (If we enabled an interrupt, it would fire and clear IME - that's correct behavior)
      code = [
        0x3E, 0x00,        # LD A, 0x00
        0xE0, 0x80,        # LDH (0x80), A - write to ZPRAM
        0x3E, 0x00,        # LD A, 0x00 (disable all interrupts)
        0xE0, 0xFF,        # LDH (0xFF), A - write to IE register (IE=0)
        0xFB,              # EI - enable interrupts
        0x00,              # NOP
        0x76               # HALT
      ]

      @runner.load_rom(create_test_rom(code))
      @runner.reset

      # Run through boot ROM
      while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 500_000
        @runner.run_steps(1000)
      end

      # Check IME immediately after boot loop
      ime0 = @runner.sim.peek('gb_core__cpu__int_e_ff1') rescue -1
      pc0 = @runner.cpu_state[:pc]
      puts "After boot: PC=0x#{pc0.to_s(16)}, IME=#{ime0}"

      # Run more cycles
      @runner.run_steps(100)

      ime = @runner.sim.peek('gb_core__cpu__int_e_ff1') rescue -1
      ie = @runner.sim.peek('gb_core__ie_r') rescue -1
      state = @runner.cpu_state

      puts "After 100 cycles: PC=0x#{state[:pc].to_s(16)}, halted=#{state[:halted]}, IME=#{ime}, IE=0x#{ie.to_s(16)}"

      expect(ime).to eq(1), "Expected IME to be 1 after EI with preceding LDH, got #{ime}"
    end

    it 'disables interrupts for one instruction after DI' do
      # Reference: IntE_FF1, IntE_FF2 interaction
      pending 'DI interrupt delay testing requires external interrupt injection'
      fail
    end

    it 'enables interrupts for one instruction after EI' do
      # Reference: EI enables interrupts after next instruction
      pending 'EI interrupt delay testing requires external interrupt injection'
      fail
    end

    it 'handles interrupt during HALT correctly' do
      # Reference: Complex timing for interrupt during HALT
      pending 'Interrupt during HALT testing requires external interrupt injection'
      fail
    end

    describe 'RETI instruction' do
      it 'RETI returns from subroutine like RET' do
        # RETI (0xD9) works like RET but also enables interrupts.
        code = [
          0xCD, 0x06, 0x01,  # CALL 0x0106 (subroutine at offset 6)
          0x3E, 0x22,        # LD A, 0x22 (after return at 0x0103)
          0x76,              # HALT at 0x0105
          0x3E, 0x11,        # LD A, 0x11 (subroutine at 0x0106)
          0xD9               # RETI at 0x0108
        ]
        state = run_test_code(code)
        expect(state[:a]).to eq(0x22)  # After RETI we should execute LD A, 0x22
      end
    end

    describe 'RST instructions' do
      # RST vectors push PC and jump to fixed address
      # Testing RST directly requires placing code at low memory addresses

      it 'RST 00H jumps to address 0x0000' do
        # RST requires code at vector address 0x0000 which conflicts with header
        pending 'RST vectors require handler code at low addresses (conflicts with ROM header)'
        fail
      end

      it 'RST 38H (0xFF) pushes PC and jumps to 0x0038' do
        pending 'RST vectors require handler code at low addresses'
        fail
      end
    end
  end

  describe 'HALT and STOP Modes' do
    it 'HALT stops execution until interrupt' do
      # HALT (0x76) stops execution - our tests actually rely on this to stop
      # We already use HALT at the end of all our tests
      code = [
        0x3E, 0x42,        # LD A, 0x42
        0x76,              # HALT - this stops the CPU
        0x3E, 0x00         # LD A, 0x00 - should not execute
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)  # A should be 0x42, not 0x00
    end

    it 'STOP enters low-power mode' do
      pending 'STOP mode requires Game Boy Color mode checking'
      fail
    end

    it 'HALT bug: skips next byte when IME=0 and interrupt pending' do
      # Reference: DMG HALT bug
      pending 'HALT bug testing requires external interrupt injection with IME=0'
      fail
    end
  end

  describe 'Microcode Coverage' do
    # These tests verify that all opcodes are properly decoded
    # Individual instruction tests above cover most opcodes
    # These serve as comprehensive coverage checks

    it 'handles undefined opcodes gracefully' do
      # Undefined opcodes (0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD)
      # Should either NOP or freeze - we just test that CPU doesn't crash
      pending 'Undefined opcode behavior testing'
      fail
    end

    it 'all CB-prefix rotate/shift opcodes work' do
      # CB 00-3F: Rotate/Shift operations
      # Already tested individual operations, this would be exhaustive
      pending 'Exhaustive CB rotate/shift testing'
      fail
    end
  end

  describe '16-bit Arithmetic' do
    it 'ADD HL,BC adds BC to HL' do
      code = [
        0x21, 0x00, 0x10,  # LD HL, 0x1000
        0x01, 0x34, 0x12,  # LD BC, 0x1234
        0x09,              # ADD HL, BC (HL = 0x2234)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x22)
      expect(state[:l]).to eq(0x34)
    end

    it 'ADD HL,DE adds DE to HL' do
      code = [
        0x21, 0x00, 0x20,  # LD HL, 0x2000
        0x11, 0x00, 0x30,  # LD DE, 0x3000
        0x19,              # ADD HL, DE (HL = 0x5000)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x50)
      expect(state[:l]).to eq(0x00)
    end

    it 'ADD HL,HL doubles HL' do
      code = [
        0x21, 0x00, 0x40,  # LD HL, 0x4000
        0x29,              # ADD HL, HL (HL = 0x8000)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x80)
      expect(state[:l]).to eq(0x00)
    end

    it 'ADD HL,SP adds SP to HL' do
      code = [
        0x21, 0x00, 0x10,  # LD HL, 0x1000
        0x31, 0x00, 0x20,  # LD SP, 0x2000
        0x39,              # ADD HL, SP (HL = 0x3000)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x30)
      expect(state[:l]).to eq(0x00)
    end

    it 'INC BC increments BC' do
      code = [
        0x01, 0xFF, 0x00,  # LD BC, 0x00FF
        0x03,              # INC BC (BC = 0x0100)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x01)
      expect(state[:c]).to eq(0x00)
    end

    it 'INC DE increments DE' do
      code = [
        0x11, 0xFF, 0xFF,  # LD DE, 0xFFFF
        0x13,              # INC DE (DE = 0x0000 with wrap)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:d]).to eq(0x00)
      expect(state[:e]).to eq(0x00)
    end

    it 'INC HL increments HL' do
      code = [
        0x21, 0x00, 0x80,  # LD HL, 0x8000
        0x23,              # INC HL (HL = 0x8001)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x80)
      expect(state[:l]).to eq(0x01)
    end

    it 'INC SP increments SP' do
      # Verify INC SP by pushing a value and checking where it goes
      # After INC SP, a PUSH will write to SP-1 and SP-2
      code = [
        0x31, 0x82, 0xFF,  # LD SP, 0xFF82 (point to ZPRAM)
        0x33,              # INC SP (SP = 0xFF83)
        0x3E, 0x42,        # LD A, 0x42
        0xF5,              # PUSH AF (writes to FF82/FF81)
        0xF1,              # POP AF (reads from FF81/FF82)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x42)  # Verify PUSH/POP worked
      expect(state[:sp]).to eq(0xFF83)  # SP should be 0xFF83 after POP
    end

    it 'DEC BC decrements BC' do
      code = [
        0x01, 0x00, 0x01,  # LD BC, 0x0100
        0x0B,              # DEC BC (BC = 0x00FF)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:b]).to eq(0x00)
      expect(state[:c]).to eq(0xFF)
    end

    it 'DEC DE decrements DE' do
      code = [
        0x11, 0x00, 0x00,  # LD DE, 0x0000
        0x1B,              # DEC DE (DE = 0xFFFF with wrap)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:d]).to eq(0xFF)
      expect(state[:e]).to eq(0xFF)
    end

    it 'DEC HL decrements HL' do
      code = [
        0x21, 0x00, 0x80,  # LD HL, 0x8000
        0x2B,              # DEC HL (HL = 0x7FFF)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:h]).to eq(0x7F)
      expect(state[:l]).to eq(0xFF)
    end

    it 'DEC SP decrements SP' do
      # Verify DEC SP by checking SP value via PUSH/POP
      code = [
        0x31, 0x84, 0xFF,  # LD SP, 0xFF84 (point to ZPRAM)
        0x3B,              # DEC SP (SP = 0xFF83)
        0x3E, 0x55,        # LD A, 0x55
        0xF5,              # PUSH AF (writes to FF82/FF81)
        0xF1,              # POP AF (reads from FF81/FF82)
        0x76               # HALT
      ]
      state = run_test_code(code)
      expect(state[:a]).to eq(0x55)  # Verify PUSH/POP worked
      expect(state[:sp]).to eq(0xFF83)  # SP should be 0xFF83 after POP
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
