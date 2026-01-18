# HDL Combinational Logic Components
# Sign Extender

module RHDL
  module HDL
    # Sign Extender
    class SignExtend < SimComponent
      # Class-level port definitions for synthesis (default 8->16 extension)
      input :a, width: 8
      output :y, width: 16

      behavior do
        # Sign bit from input
        sign = local(:sign, a[7], width: 1)

        # Extension: if sign=1, extend with 0xFF; if sign=0, extend with 0x00
        extension = local(:extension, mux(sign, lit(0xFF, width: 8), lit(0x00, width: 8)), width: 8)

        # Combine: upper byte is extension, lower byte is original
        y <= cat(extension, a)
      end

      def initialize(name = nil, in_width: 8, out_width: 16)
        @in_width = in_width
        @out_width = out_width
        super(name)
      end

      def setup_ports
        # Override default widths if different
        return if @in_width == 8 && @out_width == 16
        @inputs[:a] = Wire.new("#{@name}.a", width: @in_width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @out_width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
