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

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:load) == 1
            @state = in_val(:d)
          elsif in_val(:en) == 1
            if in_val(:dir) == 0  # Shift right
              @state = (@state >> 1) | ((in_val(:d_in) & 1) << (@width - 1))
            else  # Shift left
              @state = ((@state << 1) | (in_val(:d_in) & 1)) & ((1 << @width) - 1)
            end
          end
        end
        out_set(:q, @state)
        # Serial out is LSB when shifting right, MSB when shifting left
        serial_out = in_val(:dir) == 0 ? @state & 1 : (@state >> (@width - 1)) & 1
        out_set(:d_out, serial_out)
      end
    end
  end
end
