# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Encoder8to3 do
  let(:enc) { RHDL::HDL::Encoder8to3.new }

  it 'encodes 8-bit one-hot to 3-bit binary' do
    # Bit 5 is set (0b00100000)
    enc.set_input(:a, 0b00100000)
    enc.propagate

    expect(enc.get_output(:y)).to eq(5)
    expect(enc.get_output(:valid)).to eq(1)
  end
end
