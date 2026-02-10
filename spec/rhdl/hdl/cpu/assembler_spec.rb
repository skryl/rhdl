require 'spec_helper'
require 'support/cpu_assembler'

RSpec.describe Assembler do
  describe 'instruction assembly' do
    it 'correctly assembles single-byte instructions' do
      program = Assembler.build do |p|
        p.instr :NOP
        p.instr :HLT
      end

      expect(program).to eq([
        0x00,  # NOP
        0xF0   # HLT
      ])
    end

    it 'correctly assembles two-byte instructions' do
      program = Assembler.build do |p|
        p.instr :LDI, 0x05
        p.instr :ADD, 0x03
        p.instr :SUB, 0x02
        p.instr :CMP, 0x04
        p.instr :STA, 0x10
      end

      expect(program).to eq([
        0xA0, 0x05,  # LDI 0x05
        0x33,        # ADD 0x03
        0x42,        # SUB 0x02
        0xF3, 0x04,  # CMP 0x04
        0x21, 0x10   # STA 0x10 (2-byte direct)
      ])
    end

    it 'correctly assembles four-byte instructions with labels' do
      program = Assembler.build do |p|
        p.label :start
        p.instr :JMP_LONG, :start
      end

      expect(program).to eq([
        0xF9, 0x00, 0x00  # JMP_LONG: opcode, high byte, low byte for address 0x0000
      ])
    end

    it 'assembles complex programs with multiple instructions and labels' do
      program = Assembler.build do |p|
        p.label :start
        p.instr :LDI, 0xFF
        p.instr :STA, 0x0E
        p.label :middle
        p.instr :LDA, 0x0E
        p.instr :CMP, 0xFF
        p.instr :JNZ, :start
        p.instr :RET
      end

      expect(program).to eq([
        0xA0, 0xFF,  # LDI 0xFF
        0x2E,        # STA 0x0E (nibble-encoded)
        0x1E,        # LDA 0x0E (nibble-encoded)
        0xF3, 0xFF,  # CMP 0xFF
        0x90,        # JNZ 0x00 (jump back to start)
        0xD0         # RET
      ])
    end

    it 'assembles all supported instructions correctly' do
      program = Assembler.build do |p|
        p.instr :LDI, 0x05
        p.instr :ADD, 0x03
        p.instr :SUB, 0x02
        p.instr :CMP, 0x04
        p.instr :STA, 0x10
        p.instr :CALL, :test_label
        p.label :test_label
        p.instr :NOP
        p.instr :RET
        p.instr :MUL, 0x0C
      end

      expect(program).to eq([
        0xA0, 0x05,  # LDI 0x05
        0x33,        # ADD 0x03
        0x42,        # SUB 0x02
        0xF3, 0x04,  # CMP 0x04
        0x21, 0x10,  # STA 0x10 (2-byte)
        0xC0, 0x0A,  # CALL 0x0A (2-byte call to test_label)
        0x00,        # NOP
        0xD0,        # RET
        0xF1, 0x0C   # MUL 0x0C
      ])
    end

    it 'handles multiple labels and jumps correctly' do
      program = Assembler.build do |p|
        p.label :init
        p.instr :LDI, 0x10
        p.label :loop_start
        p.instr :SUB, 0x01
        p.instr :CMP, 0x00
        p.instr :JNZ, :loop_start
        p.instr :RET
      end

      expect(program).to eq([
        0xA0, 0x10,  # LDI 0x10
        0x41,        # SUB 0x01
        0xF3, 0x00,  # CMP 0x00
        0x92,        # JNZ 0x02 (jump to loop_start at offset 2)
        0xD0         # RET
      ])
    end

    it 'assembles conditional jumps correctly' do
      program = Assembler.build do |p|
        p.label :check_zero
        p.instr :CMP, 0x00
        p.instr :JZ_LONG, :zero_label
        p.instr :NOP
        p.label :zero_label
        p.instr :RET
      end

      expect(program).to eq([
        0xF3, 0x00,     # CMP 0x00
        0xF8, 0x00, 0x06,  # JZ_LONG to address 0x0006 (zero_label) if zero
        0x00,           # NOP
        0xD0            # RET (at zero_label)
      ])
    end

    it 'raises an error for unknown labels' do
      expect {
        Assembler.build do |p|
          p.instr :JMP_LONG, :undefined_label
        end
      }.to raise_error("Unknown label :undefined_label")
    end

    it 'raises an error for unsupported instruction formats' do
      expect {
        Assembler.build do |p|
          p.instr :UNKNOWN, 0x01 # Unknown instruction
        end
      }.to raise_error(ArgumentError) { |error|
        expect(error.message).to eq("Unknown instruction: UNKNOWN")
      }
    end
  end

  describe 'assembler edge cases' do
    it 'handles multiple labels pointing to the same address' do
      program = Assembler.build do |p|
        p.label :start
        p.label :begin
        p.instr :LDI, 0x10
        p.label :loop
        p.instr :JMP_LONG, :start
      end

      expect(program).to eq([
        0xA0, 0x10,        # LDI 0x10
        0xF9, 0x00, 0x00   # JMP_LONG to start at address 0x0000
      ])
    end

    it 'assembles a program with no instructions' do
      program = Assembler.build do |p|
        # No instructions
      end
      expect(program).to eq([])
    end
  end
end 
