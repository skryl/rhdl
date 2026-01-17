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

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:load) == 1
            @state = in_val(:d) & @max
          elsif in_val(:en) == 1
            inc_val = in_val(:inc)
            inc_val = 1 if inc_val == 0  # Default increment
            @state = (@state + inc_val) & @max
          end
        end
        out_set(:q, @state)
      end
    end
  end
end
