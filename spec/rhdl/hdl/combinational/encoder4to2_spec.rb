# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Encoder4to2 do
  let(:enc) { RHDL::HDL::Encoder4to2.new }

  it 'encodes one-hot input' do
    # Input :a is a 4-bit value where bit 2 is set (0b0100)
    enc.set_input(:a, 0b0100)
    enc.propagate

    expect(enc.get_output(:y)).to eq(2)
    expect(enc.get_output(:valid)).to eq(1)
  end

  it 'indicates invalid when no input' do
    enc.set_input(:a, 0b0000)
    enc.propagate

    expect(enc.get_output(:valid)).to eq(0)
  end

  it 'prioritizes higher input' do
    # Bits 0, 1, and 3 are set - highest is bit 3
    enc.set_input(:a, 0b1011)
    enc.propagate

    expect(enc.get_output(:y)).to eq(3)
  end
end
