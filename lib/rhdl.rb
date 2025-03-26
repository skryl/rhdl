require_relative "rhdl/version"
require_relative "rhdl/dsl"
require 'active_support/core_ext/string/inflections'

module RHDL
  class Component
    include DSL

    def self.to_vhdl
      vhdl = []
      
      # Entity declaration
      vhdl << "entity #{name.demodulize.underscore} is"
      vhdl << "  port ("
      vhdl << ports.map { |p| "    #{p.to_vhdl}" }.join("\n")
      vhdl << "  );"
      vhdl << "end #{name.demodulize.underscore};"
      vhdl << ""
      
      # Architecture
      vhdl << "architecture rtl of #{name.demodulize.underscore} is"
      unless signals.empty?
        vhdl << "  -- Internal signals"
        vhdl << signals.map { |s| "  #{s.to_vhdl}" }.join("\n")
      end
      vhdl << "begin"
      vhdl << "  -- Architecture implementation goes here"
      vhdl << "end rtl;"
      
      vhdl.join("\n")
    end
  end
end

# Require all component files
require_relative "rhdl/components/gates"
require_relative "rhdl/components/arithmetic"
require_relative "rhdl/components/multiplexers"
require_relative "rhdl/components/storage"
require_relative "rhdl/components/comparators"

# CPU components
require_relative "rhdl/components/cpu/cpu"
require_relative "rhdl/components/cpu/control_unit"
require_relative "rhdl/components/cpu/program_counter"
require_relative "rhdl/components/cpu/cpu_alu"
require_relative "rhdl/components/cpu/memory_unit"
require_relative "rhdl/components/cpu/accumulator"
