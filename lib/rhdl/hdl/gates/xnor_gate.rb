# HDL XNOR Gate
# 2-input XNOR gate (synthesizable)

module RHDL
  module HDL
    class XnorGate < SimComponent
      input :a0
      input :a1
      output :y

      behavior do
        y <= ~(a0 ^ a1)
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
