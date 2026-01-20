# HDL Bitwise XOR Gate
# Multi-bit XOR operation

module RHDL
  module HDL
    class BitwiseXor < Component
      parameter :width, default: 8

      input :a, width: :width
      input :b, width: :width
      output :y, width: :width

      behavior do
        y <= a ^ b
      end
    end
  end
end
