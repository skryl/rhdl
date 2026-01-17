# HDL Combinational Logic Components
# 1-to-4 Demultiplexer

module RHDL
  module HDL
    # 1-to-4 Demultiplexer
    class Demux4 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :sel, width: 2
        4.times { |i| output :"y#{i}", width: @width }
      end

      def propagate
        val = in_val(:a)
        sel = in_val(:sel) & 3
        4.times { |i| out_set(:"y#{i}", i == sel ? val : 0) }
      end
    end
  end
end
