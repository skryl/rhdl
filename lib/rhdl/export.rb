# Behavior export (RTL/Verilog)
require_relative "export/behavior/ir"
require_relative "export/behavior/lower"
require_relative "export/behavior/verilog"

# Structure export (gate-level synthesis)
require_relative "export/structure/ir"
require_relative "export/structure/primitives"
require_relative "export/structure/toposort"
require_relative "export/structure/lower"
require_relative "export/structure/sim_cpu"
require_relative "export/structure/sim_gpu"

module RHDL
  module Export
    class << self
      # Behavior Verilog export
      def verilog(component, top_name: nil)
        module_def = Lower.new(component, top_name: top_name).build
        Verilog.generate(module_def)
      end

      def write_verilog(component, path:, top_name: nil)
        File.write(path, verilog(component, top_name: top_name))
      end

      # Structure gate-level export
      def gate_level(components, backend: :cpu, lanes: 64, name: 'design')
        ir = Structure::Lower.from_components(components, name: name)
        case backend
        when :cpu
          Structure::SimCPU.new(ir, lanes: lanes)
        when :gpu
          Structure::SimGPU.new(ir, lanes: lanes)
        else
          raise ArgumentError, "Unknown backend: #{backend}"
        end
      end
    end
  end
end
