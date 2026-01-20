# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Debug::Watchpoint do
  let(:wire) { RHDL::Sim::Wire.new("test", width: 8) }

  it 'triggers on signal change' do
    triggered = false
    wp = RHDL::Debug::Watchpoint.new(wire, type: :change) { triggered = true }

    wire.set(10)
    expect(wp.check(nil)).to be true
    expect(triggered).to be true
  end

  it 'triggers when signal equals value' do
    wp = RHDL::Debug::Watchpoint.new(wire, type: :equals, value: 42)

    wire.set(10)
    expect(wp.check(nil)).to be false

    wire.set(42)
    expect(wp.check(nil)).to be true
  end

  it 'triggers on rising edge' do
    single_bit = RHDL::Sim::Wire.new("bit", width: 1)
    wp = RHDL::Debug::Watchpoint.new(single_bit, type: :rising_edge)

    single_bit.set(0)
    wp.check(nil)  # Update last value

    single_bit.set(1)
    expect(wp.check(nil)).to be true

    single_bit.set(1)
    expect(wp.check(nil)).to be false
  end

  it 'triggers on falling edge' do
    single_bit = RHDL::Sim::Wire.new("bit", width: 1)
    single_bit.set(1)
    wp = RHDL::Debug::Watchpoint.new(single_bit, type: :falling_edge)
    wp.check(nil)  # Initialize

    single_bit.set(0)
    expect(wp.check(nil)).to be true
  end

  it 'has descriptive description' do
    wp = RHDL::Debug::Watchpoint.new(wire, type: :equals, value: 100)
    expect(wp.description).to include("test")
    expect(wp.description).to include("100")
  end
end
