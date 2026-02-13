require_relative "rhdl/version"
require_relative "rhdl/dsl"
require 'rhdl/support/inflections'

module RHDL
  def self.minimal_runtime?
    env_flag = begin
      ENV['RHDL_MINIMAL_RUNTIME']
    rescue StandardError
      nil
    end
    ruby_engine = begin
      RUBY_ENGINE
    rescue NameError
      nil
    end
    env_flag == '1' || ruby_engine == 'mruby'
  end
end

unless RHDL.minimal_runtime?
  require_relative "rhdl/codegen"
end

# Load DSL codegen mixins for Sim::Component / Sim::SequentialComponent. These
# are safe to load in minimal runtime as long as codegen methods are not called.
require_relative "rhdl/dsl/codegen"
require_relative "rhdl/dsl/sequential_codegen"

module RHDL
  class Component
    include DSL
    include DSL::Behavior
    # to_verilog is provided by the DSL module's class_methods
    # behavior blocks are provided by the DSL::Behavior module
  end
end

# HDL simulation framework
if RHDL.minimal_runtime?
  require_relative "rhdl/sim"
else
  require_relative "rhdl/diagram"
  require_relative "rhdl/hdl"

  # Examples namespace (autoloaded)
  require_relative "rhdl/examples"
end
