# HDL Combinational Logic Components
# Leading Zero Count

module RHDL
  module HDL
    # Leading Zero Count - counts leading zeros in input
    class LZCount < SimComponent
      # Class-level port definitions for synthesis (default 8-bit)
      port_input :a, width: 8
      port_output :count, width: 4  # 4 bits for values 0-8
      port_output :all_zero

      # Behavior block for synthesis (8-bit specific)
      behavior do
        # Priority encoder approach: find first set bit from MSB
        has_7 = local(:has_7, a[7], width: 1)
        has_6 = local(:has_6, ~a[7] & a[6], width: 1)
        has_5 = local(:has_5, ~a[7] & ~a[6] & a[5], width: 1)
        has_4 = local(:has_4, ~a[7] & ~a[6] & ~a[5] & a[4], width: 1)
        has_3 = local(:has_3, ~a[7] & ~a[6] & ~a[5] & ~a[4] & a[3], width: 1)
        has_2 = local(:has_2, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & a[2], width: 1)
        has_1 = local(:has_1, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & ~a[2] & a[1], width: 1)
        has_0 = local(:has_0, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & ~a[2] & ~a[1] & a[0], width: 1)
        none = local(:none, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & ~a[2] & ~a[1] & ~a[0], width: 1)

        # Count = position from MSB: 7->0, 6->1, 5->2, 4->3, 3->4, 2->5, 1->6, 0->7, none->8
        # Encode count using mux chain
        count <= case_select(cat(has_7, has_6, has_5, has_4, has_3, has_2, has_1, has_0), {
          0b10000000 => lit(0, width: 4),  # bit 7 set -> 0 leading zeros
          0b01000000 => lit(1, width: 4),  # bit 6 set -> 1 leading zero
          0b00100000 => lit(2, width: 4),  # bit 5 set -> 2 leading zeros
          0b00010000 => lit(3, width: 4),  # bit 4 set -> 3 leading zeros
          0b00001000 => lit(4, width: 4),  # bit 3 set -> 4 leading zeros
          0b00000100 => lit(5, width: 4),  # bit 2 set -> 5 leading zeros
          0b00000010 => lit(6, width: 4),  # bit 1 set -> 6 leading zeros
          0b00000001 => lit(7, width: 4)   # bit 0 set -> 7 leading zeros
        }, default: lit(8, width: 4))  # no bits set -> 8 leading zeros

        all_zero <= none
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
        @inputs[:a].on_change { |_| propagate }
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
