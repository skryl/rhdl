# HDL Register
# Multi-bit Register with synchronous reset and enable

module RHDL
  module HDL
    class Register < SequentialComponent
      port_input :d, width: 8
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q, width: 8

      behavior do
        if rising_edge?
          if rst.value == 1
            set_state(0)
          elsif en.value == 1
            set_state(d.value)
          end
        end
        q <= state
      end

      def initialize(name = nil, width: 8)
        @width = width
        @state = 0
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end
    end
  end
end
