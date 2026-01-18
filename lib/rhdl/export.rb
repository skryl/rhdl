require_relative "export/ir"
require_relative "export/lower"
require_relative "export/verilog"

module RHDL
  module Export
    class << self
      def verilog(component, top_name: nil)
        module_def = Lower.new(component, top_name: top_name).build
        Verilog.generate(module_def)
      end

      def write_verilog(component, path:, top_name: nil)
        File.write(path, verilog(component, top_name: top_name))
      end
    end
  end
end
