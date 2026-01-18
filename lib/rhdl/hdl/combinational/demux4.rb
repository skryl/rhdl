# HDL Combinational Logic Components
# 1-to-4 Demultiplexer

module RHDL
  module HDL
    # 1-to-4 Demultiplexer - routes input to one of 4 outputs
    class Demux4 < SimComponent
      # Class-level port definitions for synthesis (default 1-bit width)
      input :a
      input :sel, width: 2
      output :y0
      output :y1
      output :y2
      output :y3

      behavior do
        w = port_width(:a)
        # Decode selector
        sel_0 = local(:sel_0, ~sel[1] & ~sel[0], width: 1)  # sel == 0
        sel_1 = local(:sel_1, ~sel[1] & sel[0], width: 1)   # sel == 1
        sel_2 = local(:sel_2, sel[1] & ~sel[0], width: 1)   # sel == 2
        sel_3 = local(:sel_3, sel[1] & sel[0], width: 1)    # sel == 3

        # Route input to selected output, others get 0
        y0 <= mux(sel_0, a, lit(0, width: w))
        y1 <= mux(sel_1, a, lit(0, width: w))
        y2 <= mux(sel_2, a, lit(0, width: w))
        y3 <= mux(sel_3, a, lit(0, width: w))
      end

      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 1
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:y0] = Wire.new("#{@name}.y0", width: @width)
        @outputs[:y1] = Wire.new("#{@name}.y1", width: @width)
        @outputs[:y2] = Wire.new("#{@name}.y2", width: @width)
        @outputs[:y3] = Wire.new("#{@name}.y3", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
