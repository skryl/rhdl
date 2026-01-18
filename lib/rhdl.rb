require_relative "rhdl/version"
require_relative "rhdl/dsl"
require_relative "rhdl/export"
require 'active_support/core_ext/string/inflections'

module RHDL
  class Component
    include DSL
    include DSL::Behavior
    # to_verilog is provided by the DSL module's class_methods
    # behavior blocks are provided by the DSL::Behavior module
  end
end

# HDL simulation framework
require_relative "rhdl/diagram"
require_relative "rhdl/hdl"
