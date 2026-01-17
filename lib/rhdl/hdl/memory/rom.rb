# frozen_string_literal: true

module RHDL
  module HDL
    # ROM (Read-Only Memory)
    # Combinational read with enable - can be synthesized as LUT or block ROM
    class ROM < SimComponent
      port_input :addr, width: 8
      port_input :en
      port_output :dout, width: 8

      def initialize(name = nil, data_width: 8, addr_width: 8, contents: [])
        @data_width = data_width
        @addr_width = addr_width
        @depth = 1 << addr_width
        @memory = Array.new(@depth, 0)
        contents.each_with_index { |v, i| @memory[i] = v if i < @depth }
        super(name)
      end

      def setup_ports
        return if @data_width == 8 && @addr_width == 8
        @inputs[:addr] = Wire.new("#{@name}.addr", width: @addr_width)
        @outputs[:dout] = Wire.new("#{@name}.dout", width: @data_width)
      end

      def propagate
        if in_val(:en) == 1
          addr = in_val(:addr) & (@depth - 1)
          out_set(:dout, @memory[addr])
        else
          out_set(:dout, 0)
        end
      end

      def read_mem(addr)
        @memory[addr & (@depth - 1)]
      end
    end
  end
end
