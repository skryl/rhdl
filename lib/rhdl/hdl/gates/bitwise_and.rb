# HDL Bitwise AND Gate
# Multi-bit AND operation

module RHDL
  module HDL
    class BitwiseAnd < SimComponent
      parameter :width, default: 8

      input :a, width: :width
      input :b, width: :width
      output :y, width: :width

      behavior do
        y <= a & b
      end
    end
  end
end
