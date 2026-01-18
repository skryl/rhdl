# HDL Combinational Logic Components
# Population Count (count 1 bits)

module RHDL
  module HDL
    # Population Count (count 1 bits)
    class PopCount < SimComponent
      parameter :width, default: 8
      parameter :out_width, default: 4  # log2(8+1) = 4 bits needed

      input :a, width: :width
      output :count, width: :out_width

      behavior do
        # Count 1 bits by adding all individual bits
        # For 8 bits: count = a[0] + a[1] + a[2] + a[3] + a[4] + a[5] + a[6] + a[7]
        count <= a[0] + a[1] + a[2] + a[3] + a[4] + a[5] + a[6] + a[7]
      end

      def initialize(name = nil, width: 8)
        @width = width
        @out_width = Math.log2(width + 1).ceil
        super(name)
      end
    end
  end
end
