# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::DebugSimulator do
  let(:sim) { RHDL::HDL::DebugSimulator.new }
  let(:counter) { RHDL::HDL::Counter.new("counter", width: 4) }
  let(:clock) { RHDL::HDL::Clock.new("clk") }

  before do
    sim.add_component(counter)
    sim.add_clock(clock)
    RHDL::HDL::SimComponent.connect(clock, counter.inputs[:clk])
    counter.set_input(:rst, 0)
    counter.set_input(:en, 1)
    counter.set_input(:up, 1)
    counter.set_input(:load, 0)
  end

  it 'adds probes to signals' do
    probe = sim.probe(counter, :q)
    expect(probe).to be_a(RHDL::HDL::SignalProbe)
    expect(sim.waveform.probes).not_to be_empty
  end

  it 'adds and removes breakpoints' do
    bp = sim.add_breakpoint { |s| s.current_cycle > 5 }
    expect(sim.breakpoints.size).to eq(1)

    sim.remove_breakpoint(bp.id)
    expect(sim.breakpoints).to be_empty
  end

  it 'adds watchpoints' do
    wp = sim.watch(counter.outputs[:q], type: :change)
    expect(wp).to be_a(RHDL::HDL::Watchpoint)
    expect(sim.breakpoints).to include(wp)
  end

  it 'clears breakpoints' do
    sim.add_breakpoint { true }
    sim.watch(counter.outputs[:q], type: :change)
    expect(sim.breakpoints.size).to eq(2)

    sim.clear_breakpoints
    expect(sim.breakpoints).to be_empty
  end

  it 'enables and disables step mode' do
    expect(sim.step_mode).to be false

    sim.enable_step_mode
    expect(sim.step_mode).to be true

    sim.disable_step_mode
    expect(sim.step_mode).to be false
  end

  it 'steps through cycles' do
    expect(sim.current_cycle).to eq(0)

    sim.step_cycle
    expect(sim.current_cycle).to eq(1)

    sim.step_cycle
    expect(sim.current_cycle).to eq(2)
  end

  it 'runs multiple cycles' do
    sim.run(10)
    expect(sim.time).to eq(10)
  end

  it 'pauses on breakpoint' do
    triggered = false
    sim.add_breakpoint { |s| s.current_cycle >= 5 }
    sim.on_break = -> (s, bp) { triggered = true; s.pause }

    sim.run(20)

    expect(triggered).to be true
    expect(sim.paused?).to be true
    expect(sim.current_cycle).to be >= 5
    expect(sim.current_cycle).to be < 20
  end

  it 'captures waveform during run' do
    sim.probe(counter, :q)

    sim.run(10)

    expect(sim.waveform.probes.values.first.history).not_to be_empty
  end

  it 'gets current signal state' do
    counter.set_input(:en, 1)
    sim.step_cycle
    sim.step_cycle

    state = sim.signal_state
    expect(state).to be_a(Hash)
    expect(state.keys).to include("counter.q")
  end

  it 'dumps simulation state' do
    sim.step_cycle
    dump = sim.dump_state

    expect(dump).to include("Simulation State")
    expect(dump).to include("counter")
    expect(dump).to include("Breakpoints")
  end

  it 'resets simulation' do
    sim.run(5)
    expect(sim.time).to eq(5)

    sim.reset
    expect(sim.time).to eq(0)
  end

  describe 'Integration test' do
    it 'captures complete simulation with probes and breakpoints' do
      sim = RHDL::HDL::DebugSimulator.new
      clock = RHDL::HDL::Clock.new("clk")
      counter = RHDL::HDL::Counter.new("cnt", width: 4)

      sim.add_clock(clock)
      sim.add_component(counter)
      RHDL::HDL::SimComponent.connect(clock, counter.inputs[:clk])

      counter.set_input(:rst, 0)
      counter.set_input(:en, 1)
      counter.set_input(:up, 1)
      counter.set_input(:load, 0)

      # Add probe
      sim.probe(counter, :q)

      # Add watchpoint for value 8
      watch_hits = 0
      sim.watch(counter.outputs[:q], type: :equals, value: 8) { watch_hits += 1 }

      # Run simulation
      sim.run(20)

      # Verify
      expect(sim.waveform.probes.values.first.history.size).to be > 0
      expect(watch_hits).to be >= 1
    end
  end
end
