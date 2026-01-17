# frozen_string_literal: true

module RHDL
  module HDL
    # Synchronous RAM with single port
    # Sequential - requires always @(posedge clk) and memory inference for synthesis
    class RAM < SimComponent
      port_input :clk
      port_input :we       # Write enable
      port_input :addr, width: 8
      port_input :din, width: 8
      port_output :dout, width: 8

      behavior do
        depth = param(:depth)
        data_width = param(:data_width)
        addr_val = addr.value & (depth - 1)

        # Write on rising edge
        if rising_edge? && we.value == 1
          mem_write(addr_val, din.value & ((1 << data_width) - 1))
        end

        # Async read
        dout <= mem_read(addr_val)
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
        @inputs[:addr] = Wire.new("#{@name}.addr", width: @addr_width)
        @inputs[:din] = Wire.new("#{@name}.din", width: @data_width)
        @outputs[:dout] = Wire.new("#{@name}.dout", width: @data_width)
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        @memory[addr & (@depth - 1)]
      end

      def write_mem(addr, data)
        @memory[addr & (@depth - 1)] = data & ((1 << @data_width) - 1)
      end

      def load_program(program, start_addr = 0)
        program.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end
    end
  end
end
