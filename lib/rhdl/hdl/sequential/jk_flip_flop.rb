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

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1
            j = in_val(:j) & 1
            k = in_val(:k) & 1
            case [j, k]
            when [0, 0] then # Hold
            when [0, 1] then @state = 0
            when [1, 0] then @state = 1
            when [1, 1] then @state = @state == 0 ? 1 : 0
            end
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end
  end
end
