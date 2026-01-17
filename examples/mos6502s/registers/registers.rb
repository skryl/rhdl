# MOS 6502 CPU Registers (A, X, Y) - Synthesizable DSL Version
# 8-bit General Purpose Registers using sequential DSL for automatic synthesis

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502S
  # 8-bit General Purpose Registers (A, X, Y) - Synthesizable via Sequential DSL
  class Registers < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

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

    # Sequential block for both simulation and synthesis
    # Defines the clocked behavior with reset
    sequential clock: :clk, reset: :rst, reset_values: { a: 0, x: 0, y: 0 } do
      # On clock edge, conditionally load registers
      # mux(condition, when_true, when_false) generates proper Verilog ternary
      a <= mux(load_a, data_in, a)
      x <= mux(load_x, data_in, x)
      y <= mux(load_y, data_in, y)
    end

    # Direct access for testing (bypasses normal signal flow)
    def read_a; @reg_a; end
    def read_x; @reg_x; end
    def read_y; @reg_y; end
    def write_a(v); @reg_a = v & 0xFF; out_set(:a, @reg_a); end
    def write_x(v); @reg_x = v & 0xFF; out_set(:x, @reg_x); end
    def write_y(v); @reg_y = v & 0xFF; out_set(:y, @reg_y); end

    # Override propagate to maintain internal state for testing
    # The sequential block defines the synthesizable behavior,
    # but we need custom propagate to maintain @reg_* for direct access
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

    # Override to_verilog to use the proper module name
    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_registers'))
    end
  end
end
