# Single-Port RAM
# Corresponds to: reference/rtl/spram.vhd
#
# Simple single-port RAM with single clock domain.
# Uses the Memory DSL for proper simulation and Verilog export.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../../../../lib/rhdl/dsl/memory'

module GameBoy
  class SPRAM < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential
    include RHDL::DSL::Memory

    # Fixed 8KB configuration
    ADDR_WIDTH = 13
    DATA_WIDTH = 8
    DEPTH = 8192

    input :clock
    input :address, width: ADDR_WIDTH
    input :wren, default: 0
    input :data_in, width: DATA_WIDTH
    output :data_out, width: DATA_WIDTH

    # Define single-port memory using Memory DSL
    memory :mem, depth: DEPTH, width: DATA_WIDTH do |m|
      # Write port
      m.write_port clock: :clock, enable: :wren, addr: :address, data: :data_in
      # Synchronous read port
      m.sync_read_port clock: :clock, addr: :address, output: :data_out
    end

    # Instance initialization - ensure memory arrays are initialized
    def initialize(name = nil, **kwargs)
      super(name, **kwargs)
      initialize_memories
    end

    # Direct memory access for external use (debugging, initialization)
    def read_mem(addr)
      mem_read(:mem, addr & (DEPTH - 1))
    end

    def write_mem(addr, data)
      mem_write(:mem, addr & (DEPTH - 1), data, DATA_WIDTH)
    end

    # Get the memory array for bulk operations
    def memory_array
      @_memory_arrays[:mem]
    end
  end
end
