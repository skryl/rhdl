# Reservation set state for LR/SC.
# Tracks whether a reservation is active and the reserved word address.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      class AtomicReservation < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst
        input :set
        input :clear
        input :set_addr, width: 32

        output :valid
        output :addr, width: 32

        sequential clock: :clk, reset: :rst, reset_values: { valid: 0, addr: 0 } do
          valid <= mux(clear, lit(0, width: 1), mux(set, lit(1, width: 1), valid))
          addr <= mux(set, set_addr, addr)
        end
      end
    end
  end
end
