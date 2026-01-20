# HDL Half Adder
# Adds 2 bits, produces sum and carry

module RHDL
  module HDL
    class HalfAdder < Component
      input :a
      input :b
      output :sum
      output :cout

      behavior do
        sum <= a ^ b
        cout <= a & b
      end
    end
  end
end
