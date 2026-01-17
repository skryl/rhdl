# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::DecoderN do
  let(:dec) { RHDL::HDL::DecoderN.new(nil, width: 4) }

  it 'decodes N-bit input to 2^N outputs' do
    dec.set_input(:en, 1)

    dec.set_input(:a, 10)
    dec.propagate
    expect(dec.get_output(:y10)).to eq(1)
    expect(dec.get_output(:y0)).to eq(0)
    expect(dec.get_output(:y15)).to eq(0)
  end
end
