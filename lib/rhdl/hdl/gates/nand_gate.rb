# HDL NAND Gate
# 2-input NAND gate (synthesizable)

module RHDL
  module HDL
    class NandGate < Component
      input :a0
      input :a1
      output :y

      behavior do
        y <= ~(a0 & a1)
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
