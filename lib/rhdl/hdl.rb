# RHDL HDL Module
# Hardware Description Language with simulation support

require_relative 'hdl/simulation'
require_relative 'hdl/gates'
require_relative 'hdl/sequential'
require_relative 'hdl/arithmetic'
require_relative 'hdl/combinational'
require_relative 'hdl/memory'
require_relative 'hdl/debug'
require_relative 'hdl/tui'
require_relative 'hdl/cpu'
require_relative 'hdl/diagram'

module RHDL
  module HDL
    # Include diagram methods in SimComponent
    SimComponent.include(DiagramMethods)
    # Convenience method to create a simulator with components
    def self.simulator(&block)
      sim = Simulator.new
      block.call(sim) if block_given?
      sim
    end

    # Create a debug simulator with TUI support
    def self.debug_simulator(&block)
      sim = DebugSimulator.new
      block.call(sim) if block_given?
      sim
    end

    # Launch the TUI for a simulator
    def self.tui(simulator = nil)
      tui = SimulatorTUI.new(simulator)
      tui
    end

    # Create an HDL CPU instance
    def self.cpu(name = nil)
      CPU::CPU.new(name)
    end
  end
end
