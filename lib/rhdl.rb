require_relative "rhdl/version"
require_relative "rhdl/dsl"
require_relative "rhdl/exporter"
require 'active_support/core_ext/string/inflections'

module RHDL
  class Component
    include DSL
    # to_vhdl and to_verilog are provided by the DSL module's class_methods
  end
end

# CPU components (top-level directory)
require_relative "../cpu/cpu"
require_relative "../cpu/control_unit"
require_relative "../cpu/program_counter"
require_relative "../cpu/cpu_alu"
require_relative "../cpu/memory_unit"
require_relative "../cpu/accumulator"

# HDL simulation framework
require_relative "rhdl/hdl"
require_relative "rhdl/gates"
require_relative "rhdl/diagram"
