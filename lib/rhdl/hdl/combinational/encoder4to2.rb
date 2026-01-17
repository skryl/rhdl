# HDL Combinational Logic Components
# 4-to-2 Priority Encoder

module RHDL
  module HDL
    # 4-to-2 Priority Encoder
    class Encoder4to2 < SimComponent
      def setup_ports
        input :a, width: 4
        output :y, width: 2
        output :valid
      end

      def propagate
        val = in_val(:a) & 0xF
        if val == 0
          out_set(:y, 0)
          out_set(:valid, 0)
        elsif (val & 8) != 0
          out_set(:y, 3)
          out_set(:valid, 1)
        elsif (val & 4) != 0
          out_set(:y, 2)
          out_set(:valid, 1)
        elsif (val & 2) != 0
          out_set(:y, 1)
          out_set(:valid, 1)
        else
          out_set(:y, 0)
          out_set(:valid, 1)
        end
      end
    end
  end
end
