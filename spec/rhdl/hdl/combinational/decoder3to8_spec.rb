# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder3to8 do
  let(:dec) { RHDL::HDL::Decoder3to8.new }

  it 'decodes all 8 values' do
    dec.set_input(:en, 1)

    8.times do |i|
      dec.set_input(:a, i)
      dec.propagate

      8.times do |j|
        expected = (i == j) ? 1 : 0
        expect(dec.get_output("y#{j}".to_sym)).to eq(expected)
      end
    end
  end
end
