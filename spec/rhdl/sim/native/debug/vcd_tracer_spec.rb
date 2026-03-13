# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'rhdl/sim/native/debug/vcd_tracer'

RSpec.describe RHDL::Sim::Native::Debug::VcdTracer do
  it 'captures buffered changes and emits VCD output' do
    tracer = described_class.new(
      signal_names: %w[clk cpu.pc],
      signal_widths: [1, 8]
    )

    tracer.add_signal_by_name('clk')
    tracer.add_signal_by_name('cpu.pc')
    tracer.start
    tracer.capture([0, 0])
    tracer.capture([1, 16])
    tracer.capture([0, 16])
    tracer.stop

    vcd = tracer.to_vcd

    expect(tracer.change_count).to eq(3)
    expect(tracer.signal_count).to eq(2)
    expect(vcd).to include('$timescale 1ns $end')
    expect(vcd).to include('$scope module top $end')
    expect(vcd).to include('$var wire 1 ! clk $end')
    expect(vcd).to include('$var wire 8 " cpu_pc $end')
    expect(vcd).to include('#1')
    expect(vcd).to include('1!')
    expect(vcd).to include('b00010000 "')
  end

  it 'streams live chunks and writes files' do
    tracer = described_class.new(
      signal_names: ['sig'],
      signal_widths: [4]
    )

    Tempfile.create(['trace', '.vcd']) do |file|
      tracer.add_signal_by_name('sig')
      tracer.open_file(file.path)
      tracer.start
      tracer.capture([0])
      tracer.capture([3])
      tracer.stop

      live = tracer.take_live_chunk
      expect(live).to include('$dumpvars')
      expect(live).to include('#1')
      expect(live).to include('b0011 !')
      expect(tracer.take_live_chunk).to eq('')
      expect(File.binread(file.path)).to include('b0011 !')
    end
  end
end
