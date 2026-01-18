# HDL Bitwise NOT Gate
# Multi-bit NOT operation

module RHDL
  module HDL
    class BitwiseNot < SimComponent
      parameter :width, default: 8

      input :a, width: :width
      output :y, width: :width

      behavior do
        y <= ~a
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end
    end
  end
end
