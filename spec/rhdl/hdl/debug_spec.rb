require 'spec_helper'

RSpec.describe 'HDL Debug Features' do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  describe RHDL::HDL::SignalProbe do
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

  describe RHDL::HDL::WaveformCapture do
    let(:wire1) { RHDL::HDL::Wire.new("signal_a", width: 1) }
    let(:wire2) { RHDL::HDL::Wire.new("signal_b", width: 8) }
    let(:capture) { RHDL::HDL::WaveformCapture.new }

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

  describe RHDL::HDL::Breakpoint do
    it 'checks condition and triggers' do
      counter = 0
      bp = RHDL::HDL::Breakpoint.new(condition: -> (ctx) { ctx[:value] > 5 }) do
        counter += 1
      end

      expect(bp.check({ value: 3 })).to be false
      expect(bp.check({ value: 10 })).to be true
      expect(counter).to eq(1)
      expect(bp.hit_count).to eq(1)
    end

    it 'can be enabled and disabled' do
      bp = RHDL::HDL::Breakpoint.new(condition: -> (ctx) { true })

      expect(bp.check({})).to be true

      bp.disable!
      expect(bp.check({})).to be false

      bp.enable!
      expect(bp.check({})).to be true
    end

    it 'resets hit count' do
      bp = RHDL::HDL::Breakpoint.new(condition: -> (ctx) { true })
      bp.check({})
      bp.check({})
      expect(bp.hit_count).to eq(2)

      bp.reset!
      expect(bp.hit_count).to eq(0)
    end
  end

  describe RHDL::HDL::Watchpoint do
    let(:wire) { RHDL::HDL::Wire.new("test", width: 8) }

    it 'triggers on signal change' do
      triggered = false
      wp = RHDL::HDL::Watchpoint.new(wire, type: :change) { triggered = true }

      wire.set(10)
      expect(wp.check(nil)).to be true
      expect(triggered).to be true
    end

    it 'triggers when signal equals value' do
      wp = RHDL::HDL::Watchpoint.new(wire, type: :equals, value: 42)

      wire.set(10)
      expect(wp.check(nil)).to be false

      wire.set(42)
      expect(wp.check(nil)).to be true
    end

    it 'triggers on rising edge' do
      single_bit = RHDL::HDL::Wire.new("bit", width: 1)
      wp = RHDL::HDL::Watchpoint.new(single_bit, type: :rising_edge)

      single_bit.set(0)
      wp.check(nil)  # Update last value

      single_bit.set(1)
      expect(wp.check(nil)).to be true

      single_bit.set(1)
      expect(wp.check(nil)).to be false
    end

    it 'triggers on falling edge' do
      single_bit = RHDL::HDL::Wire.new("bit", width: 1)
      single_bit.set(1)
      wp = RHDL::HDL::Watchpoint.new(single_bit, type: :falling_edge)
      wp.check(nil)  # Initialize

      single_bit.set(0)
      expect(wp.check(nil)).to be true
    end

    it 'has descriptive description' do
      wp = RHDL::HDL::Watchpoint.new(wire, type: :equals, value: 100)
      expect(wp.description).to include("test")
      expect(wp.description).to include("100")
    end
  end

  describe RHDL::HDL::DebugSimulator do
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
