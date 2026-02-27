# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/fp_register_file'

RSpec.describe RHDL::Examples::RISCV::FPRegisterFile do
  it 'nan-boxes 32-bit writes into 64-bit FP register storage' do
    rf = described_class.new

    rf.write_reg(1, 0x3F80_0000)

    expect(rf.read_reg(1)).to eq(0x3F80_0000)
    expect(rf.read_reg64(1)).to eq(0xFFFF_FFFF_3F80_0000)
  end

  it 'preserves full 64-bit values on explicit 64-bit helper writes' do
    rf = described_class.new
    value = 0x4008_0000_0000_0000

    rf.write_reg64(2, value)

    expect(rf.read_reg64(2)).to eq(value)
    expect(rf.read_reg(2)).to eq(0x0000_0000)
  end
end
