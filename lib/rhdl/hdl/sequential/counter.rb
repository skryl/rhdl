# HDL Counter
# Binary Counter with up/down, load, and wrap

module RHDL
  module HDL
    class Counter < SequentialComponent
      port_input :clk
      port_input :rst
      port_input :en
      port_input :up        # 1 = count up, 0 = count down
      port_input :load
      port_input :d, width: 8
      port_output :q, width: 8
      port_output :tc       # Terminal count (max when up, 0 when down)
      port_output :zero     # Zero flag

      def initialize(name = nil, width: 8)
        @width = width
        @state = 0
        @max = (1 << width) - 1
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
            @state = in_val(:d) & @max
          elsif in_val(:en) == 1
            if in_val(:up) == 1
              @state = (@state + 1) & @max
            else
              @state = (@state - 1) & @max
            end
          end
        end
        out_set(:q, @state)
        tc = in_val(:up) == 1 ? (@state == @max ? 1 : 0) : (@state == 0 ? 1 : 0)
        out_set(:tc, tc)
        out_set(:zero, @state == 0 ? 1 : 0)
      end
    end
  end
end
