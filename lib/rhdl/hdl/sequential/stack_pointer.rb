# HDL Stack Pointer
# Stack Pointer Register
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class StackPointer < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :push     # Decrement SP
      input :pop      # Increment SP
      output :q, width: 8
      output :empty   # SP at max (empty stack)
      output :full    # SP at 0 (full stack)

      # Sequential block for stack pointer
      # Push decrements, pop increments (6502-style stack)
      sequential clock: :clk, reset: :rst, reset_values: { q: 0xFF } do
        # Priority: push > pop
        sp_dec = q - lit(1, width: 8)
        sp_inc = q + lit(1, width: 8)
        q <= mux(push, sp_dec, mux(pop, sp_inc, q))
      end

      # Combinational outputs for empty/full flags
      behavior do
        empty <= (q == lit(0xFF, width: 8))
        full <= (q == lit(0, width: 8))
      end
    end
  end
end
