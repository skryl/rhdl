require_relative 'export/structural/ir'
require_relative 'export/structural/primitives'
require_relative 'export/structural/toposort'
require_relative 'export/structural/lower'
require_relative 'export/structural/sim_cpu'
require_relative 'export/structural/sim_gpu'

module RHDL
  module Gates
    def self.gate_level(components, backend: :cpu, lanes: 64, name: 'design')
      ir = Lower.from_components(components, name: name)
      case backend
      when :cpu
        SimCPU.new(ir, lanes: lanes)
      when :gpu
        SimGPU.new(ir, lanes: lanes)
      else
        raise ArgumentError, "Unknown backend: #{backend}"
      end
    end
  end
end
