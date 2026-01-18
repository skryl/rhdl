# HDL Combinational Logic Components
# 8-to-1 Multiplexer

module RHDL
  module HDL
    # 8-to-1 Multiplexer - selects one of 8 inputs
    class Mux8 < SimComponent
      # Class-level port definitions for synthesis (default 1-bit width)
      input :in0
      input :in1
      input :in2
      input :in3
      input :in4
      input :in5
      input :in6
      input :in7
      input :sel, width: 3
      output :y

      behavior do
        # 8-to-1 mux using case_select
        w = port_width(:y)
        y <= case_select(sel, {
          0 => in0,
          1 => in1,
          2 => in2,
          3 => in3,
          4 => in4,
          5 => in5,
          6 => in6,
          7 => in7
        }, default: lit(0, width: w))
      end

      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 1
        8.times { |i| @inputs[:"in#{i}"] = Wire.new("#{@name}.in#{i}", width: @width) }
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        8.times { |i| @inputs[:"in#{i}"].on_change { |_| propagate } }
      end
    end
  end
end
