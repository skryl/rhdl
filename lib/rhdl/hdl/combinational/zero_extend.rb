# HDL Combinational Logic Components
# Zero Extender

module RHDL
  module HDL
    # Zero Extender - extends a narrower value with zeros
    class ZeroExtend < SimComponent
      input :a, width: 8
      output :y, width: 16

      # Zero extension is just assignment - output width is larger than input
      behavior do
        y <= a
      end

      def initialize(name = nil, in_width: 8, out_width: 16)
        @in_width = in_width
        @out_width = out_width
        super(name)
      end

      def setup_ports
        return if @in_width == 8 && @out_width == 16
        @inputs[:a] = Wire.new("#{@name}.a", width: @in_width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @out_width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
