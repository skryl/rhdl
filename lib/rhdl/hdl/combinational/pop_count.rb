# HDL Combinational Logic Components
# Population Count (count 1 bits)

module RHDL
  module HDL
    # Population Count (count 1 bits)
    class PopCount < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        @out_width = Math.log2(width + 1).ceil
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :count, width: @out_width
      end

      def propagate
        val = in_val(:a)
        count = 0
        @width.times do |i|
          count += (val >> i) & 1
        end
        out_set(:count, count)
      end
    end
  end
end
