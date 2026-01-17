# HDL Full Adder
# Adds 2 bits plus carry, produces sum and carry

module RHDL
  module HDL
    class FullAdder < SimComponent
      port_input :a
      port_input :b
      port_input :cin
      port_output :sum
      port_output :cout

      behavior do
        sum <= a ^ b ^ cin
        cout <= (a & b) | (cin & (a ^ b))
      end
    end
  end
end
