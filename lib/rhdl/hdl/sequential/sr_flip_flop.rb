# HDL SR Flip-Flop
# Set-Reset Flip-Flop

module RHDL
  module HDL
    class SRFlipFlop < SequentialComponent
      port_input :s
      port_input :r
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
            s_val = s.value & 1
            r_val = r.value & 1
            # SR truth table: S=1,R=0 -> set; S=0,R=1 -> reset; S=R=0 -> hold; S=R=1 -> invalid (force 0)
            if s_val == 1 && r_val == 0
              set_state(1)
            elsif r_val == 1  # R=1 takes precedence
              set_state(0)
            end
            # s_val == 0 && r_val == 0: hold state
          end
        end
        q <= state
        qn <= mux(state, lit(0, width: 1), lit(1, width: 1))
      end
    end
  end
end
