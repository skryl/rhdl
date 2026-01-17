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

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1
            s = in_val(:s) & 1
            r = in_val(:r) & 1
            case [s, r]
            when [0, 0] then # Hold
            when [0, 1] then @state = 0
            when [1, 0] then @state = 1
            when [1, 1] then @state = 0  # Invalid, but we default to 0
            end
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end
  end
end
