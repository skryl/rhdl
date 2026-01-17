# HDL Shift Register
# Shift Register with serial/parallel I/O

module RHDL
  module HDL
    class ShiftRegister < SequentialComponent
      port_input :d_in       # Serial input
      port_input :clk
      port_input :rst
      port_input :en
      port_input :dir        # 0 = right, 1 = left
      port_input :load       # Parallel load enable
      port_input :d, width: 8  # Parallel load data
      port_output :q, width: 8
      port_output :d_out     # Serial output

      behavior do
        w = param(:width)
        mask = (1 << w) - 1
        if rising_edge?
          if rst.value == 1
            set_state(0)
          elsif load.value == 1
            set_state(d.value)
          elsif en.value == 1
            if dir.value == 0  # Shift right
              set_state((state >> 1) | ((d_in.value & 1) << (w - 1)))
            else  # Shift left
              set_state(((state << 1) | (d_in.value & 1)) & mask)
            end
          end
        end
        q <= state
        # Serial out is LSB when shifting right, MSB when shifting left
        d_out <= dir.value == 0 ? state & 1 : (state >> (w - 1)) & 1
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
