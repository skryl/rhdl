# Dual-Port RAM
# Corresponds to: reference/rtl/dpram.vhd
#
# True dual-port RAM with independent read/write ports.
# Used for VRAM, WRAM, etc.
#
# Uses the Memory DSL for proper simulation and synthesis support.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../../../../lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module GameBoy
      class DPRAM < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory

        # Default 8KB configuration (VRAM-style)
        DEFAULT_ADDR_WIDTH = 13
        DATA_WIDTH = 8

        # Port A (read/write)
        input :clock_a
        input :address_a, width: DEFAULT_ADDR_WIDTH
        input :wren_a, default: 0
        input :data_a, width: DATA_WIDTH
        output :q_a, width: DATA_WIDTH

        # Port B (read/write)
        input :clock_b
        input :address_b, width: DEFAULT_ADDR_WIDTH
        input :wren_b, default: 0
        input :data_b, width: DATA_WIDTH
        output :q_b, width: DATA_WIDTH

        # Keep both ports asynchronous for compatibility with current Verilog
        # generation while preserving dual-clock write behavior.
        memory :mem, depth: 2**DEFAULT_ADDR_WIDTH, width: DATA_WIDTH do |m|
          m.write_port clock: :clock_a, enable: :wren_a, addr: :address_a, data: :data_a
          m.async_read_port addr: :address_a, output: :q_a

          m.write_port clock: :clock_b, enable: :wren_b, addr: :address_b, data: :data_b
          m.async_read_port addr: :address_b, output: :q_b
        end

        # Kept for backwards compatibility in specs/helpers.
        def initialize(name = nil, addr_width: DEFAULT_ADDR_WIDTH, **kwargs)
          @addr_width = addr_width
          super(name, **kwargs)
          initialize_memories
        end

        # Direct memory access for external use (debugging, initialization)
        def read_mem(addr)
          mem_read(:mem, addr & ((1 << @addr_width) - 1))
        end

        def write_mem(addr, data)
          mem_write(:mem, addr & ((1 << @addr_width) - 1), data, DATA_WIDTH)
        end

        # Get the memory array for bulk operations
        def memory_array
          @_memory_arrays[:mem]
        end
      end

      # 32KB variant for CGB WRAM (2^15)
      class DPRAM15 < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory

        ADDR_WIDTH = 15
        DATA_WIDTH = 8

        input :clock_a
        input :address_a, width: ADDR_WIDTH
        input :wren_a, default: 0
        input :data_a, width: DATA_WIDTH
        output :q_a, width: DATA_WIDTH

        input :clock_b
        input :address_b, width: ADDR_WIDTH
        input :wren_b, default: 0
        input :data_b, width: DATA_WIDTH
        output :q_b, width: DATA_WIDTH

        memory :mem, depth: 2**ADDR_WIDTH, width: DATA_WIDTH do |m|
          m.write_port clock: :clock_a, enable: :wren_a, addr: :address_a, data: :data_a
          m.async_read_port addr: :address_a, output: :q_a

          m.write_port clock: :clock_b, enable: :wren_b, addr: :address_b, data: :data_b
          m.async_read_port addr: :address_b, output: :q_b
        end

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          initialize_memories
        end

        def read_mem(addr)
          mem_read(:mem, addr & ((1 << ADDR_WIDTH) - 1))
        end

        def write_mem(addr, data)
          mem_write(:mem, addr & ((1 << ADDR_WIDTH) - 1), data, DATA_WIDTH)
        end

        def memory_array
          @_memory_arrays[:mem]
        end
      end

      # 128-byte variant for HRAM/ZPRAM window (2^7)
      class DPRAM7 < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory

        ADDR_WIDTH = 7
        DATA_WIDTH = 8

        input :clock_a
        input :address_a, width: ADDR_WIDTH
        input :wren_a, default: 0
        input :data_a, width: DATA_WIDTH
        output :q_a, width: DATA_WIDTH

        input :clock_b
        input :address_b, width: ADDR_WIDTH
        input :wren_b, default: 0
        input :data_b, width: DATA_WIDTH
        output :q_b, width: DATA_WIDTH

        memory :mem, depth: 2**ADDR_WIDTH, width: DATA_WIDTH do |m|
          m.write_port clock: :clock_a, enable: :wren_a, addr: :address_a, data: :data_a
          m.async_read_port addr: :address_a, output: :q_a

          m.write_port clock: :clock_b, enable: :wren_b, addr: :address_b, data: :data_b
          m.async_read_port addr: :address_b, output: :q_b
        end

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          initialize_memories
        end

        def read_mem(addr)
          mem_read(:mem, addr & ((1 << ADDR_WIDTH) - 1))
        end

        def write_mem(addr, data)
          mem_write(:mem, addr & ((1 << ADDR_WIDTH) - 1), data, DATA_WIDTH)
        end

        def memory_array
          @_memory_arrays[:mem]
        end
      end
    end
  end
end
