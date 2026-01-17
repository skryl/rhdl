# HDL SR Latch
# Level-sensitive SR Latch (not edge-triggered)

module RHDL
  module HDL
    class SRLatch < SimComponent
      port_input :s
      port_input :r
      port_input :en
      port_output :q
      port_output :qn

      def initialize(name = nil)
        @state = 0
        super(name)
      end

      def propagate
        if in_val(:en) == 1
          s = in_val(:s) & 1
          r = in_val(:r) & 1
          case [s, r]
          when [0, 0] then # Hold
          when [0, 1] then @state = 0
          when [1, 0] then @state = 1
          when [1, 1] then @state = 0  # Invalid
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end
  end
end
