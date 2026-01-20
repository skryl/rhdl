# HDL Bitwise NOT Gate
# Multi-bit NOT operation

module RHDL
  module HDL
    class BitwiseNot < Component
      parameter :width, default: 8

      input :a, width: :width
      output :y, width: :width

      behavior do
        y <= ~a
      end
    end
  end
end
