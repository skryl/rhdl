# HDL Combinational Logic Components
# 2-to-4 Decoder

module RHDL
  module HDL
    # 2-to-4 Decoder
    class Decoder2to4 < SimComponent
      def setup_ports
        input :a, width: 2
        input :en
        output :y0
        output :y1
        output :y2
        output :y3
      end

      def propagate
        if in_val(:en) == 0
          4.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & 3
          4.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end
  end
end
