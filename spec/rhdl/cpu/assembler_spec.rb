require 'spec_helper'
require 'support/assembler'

RSpec.describe Assembler do
  describe 'instruction assembly' do
    it 'correctly assembles single-byte instructions' do
      program = Assembler.build do |p|
        p.instr :NOP
        p.instr :HLT
      end

      expect(program).to eq([
        :NOP, 0x00,
        :HLT, 0x00
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
        :LDI, 0x05,
        :ADD, 0x03,
        :SUB, 0x02,
        :CMP, 0x04,
        :STA, 0x10
      ])
    end

    it 'correctly assembles four-byte instructions with labels' do
      program = Assembler.build do |p|
        p.label :start
        p.instr :JMP_LONG, :start
      end

      expect(program).to eq([
        :JMP_LONG, 0x00, 0x00  # high byte, low byte for address 0x0000
      ])
    end

    it 'assembles complex programs with multiple instructions and labels' do
      program = Assembler.build do |p|
        p.label :start
        p.instr :LDI, 0xFF
        p.instr :STA, 0x20
        p.label :middle
        p.instr :LDA, 0x20
        p.instr :CMP, 0xFF
        p.instr :JNZ, :start
        p.instr :RET
      end

      expect(program).to eq([
        :LDI, 0xFF,
        :STA, 0x20,
        :LDA, 0x20,
        :CMP, 0xFF,
        :JNZ, 0x00,    # Jump back to start (address 0x00)
        :RET, 0x00
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
        :LDI, 0x05,
        :ADD, 0x03,
        :SUB, 0x02,
        :CMP, 0x04,
        :STA, 0x10,
        :CALL, 0x07,   # Call to address 0x07 (test_label)
        :NOP, 0x00,
        :RET, 0x00,
        :MUL, 0x0C
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
        :LDI, 0x10,
        :SUB, 0x01,
        :CMP, 0x00,
        :JNZ, 0x02,    # Jump to loop_start (address 0x02)
        :RET, 0x00
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
        :CMP, 0x00,
        :JZ_LONG, 0x00, 0x05,  # Jump to address 0x0005 if zero
        :NOP, 0x00,
        :RET, 0x00
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
        :LDI, 0x10,
        :JMP_LONG, 0x00, 0x00  # Jump to start at address 0x0000
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
