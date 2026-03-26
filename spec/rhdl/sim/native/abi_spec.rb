# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/sim/native/ir/simulator'
require 'rhdl/sim/native/abi'

RSpec.describe RHDL::Sim::Native::ABI do
  it 'keeps the signal opcodes aligned with the IR native ABI' do
    expect(described_class::SIM_SIGNAL_HAS).to eq(RHDL::Sim::Native::IR::Simulator::SIM_SIGNAL_HAS)
    expect(described_class::SIM_SIGNAL_GET_INDEX).to eq(RHDL::Sim::Native::IR::Simulator::SIM_SIGNAL_GET_INDEX)
    expect(described_class::SIM_SIGNAL_PEEK).to eq(RHDL::Sim::Native::IR::Simulator::SIM_SIGNAL_PEEK)
    expect(described_class::SIM_SIGNAL_POKE).to eq(RHDL::Sim::Native::IR::Simulator::SIM_SIGNAL_POKE)
    expect(described_class::SIM_SIGNAL_PEEK_INDEX).to eq(RHDL::Sim::Native::IR::Simulator::SIM_SIGNAL_PEEK_INDEX)
    expect(described_class::SIM_SIGNAL_POKE_INDEX).to eq(RHDL::Sim::Native::IR::Simulator::SIM_SIGNAL_POKE_INDEX)
  end

  it 'keeps the exec opcodes aligned with the IR native ABI' do
    expect(described_class::SIM_EXEC_EVALUATE).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_EVALUATE)
    expect(described_class::SIM_EXEC_TICK).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_TICK)
    expect(described_class::SIM_EXEC_TICK_FORCED).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_TICK_FORCED)
    expect(described_class::SIM_EXEC_SET_PREV_CLOCK).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_SET_PREV_CLOCK)
    expect(described_class::SIM_EXEC_GET_CLOCK_LIST_IDX).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_GET_CLOCK_LIST_IDX)
    expect(described_class::SIM_EXEC_RESET).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_RESET)
    expect(described_class::SIM_EXEC_RUN_TICKS).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_RUN_TICKS)
    expect(described_class::SIM_EXEC_SIGNAL_COUNT).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_SIGNAL_COUNT)
    expect(described_class::SIM_EXEC_REG_COUNT).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_REG_COUNT)
    expect(described_class::SIM_EXEC_COMPILE).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_COMPILE)
    expect(described_class::SIM_EXEC_IS_COMPILED).to eq(RHDL::Sim::Native::IR::Simulator::SIM_EXEC_IS_COMPILED)
  end

  it 'keeps the trace and blob opcodes aligned with the IR native ABI' do
    expect(described_class::SIM_TRACE_START).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_START)
    expect(described_class::SIM_TRACE_START_STREAMING).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_START_STREAMING)
    expect(described_class::SIM_TRACE_STOP).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_STOP)
    expect(described_class::SIM_TRACE_ENABLED).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_ENABLED)
    expect(described_class::SIM_TRACE_CAPTURE).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_CAPTURE)
    expect(described_class::SIM_TRACE_ADD_SIGNAL).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_ADD_SIGNAL)
    expect(described_class::SIM_TRACE_ADD_SIGNALS_MATCHING).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_ADD_SIGNALS_MATCHING)
    expect(described_class::SIM_TRACE_ALL_SIGNALS).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_ALL_SIGNALS)
    expect(described_class::SIM_TRACE_CLEAR_SIGNALS).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_CLEAR_SIGNALS)
    expect(described_class::SIM_TRACE_CLEAR).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_CLEAR)
    expect(described_class::SIM_TRACE_CHANGE_COUNT).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_CHANGE_COUNT)
    expect(described_class::SIM_TRACE_SIGNAL_COUNT).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_SIGNAL_COUNT)
    expect(described_class::SIM_TRACE_SET_TIMESCALE).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_SET_TIMESCALE)
    expect(described_class::SIM_TRACE_SET_MODULE_NAME).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_SET_MODULE_NAME)
    expect(described_class::SIM_TRACE_SAVE_VCD).to eq(RHDL::Sim::Native::IR::Simulator::SIM_TRACE_SAVE_VCD)
    expect(described_class::SIM_BLOB_INPUT_NAMES).to eq(RHDL::Sim::Native::IR::Simulator::SIM_BLOB_INPUT_NAMES)
    expect(described_class::SIM_BLOB_OUTPUT_NAMES).to eq(RHDL::Sim::Native::IR::Simulator::SIM_BLOB_OUTPUT_NAMES)
    expect(described_class::SIM_BLOB_TRACE_TO_VCD).to eq(RHDL::Sim::Native::IR::Simulator::SIM_BLOB_TRACE_TO_VCD)
    expect(described_class::SIM_BLOB_TRACE_TAKE_LIVE_VCD).to eq(RHDL::Sim::Native::IR::Simulator::SIM_BLOB_TRACE_TAKE_LIVE_VCD)
  end
end
