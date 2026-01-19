# frozen_string_literal: true

# HDL FIFO Component
# First-In First-Out queue with read/write operations
# Synthesizable via MemoryDSL + Sequential DSL

require_relative '../../dsl/memory_dsl'
require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    # FIFO Queue with fixed depth
    # Combines memory for data and sequential logic for pointers
    class FIFO < SequentialComponent
      include RHDL::DSL::MemoryDSL
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :wr_en
      input :rd_en
      input :din, width: 8
      output :dout, width: 8
      output :empty
      output :full
      output :count, width: 5
      output :wr_ptr, width: 4
      output :rd_ptr, width: 4

      # Memory for FIFO data (16 entries x 8-bit)
      memory :data, depth: 16, width: 8

      # Synchronous write at wr_ptr when write enabled and not full
      sync_write :data, clock: :clk, enable: :wr_en, addr: :wr_ptr, data: :din

      # Asynchronous read from rd_ptr
      async_read :dout, from: :data, addr: :rd_ptr

      # Pointers and count managed via sequential DSL
      sequential clock: :clk, reset: :rst, reset_values: { wr_ptr: 0, rd_ptr: 0, count: 0 } do
        # Calculate enable conditions
        can_write = wr_en & ~full
        can_read = rd_en & ~empty

        # Write pointer: increment (mod 16) when writing
        wr_ptr <= mux(can_write, (wr_ptr + lit(1, width: 4))[3..0], wr_ptr)

        # Read pointer: increment (mod 16) when reading
        rd_ptr <= mux(can_read, (rd_ptr + lit(1, width: 4))[3..0], rd_ptr)

        # Count: increment on write, decrement on read, stay same if both or neither
        count <= mux(can_write & ~can_read, count + lit(1, width: 5),
                     mux(can_read & ~can_write, count - lit(1, width: 5), count))
      end

      # Combinational outputs
      behavior do
        # FIFO empty when count == 0
        empty <= (count == lit(0, width: 5))
        # FIFO full when count == 16
        full <= (count == lit(16, width: 5))
        # dout is handled by async_read above
      end

    end
  end
end
