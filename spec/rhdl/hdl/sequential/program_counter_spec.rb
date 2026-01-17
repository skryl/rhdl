require 'spec_helper'

RSpec.describe RHDL::HDL::ProgramCounter do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:pc) { RHDL::HDL::ProgramCounter.new(nil, width: 16) }

  before do
    pc.set_input(:rst, 0)
    pc.set_input(:en, 1)
    pc.set_input(:load, 0)
    pc.set_input(:inc, 1)
  end

  it 'increments by 1 by default' do
    expect(pc.get_output(:q)).to eq(0)

    clock_cycle(pc)
    expect(pc.get_output(:q)).to eq(1)

    clock_cycle(pc)
    expect(pc.get_output(:q)).to eq(2)
  end

  it 'loads a new address' do
    pc.set_input(:load, 1)
    pc.set_input(:d, 0x1000)
    clock_cycle(pc)

    expect(pc.get_output(:q)).to eq(0x1000)
  end

  it 'increments by variable amount' do
    pc.set_input(:inc, 3)
    clock_cycle(pc)
    expect(pc.get_output(:q)).to eq(3)
  end
end
