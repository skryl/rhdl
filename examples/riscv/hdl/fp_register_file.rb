# RV32F/RV32D FP Register File - 32 x 64-bit registers
# Two read ports, one write port (current datapath writes 32-bit values).
# 32-bit writes are NaN-boxed into the 64-bit register storage.

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
    input :rs3_addr, width: 5
    output :rs1_data, width: 32
    output :rs2_data, width: 32
    output :rs3_data, width: 32
    output :rs1_data64, width: 64
    output :rs2_data64, width: 64
    output :rs3_data64, width: 64

    input :rd_addr, width: 5
    input :rd_data, width: 32
    input :rd_we
    input :rd_data64, width: 64
    input :rd_we64

    memory :regs, depth: 32, width: 64
    wire :rf_write_en
    wire :rd_data_nanboxed, width: 64
    wire :rd_data_write, width: 64
    sync_write :regs, clock: :clk, enable: :rf_write_en, addr: :rd_addr, data: :rd_data_write

    behavior do
      rf_write_en <= (rd_we | rd_we64) & ~rst
      rd_data_nanboxed <= cat(lit(0xFFFF_FFFF, width: 32), rd_data)
      rd_data_write <= mux(rd_we64, rd_data64, rd_data_nanboxed)
      rs1_word = local(:rs1_word, mem_read_expr(:regs, rs1_addr, width: 64), width: 64)
      rs2_word = local(:rs2_word, mem_read_expr(:regs, rs2_addr, width: 64), width: 64)
      rs3_word = local(:rs3_word, mem_read_expr(:regs, rs3_addr, width: 64), width: 64)
      rs1_data <= rs1_word[31..0]
      rs2_data <= rs2_word[31..0]
      rs3_data <= rs3_word[31..0]
      rs1_data64 <= rs1_word
      rs2_data64 <= rs2_word
      rs3_data64 <= rs3_word
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
        rd_we64 = in_val(:rd_we64)
        rd_addr = in_val(:rd_addr)
        rd_data = in_val(:rd_data)
        rd_data64 = in_val(:rd_data64)
        if rd_we64 == 1
          @regs[rd_addr & 0x1F] = rd_data64 & 0xFFFF_FFFF_FFFF_FFFF
        elsif rd_we == 1
          nanboxed = 0xFFFF_FFFF_0000_0000 | (rd_data & 0xFFFF_FFFF)
          @regs[rd_addr & 0x1F] = nanboxed & 0xFFFF_FFFF_FFFF_FFFF
        end
      end
      @prev_clk = clk

      update_outputs
    end

    def update_outputs
      rs1_addr = in_val(:rs1_addr) & 0x1F
      rs2_addr = in_val(:rs2_addr) & 0x1F
      rs3_addr = in_val(:rs3_addr) & 0x1F
      out_set(:rs1_data, @regs[rs1_addr] & 0xFFFF_FFFF)
      out_set(:rs2_data, @regs[rs2_addr] & 0xFFFF_FFFF)
      out_set(:rs3_data, @regs[rs3_addr] & 0xFFFF_FFFF)
      out_set(:rs1_data64, @regs[rs1_addr] & 0xFFFF_FFFF_FFFF_FFFF)
      out_set(:rs2_data64, @regs[rs2_addr] & 0xFFFF_FFFF_FFFF_FFFF)
      out_set(:rs3_data64, @regs[rs3_addr] & 0xFFFF_FFFF_FFFF_FFFF)
    end

    def read_reg(index)
      @regs[index & 0x1F] & 0xFFFF_FFFF
    end

    def read_reg64(index)
      @regs[index & 0x1F] & 0xFFFF_FFFF_FFFF_FFFF
    end

    def write_reg(index, value)
      @regs[index & 0x1F] = (0xFFFF_FFFF_0000_0000 | (value & 0xFFFF_FFFF)) & 0xFFFF_FFFF_FFFF_FFFF
    end

    def write_reg64(index, value)
      @regs[index & 0x1F] = value & 0xFFFF_FFFF_FFFF_FFFF
    end
      end
    end
  end
end
