# RV32C extension regression tests for single-cycle and pipelined cores.

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe 'RISC-V RV32C extension', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  describe RHDL::Examples::RISCV::IRHarness do
    let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

    before do
      skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
      cpu.reset!
    end

    it 'executes mixed-width streams with correct PC progression' do
      program = asm.pack_mixed([
        asm.c_li(1, 5),        # x1 = 5, PC += 2
        asm.addi(1, 1, 7),     # x1 = 12, PC += 4
        asm.c_addi(1, -2),     # x1 = 10, PC += 2
        asm.c_mv(2, 1)         # x2 = x1, PC += 2
      ])

      cpu.load_program(program)
      cpu.reset!

      expect(cpu.read_pc).to eq(0)
      cpu.clock_cycle
      expect(cpu.read_pc).to eq(2)
      cpu.clock_cycle
      expect(cpu.read_pc).to eq(6)
      cpu.clock_cycle
      expect(cpu.read_pc).to eq(8)
      cpu.clock_cycle
      expect(cpu.read_pc).to eq(10)

      expect(cpu.read_reg(1)).to eq(10)
      expect(cpu.read_reg(2)).to eq(10)
    end

    it 'executes compressed control flow with mixed-width targets' do
      program = asm.pack_mixed([
        asm.c_li(1, 1),        # 0x0000
        asm.c_j(8),            # 0x0002 -> jump to 0x000A
        asm.c_li(1, 9),        # 0x0004 (skipped)
        asm.addi(3, 0, 33),    # 0x0006 (skipped)
        asm.c_li(2, 7)         # 0x000A
      ])

      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(4)

      expect(cpu.read_reg(1)).to eq(1)
      expect(cpu.read_reg(2)).to eq(7)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'raises illegal-instruction trap for invalid compressed encodings' do
      program = asm.pack_mixed([
        asm.c_raw(0x4005) # Reserved C.LI form (rd=x0) => illegal instruction trap
      ])

      cpu.load_program(program)
      cpu.reset!
      cpu.clock_cycle
      expect(cpu.read_pc).to eq(0)
      cpu.clock_cycle

      # mtvec defaults to 0, so illegal instruction traps back to PC 0.
      expect(cpu.read_pc).to eq(0)
    end
  end

  describe RHDL::Examples::RISCV::Pipeline::IRHarness do
    let(:cpu) { described_class.new('test_cpu', backend: :jit, allow_fallback: false) }

    before do
      skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
      cpu.reset!
    end

    def run_and_drain(program, extra_cycles = 0)
      cpu.load_program(program)
      cpu.reset!
      cpu.run_cycles(16 + extra_cycles)
    end

    it 'executes mixed-width compressed and base instructions' do
      program = asm.pack_mixed([
        asm.c_li(1, 3),
        asm.addi(1, 1, 4),
        asm.c_addi(1, 5),
        asm.c_mv(2, 1)
      ])

      run_and_drain(program, 8)

      expect(cpu.read_reg(1)).to eq(12)
      expect(cpu.read_reg(2)).to eq(12)
    end

    it 'handles compressed jumps and flushes wrong-path work' do
      program = asm.pack_mixed([
        asm.c_li(1, 1),        # 0x0000
        asm.c_j(8),            # 0x0002 -> jump to 0x000A
        asm.c_addi(1, 9),      # 0x0004 (wrong path)
        asm.addi(3, 0, 99),    # 0x0006 (wrong path)
        asm.c_addi(1, 2),      # 0x000A
        asm.c_mv(2, 1)
      ])

      run_and_drain(program, 12)

      expect(cpu.read_reg(1)).to eq(3)
      expect(cpu.read_reg(2)).to eq(3)
      expect(cpu.read_reg(3)).to eq(0)
    end

    it 'raises illegal-instruction trap for invalid compressed encodings' do
      program = asm.pack_mixed([
        asm.c_raw(0x4005),
        asm.c_li(1, 7)
      ])

      run_and_drain(program, 8)

      # Illegal trap at PC 0 prevents the following instruction from committing.
      expect(cpu.read_reg(1)).to eq(0)
    end
  end
end
