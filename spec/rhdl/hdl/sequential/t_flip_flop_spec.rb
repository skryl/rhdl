require 'spec_helper'

RSpec.describe RHDL::HDL::TFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:tff) { RHDL::HDL::TFlipFlop.new }

  before do
    tff.set_input(:rst, 0)
    tff.set_input(:en, 1)
  end

  it 'toggles on T=1' do
    tff.set_input(:t, 1)

    clock_cycle(tff)
    expect(tff.get_output(:q)).to eq(1)

    clock_cycle(tff)
    expect(tff.get_output(:q)).to eq(0)

    clock_cycle(tff)
    expect(tff.get_output(:q)).to eq(1)
  end

  it 'holds on T=0' do
    tff.set_input(:t, 1)
    clock_cycle(tff)
    expect(tff.get_output(:q)).to eq(1)

    tff.set_input(:t, 0)
    clock_cycle(tff)
    expect(tff.get_output(:q)).to eq(1)
  end
end
