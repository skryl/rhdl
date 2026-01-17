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

      behavior do
        max_val = param(:max)
        if rising_edge?
          if rst.value == 1
            set_state(0)
          elsif load.value == 1
            set_state(d.value & max_val)
          elsif en.value == 1
            if up.value == 1
              set_state((state + 1) & max_val)
            else
              set_state((state - 1) & max_val)
            end
          end
        end
        q <= state
        # Terminal count: max when counting up, 0 when counting down
        tc_val = up.value == 1 ? (state == max_val ? 1 : 0) : (state == 0 ? 1 : 0)
        tc <= tc_val
        zero <= (state == 0 ? 1 : 0)
      end

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
    end
  end
end
