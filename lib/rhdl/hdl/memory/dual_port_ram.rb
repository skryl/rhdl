# frozen_string_literal: true

# HDL Dual Port RAM Component
# True Dual-Port RAM with two independent read/write ports
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # True Dual-Port RAM with two independent read/write ports
    # Sequential write on rising clock edge, combinational read
    class DualPortRAM < Component
      include RHDL::DSL::MemoryDSL

      input :clk
      input :we_a
      input :we_b
      input :addr_a, width: 8
      input :addr_b, width: 8
      input :din_a, width: 8
      input :din_b, width: 8
      output :dout_a, width: 8
      output :dout_b, width: 8

      # Define memory array (256 x 8-bit)
      memory :mem, depth: 256, width: 8

      # Synchronous writes for both ports
      sync_write :mem, clock: :clk, enable: :we_a, addr: :addr_a, data: :din_a
      sync_write :mem, clock: :clk, enable: :we_b, addr: :addr_b, data: :din_b

      # Asynchronous reads for both ports
      async_read :dout_a, from: :mem, addr: :addr_a
      async_read :dout_b, from: :mem, addr: :addr_b

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        mem_read(:mem, addr & 0xFF)
      end

      def write_mem(addr, data)
        mem_write(:mem, addr & 0xFF, data, 8)
      end

    end
  end
end
