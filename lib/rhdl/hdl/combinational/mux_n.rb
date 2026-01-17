# HDL Combinational Logic Components
# N-to-1 Multiplexer (generic)

module RHDL
  module HDL
    # N-to-1 Multiplexer (generic)
    class MuxN < SimComponent
      def initialize(name = nil, inputs: 2, width: 1)
        @input_count = inputs
        @sel_width = Math.log2(inputs).ceil
        @width = width
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"in#{i}", width: @width }
        input :sel, width: @sel_width
        output :y, width: @width
      end

      def propagate
        sel = in_val(:sel) & ((1 << @sel_width) - 1)
        if sel < @input_count
          out_set(:y, in_val(:"in#{sel}"))
        else
          out_set(:y, 0)
        end
      end
    end
  end
end
