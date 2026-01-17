# frozen_string_literal: true

module RHDL
  module HDL
    # True Dual-Port RAM with two independent read/write ports
    # Sequential - requires always @(posedge clk) and memory inference for synthesis
    class DualPortRAM < SimComponent
      port_input :clk
      port_input :we_a
      port_input :we_b
      port_input :addr_a, width: 8
      port_input :addr_b, width: 8
      port_input :din_a, width: 8
      port_input :din_b, width: 8
      port_output :dout_a, width: 8
      port_output :dout_b, width: 8

      behavior do
        depth = param(:depth)
        data_width = param(:data_width)
        data_mask = (1 << data_width) - 1
        addr_a_val = addr_a.value & (depth - 1)
        addr_b_val = addr_b.value & (depth - 1)

        # Write on rising edge
        if rising_edge?
          mem_write(addr_a_val, din_a.value & data_mask) if we_a.value == 1
          mem_write(addr_b_val, din_b.value & data_mask) if we_b.value == 1
        end

        # Async read from both ports
        dout_a <= mem_read(addr_a_val)
        dout_b <= mem_read(addr_b_val)
      end

      def initialize(name = nil, data_width: 8, addr_width: 8)
        @data_width = data_width
        @addr_width = addr_width
        @depth = 1 << addr_width
        @memory = Array.new(@depth, 0)
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        return if @data_width == 8 && @addr_width == 8
        @inputs[:addr_a] = Wire.new("#{@name}.addr_a", width: @addr_width)
        @inputs[:addr_b] = Wire.new("#{@name}.addr_b", width: @addr_width)
        @inputs[:din_a] = Wire.new("#{@name}.din_a", width: @data_width)
        @inputs[:din_b] = Wire.new("#{@name}.din_b", width: @data_width)
        @outputs[:dout_a] = Wire.new("#{@name}.dout_a", width: @data_width)
        @outputs[:dout_b] = Wire.new("#{@name}.dout_b", width: @data_width)
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def read_mem(addr)
        @memory[addr & (@depth - 1)]
      end

      def write_mem(addr, data)
        @memory[addr & (@depth - 1)] = data & ((1 << @data_width) - 1)
      end
    end
  end
end
