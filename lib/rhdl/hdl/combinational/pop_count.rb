# HDL Combinational Logic Components
# Population Count (count 1 bits)

module RHDL
  module HDL
    # Population Count (count 1 bits)
    class PopCount < SimComponent
      # Class-level port definitions for synthesis (default 8-bit input)
      input :a, width: 8
      output :count, width: 4  # log2(8+1) = 4 bits needed

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

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:count] = Wire.new("#{@name}.count", width: @out_width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
