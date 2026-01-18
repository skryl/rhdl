# MOS 6502 Program Counter - Synthesizable DSL Version
# 16-bit program counter with increment and load capabilities

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module MOS6502
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

    # Test helper accessors (use DSL state management)
    def read_pc; read_reg(:pc) || 0xFFFC; end
    def write_pc(v); write_reg(:pc, v & 0xFFFF); end

    def self.verilog_module_name
      'mos6502_program_counter'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
