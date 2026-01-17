# HDL Half Adder
# Adds 2 bits, produces sum and carry

module RHDL
  module HDL
    class HalfAdder < SimComponent
      port_input :a
      port_input :b
      port_output :sum
      port_output :cout

      behavior do
        sum <= a ^ b
        cout <= a & b
      end
    end
  end
end
