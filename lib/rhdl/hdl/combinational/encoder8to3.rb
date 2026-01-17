# HDL Combinational Logic Components
# 8-to-3 Priority Encoder

module RHDL
  module HDL
    # 8-to-3 Priority Encoder
    class Encoder8to3 < SimComponent
      def setup_ports
        input :a, width: 8
        output :y, width: 3
        output :valid
      end

      def propagate
        val = in_val(:a) & 0xFF
        if val == 0
          out_set(:y, 0)
          out_set(:valid, 0)
        else
          # Find highest set bit
          result = 0
          7.downto(0) do |i|
            if (val & (1 << i)) != 0
              result = i
              break
            end
          end
          out_set(:y, result)
          out_set(:valid, 1)
        end
      end
    end
  end
end
