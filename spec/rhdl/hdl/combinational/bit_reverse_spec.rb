# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::BitReverse do
  let(:rev) { RHDL::HDL::BitReverse.new(nil, width: 8) }

  it 'reverses bit order' do
    rev.set_input(:a, 0b10110001)
    rev.propagate

    expect(rev.get_output(:y)).to eq(0b10001101)
  end

  it 'handles symmetric patterns' do
    rev.set_input(:a, 0b10000001)
    rev.propagate

    expect(rev.get_output(:y)).to eq(0b10000001)
  end

  it 'reverses all zeros' do
    rev.set_input(:a, 0b00000000)
    rev.propagate

    expect(rev.get_output(:y)).to eq(0b00000000)
  end

  it 'reverses all ones' do
    rev.set_input(:a, 0b11111111)
    rev.propagate

    expect(rev.get_output(:y)).to eq(0b11111111)
  end
end
