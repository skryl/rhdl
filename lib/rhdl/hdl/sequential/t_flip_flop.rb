# HDL T Flip-Flop
# Toggle Flip-Flop

module RHDL
  module HDL
    class TFlipFlop < SequentialComponent
      port_input :t
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      behavior do
        if rising_edge?
          if rst.value == 1
            set_state(0)
          elsif en.value == 1 && t.value == 1
            set_state(state == 0 ? 1 : 0)
          end
        end
        q <= state
        qn <= mux(state, lit(0, width: 1), lit(1, width: 1))
      end
    end
  end
end
