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

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = @initial
          elsif in_val(:push) == 1
            @state = (@state - 1) & @max
          elsif in_val(:pop) == 1
            @state = (@state + 1) & @max
          end
        end
        out_set(:q, @state)
        out_set(:empty, @state == @max ? 1 : 0)
        out_set(:full, @state == 0 ? 1 : 0)
      end
    end
  end
end
