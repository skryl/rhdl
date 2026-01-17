# frozen_string_literal: true

module RHDL
  module HDL
    # Stack (LIFO) with fixed depth
    # Sequential - requires always @(posedge clk) for synthesis
    class Stack < SimComponent
      port_input :clk
      port_input :rst
      port_input :push
      port_input :pop
      port_input :din, width: 8
      port_output :dout, width: 8
      port_output :empty
      port_output :full
      port_output :sp, width: 4

      def initialize(name = nil, data_width: 8, depth: 16)
        @data_width = data_width
        @depth = depth
        @addr_width = Math.log2(depth).ceil
        @memory = Array.new(depth, 0)
        @sp = 0
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        return if @data_width == 8 && @depth == 16
        @inputs[:din] = Wire.new("#{@name}.din", width: @data_width)
        @outputs[:dout] = Wire.new("#{@name}.dout", width: @data_width)
        @outputs[:sp] = Wire.new("#{@name}.sp", width: @addr_width)
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @sp = 0
          elsif in_val(:push) == 1 && @sp < @depth
            @memory[@sp] = in_val(:din) & ((1 << @data_width) - 1)
            @sp += 1
          elsif in_val(:pop) == 1 && @sp > 0
            @sp -= 1
          end
        end

        # Output top of stack
        dout = @sp > 0 ? @memory[@sp - 1] : 0
        out_set(:dout, dout)
        out_set(:empty, @sp == 0 ? 1 : 0)
        out_set(:full, @sp >= @depth ? 1 : 0)
        out_set(:sp, @sp)
      end
    end
  end
end
