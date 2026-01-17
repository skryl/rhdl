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

      behavior do
        if en.value == 1
          s_val = s.value & 1
          r_val = r.value & 1
          # SR latch truth table: S=1,R=0 -> Q=1; S=0,R=1 -> Q=0; S=R=0 -> hold; S=R=1 -> invalid (force 0)
          if s_val == 1 && r_val == 0
            set_state(1)
          elsif r_val == 1  # R=1 takes precedence (covers S=0,R=1 and S=1,R=1)
            set_state(0)
          end
          # S=0, R=0: hold state (no change)
        end
        q <= state
        qn <= mux(state, lit(0, width: 1), lit(1, width: 1))
      end

      def initialize(name = nil)
        @state = 0
        super(name)
      end
    end
  end
end
