require 'spec_helper'
require 'support/cpu_test_helper'
require 'support/assembler'
require 'support/display_helper'

RSpec.describe RHDL::Components::CPU::CPU do
  include CpuTestHelper
  include DisplayHelper

  describe 'program tests' do
    before(:each) do
      @memory = MemorySimulator::Memory.new
      @cpu = described_class.new(@memory)
      @cpu.reset
    end

    it 'calculates sum of two numbers' do
      program = Assembler.build do |p|
        p.instr :LDA, 0xE      # Load first operand
        p.instr :ADD, 0xF      # Add second operand
        p.instr :STA, 0xD      # Store result
        p.instr :HLT
      end

      load_program(program)
      @memory.write(0xE, 0x24)
      @memory.write(0xF, 0x18)
      simulate_cycles(10)

      expect(@memory.read(0xD)).to eq(0x3C)
      expect(@cpu.halted).to be true
    end

    it 'finds maximum of two numbers' do
      program = Assembler.build do |p|
        p.instr :LDA, 0xE
        p.instr :SUB, 0xF
        p.instr :JZ_LONG, :equal_label

        p.instr :LDA, 0xE
        p.instr :STA, 0xD
        p.instr :HLT

        p.label :equal_label
        p.instr :LDA, 0xF
        p.instr :STA, 0xD
        p.instr :HLT
      end

      load_program(program)
      @memory.write(0xE, 0x42)
      @memory.write(0xF, 0x24)
      simulate_cycles(20)

      expect(@memory.read(0xD)).to eq(0x42)
      expect(@cpu.halted).to be true
    end

    it 'counts down from a number to zero' do
      program = Assembler.build do |p|
        p.label :start
        p.instr :LDA, 0xE
        p.instr :JZ_LONG, :done
        p.instr :SUB, 0xD
        p.instr :STA, 0xE
        p.instr :JMP, :start    # Jump to :start label
        p.label :done
        p.instr :HLT
      end

      load_program(program)
      @memory.write(0xE, 0x05)
      @memory.write(0xD, 0x01)
      simulate_cycles(50)

      expect(@cpu.halted).to be true
      expect(@memory.read(0xE)).to eq(0)
    end

    it 'calculates factorial of a small number' do
      program = Assembler.build do |p|
        p.label :start
        p.instr :LDA, 0xE
        p.instr :JZ_LONG, :halt
        p.instr :STA, 0xC
        p.instr :LDA, 0xF
        p.instr :MUL, 0xC
        p.instr :STA, 0xF
        p.instr :LDA, 0xE
        p.instr :SUB, 0xD
        p.instr :STA, 0xE
        p.instr :JMP, 0x0    # jump back to offset 0
        p.label :halt
        p.instr :HLT
      end

      load_program(program)
      @memory.write(0xE, 5)   # N=5
      @memory.write(0xD, 1)   # decrement=1
      @memory.write(0xF, 1)   # result=1
      simulate_cycles(100)

      expect(@cpu.halted).to be true
      expect(@memory.read(0xF)).to eq(120)
    end

    it 'doubles a number' do
      program = Assembler.build do |p|
        p.instr :LDA, 0xE
        p.instr :ADD, 0xE
        p.instr :STA, 0xD
        p.instr :HLT
      end

      load_program(program)
      @memory.write(0xE, 0x10)  # 0x10 (16 decimal)
      simulate_cycles(10)

      expect(@cpu.halted).to be true
      expect(@memory.read(0xD)).to eq(0x20)  # 16 doubled is 32
    end
  end
end
