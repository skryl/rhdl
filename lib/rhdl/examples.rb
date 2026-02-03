# frozen_string_literal: true

# Examples namespace loader
# All example implementations are nested under RHDL::Examples

module RHDL
  module Examples
    # Autoload example modules
    autoload :MOS6502, 'rhdl/examples/mos6502'
  end
end
