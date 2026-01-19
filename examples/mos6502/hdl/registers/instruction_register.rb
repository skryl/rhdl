# MOS 6502 Instruction Register - Synthesizable DSL Version
# Holds opcode and operand bytes during instruction execution

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module MOS6502
  # Instruction Register and Operand Latches - Synthesizable via Sequential DSL
  class InstructionRegister < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :load_opcode
    input :load_operand_lo
    input :load_operand_hi
    input :data_in, width: 8

    output :opcode, width: 8
    output :operand_lo, width: 8
    output :operand_hi, width: 8
    output :operand, width: 16

    # Sequential block for opcode and operand registers
    sequential clock: :clk, reset: :rst, reset_values: { opcode: 0, operand_lo: 0, operand_hi: 0 } do
      opcode <= mux(load_opcode, data_in, opcode)
      operand_lo <= mux(load_operand_lo, data_in, operand_lo)
      operand_hi <= mux(load_operand_hi, data_in, operand_hi)
    end

    # Combinational output: 16-bit operand from hi/lo bytes
    behavior do
      operand <= cat(operand_hi, operand_lo)
    end

    # Test helper accessors (use DSL state management)
    def read_opcode; read_reg(:opcode) || 0; end
    def read_operand; ((read_reg(:operand_hi) || 0) << 8) | (read_reg(:operand_lo) || 0); end

  end
end
