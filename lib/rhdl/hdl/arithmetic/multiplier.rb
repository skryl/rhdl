# HDL Multiplier
# Combinational multiplier (8x8 -> 16)

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

      def propagate
        if @width == 8 && self.class.behavior_defined?
          execute_behavior
        else
          a = in_val(:a)
          b = in_val(:b)
          product = a * b
          out_set(:product, product & ((1 << (@width * 2)) - 1))
        end
      end
    end
  end
end
