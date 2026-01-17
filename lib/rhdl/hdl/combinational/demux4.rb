# HDL Combinational Logic Components
# 1-to-4 Demultiplexer

module RHDL
  module HDL
    # 1-to-4 Demultiplexer - routes input to one of 4 outputs
    class Demux4 < SimComponent
      # Class-level port definitions for synthesis (default 1-bit width)
      port_input :a
      port_input :sel, width: 2
      port_output :y0
      port_output :y1
      port_output :y2
      port_output :y3

      behavior do
        # Decode selector
        sel_0 = local(:sel_0, ~sel[1] & ~sel[0], width: 1)  # sel == 0
        sel_1 = local(:sel_1, ~sel[1] & sel[0], width: 1)   # sel == 1
        sel_2 = local(:sel_2, sel[1] & ~sel[0], width: 1)   # sel == 2
        sel_3 = local(:sel_3, sel[1] & sel[0], width: 1)    # sel == 3

        # Route input to selected output, others get 0
        y0 <= mux(sel_0, a, lit(0, width: 1))
        y1 <= mux(sel_1, a, lit(0, width: 1))
        y2 <= mux(sel_2, a, lit(0, width: 1))
        y3 <= mux(sel_3, a, lit(0, width: 1))
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

      def propagate
        if @width == 1 && self.class.behavior_defined?
          execute_behavior
        else
          val = in_val(:a)
          sel = in_val(:sel) & 3
          4.times { |i| out_set(:"y#{i}", i == sel ? val : 0) }
        end
      end
    end
  end
end
