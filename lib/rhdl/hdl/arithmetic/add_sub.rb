# HDL Add-Subtract Unit
# Combined adder/subtractor

module RHDL
  module HDL
    class AddSub < SimComponent
      # Class-level port definitions for synthesis (default 8-bit width)
      port_input :a, width: 8
      port_input :b, width: 8
      port_input :sub      # 0 = add, 1 = subtract
      port_output :result, width: 8
      port_output :cout
      port_output :overflow
      port_output :zero
      port_output :negative

      behavior do
        # Compute sum and difference
        sum_result = local(:sum_result, a + b, width: 8)
        diff_result = local(:diff_result, a - b, width: 8)

        # Select result based on sub flag (mux returns when_true if condition != 0)
        # When sub=1: diff_result; when sub=0: sum_result
        result <= mux(sub, diff_result, sum_result)

        # Carry/borrow out
        # For addition: carry is bit 8 of sum
        # For subtraction: borrow is 1 when a < b
        add_carry = local(:add_carry, (a + b)[8], width: 1)
        sub_borrow = local(:sub_borrow, a < b, width: 1)
        cout <= mux(sub, sub_borrow, add_carry)

        # Sign bits for overflow detection
        a_sign = local(:a_sign, a[7], width: 1)
        b_sign = local(:b_sign, b[7], width: 1)
        result_val = local(:result_val, mux(sub, diff_result, sum_result), width: 8)
        r_sign = local(:r_sign, result_val[7], width: 1)

        # Overflow detection:
        # Addition: overflow when operand signs are same but result sign differs
        # Subtraction: overflow when operand signs differ and result sign differs from a
        add_overflow = local(:add_overflow, (a_sign == b_sign) & (r_sign ^ a_sign), width: 1)
        sub_overflow = local(:sub_overflow, (a_sign ^ b_sign) & (r_sign ^ a_sign), width: 1)
        overflow <= mux(sub, sub_overflow, add_overflow)

        # Zero and negative flags
        zero <= (result_val == lit(0, width: 8))
        negative <= r_sign
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:result] = Wire.new("#{@name}.result", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end
    end
  end
end
