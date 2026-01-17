# HDL Combinational Logic Components
# 4-to-1 Multiplexer

module RHDL
  module HDL
    # 4-to-1 Multiplexer
    class Mux4 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :c, width: @width
        input :d, width: @width
        input :sel, width: 2
        output :y, width: @width
      end

      def propagate
        case in_val(:sel) & 3
        when 0 then out_set(:y, in_val(:a))
        when 1 then out_set(:y, in_val(:b))
        when 2 then out_set(:y, in_val(:c))
        when 3 then out_set(:y, in_val(:d))
        end
      end
    end
  end
end
