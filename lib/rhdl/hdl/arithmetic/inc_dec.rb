# HDL Increment/Decrement Unit
# Increment or decrement by 1

module RHDL
  module HDL
    class IncDec < SimComponent
      # Class-level port definitions for synthesis (default 8-bit width)
      port_input :a, width: 8
      port_input :inc    # 1 = increment, 0 = decrement
      port_output :result, width: 8
      port_output :cout  # Carry/borrow

      behavior do
        # Compute both increment and decrement results
        inc_result = local(:inc_result, a + lit(1, width: 8), width: 8)
        dec_result = local(:dec_result, a - lit(1, width: 8), width: 8)

        # Select result based on inc flag
        # mux(cond, when_true, when_false): when inc=1, use inc_result; when inc=0, use dec_result
        result <= mux(inc, inc_result, dec_result)

        # Carry/borrow detection
        # Overflow on increment: a == 0xFF (255)
        # Underflow on decrement: a == 0x00
        inc_cout = local(:inc_cout, a == lit(255, width: 8), width: 1)
        dec_cout = local(:dec_cout, a == lit(0, width: 8), width: 1)
        cout <= mux(inc, inc_cout, dec_cout)
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:result] = Wire.new("#{@name}.result", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
