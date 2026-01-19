# HDL Full Adder
# Adds 2 bits plus carry, produces sum and carry

module RHDL
  module HDL
    class FullAdder < SimComponent
      input :a
      input :b
      input :cin
      output :sum
      output :cout

      behavior do
        sum <= a ^ b ^ cin
        cout <= (a & b) | (cin & (a ^ b))
      end
    end
  end
end
