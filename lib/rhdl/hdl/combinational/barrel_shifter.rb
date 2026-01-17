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

      behavior do
        w = param(:width)
        mask = (1 << w) - 1
        shift_amt = shift.value & (w - 1)

        val = a.value
        dir_val = dir.value & 1
        arith_val = arith.value & 1
        rotate_val = rotate.value & 1

        if dir_val == 0  # Left
          if rotate_val == 1
            # Rotate left
            y <= (((val << shift_amt) | (val >> (w - shift_amt))) & mask)
          else
            # Shift left (logical)
            y <= ((val << shift_amt) & mask)
          end
        else  # Right
          if rotate_val == 1
            # Rotate right
            y <= (((val >> shift_amt) | (val << (w - shift_amt))) & mask)
          elsif arith_val == 1
            # Arithmetic right shift (sign extend)
            sign = (val >> (w - 1)) & 1
            shifted = val >> shift_amt
            if sign == 1
              fill = ((1 << shift_amt) - 1) << (w - shift_amt)
              y <= ((shifted | fill) & mask)
            else
              y <= shifted
            end
          else
            # Shift right (logical)
            y <= (val >> shift_amt)
          end
        end
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
      end
    end
  end
end
