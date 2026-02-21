require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe 'RV32F minimal subset (single-cycle + pipeline)', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }
  let(:single) { RHDL::Examples::RISCV::IRHarness.new(mem_size: 4096, backend: :jit, allow_fallback: false) }
  let(:pipe) { RHDL::Examples::RISCV::Pipeline::IRHarness.new('rv32f_pipe', backend: :jit, allow_fallback: false) }

  before do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
    single.reset!
    pipe.reset!
  end

  describe 'single-cycle core' do
    it 'supports flw/fsw and fmv.x.w data movement' do
      word = 0x4040_0000 # 3.0f
      single.write_data_word(0x100, word)

      program = [
        asm.addi(1, 0, 0x100),
        asm.flw(1, 1, 0),
        asm.fmv_x_w(2, 1),
        asm.fsw(1, 1, 4)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(2)).to eq(word)
      expect(single.read_data_word(0x104)).to eq(word)
    end

    it 'supports fmv.w.x and fcsr csr round-trip' do
      program = [
        asm.lui(1, 0x3F800),      # 1.0f as raw bits
        asm.fmv_w_x(2, 1),
        asm.fmv_x_w(3, 2),
        asm.addi(4, 0, 0x55),
        asm.csrrw(0, 0x003, 4),
        asm.csrrs(5, 0x003, 0)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(3)).to eq(0x3F80_0000)
      expect(single.read_reg(5)).to eq(0x55)
    end
  end

  describe 'pipelined core' do
    def run_pipe(program, extra_cycles = 0)
      pipe.load_program(program)
      pipe.reset!
      pipe.run_cycles(program.length + 8 + extra_cycles)
    end

    it 'supports flw/fsw and fmv.x.w data movement' do
      word = 0x3FC0_0000 # 1.5f
      pipe.write_data(0x100, word)

      program = [
        asm.addi(1, 0, 0x100),
        asm.nop,
        asm.nop,
        asm.flw(1, 1, 0),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(2, 1),
        asm.nop,
        asm.nop,
        asm.fsw(1, 1, 4)
      ]

      run_pipe(program)

      expect(pipe.read_reg(2)).to eq(word)
      expect(pipe.read_data(0x104)).to eq(word)
    end

    it 'supports fmv.w.x and fcsr csr round-trip' do
      program = [
        asm.lui(1, 0x40000),
        asm.nop,
        asm.nop,
        asm.fmv_w_x(2, 1),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(3, 2),
        asm.addi(4, 0, 0x2A),
        asm.csrrw(0, 0x003, 4),
        asm.csrrs(5, 0x003, 0)
      ]

      run_pipe(program)

      expect(pipe.read_reg(3)).to eq(0x4000_0000)
      expect(pipe.read_reg(5)).to eq(0x2A)
    end
  end
end
