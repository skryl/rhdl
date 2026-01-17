# MOS 6502 Program Counter - Synthesizable DSL Version
# 16-bit program counter with increment and load capabilities

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502S
  # 6502 Program Counter - Synthesizable via Sequential DSL
  class ProgramCounter < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    port_input :clk
    port_input :rst
    port_input :inc
    port_input :load
    port_input :addr_in, width: 16

    port_output :pc, width: 16
    port_output :pc_hi, width: 8
    port_output :pc_lo, width: 8

    def initialize(name = nil)
      @pc_reg = 0x0000
      super(name)
    end

    # Sequential block for the PC register
    # Priority: reset > load+inc > load > inc > hold
    sequential clock: :clk, reset: :rst, reset_values: { pc: 0xFFFC } do
      # Complex priority logic using nested mux:
      # if load && inc: pc = addr_in + 1
      # elif load: pc = addr_in
      # elif inc: pc = pc + 1
      # else: hold
      pc <= mux(load,
               mux(inc, addr_in + lit(1, width: 16), addr_in),
               mux(inc, pc + lit(1, width: 16), pc))
    end

    # Combinational outputs derived from pc
    behavior do
      pc_hi <= pc[15..8]
      pc_lo <= pc[7..0]
    end

    # Override propagate to maintain internal state for testing
    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @pc_reg = 0xFFFC
        elsif in_val(:load) == 1
          next_pc = in_val(:addr_in) & 0xFFFF
          next_pc = (next_pc + 1) & 0xFFFF if in_val(:inc) == 1
          @pc_reg = next_pc
        elsif in_val(:inc) == 1
          @pc_reg = (@pc_reg + 1) & 0xFFFF
        end
      end

      out_set(:pc, @pc_reg)
      out_set(:pc_hi, (@pc_reg >> 8) & 0xFF)
      out_set(:pc_lo, @pc_reg & 0xFF)
    end

    def read_pc; @pc_reg; end
    def write_pc(v); @pc_reg = v & 0xFFFF; end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_program_counter'))
    end
  end
end
