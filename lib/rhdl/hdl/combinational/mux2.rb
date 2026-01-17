# HDL Combinational Logic Components
# 2-to-1 Multiplexer

module RHDL
  module HDL
    # 2-to-1 Multiplexer
    class Mux2 < SimComponent
      port_input :a   # Selected when sel = 0
      port_input :b   # Selected when sel = 1
      port_input :sel
      port_output :y

      # mux(sel, if_true, if_false) - sel ? if_true : if_false
      # Note: sel=0 selects a (first arg), sel=1 selects b (second arg)
      behavior do
        y <= mux(sel, b, a)
      end

      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 1
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      def propagate
        if @width == 1 && self.class.behavior_defined?
          execute_behavior
        else
          if in_val(:sel) == 0
            out_set(:y, in_val(:a))
          else
            out_set(:y, in_val(:b))
          end
        end
      end
    end
  end
end
