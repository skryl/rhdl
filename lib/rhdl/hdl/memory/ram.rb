# frozen_string_literal: true

# HDL RAM Component
# Synchronous RAM with single port
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # Synchronous RAM with single port
    # Sequential write on rising clock edge, combinational read
    class RAM < Component
      include RHDL::DSL::MemoryDSL

      input :clk
      input :we       # Write enable
      input :addr, width: 8
      input :din, width: 8
      output :dout, width: 8

      # Define memory array (256 x 8-bit)
      memory :mem, depth: 256, width: 8

      # Synchronous write
      sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din

      # Asynchronous read
      async_read :dout, from: :mem, addr: :addr

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        mem_read(:mem, addr & 0xFF)
      end

      def write_mem(addr, data)
        mem_write(:mem, addr & 0xFF, data, 8)
      end

      def load_program(program, start_addr = 0)
        program.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end

    end
  end
end
