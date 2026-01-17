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
        # Default 2-to-1 mux: sel=0 -> in0, sel=1 -> in1
        y <= mux(sel, in1, in0)
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
        @input_count.times { |i| @inputs[:"in#{i}"].on_change { |_| propagate } }
      end

      def propagate
        sel = in_val(:sel) & ((1 << @sel_width) - 1)
        if sel < @input_count
          out_set(:y, in_val(:"in#{sel}"))
        else
          out_set(:y, 0)
        end
      end
    end
  end
end
