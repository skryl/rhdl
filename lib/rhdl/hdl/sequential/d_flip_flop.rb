# HDL D Flip-Flop
# D Flip-Flop with synchronous reset and enable

module RHDL
  module HDL
    class DFlipFlop < SequentialComponent
      port_input :d
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      behavior do
        if rising_edge?
          if rst.value == 1
            set_state(0)
          elsif en.value == 1
            set_state(d.value & 1)
          end
        end
        q <= state
        qn <= mux(state, lit(0, width: 1), lit(1, width: 1))
      end
    end
  end
end
