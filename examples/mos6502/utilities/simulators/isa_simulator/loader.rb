# frozen_string_literal: true

# Behavioral 8-bit CPU simulator loader
# Loads all CPU component classes for testing

# Define the namespace modules first
module RHDL
  module Examples
    module MOS6502
      module Components
        module CPU
        end
      end
    end
  end
end

# Load CPU components
require_relative 'accumulator'
require_relative 'program_counter'
require_relative 'memory_unit'
require_relative 'cpu_alu'
require_relative 'control_unit'
require_relative 'cpu'
