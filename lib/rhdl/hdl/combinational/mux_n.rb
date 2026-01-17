# HDL Combinational Logic Components
# N-to-1 Multiplexer (generic)

module RHDL
  module HDL
    # N-to-1 Multiplexer (generic) - selects one of N inputs
    class MuxN < SimComponent
      # Class-level port definitions for synthesis (default 2-to-1)
      port_input :in0
      port_input :in1
      port_input :sel
      port_output :y

      behavior do
        input_cnt = param(:input_count)
        sel_w = param(:sel_width)
        sel_val = sel.value & ((1 << sel_w) - 1)

        if sel_val < input_cnt
          y <= input_val(:"in#{sel_val}")
        else
          y <= 0
        end
      end

      def initialize(name = nil, inputs: 2, width: 1)
        @input_count = inputs
        @sel_width = Math.log2(inputs).ceil
        @width = width
        super(name)
      end

      def setup_ports
        return if @input_count == 2 && @width == 1
        @input_count.times { |i| @inputs[:"in#{i}"] = Wire.new("#{@name}.in#{i}", width: @width) }
        @inputs[:sel] = Wire.new("#{@name}.sel", width: @sel_width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
      end
    end
  end
end
