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

    it 'supports fsgnj/fmin/fcmp/fclass subset operations' do
      program = [
        asm.lui(1, 0x3FC00),      # +1.5f (0x3FC00000)
        asm.fmv_w_x(1, 1),        # f1 = +1.5
        asm.lui(2, 0xC0000),      # -2.0f (0xC0000000)
        asm.fmv_w_x(2, 2),        # f2 = -2.0
        asm.fsgnj_s(3, 1, 2),     # f3 = -1.5
        asm.fmv_x_w(10, 3),       # x10 = bits(f3)
        asm.fmin_s(4, 1, 2),      # f4 = -2.0
        asm.fmv_x_w(11, 4),       # x11 = bits(f4)
        asm.feq_s(12, 1, 1),      # x12 = 1
        asm.flt_s(13, 2, 1),      # x13 = 1
        asm.fclass_s(14, 2)       # x14 = negative normal => bit1
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(10)).to eq(0xBFC0_0000)
      expect(single.read_reg(11)).to eq(0xC000_0000)
      expect(single.read_reg(12)).to eq(1)
      expect(single.read_reg(13)).to eq(1)
      expect(single.read_reg(14)).to eq(1 << 1)
    end

    it 'supports fcvt.s.w/fcvt.s.wu and fcvt.w.s/fcvt.wu.s conversions' do
      program = [
        asm.addi(1, 0, -7),
        asm.addi(4, 0, 42),
        asm.fcvt_s_w(1, 1),
        asm.fmv_x_w(2, 1),
        asm.fcvt_w_s(3, 1),
        asm.fcvt_s_wu(2, 4),
        asm.fmv_x_w(6, 2),
        asm.fcvt_wu_s(5, 2)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(2)).to eq(0xC0E0_0000)
      expect(single.read_reg(3)).to eq(0xFFFF_FFF9)
      expect(single.read_reg(6)).to eq(0x4228_0000)
      expect(single.read_reg(5)).to eq(42)
    end

    it 'supports fcvt.d.s -> fcvt.s.d round-trip' do
      program = [
        asm.lui(1, 0x3FC00),   # 1.5f
        asm.fmv_w_x(1, 1),
        asm.fcvt_d_s(2, 1),
        asm.fcvt_s_d(3, 2),
        asm.fmv_x_w(10, 3)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(10)).to eq(0x3FC0_0000)
    end

    it 'supports fcvt.d.w/fcvt.d.wu and fcvt.w.d/fcvt.wu.d conversions' do
      program = [
        asm.addi(1, 0, -9),
        asm.addi(2, 0, 9),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_w_d(3, 1),
        asm.fcvt_d_wu(2, 2),
        asm.fcvt_wu_d(4, 2)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(3)).to eq(0xFFFF_FFF7)
      expect(single.read_reg(4)).to eq(9)
    end

    it 'supports fclass.d classification' do
      program = [
        asm.addi(1, 0, -5),
        asm.addi(2, 0, 5),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.fclass_d(10, 1),
        asm.fclass_d(11, 2)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(10)).to eq(1 << 1)
      expect(single.read_reg(11)).to eq(1 << 6)
    end

    it 'supports fsgnj.d/fsgnjn.d/fsgnjx.d sign operations' do
      program = [
        asm.addi(1, 0, 3),
        asm.addi(2, 0, -2),
        asm.fcvt_d_w(1, 1),      # f1 = +3.0
        asm.fcvt_d_w(2, 2),      # f2 = -2.0
        asm.fsgnj_d(3, 1, 2),    # f3 = -3.0
        asm.fsgnjn_d(4, 1, 2),   # f4 = +3.0
        asm.fsgnjx_d(5, 1, 2),   # f5 = -3.0
        asm.fclass_d(10, 3),
        asm.fclass_d(11, 4),
        asm.fclass_d(12, 5)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(10)).to eq(1 << 1)
      expect(single.read_reg(11)).to eq(1 << 6)
      expect(single.read_reg(12)).to eq(1 << 1)
    end

    it 'supports fmin.d/fmax.d and feq.d/flt.d/fle.d' do
      program = [
        asm.addi(1, 0, 5),
        asm.addi(2, 0, -7),
        asm.fcvt_d_w(1, 1),      # f1 = +5.0
        asm.fcvt_d_w(2, 2),      # f2 = -7.0
        asm.fmin_d(3, 1, 2),     # f3 = -7.0
        asm.fmax_d(4, 1, 2),     # f4 = +5.0
        asm.fclass_d(13, 3),
        asm.fclass_d(14, 4),
        asm.feq_d(15, 1, 1),     # 1
        asm.flt_d(16, 2, 1),     # 1
        asm.fle_d(17, 2, 2)      # 1
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(13)).to eq(1 << 1)
      expect(single.read_reg(14)).to eq(1 << 6)
      expect(single.read_reg(15)).to eq(1)
      expect(single.read_reg(16)).to eq(1)
      expect(single.read_reg(17)).to eq(1)
    end

    it 'supports fadd.d/fsub.d/fmul.d/fdiv.d/fsqrt.d arithmetic' do
      program = [
        asm.addi(1, 0, 9),
        asm.addi(2, 0, 3),
        asm.addi(3, 0, 16),
        asm.fcvt_d_w(1, 1),      # f1 = 9.0
        asm.fcvt_d_w(2, 2),      # f2 = 3.0
        asm.fcvt_d_w(3, 3),      # f3 = 16.0
        asm.fadd_d(4, 1, 2),     # 12
        asm.fsub_d(5, 1, 2),     # 6
        asm.fmul_d(6, 1, 2),     # 27
        asm.fdiv_d(7, 1, 2),     # 3
        asm.fsqrt_d(8, 3),       # 4
        asm.fcvt_w_d(10, 4),
        asm.fcvt_w_d(11, 5),
        asm.fcvt_w_d(12, 6),
        asm.fcvt_w_d(13, 7),
        asm.fcvt_w_d(14, 8)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(10)).to eq(12)
      expect(single.read_reg(11)).to eq(6)
      expect(single.read_reg(12)).to eq(27)
      expect(single.read_reg(13)).to eq(3)
      expect(single.read_reg(14)).to eq(4)
    end

    it 'supports fmadd.d/fmsub.d/fnmsub.d/fnmadd.d fused arithmetic' do
      program = [
        asm.addi(1, 0, 2),
        asm.addi(2, 0, 3),
        asm.addi(3, 0, 4),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.fcvt_d_w(3, 3),
        asm.fmadd_d(4, 1, 2, 3),   # (2 * 3) + 4 = 10
        asm.fmsub_d(5, 1, 2, 3),   # (2 * 3) - 4 = 2
        asm.fnmsub_d(6, 1, 2, 3),  # -(2 * 3) + 4 = -2
        asm.fnmadd_d(7, 1, 2, 3),  # -(2 * 3) - 4 = -10
        asm.fcvt_w_d(10, 4),
        asm.fcvt_w_d(11, 5),
        asm.fcvt_w_d(12, 6),
        asm.fcvt_w_d(13, 7)
      ]

      single.load_program(program)
      single.reset!
      single.run_cycles(program.length)

      expect(single.read_reg(10)).to eq(10)
      expect(single.read_reg(11)).to eq(2)
      expect(single.read_reg(12)).to eq(0xFFFF_FFFE)
      expect(single.read_reg(13)).to eq(0xFFFF_FFF6)
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

    it 'supports fsgnj/fmin/fcmp/fclass subset operations' do
      program = [
        asm.lui(1, 0x3FC00),
        asm.nop,
        asm.nop,
        asm.fmv_w_x(1, 1),
        asm.lui(2, 0xC0000),
        asm.nop,
        asm.nop,
        asm.fmv_w_x(2, 2),
        asm.nop,
        asm.nop,
        asm.fsgnj_s(3, 1, 2),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(10, 3),
        asm.fmin_s(4, 1, 2),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(11, 4),
        asm.feq_s(12, 1, 1),
        asm.flt_s(13, 2, 1),
        asm.fclass_s(14, 2)
      ]

      run_pipe(program, 6)

      expect(pipe.read_reg(10)).to eq(0xBFC0_0000)
      expect(pipe.read_reg(11)).to eq(0xC000_0000)
      expect(pipe.read_reg(12)).to eq(1)
      expect(pipe.read_reg(13)).to eq(1)
      expect(pipe.read_reg(14)).to eq(1 << 1)
    end

    it 'supports fcvt.s.w/fcvt.s.wu and fcvt.w.s/fcvt.wu.s conversions' do
      program = [
        asm.addi(1, 0, -7),
        asm.addi(4, 0, 42),
        asm.fcvt_s_w(1, 1),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(2, 1),
        asm.fcvt_w_s(3, 1),
        asm.fcvt_s_wu(2, 4),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(6, 2),
        asm.fcvt_wu_s(5, 2)
      ]

      run_pipe(program, 6)

      expect(pipe.read_reg(2)).to eq(0xC0E0_0000)
      expect(pipe.read_reg(3)).to eq(0xFFFF_FFF9)
      expect(pipe.read_reg(6)).to eq(0x4228_0000)
      expect(pipe.read_reg(5)).to eq(42)
    end

    it 'supports fcvt.d.s -> fcvt.s.d round-trip' do
      program = [
        asm.lui(1, 0x3FC00),
        asm.nop,
        asm.nop,
        asm.fmv_w_x(1, 1),
        asm.nop,
        asm.nop,
        asm.fcvt_d_s(2, 1),
        asm.nop,
        asm.nop,
        asm.fcvt_s_d(3, 2),
        asm.nop,
        asm.nop,
        asm.fmv_x_w(10, 3)
      ]

      run_pipe(program, 8)

      expect(pipe.read_reg(10)).to eq(0x3FC0_0000)
    end

    it 'supports fcvt.d.w/fcvt.d.wu and fcvt.w.d/fcvt.wu.d conversions' do
      program = [
        asm.addi(1, 0, -9),
        asm.addi(2, 0, 9),
        asm.fcvt_d_w(1, 1),
        asm.nop,
        asm.nop,
        asm.fcvt_w_d(3, 1),
        asm.fcvt_d_wu(2, 2),
        asm.nop,
        asm.nop,
        asm.fcvt_wu_d(4, 2)
      ]

      run_pipe(program, 8)

      expect(pipe.read_reg(3)).to eq(0xFFFF_FFF7)
      expect(pipe.read_reg(4)).to eq(9)
    end

    it 'supports fclass.d classification' do
      program = [
        asm.addi(1, 0, -5),
        asm.addi(2, 0, 5),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.nop,
        asm.nop,
        asm.fclass_d(10, 1),
        asm.fclass_d(11, 2)
      ]

      run_pipe(program, 8)

      expect(pipe.read_reg(10)).to eq(1 << 1)
      expect(pipe.read_reg(11)).to eq(1 << 6)
    end

    it 'supports fsgnj.d/fsgnjn.d/fsgnjx.d sign operations' do
      program = [
        asm.addi(1, 0, 3),
        asm.addi(2, 0, -2),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.nop,
        asm.nop,
        asm.fsgnj_d(3, 1, 2),
        asm.fsgnjn_d(4, 1, 2),
        asm.fsgnjx_d(5, 1, 2),
        asm.nop,
        asm.nop,
        asm.fclass_d(10, 3),
        asm.fclass_d(11, 4),
        asm.fclass_d(12, 5)
      ]

      run_pipe(program, 10)

      expect(pipe.read_reg(10)).to eq(1 << 1)
      expect(pipe.read_reg(11)).to eq(1 << 6)
      expect(pipe.read_reg(12)).to eq(1 << 1)
    end

    it 'supports fmin.d/fmax.d and feq.d/flt.d/fle.d' do
      program = [
        asm.addi(1, 0, 5),
        asm.addi(2, 0, -7),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.nop,
        asm.nop,
        asm.fmin_d(3, 1, 2),
        asm.fmax_d(4, 1, 2),
        asm.nop,
        asm.nop,
        asm.fclass_d(13, 3),
        asm.fclass_d(14, 4),
        asm.feq_d(15, 1, 1),
        asm.flt_d(16, 2, 1),
        asm.fle_d(17, 2, 2)
      ]

      run_pipe(program, 10)

      expect(pipe.read_reg(13)).to eq(1 << 1)
      expect(pipe.read_reg(14)).to eq(1 << 6)
      expect(pipe.read_reg(15)).to eq(1)
      expect(pipe.read_reg(16)).to eq(1)
      expect(pipe.read_reg(17)).to eq(1)
    end

    it 'supports fadd.d/fsub.d/fmul.d/fdiv.d/fsqrt.d arithmetic' do
      program = [
        asm.addi(1, 0, 9),
        asm.addi(2, 0, 3),
        asm.addi(3, 0, 16),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.fcvt_d_w(3, 3),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.fadd_d(4, 1, 2),
        asm.nop,
        asm.nop,
        asm.fsub_d(5, 1, 2),
        asm.nop,
        asm.nop,
        asm.fmul_d(6, 1, 2),
        asm.nop,
        asm.nop,
        asm.fdiv_d(7, 1, 2),
        asm.nop,
        asm.nop,
        asm.fsqrt_d(8, 3),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.fcvt_w_d(10, 4),
        asm.fcvt_w_d(11, 5),
        asm.fcvt_w_d(12, 6),
        asm.fcvt_w_d(13, 7),
        asm.fcvt_w_d(14, 8)
      ]

      run_pipe(program, 12)

      expect(pipe.read_reg(10)).to eq(12)
      expect(pipe.read_reg(11)).to eq(6)
      expect(pipe.read_reg(12)).to eq(27)
      expect(pipe.read_reg(13)).to eq(3)
      expect(pipe.read_reg(14)).to eq(4)
    end

    it 'supports fmadd.d/fmsub.d/fnmsub.d/fnmadd.d fused arithmetic' do
      program = [
        asm.addi(1, 0, 2),
        asm.addi(2, 0, 3),
        asm.addi(3, 0, 4),
        asm.fcvt_d_w(1, 1),
        asm.fcvt_d_w(2, 2),
        asm.fcvt_d_w(3, 3),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.fmadd_d(4, 1, 2, 3),
        asm.fmsub_d(5, 1, 2, 3),
        asm.fnmsub_d(6, 1, 2, 3),
        asm.fnmadd_d(7, 1, 2, 3),
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.nop,
        asm.fcvt_w_d(10, 4),
        asm.fcvt_w_d(11, 5),
        asm.fcvt_w_d(12, 6),
        asm.fcvt_w_d(13, 7)
      ]

      run_pipe(program, 14)

      expect(pipe.read_reg(10)).to eq(10)
      expect(pipe.read_reg(11)).to eq(2)
      expect(pipe.read_reg(12)).to eq(0xFFFF_FFFE)
      expect(pipe.read_reg(13)).to eq(0xFFFF_FFF6)
    end

  end
end
