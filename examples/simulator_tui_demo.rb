#!/usr/bin/env ruby
# RHDL Simulator TUI Demo
# Demonstrates the terminal-based simulator interface

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rhdl'

# Create a simple circuit to simulate - a counter with control logic
class DemoCounter < RHDL::HDL::SimComponent
  def setup_ports
    input :clk
    input :rst
    input :en
    input :load
    input :data, width: 8
    output :count, width: 8
    output :zero
    output :overflow
  end

  def initialize(name = nil)
    @state = 0
    @prev_clk = 0
    super(name)
  end

  def propagate
    # Detect rising edge
    clk_val = in_val(:clk)
    rising = @prev_clk == 0 && clk_val == 1
    @prev_clk = clk_val

    if rising
      if in_val(:rst) == 1
        @state = 0
      elsif in_val(:load) == 1
        @state = in_val(:data) & 0xFF
      elsif in_val(:en) == 1
        @state = (@state + 1) & 0xFF
      end
    end

    out_set(:count, @state)
    out_set(:zero, @state == 0 ? 1 : 0)
    out_set(:overflow, @state == 0xFF ? 1 : 0)
  end
end

# Create another component - a simple state machine
class DemoFSM < RHDL::HDL::SimComponent
  IDLE = 0
  RUNNING = 1
  PAUSED = 2
  DONE = 3

  def setup_ports
    input :clk
    input :rst
    input :start
    input :pause
    input :counter_overflow
    output :state, width: 2
    output :counter_enable
    output :done
  end

  def initialize(name = nil)
    @state = IDLE
    @prev_clk = 0
    super(name)
  end

  def propagate
    clk_val = in_val(:clk)
    rising = @prev_clk == 0 && clk_val == 1
    @prev_clk = clk_val

    if rising
      if in_val(:rst) == 1
        @state = IDLE
      else
        case @state
        when IDLE
          @state = RUNNING if in_val(:start) == 1
        when RUNNING
          if in_val(:counter_overflow) == 1
            @state = DONE
          elsif in_val(:pause) == 1
            @state = PAUSED
          end
        when PAUSED
          @state = RUNNING if in_val(:pause) == 0 && in_val(:start) == 1
        when DONE
          @state = IDLE if in_val(:start) == 0
        end
      end
    end

    out_set(:state, @state)
    out_set(:counter_enable, @state == RUNNING ? 1 : 0)
    out_set(:done, @state == DONE ? 1 : 0)
  end
end

puts "RHDL Simulator TUI Demo"
puts "======================="
puts ""
puts "This demo creates a simple circuit with:"
puts "  - An 8-bit counter"
puts "  - A state machine that controls the counter"
puts ""
puts "Starting TUI..."
puts ""

# Create debug simulator
sim = RHDL::HDL::DebugSimulator.new

# Create clock
clock = RHDL::HDL::Clock.new("clk", period: 10)
sim.add_clock(clock)

# Create components
counter = DemoCounter.new("counter")
fsm = DemoFSM.new("fsm")

sim.add_component(counter)
sim.add_component(fsm)

# Wire clock to both components
RHDL::HDL::SimComponent.connect(clock, counter.inputs[:clk])
RHDL::HDL::SimComponent.connect(clock, fsm.inputs[:clk])

# Connect FSM output to counter enable
RHDL::HDL::SimComponent.connect(fsm.outputs[:counter_enable], counter.inputs[:en])

# Connect counter overflow to FSM
RHDL::HDL::SimComponent.connect(counter.outputs[:overflow], fsm.inputs[:counter_overflow])

# Initialize reset signals
counter.set_input(:rst, 0)
counter.set_input(:load, 0)
counter.set_input(:data, 0)
fsm.set_input(:rst, 0)
fsm.set_input(:start, 0)
fsm.set_input(:pause, 0)

# Create TUI
tui = RHDL::HDL::SimulatorTUI.new(sim)

# Add components to TUI
tui.add_component(counter)
tui.add_component(fsm)

# Add some initial watchpoints
sim.watch(counter.outputs[:overflow], type: :rising_edge) do |s|
  tui.log("Counter overflow detected!", level: :warning)
end

sim.watch(fsm.outputs[:state], type: :change) do |s|
  state_names = %w[IDLE RUNNING PAUSED DONE]
  tui.log("FSM state changed to #{state_names[fsm.outputs[:state].get]}", level: :info)
end

# Run the TUI
tui.run
