# HDL Bitwise XOR Gate
# Multi-bit XOR operation

module RHDL
  module HDL
    class BitwiseXor < SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= a ^ b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      def propagate
        out_set(:y, in_val(:a) ^ in_val(:b))
      end
    end
  end
end
