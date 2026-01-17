# HDL Combinational Logic Components
# 1-to-2 Demultiplexer

module RHDL
  module HDL
    # 1-to-2 Demultiplexer
    class Demux2 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :sel
        output :y0, width: @width
        output :y1, width: @width
      end

      def propagate
        val = in_val(:a)
        if in_val(:sel) == 0
          out_set(:y0, val)
          out_set(:y1, 0)
        else
          out_set(:y0, 0)
          out_set(:y1, val)
        end
      end
    end
  end
end
