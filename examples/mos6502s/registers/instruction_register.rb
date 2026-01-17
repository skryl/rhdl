# MOS 6502 Instruction Register - Synthesizable DSL Version
# Holds opcode and operand bytes during instruction execution

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502S
  # Instruction Register and Operand Latches - Synthesizable via Sequential DSL
  class InstructionRegister < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    port_input :clk
    port_input :rst
    port_input :load_opcode
    port_input :load_operand_lo
    port_input :load_operand_hi
    port_input :data_in, width: 8

    port_output :opcode, width: 8
    port_output :operand_lo, width: 8
    port_output :operand_hi, width: 8
    port_output :operand, width: 16

    def initialize(name = nil)
      @opcode_reg = 0
      @operand_lo_reg = 0
      @operand_hi_reg = 0
      super(name)
    end

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

    # Override propagate to maintain internal state for testing
    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @opcode_reg = 0
          @operand_lo_reg = 0
          @operand_hi_reg = 0
        else
          data = in_val(:data_in) & 0xFF
          @opcode_reg = data if in_val(:load_opcode) == 1
          @operand_lo_reg = data if in_val(:load_operand_lo) == 1
          @operand_hi_reg = data if in_val(:load_operand_hi) == 1
        end
      end

      out_set(:opcode, @opcode_reg)
      out_set(:operand_lo, @operand_lo_reg)
      out_set(:operand_hi, @operand_hi_reg)
      out_set(:operand, (@operand_hi_reg << 8) | @operand_lo_reg)
    end

    def read_opcode; @opcode_reg; end
    def read_operand; (@operand_hi_reg << 8) | @operand_lo_reg; end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_instruction_register'))
    end
  end
end
