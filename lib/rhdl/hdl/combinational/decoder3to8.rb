# HDL Combinational Logic Components
# 3-to-8 Decoder

module RHDL
  module HDL
    # 3-to-8 Decoder
    class Decoder3to8 < SimComponent
      def setup_ports
        input :a, width: 3
        input :en
        8.times { |i| output :"y#{i}" }
      end

      def propagate
        if in_val(:en) == 0
          8.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & 7
          8.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end
  end
end
