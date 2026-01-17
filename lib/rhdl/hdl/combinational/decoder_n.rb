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
        # Decode 3-bit input to 8 outputs when enabled
        dec_0 = local(:dec_0, ~a[2] & ~a[1] & ~a[0], width: 1)  # a == 0
        dec_1 = local(:dec_1, ~a[2] & ~a[1] & a[0], width: 1)   # a == 1
        dec_2 = local(:dec_2, ~a[2] & a[1] & ~a[0], width: 1)   # a == 2
        dec_3 = local(:dec_3, ~a[2] & a[1] & a[0], width: 1)    # a == 3
        dec_4 = local(:dec_4, a[2] & ~a[1] & ~a[0], width: 1)   # a == 4
        dec_5 = local(:dec_5, a[2] & ~a[1] & a[0], width: 1)    # a == 5
        dec_6 = local(:dec_6, a[2] & a[1] & ~a[0], width: 1)    # a == 6
        dec_7 = local(:dec_7, a[2] & a[1] & a[0], width: 1)     # a == 7

        y0 <= en & dec_0
        y1 <= en & dec_1
        y2 <= en & dec_2
        y3 <= en & dec_3
        y4 <= en & dec_4
        y5 <= en & dec_5
        y6 <= en & dec_6
        y7 <= en & dec_7
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
        @inputs[:a].on_change { |_| propagate }
      end

      def propagate
        if in_val(:en) == 0
          @output_count.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & ((1 << @width) - 1)
          @output_count.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end
  end
end
