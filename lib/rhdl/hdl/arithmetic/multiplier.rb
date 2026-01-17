# HDL Multiplier
# Combinational multiplier (8x8 -> 16, synthesizable)

module RHDL
  module HDL
    class Multiplier < SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :product, width: 16

      behavior do
        product <= a * b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:product] = Wire.new("#{@name}.product", width: @width * 2)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
