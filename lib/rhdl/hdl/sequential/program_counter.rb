# HDL Program Counter
# 16-bit Program Counter for CPU

module RHDL
  module HDL
    class ProgramCounter < SequentialComponent
      port_input :clk
      port_input :rst
      port_input :en          # Increment enable
      port_input :load        # Load new address
      port_input :d, width: 16
      port_input :inc, width: 16  # Increment amount (usually 1, 2, or 3)
      port_output :q, width: 16

      behavior do
        max_val = param(:max)
        if rising_edge?
          if rst.value == 1
            set_state(0)
          elsif load.value == 1
            set_state(d.value & max_val)
          elsif en.value == 1
            inc_val = inc.value
            inc_val = 1 if inc_val == 0  # Default increment
            set_state((state + inc_val) & max_val)
          end
        end
        q <= state
      end

      def initialize(name = nil, width: 16)
        @width = width
        @state = 0
        @max = (1 << width) - 1
        super(name)
      end

      def setup_ports
        return if @width == 16
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @inputs[:inc] = Wire.new("#{@name}.inc", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end
    end
  end
end
