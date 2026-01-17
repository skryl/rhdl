# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux8 do
  let(:mux) { RHDL::HDL::Mux8.new(nil, width: 8) }

  it 'selects from 8 inputs' do
    8.times { |i| mux.set_input("in#{i}".to_sym, (i + 1) * 10) }

    mux.set_input(:sel, 5)
    mux.propagate
    expect(mux.get_output(:y)).to eq(60)

    mux.set_input(:sel, 7)
    mux.propagate
    expect(mux.get_output(:y)).to eq(80)
  end
end
