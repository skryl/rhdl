# frozen_string_literal: true

# Apple II RAM
# Based on neoapple2 implementation
#
# 48KB main RAM for Apple II
# Synchronous RAM with single port
# Address range: $0000 - $BFFF (48K)

require 'rhdl'

module RHDL
  module Apple2
    class RAM < Component
      include RHDL::DSL::Memory

      # Parameters
      parameter :addr_width, default: 16
      parameter :data_width, default: 8
      parameter :depth, default: 48 * 1024  # 48KB

      # Ports
      input :clk
      input :cs                           # Chip select
      input :we                           # Write enable
      input :addr, width: :addr_width
      input :din, width: :data_width
      output :dout, width: :data_width

      # Define memory array
      memory :mem, depth: :depth, width: :data_width

      # Synchronous write on rising edge when cs and we are high
      # Using expression-based enable: no intermediate wire needed
      sync_write :mem, clock: :clk, enable: [:cs, :&, :we], addr: :addr, data: :din

      # Asynchronous read (combinational) - suitable for distributed RAM
      # For BRAM inference, use: sync_read :dout, from: :mem, clock: :clk, addr: :addr, enable: :cs
      async_read :dout, from: :mem, addr: :addr, enable: :cs

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        effective_addr = addr & ((1 << fetch_parameter(:addr_width)) - 1)
        mem_read(:mem, effective_addr)
      end

      def write_mem(addr, data)
        effective_addr = addr & ((1 << fetch_parameter(:addr_width)) - 1)
        mem_write(:mem, effective_addr, data, fetch_parameter(:data_width))
      end

      def load_binary(data, start_addr = 0)
        data.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end

      def dump(start_addr, length)
        (0...length).map { |i| read_mem(start_addr + i) }
      end
    end

    # Dual-port RAM variant for video memory access
    # Uses multi-port memory DSL with expression-based enables
    class DualPortRAM < Component
      include RHDL::DSL::Memory

      parameter :addr_width, default: 16
      parameter :data_width, default: 8
      parameter :depth, default: 48 * 1024

      # Port A (CPU access)
      input :clk_a
      input :cs_a
      input :we_a
      input :addr_a, width: :addr_width
      input :din_a, width: :data_width
      output :dout_a, width: :data_width

      # Port B (Video access - read only)
      input :clk_b
      input :cs_b
      input :addr_b, width: :addr_width
      output :dout_b, width: :data_width

      # Define memory array with multiple ports using block syntax
      memory :mem, depth: :depth, width: :data_width do |m|
        # Port A: write with expression-based enable (cs_a & we_a)
        m.write_port clock: :clk_a, enable: [:cs_a, :&, :we_a], addr: :addr_a, data: :din_a

        # Port A: async read
        m.async_read_port addr: :addr_a, output: :dout_a, enable: :cs_a

        # Port B: async read only
        m.async_read_port addr: :addr_b, output: :dout_b, enable: :cs_b
      end

      # Direct memory access
      def read_mem(addr)
        effective_addr = addr & ((1 << fetch_parameter(:addr_width)) - 1)
        mem_read(:mem, effective_addr)
      end

      def write_mem(addr, data)
        effective_addr = addr & ((1 << fetch_parameter(:addr_width)) - 1)
        mem_write(:mem, effective_addr, data, fetch_parameter(:data_width))
      end
    end
  end
end
