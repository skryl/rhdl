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

      behavior do
        depth_val = param(:depth)
        data_width = param(:data_width)
        sp_val = param(:sp)

        if rising_edge?
          if rst.value == 1
            set_sp(0)
          elsif push.value == 1 && sp_val < depth_val
            mem_write(sp_val, din.value & ((1 << data_width) - 1))
            set_sp(sp_val + 1)
          elsif pop.value == 1 && sp_val > 0
            set_sp(sp_val - 1)
          end
        end

        # Output top of stack (re-read sp after potential update)
        current_sp = param(:sp)
        dout_val = current_sp > 0 ? mem_read(current_sp - 1) : 0
        dout <= dout_val
        empty <= (current_sp == 0 ? 1 : 0)
        full <= (current_sp >= depth_val ? 1 : 0)
        sp <= current_sp
      end

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
    end
  end
end
