# frozen_string_literal: true

module RHDL
  module HDL
    # Register File (multiple registers with read/write ports)
    # Sequential write, combinational read - typical FPGA register file
    class RegisterFile < SimComponent
      port_input :clk
      port_input :we
      port_input :waddr, width: 3
      port_input :raddr1, width: 3
      port_input :raddr2, width: 3
      port_input :wdata, width: 8
      port_output :rdata1, width: 8
      port_output :rdata2, width: 8

      behavior do
        num_regs = param(:num_regs)
        data_width = param(:data_width)

        # Write on rising edge
        if rising_edge? && we.value == 1
          waddr_val = waddr.value & (num_regs - 1)
          mem_write(waddr_val, wdata.value & ((1 << data_width) - 1), :registers)
        end

        # Async read
        raddr1_val = raddr1.value & (num_regs - 1)
        raddr2_val = raddr2.value & (num_regs - 1)
        rdata1 <= mem_read(raddr1_val, :registers)
        rdata2 <= mem_read(raddr2_val, :registers)
      end

      def initialize(name = nil, data_width: 8, num_regs: 8)
        @data_width = data_width
        @num_regs = num_regs
        @addr_width = Math.log2(num_regs).ceil
        @registers = Array.new(num_regs, 0)
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        return if @data_width == 8 && @num_regs == 8
        @inputs[:waddr] = Wire.new("#{@name}.waddr", width: @addr_width)
        @inputs[:raddr1] = Wire.new("#{@name}.raddr1", width: @addr_width)
        @inputs[:raddr2] = Wire.new("#{@name}.raddr2", width: @addr_width)
        @inputs[:wdata] = Wire.new("#{@name}.wdata", width: @data_width)
        @outputs[:rdata1] = Wire.new("#{@name}.rdata1", width: @data_width)
        @outputs[:rdata2] = Wire.new("#{@name}.rdata2", width: @data_width)
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def read_reg(addr)
        @registers[addr & (@num_regs - 1)]
      end

      def write_reg(addr, data)
        @registers[addr & (@num_regs - 1)] = data & ((1 << @data_width) - 1)
      end
    end
  end
end
