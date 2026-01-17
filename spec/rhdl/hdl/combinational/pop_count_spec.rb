# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::PopCount do
  let(:pop) { RHDL::HDL::PopCount.new(nil, width: 8) }

  it 'counts set bits' do
    pop.set_input(:a, 0b10101010)
    pop.propagate
    expect(pop.get_output(:count)).to eq(4)

    pop.set_input(:a, 0b11111111)
    pop.propagate
    expect(pop.get_output(:count)).to eq(8)

    pop.set_input(:a, 0b00000000)
    pop.propagate
    expect(pop.get_output(:count)).to eq(0)
  end
end
