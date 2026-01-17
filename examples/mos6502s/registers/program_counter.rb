# MOS 6502 Program Counter - Synthesizable DSL Version
# 16-bit program counter with increment and load capabilities

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502S
  # 6502 Program Counter - Synthesizable via DSL
  class ProgramCounter < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

    port_input :clk
    port_input :rst
    port_input :inc
    port_input :load
    port_input :addr_in, width: 16

    port_output :pc, width: 16
    port_output :pc_hi, width: 8
    port_output :pc_lo, width: 8

    def initialize(name = nil)
      @pc_reg = 0x0000
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @pc_reg = 0xFFFC
        elsif in_val(:load) == 1
          next_pc = in_val(:addr_in) & 0xFFFF
          next_pc = (next_pc + 1) & 0xFFFF if in_val(:inc) == 1
          @pc_reg = next_pc
        elsif in_val(:inc) == 1
          @pc_reg = (@pc_reg + 1) & 0xFFFF
        end
      end

      out_set(:pc, @pc_reg)
      out_set(:pc_hi, (@pc_reg >> 8) & 0xFF)
      out_set(:pc_lo, @pc_reg & 0xFF)
    end

    def read_pc; @pc_reg; end
    def write_pc(v); @pc_reg = v & 0xFFFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Program Counter - Synthesizable Verilog
        // Generated from RHDL Behavior DSL
        module mos6502s_program_counter (
          input         clk,
          input         rst,
          input         inc,
          input         load,
          input  [15:0] addr_in,
          output reg [15:0] pc,
          output  [7:0] pc_hi,
          output  [7:0] pc_lo
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              pc <= 16'hFFFC;
            end else if (load) begin
              if (inc)
                pc <= addr_in + 16'h0001;
              else
                pc <= addr_in;
            end else if (inc) begin
              pc <= pc + 16'h0001;
            end
          end

          assign pc_hi = pc[15:8];
          assign pc_lo = pc[7:0];

        endmodule
      VERILOG
    end
  end
end
