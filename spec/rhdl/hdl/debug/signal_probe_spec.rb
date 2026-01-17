# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::SignalProbe do
  let(:wire) { RHDL::HDL::Wire.new("test_signal", width: 8) }
  let!(:probe) { RHDL::HDL::SignalProbe.new(wire, name: "test_probe") }  # Use let! for eager evaluation

  it 'records signal transitions' do
    wire.set(10)
    wire.set(20)
    wire.set(30)

    expect(probe.history.size).to eq(3)
    expect(probe.history.map(&:last)).to eq([10, 20, 30])
  end

  it 'tracks current value' do
    wire.set(42)
    expect(probe.current_value).to eq(42)
  end

  it 'can be enabled and disabled' do
    probe.disable!
    wire.set(100)
    expect(probe.history).to be_empty

    probe.enable!
    wire.set(200)
    expect(probe.history.size).to eq(1)
  end

  it 'clears history' do
    wire.set(10)
    wire.set(20)
    expect(probe.history.size).to eq(2)

    probe.clear!
    expect(probe.history).to be_empty
  end

  it 'counts transitions' do
    wire.set(1)
    wire.set(2)
    wire.set(3)
    expect(probe.transitions).to eq(3)
  end

  it 'generates waveform string' do
    wire.set(1)
    wire.set(0)
    wire.set(1)
    waveform = probe.to_waveform(width: 20)
    expect(waveform).to be_a(String)
    expect(waveform.length).to be > 0
  end
end
