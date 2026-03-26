# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/sim/native/abi'
require 'rhdl/sim/native/debug/trace_support'

RSpec.describe RHDL::Sim::Native::Debug::TraceSupport do
  let(:sim_class) do
    Class.new do
      attr_reader :input_names, :output_names

      def initialize
        @input_names = ['clk']
        @output_names = ['value']
        @signal_values = [0, 0]
        @signal_widths_by_name = { 'clk' => 1, 'value' => 8 }
        @signal_widths_by_idx = [1, 8]
        @sim_caps_flags = 0
        @backend_label = 'dummy'
      end

      def peek_by_idx(idx)
        @signal_values.fetch(idx)
      end

      def set_signal_values(values)
        @signal_values = values
      end

      def cap?(flag)
        (@sim_caps_flags & flag) != 0
      end
    end
  end

  it 'adds soft trace support and promotes trace caps' do
    sim = sim_class.new

    described_class.attach(sim, module_name: 'dummy_top')

    expect(sim.trace_supported?).to be(true)
    expect(sim.cap?(RHDL::Sim::Native::ABI::SIM_CAP_TRACE)).to be(true)
    expect(sim.cap?(RHDL::Sim::Native::ABI::SIM_CAP_TRACE_STREAMING)).to be(true)

    sim.trace_add_signal('clk')
    sim.trace_add_signal('value')
    sim.trace_start
    sim.set_signal_values([0, 0])
    sim.trace_capture
    sim.set_signal_values([1, 42])
    sim.trace_capture

    vcd = sim.trace_to_vcd

    expect(sim.trace_enabled?).to be(true)
    expect(sim.trace_signal_count).to eq(2)
    expect(sim.trace_change_count).to eq(2)
    expect(vcd).to include('$scope module dummy_top $end')
    expect(vcd).to include('1!')
    expect(vcd).to include('b00101010 "')

    sim.trace_clear
    expect(sim.trace_change_count).to eq(0)
  end
end
