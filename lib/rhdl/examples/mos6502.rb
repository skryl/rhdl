# frozen_string_literal: true

# MOS6502 example loader
# Loads the MOS6502 CPU implementation from examples/mos6502

module RHDL
  module Examples
    module MOS6502
    end
  end
end

# Load MOS6502 components from examples directory
require_relative '../../../examples/mos6502/hdl/cpu'
