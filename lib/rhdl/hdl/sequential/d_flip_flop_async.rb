# HDL D Flip-Flop with Async Reset
# D Flip-Flop with asynchronous reset

module RHDL
  module HDL
    class DFlipFlopAsync < SequentialComponent
      port_input :d
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      behavior do
        # Async reset - checked outside rising edge
        if rst.value == 1
          set_state(0)
        elsif rising_edge? && en.value == 1
          set_state(d.value & 1)
        end
        q <= state
        qn <= mux(state, lit(0, width: 1), lit(1, width: 1))
      end
    end
  end
end
