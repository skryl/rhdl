# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::MuxN do
  let(:mux) { RHDL::HDL::MuxN.new(nil, width: 8, inputs: 6) }

  it 'handles arbitrary number of inputs' do
    6.times { |i| mux.set_input("in#{i}".to_sym, 100 + i) }

    mux.set_input(:sel, 3)
    mux.propagate
    expect(mux.get_output(:y)).to eq(103)
  end
end
