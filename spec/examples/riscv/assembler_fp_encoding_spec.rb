# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/utilities/assembler'
require_relative '../../../examples/riscv/hdl/constants'

RSpec.describe RHDL::Examples::RISCV::Assembler do
  let(:asm) { described_class }

  def bits(value, hi, lo)
    (value >> lo) & ((1 << (hi - lo + 1)) - 1)
  end

  it 'encodes fld/fsd with floating-point load/store opcode and DOUBLE width' do
    fld = asm.fld(1, 2, 16)
    fsd = asm.fsd(3, 4, 24)

    expect(bits(fld, 6, 0)).to eq(RHDL::Examples::RISCV::Opcode::LOAD_FP)
    expect(bits(fld, 14, 12)).to eq(RHDL::Examples::RISCV::Funct3::DOUBLE)

    expect(bits(fsd, 6, 0)).to eq(RHDL::Examples::RISCV::Opcode::STORE_FP)
    expect(bits(fsd, 14, 12)).to eq(RHDL::Examples::RISCV::Funct3::DOUBLE)
  end

  it 'encodes fadd.d and fcvt.d.s with OP_FP opcode and expected funct7' do
    fadd_d = asm.fadd_d(5, 6, 7)
    fcvt_d_s = asm.fcvt_d_s(8, 9)

    expect(bits(fadd_d, 6, 0)).to eq(RHDL::Examples::RISCV::Opcode::OP_FP)
    expect(bits(fadd_d, 31, 25)).to eq(0b0000001)

    expect(bits(fcvt_d_s, 6, 0)).to eq(RHDL::Examples::RISCV::Opcode::OP_FP)
    expect(bits(fcvt_d_s, 31, 25)).to eq(0b0100001)
    expect(bits(fcvt_d_s, 24, 20)).to eq(0b00000)
  end

  it 'encodes fmadd.d as R4 with D fmt and MADD opcode' do
    fmadd_d = asm.fmadd_d(10, 11, 12, 13)

    expect(bits(fmadd_d, 6, 0)).to eq(RHDL::Examples::RISCV::Opcode::MADD)
    expect(bits(fmadd_d, 26, 25)).to eq(0b01)
    expect(bits(fmadd_d, 31, 27)).to eq(13)
    expect(bits(fmadd_d, 11, 7)).to eq(10)
  end
end
