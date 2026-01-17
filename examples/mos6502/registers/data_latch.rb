# MOS 6502 Data Latch - Synthesizable DSL Version
# 8-bit data latch for holding memory data

require_relative '../../../lib/rhdl'

module MOS6502
  # Data Latch - DSL Version
  class DataLatch < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :load
    port_input :data_in, width: 8

    port_output :data, width: 8

    def initialize(name = nil)
      @data = 0
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @data = 0
        elsif in_val(:load) == 1
          @data = in_val(:data_in) & 0xFF
        end
      end

      out_set(:data, @data)
    end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Data Latch - Synthesizable Verilog
        module mos6502_data_latch (
          input        clk,
          input        rst,
          input        load,
          input  [7:0] data_in,
          output reg [7:0] data
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              data <= 8'h00;
            end else if (load) begin
              data <= data_in;
            end
          end

        endmodule
      VERILOG
    end
  end
end
