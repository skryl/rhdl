# MOS 6502 Address Generation Unit - Synthesizable DSL Version
# Computes effective addresses for all 6502 addressing modes
# Combinational logic - direct Verilog synthesis

require_relative '../../../lib/rhdl'

# Load individual address generation components
require_relative 'address_gen/address_generator'
require_relative 'address_gen/indirect_address_calc'

module MOS6502
  # Module is populated by the required files
end
