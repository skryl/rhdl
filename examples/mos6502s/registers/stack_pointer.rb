# MOS 6502 Stack Pointer - Synthesizable DSL Version
# 8-bit stack pointer with 16-bit stack address generation

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502S
  # 6502 Stack Pointer - Synthesizable via DSL
  class StackPointer < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

    STACK_BASE = 0x0100

    port_input :clk
    port_input :rst
    port_input :inc
    port_input :dec
    port_input :load
    port_input :data_in, width: 8

    port_output :sp, width: 8
    port_output :addr, width: 16
    port_output :addr_plus1, width: 16

    def initialize(name = nil)
      @sp_reg = 0xFD
      super(name)
    end

    def propagate
      sp_before = @sp_reg

      if rising_edge?
        if in_val(:rst) == 1
          @sp_reg = 0xFD
        elsif in_val(:load) == 1
          @sp_reg = in_val(:data_in) & 0xFF
        elsif in_val(:dec) == 1
          @sp_reg = (@sp_reg - 1) & 0xFF
        elsif in_val(:inc) == 1
          @sp_reg = (@sp_reg + 1) & 0xFF
        end
      end

      out_set(:sp, @sp_reg)
      out_set(:addr, STACK_BASE | sp_before)
      out_set(:addr_plus1, STACK_BASE | ((sp_before + 1) & 0xFF))
    end

    def read_sp; @sp_reg; end
    def write_sp(v); @sp_reg = v & 0xFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Stack Pointer - Synthesizable Verilog
        // Generated from RHDL Behavior DSL
        module mos6502s_stack_pointer (
          input        clk,
          input        rst,
          input        inc,
          input        dec,
          input        load,
          input  [7:0] data_in,
          output reg [7:0] sp,
          output [15:0] addr,
          output [15:0] addr_plus1
        );

          localparam STACK_BASE = 16'h0100;

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              sp <= 8'hFD;
            end else if (load) begin
              sp <= data_in;
            end else if (dec) begin
              sp <= sp - 8'h01;
            end else if (inc) begin
              sp <= sp + 8'h01;
            end
          end

          assign addr = STACK_BASE | {8'h00, sp};
          assign addr_plus1 = STACK_BASE | {8'h00, sp + 8'h01};

        endmodule
      VERILOG
    end
  end
end
