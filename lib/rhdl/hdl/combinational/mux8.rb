# HDL Combinational Logic Components
# 8-to-1 Multiplexer

module RHDL
  module HDL
    # 8-to-1 Multiplexer
    class Mux8 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        8.times { |i| input :"in#{i}", width: @width }
        input :sel, width: 3
        output :y, width: @width
      end

      def propagate
        sel = in_val(:sel) & 7
        out_set(:y, in_val(:"in#{sel}"))
      end
    end
  end
end
