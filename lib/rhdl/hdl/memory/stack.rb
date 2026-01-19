# frozen_string_literal: true

# HDL Stack Component
# LIFO stack with push/pop operations
# Synthesizable via MemoryDSL + Sequential DSL

require_relative '../../dsl/memory_dsl'
require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    # Stack (LIFO) with fixed depth
    # Combines memory for data and sequential logic for pointer
    class Stack < SequentialComponent
      include RHDL::DSL::MemoryDSL
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :push
      input :pop
      input :din, width: 8
      output :dout, width: 8
      output :empty
      output :full
      output :sp, width: 5

      # Memory for stack data (16 entries x 8-bit)
      memory :data, depth: 16, width: 8

      # Synchronous write - write to current sp when push is enabled
      # Note: sync_write uses signal_val() which reads from @_seq_state for sp
      sync_write :data, clock: :clk, enable: :push, addr: :sp, data: :din

      # Asynchronous read from top of stack (sp - 1)
      # Note: We need special handling for reading at sp-1, not sp
      # This is handled in the behavior block

      # Stack pointer managed via sequential DSL
      # Push increments, pop decrements
      sequential clock: :clk, reset: :rst, reset_values: { sp: 0 } do
        # Push: write to sp, then increment
        # Pop: decrement sp
        push_enabled = push & ~full
        pop_enabled = pop & ~empty
        sp <= mux(push_enabled, sp + lit(1, width: 5),
                  mux(pop_enabled, sp - lit(1, width: 5), sp))
      end

      # Combinational outputs
      behavior do
        # Stack empty when sp == 0
        empty <= (sp == lit(0, width: 5))
        # Stack full when sp == 16
        full <= (sp == lit(16, width: 5))
        # Read top of stack (sp - 1), return 0 when empty
        dout <= mux(sp > lit(0, width: 5),
                    mem_read_expr(:data, sp - lit(1, width: 5), width: 8),
                    lit(0, width: 8))
      end

    end
  end
end
