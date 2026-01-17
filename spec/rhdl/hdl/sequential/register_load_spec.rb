require 'spec_helper'

RSpec.describe RHDL::HDL::RegisterLoad do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:reg) { RHDL::HDL::RegisterLoad.new(nil, width: 8) }

  before do
    reg.set_input(:rst, 0)
    reg.set_input(:load, 0)
  end

  it 'stores 8-bit values when load is high' do
    reg.set_input(:load, 1)
    reg.set_input(:d, 0xAB)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0xAB)
  end

  it 'holds value when load is low' do
    reg.set_input(:load, 1)
    reg.set_input(:d, 0xAB)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0xAB)

    reg.set_input(:load, 0)
    reg.set_input(:d, 0xFF)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0xAB)  # Still 0xAB
  end

  it 'resets to zero' do
    reg.set_input(:load, 1)
    reg.set_input(:d, 0xFF)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0xFF)

    reg.set_input(:rst, 1)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0)
  end

  it 'supports different widths' do
    reg16 = RHDL::HDL::RegisterLoad.new(nil, width: 16)
    reg16.set_input(:rst, 0)
    reg16.set_input(:load, 1)
    reg16.set_input(:d, 0xABCD)
    clock_cycle(reg16)
    expect(reg16.get_output(:q)).to eq(0xABCD)
  end
end
