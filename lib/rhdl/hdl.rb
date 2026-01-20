# RHDL HDL Module
# Hardware Description Language with simulation support

require_relative 'sim'

# Base class aliases for HDL component definitions
module RHDL
  module HDL
    SimComponent = Sim::Component
    SequentialComponent = Sim::SequentialComponent
  end
end

require_relative 'hdl/gates'
require_relative 'hdl/sequential'
require_relative 'hdl/arithmetic'
require_relative 'hdl/combinational'
require_relative 'hdl/memory'
require_relative 'debug'
require_relative 'tui'
require_relative 'hdl/cpu/harness'

module RHDL
  module HDL
    # Include diagram methods in SimComponent
    SimComponent.include(RHDL::Diagram::Methods)
    # Convenience method to create a simulator with components
    def self.simulator(&block)
      sim = RHDL::Sim::Simulator.new
      block.call(sim) if block_given?
      sim
    end

    # Create a debug simulator with TUI support
    def self.debug_simulator(&block)
      sim = RHDL::Debug::DebugSimulator.new
      block.call(sim) if block_given?
      sim
    end

    # Launch the TUI for a simulator
    def self.tui(simulator = nil)
      tui = RHDL::TUI::SimulatorTUI.new(simulator)
      tui
    end

    # Create an HDL CPU instance
    def self.cpu(name = nil)
      CPU::Harness.new(name)
    end
  end
end
