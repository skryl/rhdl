# HDL JK Flip-Flop
# JK Flip-Flop with all standard operations

module RHDL
  module HDL
    class JKFlipFlop < SequentialComponent
      port_input :j
      port_input :k
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
            j_val = j.value & 1
            k_val = k.value & 1
            # JK truth table: J=0,K=0 -> hold; J=0,K=1 -> reset; J=1,K=0 -> set; J=1,K=1 -> toggle
            if j_val == 0 && k_val == 1
              set_state(0)
            elsif j_val == 1 && k_val == 0
              set_state(1)
            elsif j_val == 1 && k_val == 1
              set_state(state == 0 ? 1 : 0)
            end
            # j_val == 0 && k_val == 0: hold state
          end
        end
        q <= state
        qn <= mux(state, lit(0, width: 1), lit(1, width: 1))
      end
    end
  end
end
