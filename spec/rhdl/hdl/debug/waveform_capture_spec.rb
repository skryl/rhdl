# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Debug::WaveformCapture do
  let(:wire1) { RHDL::Sim::Wire.new("signal_a", width: 1) }
  let(:wire2) { RHDL::Sim::Wire.new("signal_b", width: 8) }
  let(:capture) { RHDL::Debug::WaveformCapture.new }

  before do
    capture.add_probe(wire1, name: "clk")
    capture.add_probe(wire2, name: "data")
  end

  it 'adds probes' do
    expect(capture.probes.size).to eq(2)
    expect(capture.probes.keys).to include("clk", "data")
  end

  it 'removes probes' do
    capture.remove_probe("clk")
    expect(capture.probes.size).to eq(1)
    expect(capture.probes.keys).not_to include("clk")
  end

  it 'captures snapshots while recording' do
    capture.start_recording

    wire1.set(1)
    capture.capture_snapshot
    wire1.set(0)
    capture.capture_snapshot

    capture.stop_recording

    expect(capture.probes["clk"].history.size).to be >= 2
  end

  it 'generates VCD output' do
    capture.start_recording
    wire1.set(1)
    capture.capture_snapshot
    wire2.set(0xFF)
    capture.capture_snapshot
    capture.stop_recording

    vcd = capture.to_vcd
    expect(vcd).to include("$timescale")
    expect(vcd).to include("$var wire")
    expect(vcd).to include("$dumpvars")
  end

  it 'displays text-based waveforms' do
    capture.start_recording
    wire1.set(1)
    wire1.set(0)
    capture.stop_recording

    display = capture.display(width: 40)
    expect(display).to include("clk")
    expect(display).to include("data")
  end

  it 'clears all probes' do
    wire1.set(1)
    wire2.set(100)

    capture.clear_all
    capture.probes.each_value do |probe|
      expect(probe.history).to be_empty
    end
  end
end
