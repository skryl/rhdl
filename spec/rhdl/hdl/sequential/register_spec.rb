require 'spec_helper'

RSpec.describe RHDL::HDL::Register do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:reg) { RHDL::HDL::Register.new(nil, width: 8) }

  before do
    reg.set_input(:rst, 0)
    reg.set_input(:en, 1)
  end

  it 'stores 8-bit values' do
    reg.set_input(:d, 0xAB)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0xAB)
  end

  it 'resets to zero' do
    reg.set_input(:d, 0xFF)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0xFF)

    reg.set_input(:rst, 1)
    clock_cycle(reg)
    expect(reg.get_output(:q)).to eq(0)
  end
end
