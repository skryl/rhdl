# Behavioral export (RTL/Verilog)
require_relative "export/behavioral/ir"
require_relative "export/behavioral/lower"
require_relative "export/behavioral/verilog"

# Structural export (gate-level synthesis)
require_relative "export/structural/ir"
require_relative "export/structural/primitives"
require_relative "export/structural/toposort"
require_relative "export/structural/lower"
require_relative "export/structural/sim_cpu"
require_relative "export/structural/sim_gpu"

module RHDL
  module Export
    class << self
      # Behavioral Verilog export
      def verilog(component, top_name: nil)
        module_def = Lower.new(component, top_name: top_name).build
        Verilog.generate(module_def)
      end

      def write_verilog(component, path:, top_name: nil)
        File.write(path, verilog(component, top_name: top_name))
      end

      # Structural gate-level export
      def gate_level(components, backend: :cpu, lanes: 64, name: 'design')
        ir = Structural::Lower.from_components(components, name: name)
        case backend
        when :cpu
          Structural::SimCPU.new(ir, lanes: lanes)
        when :gpu
          Structural::SimGPU.new(ir, lanes: lanes)
        else
          raise ArgumentError, "Unknown backend: #{backend}"
        end
      end
    end
  end
end
