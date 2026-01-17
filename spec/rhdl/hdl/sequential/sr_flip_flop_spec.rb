require 'spec_helper'

RSpec.describe RHDL::HDL::SRFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:srff) { RHDL::HDL::SRFlipFlop.new }

  before do
    srff.set_input(:rst, 0)
    srff.set_input(:en, 1)
  end

  it 'holds state when S=0 and R=0' do
    srff.set_input(:s, 1)
    srff.set_input(:r, 0)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(1)

    srff.set_input(:s, 0)
    srff.set_input(:r, 0)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(1)  # Hold
  end

  it 'resets when S=0 and R=1' do
    srff.set_input(:s, 1)
    srff.set_input(:r, 0)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(1)

    srff.set_input(:s, 0)
    srff.set_input(:r, 1)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(0)
    expect(srff.get_output(:qn)).to eq(1)
  end

  it 'sets when S=1 and R=0' do
    srff.set_input(:s, 1)
    srff.set_input(:r, 0)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(1)
    expect(srff.get_output(:qn)).to eq(0)
  end

  it 'handles invalid state S=1 R=1 by defaulting to 0' do
    srff.set_input(:s, 1)
    srff.set_input(:r, 0)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(1)

    srff.set_input(:s, 1)
    srff.set_input(:r, 1)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(0)  # Invalid defaults to 0
  end

  it 'resets on reset signal' do
    srff.set_input(:s, 1)
    srff.set_input(:r, 0)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(1)

    srff.set_input(:rst, 1)
    clock_cycle(srff)
    expect(srff.get_output(:q)).to eq(0)
  end
end
