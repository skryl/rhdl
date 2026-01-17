# MOS 6502 CPU Registers (A, X, Y) - Synthesizable DSL Version
# 8-bit General Purpose Registers using synthesizable patterns for Verilog/VHDL export

require_relative '../../../lib/rhdl'

module MOS6502
  # 8-bit General Purpose Registers (A, X, Y) - Synthesizable
  class Registers < RHDL::HDL::SequentialComponent
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
      @a = 0
      @x = 0
      @y = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @a = 0
          @x = 0
          @y = 0
        else
          data = in_val(:data_in) & 0xFF
          @a = data if in_val(:load_a) == 1
          @x = data if in_val(:load_x) == 1
          @y = data if in_val(:load_y) == 1
        end
      end

      out_set(:a, @a)
      out_set(:x, @x)
      out_set(:y, @y)
    end

    # Direct access for testing
    def read_a; @a; end
    def read_x; @x; end
    def read_y; @y; end
    def write_a(v); @a = v & 0xFF; end
    def write_x(v); @x = v & 0xFF; end
    def write_y(v); @y = v & 0xFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Registers (A, X, Y) - Synthesizable Verilog
        module mos6502_registers (
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
