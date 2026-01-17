# HDL SR Latch
# Level-sensitive SR Latch (not edge-triggered)
# Synthesizable via Behavior DSL

require_relative '../../dsl/behavior'

module RHDL
  module HDL
    class SRLatch < SimComponent
      include RHDL::DSL::Behavior

      port_input :s
      port_input :r
      port_input :en
      port_output :q
      port_output :qn

      # Combinational behavior block for SR latch
      # SR latch truth table: S=1,R=0 -> Q=1; S=0,R=1 -> Q=0; S=R=0 -> hold; S=R=1 -> invalid (R wins)
      # When en=0, hold state
      behavior do
        # When enabled, R has priority: r=1 -> 0, else s ? 1 : hold
        # When disabled, hold
        q <= mux(en,
          mux(r, lit(0, width: 1), mux(s, lit(1, width: 1), q)),
          q)
        qn <= ~q
      end

      def initialize(name = nil)
        @state = 0
        super(name)
      end
    end
  end
end
