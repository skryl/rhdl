require_relative 'gates/ir'
require_relative 'gates/primitives'
require_relative 'gates/toposort'
require_relative 'gates/lower'
require_relative 'gates/sim_cpu'
require_relative 'gates/sim_gpu'

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
