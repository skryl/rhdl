require 'spec_helper'

RSpec.describe RHDL::HDL::JKFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:jkff) { RHDL::HDL::JKFlipFlop.new }

  before do
    jkff.set_input(:rst, 0)
    jkff.set_input(:en, 1)
  end

  it 'holds state when J=0 and K=0' do
    jkff.set_input(:j, 1)
    jkff.set_input(:k, 0)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)

    jkff.set_input(:j, 0)
    jkff.set_input(:k, 0)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)  # Hold
  end

  it 'resets when J=0 and K=1' do
    jkff.set_input(:j, 1)
    jkff.set_input(:k, 0)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)

    jkff.set_input(:j, 0)
    jkff.set_input(:k, 1)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(0)
  end

  it 'sets when J=1 and K=0' do
    jkff.set_input(:j, 1)
    jkff.set_input(:k, 0)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)
    expect(jkff.get_output(:qn)).to eq(0)
  end

  it 'toggles when J=1 and K=1' do
    jkff.set_input(:j, 1)
    jkff.set_input(:k, 1)

    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)

    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(0)

    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)
  end

  it 'resets on reset signal' do
    jkff.set_input(:j, 1)
    jkff.set_input(:k, 0)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(1)

    jkff.set_input(:rst, 1)
    clock_cycle(jkff)
    expect(jkff.get_output(:q)).to eq(0)
  end
end
