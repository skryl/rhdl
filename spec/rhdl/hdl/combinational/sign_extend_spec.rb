# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::SignExtend do
  let(:ext) { RHDL::HDL::SignExtend.new(nil, in_width: 8, out_width: 16) }

  it 'extends positive values with zeros' do
    ext.set_input(:a, 0x7F)  # Positive (MSB = 0)
    ext.propagate
    expect(ext.get_output(:y)).to eq(0x007F)
  end

  it 'extends negative values with ones' do
    ext.set_input(:a, 0x80)  # Negative (MSB = 1)
    ext.propagate
    expect(ext.get_output(:y)).to eq(0xFF80)
  end
end
