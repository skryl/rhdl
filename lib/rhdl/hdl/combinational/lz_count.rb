# HDL Combinational Logic Components
# Leading Zero Count

module RHDL
  module HDL
    # Leading Zero Count
    class LZCount < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        @out_width = Math.log2(width + 1).ceil
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :count, width: @out_width
        output :all_zero
      end

      def propagate
        val = in_val(:a)
        count = 0
        (@width - 1).downto(0) do |i|
          if (val >> i) & 1 == 0
            count += 1
          else
            break
          end
        end
        out_set(:count, count)
        out_set(:all_zero, val == 0 ? 1 : 0)
      end
    end
  end
end
