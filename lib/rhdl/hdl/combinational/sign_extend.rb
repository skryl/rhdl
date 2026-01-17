# HDL Combinational Logic Components
# Sign Extender

module RHDL
  module HDL
    # Sign Extender
    class SignExtend < SimComponent
      def initialize(name = nil, in_width: 8, out_width: 16)
        @in_width = in_width
        @out_width = out_width
        super(name)
      end

      def setup_ports
        input :a, width: @in_width
        output :y, width: @out_width
      end

      def propagate
        val = in_val(:a)
        sign = (val >> (@in_width - 1)) & 1
        if sign == 1
          # Extend with 1s
          extension = ((1 << (@out_width - @in_width)) - 1) << @in_width
          out_set(:y, val | extension)
        else
          out_set(:y, val)
        end
      end
    end
  end
end
