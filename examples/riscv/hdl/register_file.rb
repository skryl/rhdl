# RV32I Register File - 32 x 32-bit registers
# Register x0 is hardwired to zero
# Two read ports, one write port
# Uses sequential DSL for synthesizable Verilog

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      class RegisterFile < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst

    # Read ports (asynchronous)
    input :rs1_addr, width: 5    # Source register 1 address
    input :rs2_addr, width: 5    # Source register 2 address
    output :rs1_data, width: 32  # Source register 1 data
    output :rs2_data, width: 32  # Source register 2 data

    # Write port (synchronous)
    input :rd_addr, width: 5     # Destination register address
    input :rd_data, width: 32    # Write data
    input :rd_we                 # Write enable

    # Debug outputs for testing
    output :debug_x1, width: 32
    output :debug_x2, width: 32
    output :debug_x10, width: 32
    output :debug_x11, width: 32

    def initialize(name = nil, forwarding: false)
      super(name)
      # Internal register storage
      @regs = Array.new(32, 0)
      @regs[0] = 0  # x0 always 0
      # Enable internal forwarding for pipelined designs
      # Disable for single-cycle to avoid stale value issues with DSL propagation
      @forwarding = forwarding
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      # Handle reset
      if rst == 1
        @regs = Array.new(32, 0)
        update_outputs
        @prev_clk = clk
        return
      end

      # Rising edge detection for writes
      if @prev_clk == 0 && clk == 1
        rd_we = in_val(:rd_we)
        rd_addr = in_val(:rd_addr)
        rd_data = in_val(:rd_data)

        # Write to register if enabled and not x0
        if rd_we == 1 && rd_addr != 0
          @regs[rd_addr] = rd_data & 0xFFFFFFFF
        end
      end
      @prev_clk = clk

      # Asynchronous reads
      update_outputs
    end

    def update_outputs
      rs1_addr = in_val(:rs1_addr)
      rs2_addr = in_val(:rs2_addr)

      if @forwarding
        # Internal forwarding: if reading the register being written, return write data
        # This handles the write-read hazard when WB and ID happen in the same cycle
        # Used by pipelined designs
        rd_addr = in_val(:rd_addr)
        rd_data = in_val(:rd_data)
        rd_we = in_val(:rd_we)

        if rd_we == 1 && rd_addr != 0
          rs1_val = (rs1_addr == rd_addr) ? rd_data : (rs1_addr == 0 ? 0 : @regs[rs1_addr])
          rs2_val = (rs2_addr == rd_addr) ? rd_data : (rs2_addr == 0 ? 0 : @regs[rs2_addr])
        else
          rs1_val = rs1_addr == 0 ? 0 : @regs[rs1_addr]
          rs2_val = rs2_addr == 0 ? 0 : @regs[rs2_addr]
        end
      else
        # Simple reads from register array
        # In single-cycle design, writes happen at clock edge after all reads complete
        rs1_val = rs1_addr == 0 ? 0 : @regs[rs1_addr]
        rs2_val = rs2_addr == 0 ? 0 : @regs[rs2_addr]
      end

      out_set(:rs1_data, rs1_val)
      out_set(:rs2_data, rs2_val)

      # Debug outputs
      out_set(:debug_x1, @regs[1])
      out_set(:debug_x2, @regs[2])
      out_set(:debug_x10, @regs[10])
      out_set(:debug_x11, @regs[11])
    end

    # Direct register access for testing
    def read_reg(index)
      index == 0 ? 0 : @regs[index]
    end

    def write_reg(index, value)
      @regs[index] = value & 0xFFFFFFFF unless index == 0
    end

      end
    end
  end
end
