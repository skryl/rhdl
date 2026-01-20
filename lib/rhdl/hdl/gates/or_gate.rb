# HDL OR Gate
# 2-input OR gate (synthesizable)

module RHDL
  module HDL
    class OrGate < Component
      input :a0
      input :a1
      output :y

      behavior do
        y <= a0 | a1
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
