# HDL Combinational Logic Components
# Barrel Shifter

module RHDL
  module HDL
    # Barrel Shifter
    class BarrelShifter < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        @shift_width = Math.log2(width).ceil
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :shift, width: @shift_width
        input :dir      # 0 = left, 1 = right
        input :arith    # 1 = arithmetic right shift
        input :rotate   # 1 = rotate instead of shift
        output :y, width: @width
      end

      def propagate
        val = in_val(:a)
        shift = in_val(:shift) & ((1 << @shift_width) - 1)
        dir = in_val(:dir) & 1
        arith = in_val(:arith) & 1
        rotate = in_val(:rotate) & 1
        mask = (1 << @width) - 1

        result = if dir == 0  # Left
          if rotate == 1
            ((val << shift) | (val >> (@width - shift))) & mask
          else
            (val << shift) & mask
          end
        else  # Right
          if rotate == 1
            ((val >> shift) | (val << (@width - shift))) & mask
          elsif arith == 1
            sign = (val >> (@width - 1)) & 1
            shifted = val >> shift
            if sign == 1
              fill = ((1 << shift) - 1) << (@width - shift)
              (shifted | fill) & mask
            else
              shifted
            end
          else
            val >> shift
          end
        end

        out_set(:y, result)
      end
    end
  end
end
