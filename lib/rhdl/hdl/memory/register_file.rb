# frozen_string_literal: true

# HDL Register File Component
# Multiple registers with read/write ports
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # Register File (multiple registers with read/write ports)
    # Sequential write, combinational read - typical FPGA register file
    class RegisterFile < Component
      include RHDL::DSL::MemoryDSL

      input :clk
      input :we
      input :waddr, width: 3
      input :raddr1, width: 3
      input :raddr2, width: 3
      input :wdata, width: 8
      output :rdata1, width: 8
      output :rdata2, width: 8

      # Define register array (8 x 8-bit registers)
      memory :registers, depth: 8, width: 8

      # Synchronous write
      sync_write :registers, clock: :clk, enable: :we, addr: :waddr, data: :wdata

      # Asynchronous reads from both ports
      async_read :rdata1, from: :registers, addr: :raddr1
      async_read :rdata2, from: :registers, addr: :raddr2

      # Direct register access for debugging
      def read_reg(addr)
        mem_read(:registers, addr & 0x7)
      end

      def write_reg(addr, data)
        mem_write(:registers, addr & 0x7, data, 8)
      end

    end
  end
end
