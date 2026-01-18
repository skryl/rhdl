# HDL Bitwise AND Gate
# Multi-bit AND operation

module RHDL
  module HDL
    class BitwiseAnd < SimComponent
      input :a, width: 8
      input :b, width: 8
      output :y, width: 8

      behavior do
        y <= a & b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
