# HDL AND Gate
# 2-input AND gate (synthesizable)

module RHDL
  module HDL
    class AndGate < Component
      input :a0
      input :a1
      output :y

      behavior do
        y <= a0 & a1
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
