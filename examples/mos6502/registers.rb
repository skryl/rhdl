# MOS 6502 CPU Registers - Synthesizable DSL Version
# Contains A, X, Y registers, Stack Pointer, Program Counter, and latches
# All components use synthesizable patterns for Verilog/VHDL export

require_relative '../../lib/rhdl'

# Load individual register components
require_relative 'registers/registers'
require_relative 'registers/stack_pointer'
require_relative 'registers/program_counter'
require_relative 'registers/instruction_register'
require_relative 'registers/address_latch'
require_relative 'registers/data_latch'

module MOS6502
  # Register selection constants
  REG_A = 0
  REG_X = 1
  REG_Y = 2

  # Aliases for backward compatibility
  StackPointer6502 = StackPointer
  ProgramCounter6502 = ProgramCounter
end
