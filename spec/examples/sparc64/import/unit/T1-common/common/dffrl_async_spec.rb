# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../../../../examples/sparc64/import/T1-common/common/dffrl_async'

RSpec.describe DffrlAsync do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:component) { described_class.new }

  before do
    component.set_input(:clk, 0)
    component.set_input(:rst_l, 1)
    component.set_input(:din, 0)
    component.set_input(:se, 0)
    component.set_input(:si, 1)
    component.propagate
  end

  it 'captures din on the rising edge when reset is deasserted' do
    component.set_input(:din, 1)
    clock_cycle(component)

    expect(component.get_output(:q)).to eq(1)
    expect(component.get_output(:so)).to eq(0)
  end

  it 'resets asynchronously when rst_l is driven low' do
    component.set_input(:din, 1)
    clock_cycle(component)
    expect(component.get_output(:q)).to eq(1)

    component.set_input(:rst_l, 0)
    component.propagate

    expect(component.get_output(:q)).to eq(0)
    expect(component.get_output(:so)).to eq(0)
  end

  it 'ignores scan inputs under the no-scan runtime shim' do
    component.set_input(:se, 1)
    component.set_input(:si, 1)
    component.set_input(:din, 0)
    clock_cycle(component)

    expect(component.get_output(:q)).to eq(0)
    expect(component.get_output(:so)).to eq(0)
  end
end
