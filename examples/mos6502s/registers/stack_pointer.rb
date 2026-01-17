# MOS 6502 Stack Pointer - Synthesizable DSL Version
# 8-bit stack pointer with 16-bit stack address generation

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502S
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

    def initialize(name = nil)
      @sp_reg = 0xFD
      super(name)
    end

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

    # Override propagate to maintain internal state for testing
    def propagate
      sp_before = @sp_reg

      if rising_edge?
        if in_val(:rst) == 1
          @sp_reg = 0xFD
        elsif in_val(:load) == 1
          @sp_reg = in_val(:data_in) & 0xFF
        elsif in_val(:dec) == 1
          @sp_reg = (@sp_reg - 1) & 0xFF
        elsif in_val(:inc) == 1
          @sp_reg = (@sp_reg + 1) & 0xFF
        end
      end

      out_set(:sp, @sp_reg)
      out_set(:addr, STACK_BASE | sp_before)
      out_set(:addr_plus1, STACK_BASE | ((sp_before + 1) & 0xFF))
    end

    def read_sp; @sp_reg; end
    def write_sp(v); @sp_reg = v & 0xFF; end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_stack_pointer'))
    end
  end
end
