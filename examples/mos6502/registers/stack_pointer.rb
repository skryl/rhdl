# MOS 6502 Stack Pointer - Synthesizable DSL Version
# 8-bit stack pointer with 16-bit stack address generation

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502
  # 6502 Stack Pointer - Synthesizable via Sequential DSL
  class StackPointer < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

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

    # Sequential block for the SP register with priority encoding
    # Priority: load > dec > inc (if none, hold value)
    sequential clock: :clk, reset: :rst, reset_values: { sp: 0xFD } do
      # Nested mux for priority: load > dec > inc > hold
      sp <= mux(load, data_in,
               mux(dec, sp - lit(1, width: 8),
                  mux(inc, sp + lit(1, width: 8), sp)))
    end

    # Combinational block for address outputs
    behavior do
      # addr = STACK_BASE | sp = 0x0100 | sp
      addr <= cat(lit(0x01, width: 8), sp)
      # addr_plus1 = STACK_BASE | (sp + 1), masked to 8 bits
      addr_plus1 <= cat(lit(0x01, width: 8), (sp + lit(1, width: 8))[7..0])
    end

    # Test helper accessors (use DSL state management)
    def read_sp; read_reg(:sp) || 0xFD; end
    def write_sp(v); write_reg(:sp, v & 0xFF); end

    def self.verilog_module_name
      'mos6502_stack_pointer'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
