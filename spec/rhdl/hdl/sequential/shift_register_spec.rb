require 'spec_helper'

RSpec.describe RHDL::HDL::ShiftRegister do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:sr) { RHDL::HDL::ShiftRegister.new(nil, width: 8) }

  before do
    sr.set_input(:rst, 0)
    sr.set_input(:en, 1)
    sr.set_input(:load, 0)
    sr.set_input(:dir, 1)  # Shift left
    sr.set_input(:d_in, 0)
  end

  it 'shifts left' do
    sr.set_input(:load, 1)
    sr.set_input(:d, 0b00001111)
    clock_cycle(sr)
    sr.set_input(:load, 0)

    clock_cycle(sr)
    expect(sr.get_output(:q)).to eq(0b00011110)

    clock_cycle(sr)
    expect(sr.get_output(:q)).to eq(0b00111100)
  end

  it 'shifts right' do
    sr.set_input(:load, 1)
    sr.set_input(:d, 0b11110000)
    clock_cycle(sr)
    sr.set_input(:load, 0)

    sr.set_input(:dir, 0)  # Shift right
    clock_cycle(sr)
    expect(sr.get_output(:q)).to eq(0b01111000)
  end
end
