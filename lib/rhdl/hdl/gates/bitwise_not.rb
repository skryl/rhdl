# HDL Bitwise NOT Gate
# Multi-bit NOT operation

module RHDL
  module HDL
    class BitwiseNot < SimComponent
      port_input :a, width: 8
      port_output :y, width: 8

      behavior do
        y <= ~a
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
