# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Demux4 do
  let(:demux) { RHDL::HDL::Demux4.new(nil, width: 8) }

  it 'routes to correct output' do
    demux.set_input(:a, 0xFF)

    4.times do |sel|
      demux.set_input(:sel, sel)
      demux.propagate

      4.times do |out|
        expected = (out == sel) ? 0xFF : 0
        expect(demux.get_output("y#{out}".to_sym)).to eq(expected)
      end
    end
  end
end
