# HDL Stack Pointer
# Stack Pointer Register

module RHDL
  module HDL
    class StackPointer < SequentialComponent
      port_input :clk
      port_input :rst
      port_input :push     # Decrement SP
      port_input :pop      # Increment SP
      port_output :q, width: 8
      port_output :empty   # SP at max (empty stack)
      port_output :full    # SP at 0 (full stack)

      behavior do
        max_val = param(:max)
        initial_val = param(:initial)
        if rising_edge?
          if rst.value == 1
            set_state(initial_val)
          elsif push.value == 1
            set_state((state - 1) & max_val)
          elsif pop.value == 1
            set_state((state + 1) & max_val)
          end
        end
        q <= state
        empty <= (state == max_val ? 1 : 0)
        full <= (state == 0 ? 1 : 0)
      end

      def initialize(name = nil, width: 8, initial: 0xFF)
        @width = width
        @initial = initial
        @state = initial
        @max = (1 << width) - 1
        super(name)
      end

      def setup_ports
        return if @width == 8
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end
    end
  end
end
