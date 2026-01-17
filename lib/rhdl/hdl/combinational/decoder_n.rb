# HDL Combinational Logic Components
# Generic N-bit Decoder

module RHDL
  module HDL
    # Generic N-bit Decoder
    class DecoderN < SimComponent
      def initialize(name = nil, width: 3)
        @width = width
        @output_count = 1 << width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :en
        @output_count.times { |i| output :"y#{i}" }
      end

      def propagate
        if in_val(:en) == 0
          @output_count.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & ((1 << @width) - 1)
          @output_count.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end
  end
end
