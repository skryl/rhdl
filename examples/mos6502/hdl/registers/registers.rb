# MOS 6502 CPU Registers (A, X, Y) - Synthesizable DSL Version
# 8-bit General Purpose Registers using sequential DSL for automatic synthesis

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module MOS6502
  # 8-bit General Purpose Registers (A, X, Y) - Synthesizable via Sequential DSL
  class Registers < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :data_in, width: 8
    input :load_a
    input :load_x
    input :load_y

    output :a, width: 8
    output :x, width: 8
    output :y, width: 8

    # Sequential block for both simulation and synthesis
    # Defines the clocked behavior with reset
    sequential clock: :clk, reset: :rst, reset_values: { a: 0, x: 0, y: 0 } do
      # On clock edge, conditionally load registers
      # mux(condition, when_true, when_false) generates proper Verilog ternary
      a <= mux(load_a, data_in, a)
      x <= mux(load_x, data_in, x)
      y <= mux(load_y, data_in, y)
    end

    # Test helper accessors (use DSL state management)
    def read_a; read_reg(:a) || 0; end
    def read_x; read_reg(:x) || 0; end
    def read_y; read_reg(:y) || 0; end
    def write_a(v); write_reg(:a, v & 0xFF); end
    def write_x(v); write_reg(:x, v & 0xFF); end
    def write_y(v); write_reg(:y, v & 0xFF); end

    def self.verilog_module_name
      'mos6502_registers'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
