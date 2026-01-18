# HDL Combinational Logic Components
# Leading Zero Count

module RHDL
  module HDL
    # Leading Zero Count - counts leading zeros in input
    class LZCount < SimComponent
      # Class-level port definitions for synthesis (default 8-bit)
      input :a, width: 8
      output :count, width: 4  # 4 bits for values 0-8
      output :all_zero

      behavior do
        w = param(:width)
        val = a.value

        # Count leading zeros from MSB
        lz_count = 0
        (w - 1).downto(0) do |i|
          if (val >> i) & 1 == 0
            lz_count += 1
          else
            break
          end
        end

        count <= lz_count
        all_zero <= (val == 0 ? 1 : 0)
      end

      def initialize(name = nil, width: 8)
        @width = width
        @out_width = Math.log2(width + 1).ceil
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:count] = Wire.new("#{@name}.count", width: @out_width)
      end
    end
  end
end
