# MOS 6502 Program Counter - Synthesizable DSL Version
# 16-bit program counter with increment and load capabilities

require_relative '../../../lib/rhdl'

module MOS6502
  # 6502 Program Counter - DSL Version
  class ProgramCounter < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :inc
    port_input :load
    port_input :addr_in, width: 16

    port_output :pc, width: 16
    port_output :pc_hi, width: 8
    port_output :pc_lo, width: 8

    def initialize(name = nil)
      @pc = 0x0000
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @pc = 0xFFFC
        elsif in_val(:load) == 1
          next_pc = in_val(:addr_in) & 0xFFFF
          next_pc = (next_pc + 1) & 0xFFFF if in_val(:inc) == 1
          @pc = next_pc
        elsif in_val(:inc) == 1
          @pc = (@pc + 1) & 0xFFFF
        end
      end

      out_set(:pc, @pc)
      out_set(:pc_hi, (@pc >> 8) & 0xFF)
      out_set(:pc_lo, @pc & 0xFF)
    end

    def read_pc; @pc; end
    def write_pc(v); @pc = v & 0xFFFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Program Counter - Synthesizable Verilog
        module mos6502_program_counter (
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
