# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::LZCount do
  let(:lzc) { RHDL::HDL::LZCount.new(nil, width: 8) }

  it 'counts leading zeros' do
    lzc.set_input(:a, 0b10000000)
    lzc.propagate
    expect(lzc.get_output(:count)).to eq(0)

    lzc.set_input(:a, 0b00001000)
    lzc.propagate
    expect(lzc.get_output(:count)).to eq(4)

    lzc.set_input(:a, 0b00000001)
    lzc.propagate
    expect(lzc.get_output(:count)).to eq(7)

    lzc.set_input(:a, 0b00000000)
    lzc.propagate
    expect(lzc.get_output(:count)).to eq(8)
  end
end
