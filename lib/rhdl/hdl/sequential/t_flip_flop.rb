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

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1 && in_val(:t) == 1
            @state = @state == 0 ? 1 : 0
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end
  end
end
