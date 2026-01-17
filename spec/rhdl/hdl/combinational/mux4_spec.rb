# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux4 do
  let(:mux) { RHDL::HDL::Mux4.new(nil, width: 8) }

  before do
    mux.set_input(:a, 0x10)
    mux.set_input(:b, 0x20)
    mux.set_input(:c, 0x30)
    mux.set_input(:d, 0x40)
  end

  it 'selects correct input based on sel' do
    mux.set_input(:sel, 0)
    mux.propagate
    expect(mux.get_output(:y)).to eq(0x10)

    mux.set_input(:sel, 1)
    mux.propagate
    expect(mux.get_output(:y)).to eq(0x20)

    mux.set_input(:sel, 2)
    mux.propagate
    expect(mux.get_output(:y)).to eq(0x30)

    mux.set_input(:sel, 3)
    mux.propagate
    expect(mux.get_output(:y)).to eq(0x40)
  end
end
