# RHDL HDL Module
# Hardware Description Language with simulation support

require_relative 'hdl/simulation'
require_relative 'hdl/gates'
require_relative 'hdl/sequential'
require_relative 'hdl/arithmetic'
require_relative 'hdl/combinational'
require_relative 'hdl/memory'
require_relative 'hdl/cpu'

module RHDL
  module HDL
    # Convenience method to create a simulator with components
    def self.simulator(&block)
      sim = Simulator.new
      block.call(sim) if block_given?
      sim
    end

    # Create an HDL CPU instance
    def self.cpu(name = nil)
      CPU::CPU.new(name)
    end
  end
end
