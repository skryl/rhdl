# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Demux2 do
  let(:demux) { RHDL::HDL::Demux2.new(nil, width: 8) }

  it 'routes to output a when sel=0' do
    demux.set_input(:a, 0x42)
    demux.set_input(:sel, 0)
    demux.propagate

    expect(demux.get_output(:y0)).to eq(0x42)
    expect(demux.get_output(:y1)).to eq(0)
  end

  it 'routes to output b when sel=1' do
    demux.set_input(:a, 0x42)
    demux.set_input(:sel, 1)
    demux.propagate

    expect(demux.get_output(:y0)).to eq(0)
    expect(demux.get_output(:y1)).to eq(0x42)
  end
end
