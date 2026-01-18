# HDL NOR Gate
# 2-input NOR gate (synthesizable)

module RHDL
  module HDL
    class NorGate < SimComponent
      input :a0
      input :a1
      output :y

      behavior do
        y <= ~(a0 | a1)
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
