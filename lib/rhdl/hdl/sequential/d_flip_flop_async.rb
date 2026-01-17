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

      def propagate
        if in_val(:rst) == 1
          @state = 0
        elsif rising_edge? && in_val(:en) == 1
          @state = in_val(:d) & 1
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end
  end
end
