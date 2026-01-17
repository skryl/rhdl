# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::ZeroDetect do
  let(:det) { RHDL::HDL::ZeroDetect.new(nil, width: 8) }

  it 'detects zero' do
    det.set_input(:a, 0x00)
    det.propagate

    expect(det.get_output(:zero)).to eq(1)
  end

  it 'detects non-zero' do
    det.set_input(:a, 0x01)
    det.propagate

    expect(det.get_output(:zero)).to eq(0)
  end

  it 'detects non-zero for all bits set' do
    det.set_input(:a, 0xFF)
    det.propagate

    expect(det.get_output(:zero)).to eq(0)
  end
end
