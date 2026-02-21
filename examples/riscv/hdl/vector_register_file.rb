# RVV vector register file (scoped baseline)
# 32 vector registers, each with 4 x 32-bit lanes (VLEN=128, SEW=32).

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative '../../../lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module RISCV
      class VectorRegisterFile < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory

        LANES = 4

        input :clk
        input :rst

        # Read ports (asynchronous)
        input :rs1_addr, width: 5
        input :rs2_addr, width: 5
        input :rd_addr_read, width: 5
        output :rs1_lane0, width: 32
        output :rs1_lane1, width: 32
        output :rs1_lane2, width: 32
        output :rs1_lane3, width: 32
        output :rs2_lane0, width: 32
        output :rs2_lane1, width: 32
        output :rs2_lane2, width: 32
        output :rs2_lane3, width: 32
        output :rd_lane0, width: 32
        output :rd_lane1, width: 32
        output :rd_lane2, width: 32
        output :rd_lane3, width: 32

        # Write port (synchronous)
        input :rd_addr, width: 5
        input :rd_lane0_in, width: 32
        input :rd_lane1_in, width: 32
        input :rd_lane2_in, width: 32
        input :rd_lane3_in, width: 32
        input :rd_we

        wire :write_en
        wire :rd_addr_lane0, width: 7
        wire :rd_addr_lane1, width: 7
        wire :rd_addr_lane2, width: 7
        wire :rd_addr_lane3, width: 7

        memory :regs, depth: 128, width: 32
        sync_write :regs, clock: :clk, enable: :write_en, addr: :rd_addr_lane0, data: :rd_lane0_in
        sync_write :regs, clock: :clk, enable: :write_en, addr: :rd_addr_lane1, data: :rd_lane1_in
        sync_write :regs, clock: :clk, enable: :write_en, addr: :rd_addr_lane2, data: :rd_lane2_in
        sync_write :regs, clock: :clk, enable: :write_en, addr: :rd_addr_lane3, data: :rd_lane3_in

        behavior do
          write_en <= rd_we & ~rst
          rd_addr_lane0 <= cat(rd_addr, lit(0, width: 2))
          rd_addr_lane1 <= cat(rd_addr, lit(1, width: 2))
          rd_addr_lane2 <= cat(rd_addr, lit(2, width: 2))
          rd_addr_lane3 <= cat(rd_addr, lit(3, width: 2))

          rs1_lane0 <= mem_read_expr(:regs, cat(rs1_addr, lit(0, width: 2)), width: 32)
          rs1_lane1 <= mem_read_expr(:regs, cat(rs1_addr, lit(1, width: 2)), width: 32)
          rs1_lane2 <= mem_read_expr(:regs, cat(rs1_addr, lit(2, width: 2)), width: 32)
          rs1_lane3 <= mem_read_expr(:regs, cat(rs1_addr, lit(3, width: 2)), width: 32)

          rs2_lane0 <= mem_read_expr(:regs, cat(rs2_addr, lit(0, width: 2)), width: 32)
          rs2_lane1 <= mem_read_expr(:regs, cat(rs2_addr, lit(1, width: 2)), width: 32)
          rs2_lane2 <= mem_read_expr(:regs, cat(rs2_addr, lit(2, width: 2)), width: 32)
          rs2_lane3 <= mem_read_expr(:regs, cat(rs2_addr, lit(3, width: 2)), width: 32)

          rd_lane0 <= mem_read_expr(:regs, cat(rd_addr_read, lit(0, width: 2)), width: 32)
          rd_lane1 <= mem_read_expr(:regs, cat(rd_addr_read, lit(1, width: 2)), width: 32)
          rd_lane2 <= mem_read_expr(:regs, cat(rd_addr_read, lit(2, width: 2)), width: 32)
          rd_lane3 <= mem_read_expr(:regs, cat(rd_addr_read, lit(3, width: 2)), width: 32)
        end

        def initialize(name = nil)
          super(name)
          @regs = Array.new(128, 0)
        end

        def propagate
          clk = in_val(:clk)
          rst = in_val(:rst)
          @prev_clk ||= 0

          if rst == 1
            @regs = Array.new(128, 0)
            update_outputs
            @prev_clk = clk
            return
          end

          if @prev_clk == 0 && clk == 1
            if in_val(:rd_we) == 1
              base = (in_val(:rd_addr) & 0x1F) * LANES
              @regs[base] = in_val(:rd_lane0_in) & 0xFFFF_FFFF
              @regs[base + 1] = in_val(:rd_lane1_in) & 0xFFFF_FFFF
              @regs[base + 2] = in_val(:rd_lane2_in) & 0xFFFF_FFFF
              @regs[base + 3] = in_val(:rd_lane3_in) & 0xFFFF_FFFF
            end
          end
          @prev_clk = clk

          update_outputs
        end

        def read_vreg(index)
          base = (index & 0x1F) * LANES
          [@regs[base], @regs[base + 1], @regs[base + 2], @regs[base + 3]].map { |v| v & 0xFFFF_FFFF }
        end

        def write_vreg(index, lanes)
          base = (index & 0x1F) * LANES
          values = Array.new(LANES, 0)
          lanes.each_with_index { |v, i| values[i] = v if i < LANES }
          @regs[base] = values[0].to_i & 0xFFFF_FFFF
          @regs[base + 1] = values[1].to_i & 0xFFFF_FFFF
          @regs[base + 2] = values[2].to_i & 0xFFFF_FFFF
          @regs[base + 3] = values[3].to_i & 0xFFFF_FFFF
        end

        private

        def update_outputs
          rs1_base = (in_val(:rs1_addr) & 0x1F) * LANES
          rs2_base = (in_val(:rs2_addr) & 0x1F) * LANES
          rd_base = (in_val(:rd_addr_read) & 0x1F) * LANES

          out_set(:rs1_lane0, @regs[rs1_base] & 0xFFFF_FFFF)
          out_set(:rs1_lane1, @regs[rs1_base + 1] & 0xFFFF_FFFF)
          out_set(:rs1_lane2, @regs[rs1_base + 2] & 0xFFFF_FFFF)
          out_set(:rs1_lane3, @regs[rs1_base + 3] & 0xFFFF_FFFF)

          out_set(:rs2_lane0, @regs[rs2_base] & 0xFFFF_FFFF)
          out_set(:rs2_lane1, @regs[rs2_base + 1] & 0xFFFF_FFFF)
          out_set(:rs2_lane2, @regs[rs2_base + 2] & 0xFFFF_FFFF)
          out_set(:rs2_lane3, @regs[rs2_base + 3] & 0xFFFF_FFFF)

          out_set(:rd_lane0, @regs[rd_base] & 0xFFFF_FFFF)
          out_set(:rd_lane1, @regs[rd_base + 1] & 0xFFFF_FFFF)
          out_set(:rd_lane2, @regs[rd_base + 2] & 0xFFFF_FFFF)
          out_set(:rd_lane3, @regs[rd_base + 3] & 0xFFFF_FFFF)
        end
      end
    end
  end
end
