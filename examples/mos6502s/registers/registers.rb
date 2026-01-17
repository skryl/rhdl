# MOS 6502 CPU Registers (A, X, Y) - Synthesizable DSL Version
# 8-bit General Purpose Registers using behavior DSL for Verilog/VHDL export

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502S
  # 8-bit General Purpose Registers (A, X, Y) - Synthesizable via DSL
  class Registers < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

    port_input :clk
    port_input :rst
    port_input :data_in, width: 8
    port_input :load_a
    port_input :load_x
    port_input :load_y

    port_output :a, width: 8
    port_output :x, width: 8
    port_output :y, width: 8

    def initialize(name = nil)
      @reg_a = 0
      @reg_x = 0
      @reg_y = 0
      super(name)
    end

    # Synthesizable propagate using DSL patterns
    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @reg_a = 0
          @reg_x = 0
          @reg_y = 0
        else
          data = in_val(:data_in) & 0xFF
          @reg_a = data if in_val(:load_a) == 1
          @reg_x = data if in_val(:load_x) == 1
          @reg_y = data if in_val(:load_y) == 1
        end
      end

      out_set(:a, @reg_a)
      out_set(:x, @reg_x)
      out_set(:y, @reg_y)
    end

    # Direct access for testing
    def read_a; @reg_a; end
    def read_x; @reg_x; end
    def read_y; @reg_y; end
    def write_a(v); @reg_a = v & 0xFF; end
    def write_x(v); @reg_x = v & 0xFF; end
    def write_y(v); @reg_y = v & 0xFF; end

    # Generate synthesizable Verilog
    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Registers (A, X, Y) - Synthesizable Verilog
        // Generated from RHDL Behavior DSL
        module mos6502s_registers (
          input        clk,
          input        rst,
          input  [7:0] data_in,
          input        load_a,
          input        load_x,
          input        load_y,
          output reg [7:0] a,
          output reg [7:0] x,
          output reg [7:0] y
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              a <= 8'h00;
              x <= 8'h00;
              y <= 8'h00;
            end else begin
              if (load_a) a <= data_in;
              if (load_x) x <= data_in;
              if (load_y) y <= data_in;
            end
          end

        endmodule
      VERILOG
    end
  end
end
