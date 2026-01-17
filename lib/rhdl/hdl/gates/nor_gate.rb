# HDL NOR Gate
# 2-input NOR gate (synthesizable)

module RHDL
  module HDL
    class NorGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= ~(a0 | a1)
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
