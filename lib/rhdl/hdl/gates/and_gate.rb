# HDL AND Gate
# 2-input AND gate (synthesizable)

module RHDL
  module HDL
    class AndGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= a0 & a1
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
