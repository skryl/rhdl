# HDL Combinational Logic Components
# Generic N-bit Decoder

module RHDL
  module HDL
    # Generic N-bit Decoder - decodes N-bit input to 2^N outputs
    class DecoderN < SimComponent
      # Class-level port definitions for synthesis (default 3-bit = 8 outputs)
      port_input :a, width: 3
      port_input :en
      port_output :y0
      port_output :y1
      port_output :y2
      port_output :y3
      port_output :y4
      port_output :y5
      port_output :y6
      port_output :y7

      behavior do
        output_cnt = param(:output_count)
        en_val = en.value & 1
        addr_val = a.value & (output_cnt - 1)

        # Set each output based on decoded address
        output_cnt.times do |i|
          output_set(:"y#{i}", (en_val == 1 && i == addr_val) ? 1 : 0)
        end
      end

      def initialize(name = nil, width: 3)
        @width = width
        @output_count = 1 << width
        super(name)
      end

      def setup_ports
        return if @width == 3
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @output_count.times { |i| @outputs[:"y#{i}"] = Wire.new("#{@name}.y#{i}", width: 1) }
      end
    end
  end
end
