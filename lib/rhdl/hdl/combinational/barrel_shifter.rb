# HDL Combinational Logic Components
# Barrel Shifter

module RHDL
  module HDL
    # Barrel Shifter - parameterized shifter with multiple modes
    class BarrelShifter < SimComponent
      # Class-level port definitions for synthesis (default 8-bit)
      port_input :a, width: 8
      port_input :shift, width: 3
      port_input :dir      # 0 = left, 1 = right
      port_input :arith    # 1 = arithmetic right shift
      port_input :rotate   # 1 = rotate instead of shift
      port_output :y, width: 8

      # Note: Behavior block uses simplified shift operations for synthesis
      # Full simulation uses the manual propagate method below
      behavior do
        # Simplified - just left/right logical shift for synthesis
        # The full barrel shifter with rotate/arith is done in propagate
        left_result = local(:left_result, a << (shift & lit(7, width: 3)), width: 8)
        right_result = local(:right_result, a >> (shift & lit(7, width: 3)), width: 8)
        y <= mux(dir, right_result, left_result)
      end

      def initialize(name = nil, width: 8)
        @width = width
        @shift_width = Math.log2(width).ceil
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:shift] = Wire.new("#{@name}.shift", width: @shift_width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:shift].on_change { |_| propagate }
      end

      # Override propagate for accurate simulation with all modes
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
