# HDL Combinational Logic Components
# Bit Reverser

module RHDL
  module HDL
    # Bit Reverser
    class BitReverse < SimComponent
      # Class-level port definitions for synthesis (default 8-bit)
      input :a, width: 8
      output :y, width: 8

      behavior do
        # Reverse bit order: y = {a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]}
        y <= cat(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
