# RV32F FP Register File - 32 x 32-bit registers
# Two read ports, one write port

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative '../../../lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module RISCV
      class FPRegisterFile < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential
    include RHDL::DSL::Memory

    input :clk
    input :rst

    input :rs1_addr, width: 5
    input :rs2_addr, width: 5
    output :rs1_data, width: 32
    output :rs2_data, width: 32

    input :rd_addr, width: 5
    input :rd_data, width: 32
    input :rd_we

    memory :regs, depth: 32, width: 32
    wire :rf_write_en
    sync_write :regs, clock: :clk, enable: :rf_write_en, addr: :rd_addr, data: :rd_data

    behavior do
      rf_write_en <= rd_we & ~rst
      rs1_data <= mem_read_expr(:regs, rs1_addr, width: 32)
      rs2_data <= mem_read_expr(:regs, rs2_addr, width: 32)
    end

    def initialize(name = nil)
      super(name)
      @regs = Array.new(32, 0)
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      if rst == 1
        @regs = Array.new(32, 0)
        update_outputs
        @prev_clk = clk
        return
      end

      if @prev_clk == 0 && clk == 1
        rd_we = in_val(:rd_we)
        rd_addr = in_val(:rd_addr)
        rd_data = in_val(:rd_data)
        @regs[rd_addr & 0x1F] = rd_data & 0xFFFF_FFFF if rd_we == 1
      end
      @prev_clk = clk

      update_outputs
    end

    def update_outputs
      rs1_addr = in_val(:rs1_addr) & 0x1F
      rs2_addr = in_val(:rs2_addr) & 0x1F
      out_set(:rs1_data, @regs[rs1_addr] & 0xFFFF_FFFF)
      out_set(:rs2_data, @regs[rs2_addr] & 0xFFFF_FFFF)
    end

    def read_reg(index)
      @regs[index & 0x1F] & 0xFFFF_FFFF
    end

    def write_reg(index, value)
      @regs[index & 0x1F] = value & 0xFFFF_FFFF
    end
      end
    end
  end
end
