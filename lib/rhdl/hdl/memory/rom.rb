# frozen_string_literal: true

# HDL ROM Component
# Read-Only Memory with enable
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # ROM (Read-Only Memory)
    # Combinational read with enable - can be synthesized as LUT or block ROM
    class ROM < Component
      include RHDL::DSL::MemoryDSL

      parameter :contents, default: []

      input :addr, width: 8
      input :en
      output :dout, width: 8

      # Define memory array (256 x 8-bit)
      memory :mem, depth: 256, width: 8

      # Asynchronous read with enable
      async_read :dout, from: :mem, addr: :addr, enable: :en

      # Direct memory access for initialization
      def read_mem(addr)
        mem_read(:mem, addr & 0xFF)
      end

      def write_mem(addr, data)
        mem_write(:mem, addr & 0xFF, data, 8)
      end

      def load_contents(contents, start_addr = 0)
        contents.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end

    end
  end
end
