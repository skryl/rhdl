# RV32I CPU Tests
# Tests the RISC-V single-cycle CPU implementation using the IR JIT harness

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/constants'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  describe 'Reset behavior' do
    it 'sets PC to reset vector after reset' do
      expect(cpu.read_pc).to eq(0)
    end

    it 'clears registers on reset' do
      (0..31).each do |i|
        expect(cpu.read_reg(i)).to eq(0)
      end
    end
  end

  describe 'ADDI instruction' do
    it 'adds immediate to register' do
      # addi x1, x0, 42
      program = [RHDL::Examples::RISCV::Assembler.addi(1, 0, 42)]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_reg(1)).to eq(42)
    end

    it 'handles negative immediates' do
      # addi x1, x0, -10
      program = [RHDL::Examples::RISCV::Assembler.addi(1, 0, -10)]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_reg(1)).to eq(0xFFFFFFF6)
    end

    it 'adds to non-zero register' do
      # addi x1, x0, 10
      # addi x2, x1, 5
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 10),
        RHDL::Examples::RISCV::Assembler.addi(2, 1, 5)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(1)).to eq(10)
      expect(cpu.read_reg(2)).to eq(15)
    end
  end

  describe 'XORI/ORI/ANDI instructions' do
    it 'performs bitwise XOR with immediate' do
      # addi x1, x0, 0x0F
      # xori x2, x1, -1     ; 0x0000000F ^ 0xFFFFFFFF = 0xFFFFFFF0
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x0F),
        RHDL::Examples::RISCV::Assembler.xori(2, 1, -1)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(0xFFFFFFF0)
    end

    it 'performs bitwise OR with immediate' do
      # addi x1, x0, 0xF0
      # ori x2, x1, 0x0F
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0xF0),
        RHDL::Examples::RISCV::Assembler.ori(2, 1, 0x0F)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(0xFF)
    end

    it 'performs bitwise AND with immediate' do
      # addi x1, x0, 0xFF
      # andi x2, x1, 0x0F
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0xFF),
        RHDL::Examples::RISCV::Assembler.andi(2, 1, 0x0F)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(0x0F)
    end
  end

  describe 'LUI instruction' do
    it 'loads upper immediate' do
      # lui x1, 0x12345
      program = [RHDL::Examples::RISCV::Assembler.lui(1, 0x12345)]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_reg(1)).to eq(0x12345000)
    end
  end

  describe 'AUIPC instruction' do
    it 'adds upper immediate to PC' do
      # auipc x1, 1
      program = [RHDL::Examples::RISCV::Assembler.auipc(1, 1)]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_reg(1)).to eq(0x1000)  # PC(0) + 0x1000
    end
  end

  describe 'ADD instruction' do
    it 'adds two registers' do
      # addi x1, x0, 10
      # addi x2, x0, 20
      # add x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 10),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 20),
        RHDL::Examples::RISCV::Assembler.add(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(30)
    end
  end

  describe 'SUB instruction' do
    it 'subtracts two registers' do
      # addi x1, x0, 30
      # addi x2, x0, 10
      # sub x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 30),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 10),
        RHDL::Examples::RISCV::Assembler.sub(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(20)
    end
  end

  describe 'M-extension instructions' do
    it 'executes MUL/MULH/MULHSU/MULHU instructions' do
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -2),   # x1 = 0xFFFFFFFE
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 3),    # x2 = 3
        RHDL::Examples::RISCV::Assembler.addi(6, 0, -1),   # x6 = 0xFFFFFFFF
        RHDL::Examples::RISCV::Assembler.addi(7, 0, 2),    # x7 = 2
        RHDL::Examples::RISCV::Assembler.mul(3, 1, 2),     # low 32 bits = 0xFFFFFFFA
        RHDL::Examples::RISCV::Assembler.mulh(4, 1, 2),    # high signed = 0xFFFFFFFF
        RHDL::Examples::RISCV::Assembler.mulhsu(5, 1, 2),  # high signed/unsigned = 0xFFFFFFFF
        RHDL::Examples::RISCV::Assembler.mulhu(8, 6, 7)    # high unsigned = 0x00000001
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(program.length)
      expect(cpu.read_reg(3)).to eq(0xFFFFFFFA)
      expect(cpu.read_reg(4)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(5)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(8)).to eq(0x00000001)
    end

    it 'executes DIV/DIVU/REM/REMU instructions' do
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -20),  # x1 = -20
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 3),    # x2 = 3
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 20),   # x3 = 20
        RHDL::Examples::RISCV::Assembler.div(4, 1, 2),     # -20 / 3 = -6 (toward zero)
        RHDL::Examples::RISCV::Assembler.rem(5, 1, 2),     # -20 % 3 = -2
        RHDL::Examples::RISCV::Assembler.divu(6, 3, 2),    # 20 / 3 = 6
        RHDL::Examples::RISCV::Assembler.remu(7, 3, 2)     # 20 % 3 = 2
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(program.length)
      expect(cpu.read_reg(4)).to eq(0xFFFFFFFA)
      expect(cpu.read_reg(5)).to eq(0xFFFFFFFE)
      expect(cpu.read_reg(6)).to eq(6)
      expect(cpu.read_reg(7)).to eq(2)
    end

    it 'handles divide-by-zero and signed overflow cases per RV32M spec' do
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 7),      # x1 = 7
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0),      # x2 = 0
        RHDL::Examples::RISCV::Assembler.div(3, 1, 2),       # div by zero => -1
        RHDL::Examples::RISCV::Assembler.divu(4, 1, 2),      # divu by zero => 0xFFFFFFFF
        RHDL::Examples::RISCV::Assembler.rem(5, 1, 2),       # rem by zero => dividend
        RHDL::Examples::RISCV::Assembler.remu(6, 1, 2),      # remu by zero => dividend
        RHDL::Examples::RISCV::Assembler.lui(7, 0x80000),    # x7 = 0x80000000
        RHDL::Examples::RISCV::Assembler.addi(8, 0, -1),     # x8 = 0xFFFFFFFF
        RHDL::Examples::RISCV::Assembler.div(9, 7, 8),       # overflow => 0x80000000
        RHDL::Examples::RISCV::Assembler.rem(10, 7, 8)       # overflow => 0
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(program.length)
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
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x40),        # x1 = 0x40
        RHDL::Examples::RISCV::Assembler.csrrw(2, 0x305, 1),      # x2 = old mtvec (0), mtvec = 0x40
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x305, 0)       # x3 = mtvec
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(program.length)
      expect(cpu.read_reg(2)).to eq(0)
      expect(cpu.read_reg(3)).to eq(0x40)
    end

    it 'executes CSRRSI/CSRRCI bit operations' do
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0b1010),
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = 0b1010
        RHDL::Examples::RISCV::Assembler.csrrsi(2, 0x300, 0b0101),# x2=0b1010, mstatus=0b1111
        RHDL::Examples::RISCV::Assembler.csrrci(3, 0x300, 0b0011),# x3=0b1111, mstatus=0b1100
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x300, 0)       # x4=0b1100
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(program.length)
      expect(cpu.read_reg(2)).to eq(0b1010)
      expect(cpu.read_reg(3)).to eq(0b1111)
      expect(cpu.read_reg(4)).to eq(0b1100)
    end
  end

  describe 'AND/OR/XOR instructions' do
    it 'performs bitwise AND' do
      # addi x1, x0, 0xFF
      # addi x2, x0, 0x0F
      # and x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0xFF),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x0F),
        RHDL::Examples::RISCV::Assembler.and(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(0x0F)
    end

    it 'performs bitwise OR' do
      # addi x1, x0, 0xF0
      # addi x2, x0, 0x0F
      # or x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0xF0),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x0F),
        RHDL::Examples::RISCV::Assembler.or(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(0xFF)
    end

    it 'performs bitwise XOR' do
      # addi x1, x0, 0xFF
      # addi x2, x0, 0x0F
      # xor x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0xFF),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x0F),
        RHDL::Examples::RISCV::Assembler.xor(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(0xF0)
    end
  end

  describe 'Shift instructions' do
    it 'performs shift left logical' do
      # addi x1, x0, 1
      # slli x2, x1, 4
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 1),
        RHDL::Examples::RISCV::Assembler.slli(2, 1, 4)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(16)
    end

    it 'performs shift right logical' do
      # addi x1, x0, 128
      # srli x2, x1, 3
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 128),
        RHDL::Examples::RISCV::Assembler.srli(2, 1, 3)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(16)
    end

    it 'performs shift right arithmetic' do
      # lui x1, 0xFFFFF  ; Load -4096 (0xFFFFF000)
      # srai x2, x1, 4
      program = [
        RHDL::Examples::RISCV::Assembler.lui(1, 0xFFFFF),
        RHDL::Examples::RISCV::Assembler.srai(2, 1, 4)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      # 0xFFFFF000 >> 4 with sign extension = 0xFFFFFF00
      expect(cpu.read_reg(2)).to eq(0xFFFFFF00)
    end

    it 'performs register shift left logical' do
      # addi x1, x0, 1
      # addi x2, x0, 4
      # sll x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 4),
        RHDL::Examples::RISCV::Assembler.sll(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(16)
    end

    it 'performs register shift right logical' do
      # addi x1, x0, 128
      # addi x2, x0, 3
      # srl x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 128),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 3),
        RHDL::Examples::RISCV::Assembler.srl(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(16)
    end

    it 'performs register shift right arithmetic' do
      # lui x1, 0xFFFFF      ; x1 = 0xFFFFF000
      # addi x2, x0, 4
      # sra x3, x1, x2
      program = [
        RHDL::Examples::RISCV::Assembler.lui(1, 0xFFFFF),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 4),
        RHDL::Examples::RISCV::Assembler.sra(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(0xFFFFFF00)
    end
  end

  describe 'SLT/SLTU instructions' do
    it 'sets less than (signed)' do
      # addi x1, x0, -1    ; x1 = 0xFFFFFFFF (-1 signed)
      # addi x2, x0, 1     ; x2 = 1
      # slt x3, x1, x2     ; x3 = 1 (because -1 < 1)
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 1),
        RHDL::Examples::RISCV::Assembler.slt(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(1)
    end

    it 'sets less than unsigned' do
      # addi x1, x0, -1    ; x1 = 0xFFFFFFFF (large unsigned)
      # addi x2, x0, 1     ; x2 = 1
      # sltu x3, x1, x2    ; x3 = 0 (because 0xFFFFFFFF > 1 unsigned)
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 1),
        RHDL::Examples::RISCV::Assembler.sltu(3, 1, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)
      expect(cpu.read_reg(3)).to eq(0)
    end
  end

  describe 'SLTI/SLTIU instructions' do
    it 'sets less than immediate (signed)' do
      # addi x1, x0, -1
      # slti x2, x1, 1     ; -1 < 1 => 1
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.slti(2, 1, 1)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(1)
    end

    it 'sets less than immediate (unsigned)' do
      # addi x1, x0, -1
      # sltiu x2, x1, 1    ; 0xFFFFFFFF < 1 => 0
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.sltiu(2, 1, 1)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(2)
      expect(cpu.read_reg(2)).to eq(0)
    end
  end

  describe 'JAL instruction' do
    it 'jumps and links' do
      # jal x1, 8          ; Jump to PC+8, save return address in x1
      # addi x2, x0, 1     ; Skipped
      # addi x3, x0, 2     ; Target of jump
      program = [
        RHDL::Examples::RISCV::Assembler.jal(1, 8),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_pc).to eq(8)  # Jumped to offset 8
      expect(cpu.read_reg(1)).to eq(4)  # Return address is PC+4
      cpu.clock_cycle
      expect(cpu.read_reg(3)).to eq(2)  # Executed instruction at offset 8
      expect(cpu.read_reg(2)).to eq(0)  # Skipped instruction at offset 4
    end
  end

  describe 'JALR instruction' do
    it 'jumps to register + offset' do
      # addi x1, x0, 8     ; x1 = 8
      # jalr x2, x1, 4     ; Jump to x1+4 = 12, save PC+4 in x2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 8),
        RHDL::Examples::RISCV::Assembler.jalr(2, 1, 4),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),  # Skipped
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)   # Target
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle  # addi
      cpu.clock_cycle  # jalr
      expect(cpu.read_pc).to eq(12)  # Jumped to x1+4 = 12
      expect(cpu.read_reg(2)).to eq(8)  # Return address is PC+4 of jalr
    end
  end

  describe 'Branch instructions' do
    it 'branches on equal' do
      # addi x1, x0, 5
      # addi x2, x0, 5
      # beq x1, x2, 8      ; Branch to PC+8 if x1 == x2
      # addi x3, x0, 1     ; Skipped
      # addi x4, x0, 2     ; Target
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 5),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 5),
        RHDL::Examples::RISCV::Assembler.beq(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(3)  # addi, addi, beq
      expect(cpu.read_pc).to eq(16)  # Branched to PC+8 (from PC=8)
      cpu.clock_cycle
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(3)).to eq(0)  # Skipped
    end

    it 'does not branch when not equal' do
      # addi x1, x0, 5
      # addi x2, x0, 10
      # beq x1, x2, 8      ; Don't branch
      # addi x3, x0, 1     ; Executed
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 5),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 10),
        RHDL::Examples::RISCV::Assembler.beq(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(3)).to eq(1)  # Executed
    end

    it 'branches on not equal' do
      # addi x1, x0, 5
      # addi x2, x0, 10
      # bne x1, x2, 8
      # addi x3, x0, 1
      # addi x4, x0, 2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 5),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 10),
        RHDL::Examples::RISCV::Assembler.bne(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'branches on less than (signed)' do
      # addi x1, x0, -1    ; x1 = -1
      # addi x2, x0, 1     ; x2 = 1
      # blt x1, x2, 8      ; Branch because -1 < 1
      # addi x3, x0, 1
      # addi x4, x0, 2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 1),
        RHDL::Examples::RISCV::Assembler.blt(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'branches on greater than or equal (signed)' do
      # addi x1, x0, 1
      # addi x2, x0, -1
      # bge x1, x2, 8      ; Branch because 1 >= -1 (signed)
      # addi x3, x0, 1
      # addi x4, x0, 2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, -1),
        RHDL::Examples::RISCV::Assembler.bge(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'branches on less than (unsigned)' do
      # addi x1, x0, 1
      # addi x2, x0, -1    ; 0xFFFFFFFF unsigned
      # bltu x1, x2, 8     ; Branch because 1 < 0xFFFFFFFF (unsigned)
      # addi x3, x0, 1
      # addi x4, x0, 2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, -1),
        RHDL::Examples::RISCV::Assembler.bltu(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'branches on greater than or equal (unsigned)' do
      # addi x1, x0, -1    ; 0xFFFFFFFF unsigned
      # addi x2, x0, 1
      # bgeu x1, x2, 8     ; Branch because 0xFFFFFFFF >= 1 (unsigned)
      # addi x3, x0, 1
      # addi x4, x0, 2
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 1),
        RHDL::Examples::RISCV::Assembler.bgeu(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.addi(3, 0, 1),
        RHDL::Examples::RISCV::Assembler.addi(4, 0, 2)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(3)).to eq(0)
    end
  end

  describe 'Load/Store instructions' do
    it 'stores and loads a word' do
      # addi x1, x0, 0x42  ; Value to store
      # addi x2, x0, 0x100 ; Address
      # sw x1, 0(x2)       ; Store x1 at address 0x100
      # lw x3, 0(x2)       ; Load from address 0x100
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x42),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x100),
        RHDL::Examples::RISCV::Assembler.sw(1, 2, 0),
        RHDL::Examples::RISCV::Assembler.lw(3, 2, 0)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(3)).to eq(0x42)
    end

    it 'stores and loads with offset' do
      # addi x1, x0, 0x55
      # addi x2, x0, 0x100
      # sw x1, 8(x2)       ; Store at 0x108
      # lw x3, 8(x2)       ; Load from 0x108
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x55),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x100),
        RHDL::Examples::RISCV::Assembler.sw(1, 2, 8),
        RHDL::Examples::RISCV::Assembler.lw(3, 2, 8)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)
      expect(cpu.read_reg(3)).to eq(0x55)
    end

    it 'stores and loads bytes' do
      # addi x1, x0, 0xAB
      # addi x2, x0, 0x100
      # sb x1, 0(x2)
      # lb x3, 0(x2)       ; Should sign-extend
      # lbu x4, 0(x2)      ; Should zero-extend
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0xAB),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x100),
        RHDL::Examples::RISCV::Assembler.sb(1, 2, 0),
        RHDL::Examples::RISCV::Assembler.lb(3, 2, 0),
        RHDL::Examples::RISCV::Assembler.lbu(4, 2, 0)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(5)
      expect(cpu.read_reg(3)).to eq(0xFFFFFFAB)  # Sign-extended
      expect(cpu.read_reg(4)).to eq(0xAB)        # Zero-extended
    end

    it 'stores and loads halfwords' do
      # addi x1, x0, -1
      # addi x2, x0, 0x100
      # sh x1, 0(x2)
      # lh x3, 0(x2)       ; Should sign-extend to 0xFFFFFFFF
      # lhu x4, 0(x2)      ; Should zero-extend to 0x0000FFFF
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, -1),
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x100),
        RHDL::Examples::RISCV::Assembler.sh(1, 2, 0),
        RHDL::Examples::RISCV::Assembler.lh(3, 2, 0),
        RHDL::Examples::RISCV::Assembler.lhu(4, 2, 0)
      ]
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(5)
      expect(cpu.read_reg(3)).to eq(0xFFFFFFFF)
      expect(cpu.read_reg(4)).to eq(0x0000FFFF)
    end
  end

  describe 'SYSTEM/MISC_MEM instructions' do
    it 'treats FENCE as a non-trapping no-op' do
      program = [
        RHDL::Examples::RISCV::Assembler.addi(10, 0, 0x200),
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 5),
        RHDL::Examples::RISCV::Assembler.sw(1, 10, 0),
        RHDL::Examples::RISCV::Assembler.fence,
        RHDL::Examples::RISCV::Assembler.addi(2, 1, 7),
        RHDL::Examples::RISCV::Assembler.lw(3, 10, 0)
      ]

      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(program.length)

      expect(cpu.read_reg(1)).to eq(5)
      expect(cpu.read_reg(2)).to eq(12)
      expect(cpu.read_reg(3)).to eq(5)
      expect(cpu.read_reg(0)).to eq(0)
      expect(cpu.read_data_word(0x200)).to eq(5)
    end

    it 'traps on ECALL to mtvec and returns with MRET' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 7),           # x2 = 7
        RHDL::Examples::RISCV::Assembler.ecall,                   # trap
        RHDL::Examples::RISCV::Assembler.addi(2, 2, 1),           # executes after mret
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x342, 0),      # x4 = mcause
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x341, 0),      # x3 = mepc
        RHDL::Examples::RISCV::Assembler.csrrs(5, 0x343, 0),      # x5 = mtval
        RHDL::Examples::RISCV::Assembler.addi(3, 3, 4),           # resume at next instruction
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x341, 3),      # mepc = x3
        RHDL::Examples::RISCV::Assembler.mret
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(12)

      expect(cpu.read_reg(2)).to eq(8)
      expect(cpu.read_reg(3)).to eq(16)
      expect(cpu.read_reg(4)).to eq(11)
    end

    it 'updates mstatus trap-stack bits on ECALL and MRET' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MIE bit set
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = 0x8
        RHDL::Examples::RISCV::Assembler.ecall,                   # trap
        RHDL::Examples::RISCV::Assembler.csrrs(10, 0x300, 0),     # x10 = mstatus after mret
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x300, 0),      # x2 = mstatus during trap
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x341, 0),      # x3 = mepc
        RHDL::Examples::RISCV::Assembler.addi(3, 3, 4),           # resume at next instruction
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x341, 3),      # mepc = x3
        RHDL::Examples::RISCV::Assembler.mret
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(14)

      expect(cpu.read_reg(2)).to eq(0x1880)  # trap: MPP=3, MPIE=1, MIE=0
      expect(cpu.read_reg(3)).to eq(20)
      expect(cpu.read_reg(10)).to eq(0x88)   # after mret: MPP=0, MPIE=1, MIE=1
    end

    it 'traps on EBREAK to mtvec and returns with MRET' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 9),           # x2 = 9
        RHDL::Examples::RISCV::Assembler.ebreak,                  # trap
        RHDL::Examples::RISCV::Assembler.addi(2, 2, 2),           # executes after mret
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x342, 0),      # x4 = mcause
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x341, 0),      # x3 = mepc
        RHDL::Examples::RISCV::Assembler.csrrs(5, 0x343, 0),      # x5 = mtval
        RHDL::Examples::RISCV::Assembler.addi(3, 3, 4),           # resume at next instruction
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x341, 3),      # mepc = x3
        RHDL::Examples::RISCV::Assembler.mret
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(12)

      expect(cpu.read_reg(2)).to eq(11)
      expect(cpu.read_reg(3)).to eq(16)
      expect(cpu.read_reg(4)).to eq(3)
    end

    it 'traps on illegal SYSTEM instruction with mcause=2 and returns with MRET' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        0x10600073,                                                # unknown SYSTEM funct12 => illegal instruction
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 1),           # executes after mret
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x342, 0),      # x4 = mcause
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x341, 0),      # x3 = mepc
        RHDL::Examples::RISCV::Assembler.csrrs(5, 0x343, 0),      # x5 = mtval
        RHDL::Examples::RISCV::Assembler.addi(3, 3, 4),           # resume at next instruction
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x341, 3),      # mepc = x3
        RHDL::Examples::RISCV::Assembler.mret
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(12)

      expect(cpu.read_reg(2)).to eq(1)
      expect(cpu.read_reg(3)).to eq(12)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(5)).to eq(0x10600073)
    end

    it 'takes machine timer interrupt when enabled' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x80),        # x1 = MTIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x304, 1),      # mie = MTIE
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = MIE
        RHDL::Examples::RISCV::Assembler.nop,
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x342, 0),      # x2 = mcause
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x300, 0),      # x4 = mstatus in handler
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(8)               # setup
      cpu.set_interrupts(timer: 1)    # assert MTIP
      cpu.run_cycles(6)

      expect(cpu.read_reg(2)).to eq(0x80000007)
      expect(cpu.read_reg(4)).to eq(0x1880)
    end

    it 'takes machine timer interrupt from CLINT mtimecmp when enabled' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        RHDL::Examples::RISCV::Assembler.lui(5, 0x2004),          # x5 = 0x02004000 (mtimecmp)
        RHDL::Examples::RISCV::Assembler.addi(6, 0, 20),          # mtimecmp low threshold
        RHDL::Examples::RISCV::Assembler.sw(6, 5, 0),             # mtimecmp low
        RHDL::Examples::RISCV::Assembler.sw(0, 5, 4),             # mtimecmp high = 0
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x80),        # x1 = MTIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x304, 1),      # mie = MTIE
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = MIE
        RHDL::Examples::RISCV::Assembler.nop,
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x342, 0),      # x2 = mcause
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x300, 0),      # x4 = mstatus in handler
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
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
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1
        RHDL::Examples::RISCV::Assembler.lui(5, 0x2000),          # x5 = 0x02000000 (msip)
        RHDL::Examples::RISCV::Assembler.addi(6, 0, 1),           # msip set value
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MSIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x304, 1),      # mie = MSIE
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = MIE
        RHDL::Examples::RISCV::Assembler.sw(6, 5, 0),             # msip = 1
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x342, 0),      # x2 = mcause
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x300, 0),      # x4 = mstatus in handler
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(40)

      expect(cpu.read_reg(2)).to eq(0x80000003)
      expect(cpu.read_reg(4)).to eq(0x1880)
    end

    it 'delegates ECALL to stvec and returns with SRET' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x105, 1),      # stvec = x1
        RHDL::Examples::RISCV::Assembler.lui(1, 0x1),             # x1 = 0x1000
        RHDL::Examples::RISCV::Assembler.addi(1, 1, -2048),       # x1 = 0x800 (delegate exception code 11)
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x302, 1),      # medeleg = x1
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 5),           # x2 = 5
        RHDL::Examples::RISCV::Assembler.ecall,                   # delegated trap
        RHDL::Examples::RISCV::Assembler.addi(2, 2, 1),           # executes after sret
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x142, 0),      # x4 = scause
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x141, 0),      # x3 = sepc
        RHDL::Examples::RISCV::Assembler.addi(3, 3, 4),           # resume at next instruction
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x141, 3),      # sepc = x3
        RHDL::Examples::RISCV::Assembler.sret
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x300)
      cpu.reset!
      cpu.run_cycles(20)

      expect(cpu.read_reg(2)).to eq(6)
      expect(cpu.read_reg(3)).to eq(28)
      expect(cpu.read_reg(4)).to eq(11)
    end

    it 'delegates illegal SYSTEM trap to stvec and writes stval' do
      illegal_inst = 0x10600073
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x105, 1),      # stvec = x1
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x4),         # x1 = delegate exception code 2 (illegal instruction)
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x302, 1),      # medeleg = x1
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 9),           # x2 = 9
        illegal_inst,                                              # delegated illegal SYSTEM trap
        RHDL::Examples::RISCV::Assembler.addi(2, 2, 1),           # executes after sret
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x142, 0),      # x4 = scause
        RHDL::Examples::RISCV::Assembler.csrrs(3, 0x141, 0),      # x3 = sepc
        RHDL::Examples::RISCV::Assembler.csrrs(5, 0x143, 0),      # x5 = stval
        RHDL::Examples::RISCV::Assembler.addi(3, 3, 4),           # resume at next instruction
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x141, 3),      # sepc = x3
        RHDL::Examples::RISCV::Assembler.sret
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x300)
      cpu.reset!
      cpu.run_cycles(24)

      expect(cpu.read_reg(2)).to eq(10)
      expect(cpu.read_reg(3)).to eq(24)
      expect(cpu.read_reg(4)).to eq(2)
      expect(cpu.read_reg(5)).to eq(illegal_inst)
    end

    it 'delegates machine timer interrupt to stvec when mideleg and sstatus/sie enable it' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x105, 1),      # stvec = x1
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x80),        # x1 = MTIP bit
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x303, 1),      # mideleg = MTIP
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x104, 1),      # sie = MTIE
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x2),         # x1 = sstatus.SIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x100, 1),      # sstatus = SIE
        RHDL::Examples::RISCV::Assembler.nop,
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x142, 0),      # x2 = scause
        RHDL::Examples::RISCV::Assembler.csrrs(4, 0x100, 0),      # x4 = sstatus in handler
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x300)
      cpu.reset!
      cpu.run_cycles(10)
      cpu.set_interrupts(timer: 1)    # assert MTIP
      cpu.run_cycles(8)

      expect(cpu.read_reg(2)).to eq(0x80000005)
      expect(cpu.read_reg(4)).to eq(0x120)
    end

    it 'takes machine external interrupt from PLIC source when enabled' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1

        RHDL::Examples::RISCV::Assembler.lui(5, 0xC000),          # x5 = 0x0C000000 (PLIC base)
        RHDL::Examples::RISCV::Assembler.addi(6, 0, 1),           # x6 = source id/enable value
        RHDL::Examples::RISCV::Assembler.sw(6, 5, 4),             # priority[1] = 1

        RHDL::Examples::RISCV::Assembler.lui(7, 0xC002),          # x7 = 0x0C002000 (enable)
        RHDL::Examples::RISCV::Assembler.addi(11, 0, 2),          # x11 = bit 1 set
        RHDL::Examples::RISCV::Assembler.sw(11, 7, 0),            # enable source 1

        RHDL::Examples::RISCV::Assembler.lui(8, 0xC200),          # x8 = 0x0C200000 (threshold/claim)
        RHDL::Examples::RISCV::Assembler.sw(0, 8, 0),             # threshold = 0

        RHDL::Examples::RISCV::Assembler.lui(9, 0x1),             # x9 = 0x1000
        RHDL::Examples::RISCV::Assembler.addi(9, 9, -2048),       # x9 = 0x800 (MEIE)
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x304, 9),      # mie = MEIE

        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = MIE
        RHDL::Examples::RISCV::Assembler.nop,
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x342, 0),      # x2 = mcause
        RHDL::Examples::RISCV::Assembler.lui(10, 0xC200),         # x10 = 0x0C200000
        RHDL::Examples::RISCV::Assembler.lw(3, 10, 4),            # x3 = claim id
        RHDL::Examples::RISCV::Assembler.sw(3, 10, 4),            # complete claim id
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(20)
      cpu.set_plic_sources(source1: 1)
      cpu.run_cycles(12)

      expect(cpu.read_reg(2)).to eq(0x8000000B)
    end

    it 'takes machine external interrupt from UART RX via PLIC source 10 when enabled' do
      main_program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x200),       # x1 = trap handler base
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x305, 1),      # mtvec = x1

        RHDL::Examples::RISCV::Assembler.lui(5, 0xC000),          # x5 = 0x0C000000 (PLIC base)
        RHDL::Examples::RISCV::Assembler.addi(6, 0, 1),
        RHDL::Examples::RISCV::Assembler.sw(6, 5, 40),            # priority[10] = 1

        RHDL::Examples::RISCV::Assembler.lui(7, 0xC002),          # x7 = 0x0C002000 (enable)
        RHDL::Examples::RISCV::Assembler.addi(11, 0, 1024),       # x11 = bit 10 set
        RHDL::Examples::RISCV::Assembler.sw(11, 7, 0),            # enable source 10

        RHDL::Examples::RISCV::Assembler.lui(8, 0xC200),          # x8 = 0x0C200000 (threshold/claim)
        RHDL::Examples::RISCV::Assembler.sw(0, 8, 0),             # threshold = 0

        RHDL::Examples::RISCV::Assembler.lui(12, 0x10000),        # x12 = 0x10000000 (UART)
        RHDL::Examples::RISCV::Assembler.addi(13, 0, 1),
        RHDL::Examples::RISCV::Assembler.sb(13, 12, 1),           # UART IER = RX interrupt enable

        RHDL::Examples::RISCV::Assembler.lui(9, 0x1),             # x9 = 0x1000
        RHDL::Examples::RISCV::Assembler.addi(9, 9, -2048),       # x9 = 0x800 (MEIE)
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x304, 9),      # mie = MEIE

        RHDL::Examples::RISCV::Assembler.addi(1, 0, 0x8),         # x1 = MIE
        RHDL::Examples::RISCV::Assembler.csrrw(0, 0x300, 1),      # mstatus = MIE
        RHDL::Examples::RISCV::Assembler.nop
      ]

      trap_handler = [
        RHDL::Examples::RISCV::Assembler.csrrs(2, 0x342, 0),      # x2 = mcause
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
      ]

      cpu.load_program(main_program, 0)
      cpu.load_program(trap_handler, 0x200)
      cpu.reset!
      cpu.run_cycles(26)
      cpu.uart_receive_byte(0x41)
      cpu.run_cycles(14)

      expect(cpu.read_reg(2)).to eq(0x8000000B)
    end
  end

  describe 'UART MMIO' do
    it 'emits bytes when writing THR' do
      program = [
        RHDL::Examples::RISCV::Assembler.lui(1, 0x10000),         # x1 = 0x10000000
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x41),        # 'A'
        RHDL::Examples::RISCV::Assembler.sb(2, 1, 0),             # THR = 'A'
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0x42),        # 'B'
        RHDL::Examples::RISCV::Assembler.sb(2, 1, 0)              # THR = 'B'
      ]

      cpu.load_program(program, 0)
      cpu.reset!
      cpu.clear_uart_tx_bytes
      cpu.run_cycles(program.length + 2)

      expect(cpu.uart_tx_bytes).to eq([0x41, 0x42])
    end
  end

  describe 'x0 register' do
    it 'always reads as zero' do
      expect(cpu.read_reg(0)).to eq(0)
    end

    it 'cannot be written' do
      # addi x0, x0, 42  ; Try to write to x0
      program = [RHDL::Examples::RISCV::Assembler.addi(0, 0, 42)]
      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_reg(0)).to eq(0)
    end
  end

  describe 'Simple program: sum 1 to N' do
    it 'computes sum of 1 to 5' do
      # Sum 1+2+3+4+5 = 15
      # x1 = counter (5 down to 0)
      # x2 = sum
      program = [
        RHDL::Examples::RISCV::Assembler.addi(1, 0, 5),    # x1 = 5
        RHDL::Examples::RISCV::Assembler.addi(2, 0, 0),    # x2 = 0 (sum)
        # loop:
        RHDL::Examples::RISCV::Assembler.beq(1, 0, 12),    # if x1 == 0, exit
        RHDL::Examples::RISCV::Assembler.add(2, 2, 1),     # sum += counter
        RHDL::Examples::RISCV::Assembler.addi(1, 1, -1),   # counter--
        RHDL::Examples::RISCV::Assembler.jal(0, -12),      # jump back to loop (5 instructions * -4 = -20, but we want to go back 3 = -12)
        # exit:
        RHDL::Examples::RISCV::Assembler.nop               # Done
      ]
      cpu.load_program(program)
      cpu.reset!

      # Run until we reach the NOP (max 30 cycles to be safe)
      30.times do
        break if cpu.read_pc == 24  # Address of NOP
        cpu.clock_cycle
      end

      expect(cpu.read_reg(2)).to eq(15)  # 1+2+3+4+5 = 15
    end
  end
end
