require 'spec_helper'

RSpec.describe RHDL::HDL::DFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:dff) { RHDL::HDL::DFlipFlop.new }

  before do
    dff.set_input(:rst, 0)
    dff.set_input(:en, 1)
  end

  it 'captures input on rising edge' do
    dff.set_input(:d, 1)
    clock_cycle(dff)
    expect(dff.get_output(:q)).to eq(1)
    expect(dff.get_output(:qn)).to eq(0)
  end

  it 'holds value when enable is low' do
    dff.set_input(:d, 1)
    clock_cycle(dff)
    expect(dff.get_output(:q)).to eq(1)

    dff.set_input(:en, 0)
    dff.set_input(:d, 0)
    clock_cycle(dff)
    expect(dff.get_output(:q)).to eq(1)  # Still 1
  end

  it 'resets on reset signal' do
    dff.set_input(:d, 1)
    clock_cycle(dff)
    expect(dff.get_output(:q)).to eq(1)

    dff.set_input(:rst, 1)
    clock_cycle(dff)
    expect(dff.get_output(:q)).to eq(0)
  end
end
