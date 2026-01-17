# MOS 6502 Data Latch - Synthesizable DSL Version
# 8-bit data latch for holding memory data

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502S
  # Data Latch - Synthesizable via DSL
  class DataLatch < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

    port_input :clk
    port_input :rst
    port_input :load
    port_input :data_in, width: 8

    port_output :data, width: 8

    def initialize(name = nil)
      @data_reg = 0
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @data_reg = 0
        elsif in_val(:load) == 1
          @data_reg = in_val(:data_in) & 0xFF
        end
      end

      out_set(:data, @data_reg)
    end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Data Latch - Synthesizable Verilog
        // Generated from RHDL Behavior DSL
        module mos6502s_data_latch (
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
