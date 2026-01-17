# MOS 6502 Instruction Register - Synthesizable DSL Version
# Holds opcode and operand bytes during instruction execution

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502S
  # Instruction Register and Operand Latches - Synthesizable via DSL
  class InstructionRegister < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

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
      <<~VERILOG
        // MOS 6502 Instruction Register - Synthesizable Verilog
        // Generated from RHDL Behavior DSL
        module mos6502s_instruction_register (
          input        clk,
          input        rst,
          input        load_opcode,
          input        load_operand_lo,
          input        load_operand_hi,
          input  [7:0] data_in,
          output reg [7:0] opcode,
          output reg [7:0] operand_lo,
          output reg [7:0] operand_hi,
          output [15:0] operand
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              opcode <= 8'h00;
              operand_lo <= 8'h00;
              operand_hi <= 8'h00;
            end else begin
              if (load_opcode) opcode <= data_in;
              if (load_operand_lo) operand_lo <= data_in;
              if (load_operand_hi) operand_hi <= data_in;
            end
          end

          assign operand = {operand_hi, operand_lo};

        endmodule
      VERILOG
    end
  end
end
