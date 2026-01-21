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
      include RHDL::DSL::Behavior

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

      # Internal wire for combined enable
      wire :write_enable

      # Define memory array
      memory :mem, depth: :depth, width: :data_width

      # Synchronous write on rising edge when cs and we are high
      # Note: Using intermediate signal for combined enable since DSL doesn't support lambdas
      sync_write :mem, clock: :clk, enable: :write_enable, addr: :addr, data: :din

      # Asynchronous read (combinational)
      # Note: For proper BRAM inference, sync_read would be needed (to be added to RHDL)
      async_read :dout, from: :mem, addr: :addr, enable: :cs

      # Combinational logic to compute write_enable
      behavior do
        write_enable <= cs & we
      end

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
    class DualPortRAM < Component
      include RHDL::DSL::Memory
      include RHDL::DSL::Behavior

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

      # Internal wire for combined enable
      wire :write_enable_a

      # Define memory array
      memory :mem, depth: :depth, width: :data_width

      # Port A: synchronous write
      sync_write :mem, clock: :clk_a, enable: :write_enable_a, addr: :addr_a, data: :din_a

      # Port A: asynchronous read
      async_read :dout_a, from: :mem, addr: :addr_a, enable: :cs_a

      # Port B: asynchronous read only
      async_read :dout_b, from: :mem, addr: :addr_b, enable: :cs_b

      # Combinational logic to compute write_enable
      behavior do
        write_enable_a <= cs_a & we_a
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
