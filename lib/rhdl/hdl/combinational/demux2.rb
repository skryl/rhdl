# HDL Combinational Logic Components
# 1-to-2 Demultiplexer

module RHDL
  module HDL
    # 1-to-2 Demultiplexer
    class Demux2 < SimComponent
      # Class-level port definitions for synthesis (default 1-bit width)
      input :a
      input :sel
      output :y0
      output :y1

      behavior do
        # When sel=0: y0=a, y1=0
        # When sel=1: y0=0, y1=a
        y0 <= mux(sel, lit(0, width: 1), a)  # sel=0: a, sel=1: 0
        y1 <= mux(sel, a, lit(0, width: 1))  # sel=0: 0, sel=1: a
      end

      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 1
        return if @width == 1
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:y0] = Wire.new("#{@name}.y0", width: @width)
        @outputs[:y1] = Wire.new("#{@name}.y1", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
