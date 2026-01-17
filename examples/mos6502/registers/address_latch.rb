# MOS 6502 Address Latch - Synthesizable DSL Version
# 16-bit address latch with byte-wise and full loading

require_relative '../../../lib/rhdl'

module MOS6502
  # Address Latch - DSL Version
  class AddressLatch < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :load_lo
    port_input :load_hi
    port_input :load_full
    port_input :data_in, width: 8
    port_input :addr_in, width: 16

    port_output :addr, width: 16
    port_output :addr_lo, width: 8
    port_output :addr_hi, width: 8

    def initialize(name = nil)
      @addr_lo = 0
      @addr_hi = 0
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @addr_lo = 0
          @addr_hi = 0
        elsif in_val(:load_full) == 1
          addr = in_val(:addr_in) & 0xFFFF
          @addr_lo = addr & 0xFF
          @addr_hi = (addr >> 8) & 0xFF
        else
          data = in_val(:data_in) & 0xFF
          @addr_lo = data if in_val(:load_lo) == 1
          @addr_hi = data if in_val(:load_hi) == 1
        end
      end

      out_set(:addr, (@addr_hi << 8) | @addr_lo)
      out_set(:addr_lo, @addr_lo)
      out_set(:addr_hi, @addr_hi)
    end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Address Latch - Synthesizable Verilog
        module mos6502_address_latch (
          input         clk,
          input         rst,
          input         load_lo,
          input         load_hi,
          input         load_full,
          input   [7:0] data_in,
          input  [15:0] addr_in,
          output [15:0] addr,
          output  [7:0] addr_lo,
          output  [7:0] addr_hi
        );

          reg [7:0] addr_lo_reg;
          reg [7:0] addr_hi_reg;

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              addr_lo_reg <= 8'h00;
              addr_hi_reg <= 8'h00;
            end else if (load_full) begin
              addr_lo_reg <= addr_in[7:0];
              addr_hi_reg <= addr_in[15:8];
            end else begin
              if (load_lo) addr_lo_reg <= data_in;
              if (load_hi) addr_hi_reg <= data_in;
            end
          end

          assign addr = {addr_hi_reg, addr_lo_reg};
          assign addr_lo = addr_lo_reg;
          assign addr_hi = addr_hi_reg;

        endmodule
      VERILOG
    end
  end
end
