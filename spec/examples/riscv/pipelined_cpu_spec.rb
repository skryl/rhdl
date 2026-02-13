# Pipelined RISC-V CPU Tests
# Tests cover pipeline behavior including forwarding and hazards

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness, timeout: 30 do
  let(:cpu) { described_class.new('test_cpu', backend: :jit, allow_fallback: false) }
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
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

    it 'executes AUIPC instruction' do
      program = [
        asm.auipc(1, 1),  # x1 = PC + 0x1000 (PC is 0)
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(1)).to eq(0x1000)
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
        asm.lui(5, 0xFFFFF),    # x5 = 0xFFFFF000
        asm.addi(6, 0, 4),      # x6 = 4 (arithmetic shift amount)
        asm.nop,
        asm.nop,
        asm.sll(3, 1, 2),       # x3 = 8 << 2 = 32
        asm.srl(4, 1, 2),       # x4 = 8 >> 2 = 2
        asm.sra(7, 5, 6),       # x7 = 0xFFFFF000 >> 4 = 0xFFFFFF00
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(32)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(7)).to eq(0xFFFFFF00)
    end

    it 'executes SLT/SLTU instructions' do
      program = [
        asm.addi(1, 0, -1),     # x1 = 0xFFFFFFFF
        asm.addi(2, 0, 1),      # x2 = 1
        asm.nop,
        asm.nop,
        asm.slt(3, 1, 2),       # signed: -1 < 1 => 1
        asm.sltu(4, 1, 2),      # unsigned: 0xFFFFFFFF < 1 => 0
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(1)
      expect(cpu.read_reg(4)).to eq(0)
    end
  end

  describe 'M-extension Instructions' do
    it 'executes MUL/MULH/MULHSU/MULHU instructions' do
      program = [
        asm.addi(1, 0, -2),     # x1 = 0xFFFFFFFE
        asm.addi(2, 0, 3),      # x2 = 3
        asm.addi(6, 0, -1),     # x6 = 0xFFFFFFFF
        asm.addi(7, 0, 2),      # x7 = 2
        asm.nop,
        asm.nop,
        asm.mul(3, 1, 2),       # low 32 bits = 0xFFFFFFFA
        asm.mulh(4, 1, 2),      # high signed = 0xFFFFFFFF
        asm.mulhsu(5, 1, 2),    # high signed/unsigned = 0xFFFFFFFF
        asm.mulhu(8, 6, 7),     # high unsigned = 0x00000001
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(0xFFFFFFFA)
      expect(cpu.read_reg(4)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(5)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(8)).to eq(0x00000001)
    end

    it 'executes DIV/DIVU/REM/REMU instructions' do
      program = [
        asm.addi(1, 0, -20),    # x1 = -20
        asm.addi(2, 0, 3),      # x2 = 3
        asm.addi(3, 0, 20),     # x3 = 20
        asm.nop,
        asm.nop,
        asm.div(4, 1, 2),       # -20 / 3 = -6 (toward zero)
        asm.rem(5, 1, 2),       # -20 % 3 = -2
        asm.divu(6, 3, 2),      # 20 / 3 = 6
        asm.remu(7, 3, 2),      # 20 % 3 = 2
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(4)).to eq(0xFFFFFFFA)
      expect(cpu.read_reg(5)).to eq(0xFFFFFFFE)
      expect(cpu.read_reg(6)).to eq(6)
      expect(cpu.read_reg(7)).to eq(2)
    end

    it 'handles divide-by-zero and signed overflow cases per RV32M spec' do
      program = [
        asm.addi(1, 0, 7),       # x1 = 7
        asm.addi(2, 0, 0),       # x2 = 0
        asm.lui(7, 0x80000),     # x7 = 0x80000000
        asm.addi(8, 0, -1),      # x8 = 0xFFFFFFFF
        asm.nop,
        asm.nop,
        asm.div(3, 1, 2),        # div by zero => -1
        asm.divu(4, 1, 2),       # divu by zero => 0xFFFFFFFF
        asm.rem(5, 1, 2),        # rem by zero => dividend
        asm.remu(6, 1, 2),       # remu by zero => dividend
        asm.div(9, 7, 8),        # overflow => 0x80000000
        asm.rem(10, 7, 8),       # overflow => 0
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(4)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(5)).to eq(7)
      expect(cpu.read_reg(6)).to eq(7)
      expect(cpu.read_reg(9)).to eq(0x80000000)
      expect(cpu.read_reg(10)).to eq(0)
    end
  end

  describe 'CSR instructions (Zicsr)' do
    it 'executes CSRRW/CSRRS read-write flow' do
      program = [
        asm.addi(1, 0, 0x40),         # x1 = 0x40
        asm.nop,
        asm.nop,
        asm.csrrw(2, 0x305, 1),       # x2 = old mtvec (0), mtvec = 0x40
        asm.csrrs(3, 0x305, 0),       # x3 = mtvec
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(2)).to eq(0)
      expect(cpu.read_reg(3)).to eq(0x40)
    end

    it 'executes CSRRSI/CSRRCI bit operations' do
      program = [
        asm.addi(1, 0, 0b1010),       # x1 = 0b1010
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x300, 1),       # mstatus = 0b1010
        asm.csrrsi(2, 0x300, 0b0101), # x2=0b1010, mstatus=0b1111
        asm.csrrci(3, 0x300, 0b0011), # x3=0b1111, mstatus=0b1100
        asm.csrrs(4, 0x300, 0),       # x4=0b1100
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(2)).to eq(0b1010)
      expect(cpu.read_reg(3)).to eq(0b1111)
      expect(cpu.read_reg(4)).to eq(0b1100)
    end
  end

  describe 'I-type Immediate Instructions' do
    it 'executes XORI/ORI/ANDI instructions' do
      program = [
        asm.addi(1, 0, 0xFF),   # x1 = 0x000000FF
        asm.addi(2, 0, 0xF0),   # x2 = 0x000000F0
        asm.nop,
        asm.nop,
        asm.xori(3, 1, 0x0F),   # x3 = 0x000000F0
        asm.ori(4, 2, 0x0F),    # x4 = 0x000000FF
        asm.andi(5, 1, 0x0F),   # x5 = 0x0000000F
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(3)).to eq(0xF0)
      expect(cpu.read_reg(4)).to eq(0xFF)
      expect(cpu.read_reg(5)).to eq(0x0F)
    end

    it 'executes SLTI/SLTIU instructions' do
      program = [
        asm.addi(1, 0, -1),     # x1 = 0xFFFFFFFF
        asm.nop,
        asm.nop,
        asm.nop,
        asm.slti(2, 1, 1),      # signed: -1 < 1 => 1
        asm.sltiu(3, 1, 1),     # unsigned: 0xFFFFFFFF < 1 => 0
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(2)).to eq(1)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'executes SLLI/SRLI/SRAI instructions' do
      program = [
        asm.addi(1, 0, 1),      # x1 = 1
        asm.addi(2, 0, 128),    # x2 = 128
        asm.lui(3, 0xFFFFF),    # x3 = 0xFFFFF000
        asm.nop,
        asm.slli(4, 1, 4),      # x4 = 16
        asm.srli(5, 2, 3),      # x5 = 16
        asm.srai(6, 3, 4),      # x6 = 0xFFFFFF00
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(4)).to eq(16)
      expect(cpu.read_reg(5)).to eq(16)
      expect(cpu.read_reg(6)).to eq(0xFFFFFF00)
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

    it 'executes BGE taken' do
      program = [
        asm.addi(1, 0, 10),
        asm.addi(2, 0, 5),
        asm.nop,
        asm.nop,
        asm.bge(1, 2, 8),      # Taken (10 >= 5)
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

    it 'executes BLTU taken' do
      program = [
        asm.addi(1, 0, 5),
        asm.addi(2, 0, -1),    # 0xFFFFFFFF unsigned
        asm.nop,
        asm.nop,
        asm.bltu(1, 2, 8),     # Taken (5 < 0xFFFFFFFF unsigned)
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

    it 'executes BGEU taken' do
      program = [
        asm.addi(1, 0, -1),    # 0xFFFFFFFF unsigned
        asm.addi(2, 0, 5),
        asm.nop,
        asm.nop,
        asm.bgeu(1, 2, 8),     # Taken (0xFFFFFFFF >= 5 unsigned)
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

    it 'executes SB/LB/LBU instructions' do
      program = [
        asm.addi(10, 0, 0x220),
        asm.addi(1, 0, 0xAB),
        asm.nop,
        asm.nop,
        asm.sb(1, 10, 0),      # mem8[0x220] = 0xAB
        asm.nop,
        asm.lb(2, 10, 0),      # sign-extended => 0xFFFFFFAB
        asm.lbu(3, 10, 0),     # zero-extended => 0x000000AB
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(2)).to eq(0xFFFFFFAB)
      expect(cpu.read_reg(3)).to eq(0xAB)
    end

    it 'executes SH/LH/LHU instructions' do
      program = [
        asm.addi(10, 0, 0x224),
        asm.addi(1, 0, -1),
        asm.nop,
        asm.nop,
        asm.sh(1, 10, 0),      # mem16[0x224] = 0xFFFF
        asm.nop,
        asm.lh(2, 10, 0),      # sign-extended => 0xFFFFFFFF
        asm.lhu(3, 10, 0),     # zero-extended => 0x0000FFFF
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program)
      expect(cpu.read_reg(2)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(3)).to eq(0x0000FFFF)
    end
  end

  describe 'SYSTEM/MISC_MEM instructions' do
    it 'treats FENCE as a non-trapping no-op' do
      program = [
        asm.addi(10, 0, 0x200),
        asm.addi(1, 0, 5),
        asm.sw(1, 10, 0),
        asm.nop,
        asm.nop,
        asm.fence,
        asm.addi(2, 1, 7),
        asm.lw(3, 10, 0),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]

      run_and_drain(program, 4)
      expect(cpu.read_reg(1)).to eq(5)
      expect(cpu.read_reg(2)).to eq(12)
      expect(cpu.read_reg(3)).to eq(5)
      expect(cpu.read_reg(0)).to eq(0)
      expect(cpu.read_data(0x200)).to eq(5)
    end

    it 'traps on ECALL to mtvec and returns with MRET' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        asm.addi(2, 0, 7),           # x2 = 7
        asm.nop,
        asm.nop,
        asm.ecall,                   # trap
        asm.addi(2, 2, 1),           # executes after mret
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(4, 0x342, 0),      # x4 = mcause
        asm.csrrs(3, 0x341, 0),      # x3 = mepc
        asm.csrrs(5, 0x343, 0),      # x5 = mtval
        asm.addi(3, 3, 4),           # resume at next instruction
        asm.csrrw(0, 0x341, 3),      # mepc = x3
        asm.mret,
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(40)

      expect(cpu.read_reg(2)).to eq(8)
      expect(cpu.read_reg(3)).to eq(32)
      expect(cpu.read_reg(4)).to eq(11)
    end

    it 'updates mstatus trap-stack bits on ECALL and MRET' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        asm.addi(1, 0, 0x8),         # x1 = MIE bit set
        asm.csrrw(0, 0x300, 1),      # mstatus = 0x8
        asm.nop,
        asm.nop,
        asm.ecall,                   # trap
        asm.csrrs(10, 0x300, 0),     # x10 = mstatus after mret
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x300, 0),      # x2 = mstatus during trap
        asm.csrrs(3, 0x341, 0),      # x3 = mepc
        asm.addi(3, 3, 4),           # resume at next instruction
        asm.csrrw(0, 0x341, 3),      # mepc = x3
        asm.mret,
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(50)

      expect(cpu.read_reg(2)).to eq(0x1880)  # trap: MPP=3, MPIE=1, MIE=0
      expect(cpu.read_reg(3)).to eq(36)
      expect(cpu.read_reg(10)).to eq(0x88)   # after mret: MPP=0, MPIE=1, MIE=1
    end

    it 'traps on EBREAK to mtvec and returns with MRET' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        asm.addi(2, 0, 9),           # x2 = 9
        asm.nop,
        asm.nop,
        asm.ebreak,                  # trap
        asm.addi(2, 2, 2),           # executes after mret
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(4, 0x342, 0),      # x4 = mcause
        asm.csrrs(3, 0x341, 0),      # x3 = mepc
        asm.csrrs(5, 0x343, 0),      # x5 = mtval
        asm.addi(3, 3, 4),           # resume at next instruction
        asm.csrrw(0, 0x341, 3),      # mepc = x3
        asm.mret,
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(40)

      expect(cpu.read_reg(2)).to eq(11)
      expect(cpu.read_reg(3)).to eq(32)
      expect(cpu.read_reg(4)).to eq(3)
    end

    it 'traps on illegal SYSTEM instruction with mcause=2 and returns with MRET' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        0x10600073,                  # unknown SYSTEM funct12 => illegal instruction
        asm.addi(2, 0, 1),           # executes after mret
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(4, 0x342, 0),      # x4 = mcause
        asm.csrrs(3, 0x341, 0),      # x3 = mepc
        asm.csrrs(5, 0x343, 0),      # x5 = mtval
        asm.addi(3, 3, 4),           # resume at next instruction
        asm.csrrw(0, 0x341, 3),      # mepc = x3
        asm.mret,
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(40)

      expect(cpu.read_reg(2)).to eq(1)
      expect(cpu.read_reg(3)).to eq(20)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(5)).to eq(0x10600073)
    end

    it 'takes machine timer interrupt when enabled' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        asm.addi(1, 0, 0x80),        # x1 = MTIE
        asm.csrrw(0, 0x304, 1),      # mie = MTIE
        asm.addi(1, 0, 0x8),         # x1 = MIE
        asm.csrrw(0, 0x300, 1),      # mstatus = MIE
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x342, 0),      # x2 = mcause
        asm.csrrs(4, 0x300, 0),      # x4 = mstatus in handler
        asm.jal(0, 0),
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(24)             # setup through WB
      cpu.set_interrupts(timer: 1)   # assert MTIP
      cpu.run_cycles(20)

      expect(cpu.read_reg(2)).to eq(0x80000007)
      expect(cpu.read_reg(4)).to eq(0x1880)
    end

    it 'takes machine timer interrupt from CLINT mtimecmp when enabled' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        asm.lui(5, 0x2004),          # x5 = 0x02004000 (mtimecmp)
        asm.addi(6, 0, 40),          # mtimecmp low threshold
        asm.sw(6, 5, 0),             # mtimecmp low
        asm.sw(0, 5, 4),             # mtimecmp high = 0
        asm.addi(1, 0, 0x80),        # x1 = MTIE
        asm.csrrw(0, 0x304, 1),      # mie = MTIE
        asm.addi(1, 0, 0x8),         # x1 = MIE
        asm.csrrw(0, 0x300, 1),      # mstatus = MIE
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x342, 0),      # x2 = mcause
        asm.csrrs(4, 0x300, 0),      # x4 = mstatus in handler
        asm.jal(0, 0),
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(60)

      expect(cpu.read_reg(2)).to eq(0x80000007)
      expect(cpu.read_reg(4)).to eq(0x1880)
    end

    it 'takes machine software interrupt from CLINT msip when enabled' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1
        asm.lui(5, 0x2000),          # x5 = 0x02000000 (msip)
        asm.addi(6, 0, 1),           # msip set value
        asm.addi(1, 0, 0x8),         # x1 = MSIE
        asm.csrrw(0, 0x304, 1),      # mie = MSIE
        asm.addi(1, 0, 0x8),         # x1 = MIE
        asm.csrrw(0, 0x300, 1),      # mstatus = MIE
        asm.sw(6, 5, 0),             # msip = 1
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x342, 0),      # x2 = mcause
        asm.csrrs(4, 0x300, 0),      # x4 = mstatus in handler
        asm.jal(0, 0),
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(60)

      expect(cpu.read_reg(2)).to eq(0x80000003)
      expect(cpu.read_reg(4)).to eq(0x1880)
    end

    it 'delegates ECALL to stvec and returns with SRET' do
      main_program = [
        asm.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x105, 1),      # stvec = x1
        asm.lui(1, 0x1),             # x1 = 0x1000
        asm.addi(1, 1, -2048),       # x1 = 0x800 (delegate exception code 11)
        asm.csrrw(0, 0x302, 1),      # medeleg = x1
        asm.addi(2, 0, 5),           # x2 = 5
        asm.ecall,                   # delegated trap
        asm.addi(2, 2, 1),           # executes after sret
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(4, 0x142, 0),      # x4 = scause
        asm.csrrs(3, 0x141, 0),      # x3 = sepc
        asm.addi(3, 3, 4),           # resume at next instruction
        asm.csrrw(0, 0x141, 3),      # sepc = x3
        asm.sret,
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x300)
      cpu.reset!
      cpu.run_cycles(56)

      expect(cpu.read_reg(2)).to eq(6)
      expect(cpu.read_reg(3)).to eq(36)
      expect(cpu.read_reg(4)).to eq(11)
    end

    it 'delegates illegal SYSTEM trap to stvec and writes stval' do
      illegal_inst = 0x10600073
      main_program = [
        asm.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x105, 1),      # stvec = x1
        asm.addi(1, 0, 0x4),         # x1 = delegate exception code 2
        asm.csrrw(0, 0x302, 1),      # medeleg = x1
        asm.addi(2, 0, 9),           # x2 = 9
        illegal_inst,                # delegated illegal SYSTEM trap
        asm.addi(2, 2, 1),           # executes after sret
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(4, 0x142, 0),      # x4 = scause
        asm.csrrs(3, 0x141, 0),      # x3 = sepc
        asm.csrrs(5, 0x143, 0),      # x5 = stval
        asm.addi(3, 3, 4),           # resume at next instruction
        asm.csrrw(0, 0x141, 3),      # sepc = x3
        asm.sret,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x300)
      cpu.reset!
      cpu.run_cycles(72)

      expect(cpu.read_reg(2)).to eq(10)
      expect(cpu.read_reg(3)).to eq(32)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(5)).to eq(illegal_inst)
    end

    it 'delegates machine timer interrupt to stvec when mideleg and sstatus/sie enable it' do
      main_program = [
        asm.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x105, 1),      # stvec = x1
        asm.addi(1, 0, 0x80),        # x1 = MTIP bit
        asm.csrrw(0, 0x303, 1),      # mideleg = MTIP
        asm.csrrw(0, 0x104, 1),      # sie = MTIE
        asm.addi(1, 0, 0x2),         # x1 = sstatus.SIE
        asm.csrrw(0, 0x100, 1),      # sstatus = SIE
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x142, 0),      # x2 = scause
        asm.csrrs(4, 0x100, 0),      # x4 = sstatus in handler
        asm.jal(0, 0),
        asm.nop,
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x300)
      cpu.reset!
      cpu.run_cycles(30)
      cpu.set_interrupts(timer: 1)   # assert MTIP
      cpu.run_cycles(24)

      expect(cpu.read_reg(2)).to eq(0x80000005)
      expect(cpu.read_reg(4)).to eq(0x120)
    end

    it 'takes machine external interrupt from PLIC source when enabled' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1

        asm.lui(5, 0xC000),          # x5 = 0x0C000000 (PLIC base)
        asm.addi(6, 0, 1),           # x6 = source id/enable value
        asm.sw(6, 5, 4),             # priority[1] = 1

        asm.lui(7, 0xC002),          # x7 = 0x0C002000 (enable)
        asm.addi(11, 0, 2),          # x11 = bit 1 set
        asm.sw(11, 7, 0),            # enable source 1

        asm.lui(8, 0xC200),          # x8 = 0x0C200000 (threshold/claim)
        asm.sw(0, 8, 0),             # threshold = 0

        asm.lui(9, 0x1),             # x9 = 0x1000
        asm.addi(9, 9, -2048),       # x9 = 0x800 (MEIE)
        asm.csrrw(0, 0x304, 9),      # mie = MEIE

        asm.addi(1, 0, 0x8),         # x1 = MIE
        asm.csrrw(0, 0x300, 1),      # mstatus = MIE
        asm.nop,
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x342, 0),      # x2 = mcause
        asm.lui(10, 0xC200),         # x10 = 0x0C200000
        asm.lw(3, 10, 4),            # x3 = claim id
        asm.sw(3, 10, 4),            # complete claim id
        asm.jal(0, 0),
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(40)
      cpu.set_plic_sources(source1: 1)
      cpu.run_cycles(30)

      expect(cpu.read_reg(2)).to eq(0x8000000B)
    end

    it 'takes machine external interrupt from UART RX via PLIC source 10 when enabled' do
      main_program = [
        asm.addi(1, 0, 0x200),       # x1 = trap handler base
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),      # mtvec = x1

        asm.lui(5, 0xC000),          # x5 = 0x0C000000 (PLIC base)
        asm.addi(6, 0, 1),
        asm.sw(6, 5, 40),            # priority[10] = 1

        asm.lui(7, 0xC002),          # x7 = 0x0C002000 (enable)
        asm.addi(11, 0, 1024),       # x11 = bit 10 set
        asm.sw(11, 7, 0),            # enable source 10

        asm.lui(8, 0xC200),          # x8 = 0x0C200000 (threshold/claim)
        asm.sw(0, 8, 0),             # threshold = 0

        asm.lui(12, 0x10000),        # x12 = 0x10000000 (UART)
        asm.addi(13, 0, 1),
        asm.sb(13, 12, 1),           # UART IER = RX interrupt enable

        asm.lui(9, 0x1),             # x9 = 0x1000
        asm.addi(9, 9, -2048),       # x9 = 0x800 (MEIE)
        asm.csrrw(0, 0x304, 9),      # mie = MEIE

        asm.addi(1, 0, 0x8),         # x1 = MIE
        asm.csrrw(0, 0x300, 1),      # mstatus = MIE
        asm.nop,
        asm.nop
      ]

      trap_handler = [
        asm.csrrs(2, 0x342, 0),      # x2 = mcause
        asm.jal(0, 0),
        asm.nop
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(54)
      cpu.uart_receive_byte(0x41)
      cpu.run_cycles(36)

      expect(cpu.read_reg(2)).to eq(0x8000000B)
    end
  end

  describe 'UART MMIO' do
    it 'emits bytes when writing THR' do
      program = [
        asm.lui(1, 0x10000),     # x1 = 0x10000000
        asm.addi(2, 0, 0x41),    # 'A'
        asm.nop,
        asm.nop,
        asm.sb(2, 1, 0),         # THR = 'A'
        asm.addi(2, 0, 0x42),    # 'B'
        asm.sb(2, 1, 0),         # THR = 'B'
        asm.nop,
        asm.nop,
        asm.nop
      ]

      run_and_drain(program)
      expect(cpu.uart_tx_bytes).to eq([0x41, 0x42])
    end
  end

  describe 'Complex Programs' do
    it 'computes factorial of 5' do
      # result = 1; for i = 5 downto 1: result *= i
      # x1 = i, x2 = result
      program = [
        asm.addi(1, 0, 5),      # x1 = 5
        asm.addi(2, 0, 1),      # x2 = 1
        asm.nop,
        # loop:
        asm.beq(1, 0, 16),      # if i == 0, exit
        asm.mul(2, 2, 1),       # result *= i
        asm.addi(1, 1, -1),     # i--
        asm.jal(0, -12),        # back to loop
        # exit:
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop
      ]
      run_and_drain(program, 80)
      expect(cpu.read_reg(2)).to eq(120)
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
