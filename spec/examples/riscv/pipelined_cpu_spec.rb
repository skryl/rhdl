# Pipelined RISC-V CPU Tests
# Tests cover pipeline behavior including forwarding and hazards

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/pipeline/cpu'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe RHDL::Examples::RISCV::Pipeline::PipelinedCPU do
  let(:cpu) { described_class.new('test_cpu') }
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  before(:each) do
    cpu.reset!
  end

  # Helper: run until pipeline drains (enough cycles for result to appear)
  def run_and_drain(program, extra_cycles = 0)
    cpu.load_program(program)
    cpu.reset!
    # Pipeline depth (5) + program length + extra
    cycles = program.length + 5 + extra_cycles
    cpu.run_cycles(cycles)
  end

  describe 'Basic Pipeline Operation' do
    it 'executes NOP sequence' do
      program = [
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(0)
    end

    it 'executes single ADDI instruction' do
      program = [
        asm.addi(1, 0, 42),  # x1 = 0 + 42
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(42)
    end

    it 'executes LUI instruction' do
      program = [
        asm.lui(1, 0x12345),  # x1 = 0x12345000
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(0x12345000)
    end
  end

  describe 'Data Forwarding' do
    it 'forwards from EX/MEM to EX (RAW hazard)' do
      program = [
        asm.addi(1, 0, 10),   # x1 = 10
        asm.addi(2, 1, 20),   # x2 = x1 + 20 (forward from EX/MEM)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(10)
      expect(cpu.read_reg(2)).to eq(30)
    end

    it 'forwards from MEM/WB to EX' do
      program = [
        asm.addi(1, 0, 10),   # x1 = 10
        asm.nop,              # Bubble
        asm.addi(2, 1, 20),   # x2 = x1 + 20 (forward from MEM/WB)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(10)
      expect(cpu.read_reg(2)).to eq(30)
    end

    it 'handles multiple consecutive dependencies' do
      program = [
        asm.addi(1, 0, 5),    # x1 = 5
        asm.addi(2, 1, 5),    # x2 = x1 + 5 = 10 (forward)
        asm.addi(3, 2, 5),    # x3 = x2 + 5 = 15 (forward)
        asm.addi(4, 3, 5),    # x4 = x3 + 5 = 20 (forward)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(5)
      expect(cpu.read_reg(2)).to eq(10)
      expect(cpu.read_reg(3)).to eq(15)
      expect(cpu.read_reg(4)).to eq(20)
    end
  end

  describe 'Load-Use Hazard (Stalling)' do
    it 'stalls for load-use hazard' do
      program = [
        asm.addi(10, 0, 0x100),  # x10 = 0x100 (address)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      # Store a value at memory location first
      cpu.write_data(0x100, 42)

      program = [
        asm.addi(10, 0, 0x100),  # x10 = 0x100
        asm.nop,
        asm.nop,
        asm.lw(1, 10, 0),       # x1 = mem[x10] (load 42)
        asm.addi(2, 1, 8),      # x2 = x1 + 8 (load-use hazard, should stall)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 2)  # Extra cycles for stall
      expect(cpu.read_reg(1)).to eq(42)
      expect(cpu.read_reg(2)).to eq(50)
    end
  end

  describe 'R-type Instructions' do
    it 'executes ADD instruction' do
      program = [
        asm.addi(1, 0, 15),   # x1 = 15
        asm.addi(2, 0, 27),   # x2 = 27
        asm.nop,
        asm.nop,
        asm.add(3, 1, 2),     # x3 = x1 + x2 = 42
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(42)
    end

    it 'executes SUB instruction' do
      program = [
        asm.addi(1, 0, 50),
        asm.addi(2, 0, 8),
        asm.nop,
        asm.nop,
        asm.sub(3, 1, 2),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(42)
    end

    it 'executes AND/OR/XOR instructions' do
      program = [
        asm.addi(1, 0, 0xFF),
        asm.addi(2, 0, 0x0F),
        asm.nop,
        asm.nop,
        asm.and_inst(3, 1, 2),  # 0xFF & 0x0F = 0x0F
        asm.or_inst(4, 1, 2),   # 0xFF | 0x0F = 0xFF
        asm.xor_inst(5, 1, 2),  # 0xFF ^ 0x0F = 0xF0
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(0x0F)
      expect(cpu.read_reg(4)).to eq(0xFF)
      expect(cpu.read_reg(5)).to eq(0xF0)
    end

    it 'executes shift instructions' do
      program = [
        asm.addi(1, 0, 8),      # x1 = 8
        asm.addi(2, 0, 2),      # x2 = 2 (shift amount)
        asm.nop,
        asm.nop,
        asm.sll(3, 1, 2),       # x3 = 8 << 2 = 32
        asm.srl(4, 1, 2),       # x4 = 8 >> 2 = 2
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(32)
      expect(cpu.read_reg(4)).to eq(2)
    end
  end

  describe 'Branch Instructions' do
    it 'executes BEQ taken' do
      program = [
        asm.addi(1, 0, 5),     # x1 = 5
        asm.addi(2, 0, 5),     # x2 = 5
        asm.nop,
        asm.nop,
        asm.beq(1, 2, 8),      # if x1 == x2, skip next 2 instructions
        asm.addi(3, 0, 99),    # Should be skipped
        asm.addi(3, 0, 88),    # Should be skipped
        asm.addi(3, 0, 42),    # Should execute
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 3)
      expect(cpu.read_reg(3)).to eq(42)
    end

    it 'executes BEQ not taken' do
      program = [
        asm.addi(1, 0, 5),
        asm.addi(2, 0, 10),
        asm.nop,
        asm.nop,
        asm.beq(1, 2, 8),      # Not taken (5 != 10)
        asm.addi(3, 0, 42),    # Should execute
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(42)
    end

    it 'executes BNE taken' do
      program = [
        asm.addi(1, 0, 5),
        asm.addi(2, 0, 10),
        asm.nop,
        asm.nop,
        asm.bne(1, 2, 8),      # Taken (5 != 10)
        asm.addi(3, 0, 99),    # Skipped
        asm.addi(3, 0, 88),    # Skipped
        asm.addi(3, 0, 42),    # Executed
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 3)
      expect(cpu.read_reg(3)).to eq(42)
    end

    it 'executes BLT taken' do
      program = [
        asm.addi(1, 0, 5),
        asm.addi(2, 0, 10),
        asm.nop,
        asm.nop,
        asm.blt(1, 2, 8),      # Taken (5 < 10)
        asm.addi(3, 0, 99),
        asm.addi(3, 0, 88),
        asm.addi(3, 0, 42),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 3)
      expect(cpu.read_reg(3)).to eq(42)
    end
  end

  describe 'Jump Instructions' do
    it 'executes JAL instruction' do
      program = [
        asm.jal(1, 12),        # Jump forward 12 bytes (3 instructions), x1 = PC+4
        asm.addi(2, 0, 99),    # Skipped
        asm.addi(2, 0, 88),    # Skipped
        asm.addi(2, 0, 77),    # Skipped
        asm.addi(2, 0, 42),    # Target
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 3)
      expect(cpu.read_reg(1)).to eq(4)  # Return address = PC of JAL + 4
      expect(cpu.read_reg(2)).to eq(42)
    end

    it 'executes JALR instruction' do
      program = [
        asm.addi(1, 0, 20),    # x1 = 20 (target address)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.jalr(2, 1, 0),     # Jump to x1, x2 = PC+4
        asm.addi(3, 0, 99),    # Skipped (PC=20)
        asm.addi(3, 0, 42),    # Target at address 20
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 3)
      expect(cpu.read_reg(2)).to eq(20)  # Return address
      expect(cpu.read_reg(3)).to eq(42)
    end
  end

  describe 'Memory Instructions' do
    before(:each) do
      cpu.write_data(0x100, 0xDEADBEEF)
      cpu.write_data(0x104, 0x12345678)
    end

    it 'executes LW instruction' do
      program = [
        asm.addi(10, 0, 0x100),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.lw(1, 10, 0),     # x1 = mem[0x100]
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(0xDEADBEEF)
    end

    it 'executes SW instruction' do
      program = [
        asm.addi(10, 0, 0x200),
        asm.addi(1, 0, 0x42),
        asm.nop,
        asm.nop,
        asm.sw(1, 10, 0),     # mem[0x200] = x1
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_data(0x200)).to eq(0x42)
    end
  end

  describe 'Complex Programs' do
    it 'computes factorial of 5', skip: 'Multiply instruction not implemented' do
      # Factorial: result = 1; for i = 5 downto 1: result *= i
      # Would need asm.mul_emulated or M extension
    end

    it 'sums numbers 1 to 10' do
      # sum = 0; for i = 1 to 10: sum += i
      program = [
        asm.addi(1, 0, 1),     # x1 = i = 1
        asm.addi(2, 0, 0),     # x2 = sum = 0
        asm.addi(3, 0, 11),    # x3 = limit = 11
        asm.nop,
        # Loop:
        asm.beq(1, 3, 16),     # if i == limit, exit (4 instructions forward)
        asm.nop,
        asm.add(2, 2, 1),      # sum += i
        asm.addi(1, 1, 1),     # i++
        asm.jal(0, -16),       # back to loop (-4 instructions)
        # End:
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 60)  # Extra cycles for loop iterations
      # Sum of 1 to 10 = 55
      expect(cpu.read_reg(2)).to eq(55)
    end
  end
end
