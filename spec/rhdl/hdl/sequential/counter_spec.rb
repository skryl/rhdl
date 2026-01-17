require 'spec_helper'

RSpec.describe RHDL::HDL::Counter do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:counter) { RHDL::HDL::Counter.new(nil, width: 4) }

  before do
    counter.set_input(:rst, 0)
    counter.set_input(:en, 1)
    counter.set_input(:up, 1)
    counter.set_input(:load, 0)
  end

  it 'counts up' do
    expect(counter.get_output(:q)).to eq(0)

    clock_cycle(counter)
    expect(counter.get_output(:q)).to eq(1)

    clock_cycle(counter)
    expect(counter.get_output(:q)).to eq(2)
  end

  it 'counts down' do
    counter.set_input(:load, 1)
    counter.set_input(:d, 5)
    clock_cycle(counter)
    counter.set_input(:load, 0)

    counter.set_input(:up, 0)
    clock_cycle(counter)
    expect(counter.get_output(:q)).to eq(4)
  end

  it 'wraps around' do
    counter.set_input(:load, 1)
    counter.set_input(:d, 15)
    clock_cycle(counter)
    counter.set_input(:load, 0)

    # At max value (15), tc should be 1
    expect(counter.get_output(:q)).to eq(15)
    expect(counter.get_output(:tc)).to eq(1)

    # After wrap to 0, tc should be 0 (since we're counting up)
    clock_cycle(counter)
    expect(counter.get_output(:q)).to eq(0)
    expect(counter.get_output(:tc)).to eq(0)
  end
end
