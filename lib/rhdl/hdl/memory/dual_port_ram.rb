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

      def propagate
        if rising_edge?
          # Write from port A
          if in_val(:we_a) == 1
            addr_a = in_val(:addr_a) & (@depth - 1)
            @memory[addr_a] = in_val(:din_a) & ((1 << @data_width) - 1)
          end

          # Write from port B
          if in_val(:we_b) == 1
            addr_b = in_val(:addr_b) & (@depth - 1)
            @memory[addr_b] = in_val(:din_b) & ((1 << @data_width) - 1)
          end
        end

        # Async read from both ports
        addr_a = in_val(:addr_a) & (@depth - 1)
        addr_b = in_val(:addr_b) & (@depth - 1)
        out_set(:dout_a, @memory[addr_a])
        out_set(:dout_b, @memory[addr_b])
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
