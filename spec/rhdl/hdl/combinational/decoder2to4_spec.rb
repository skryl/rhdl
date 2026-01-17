# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder2to4 do
  let(:dec) { RHDL::HDL::Decoder2to4.new }

  it 'produces one-hot output' do
    dec.set_input(:en, 1)

    dec.set_input(:a, 0)
    dec.propagate
    expect(dec.get_output(:y0)).to eq(1)
    expect(dec.get_output(:y1)).to eq(0)
    expect(dec.get_output(:y2)).to eq(0)
    expect(dec.get_output(:y3)).to eq(0)

    dec.set_input(:a, 2)
    dec.propagate
    expect(dec.get_output(:y0)).to eq(0)
    expect(dec.get_output(:y2)).to eq(1)
  end

  it 'outputs all zeros when disabled' do
    dec.set_input(:en, 0)
    dec.set_input(:a, 1)
    dec.propagate

    expect(dec.get_output(:y0)).to eq(0)
    expect(dec.get_output(:y1)).to eq(0)
    expect(dec.get_output(:y2)).to eq(0)
    expect(dec.get_output(:y3)).to eq(0)
  end
end
