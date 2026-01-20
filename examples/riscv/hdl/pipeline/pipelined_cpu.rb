# Pipelined RISC-V RV32I CPU
# 5-stage pipeline with hazard detection and forwarding

require_relative '../../../../lib/rhdl'
require_relative '../memory'
require_relative 'pipelined_datapath'

module RISCV
  module Pipeline
    class PipelinedCPU < RHDL::HDL::Component
      input :clk
      input :rst

      # Debug outputs
      output :debug_pc, width: 32
      output :debug_inst, width: 32
      output :debug_x1, width: 32
      output :debug_x2, width: 32
      output :debug_x10, width: 32
      output :debug_x11, width: 32

      def initialize(name = nil)
        super(name)
        @datapath = PipelinedDatapath.new('datapath')
        @inst_mem = RISCV::Memory.new('inst_mem')
        @data_mem = RISCV::Memory.new('data_mem')
        add_subcomponent(:datapath, @datapath)
        add_subcomponent(:inst_mem, @inst_mem)
        add_subcomponent(:data_mem, @data_mem)
      end

      def propagate
        clk = in_val(:clk)
        rst = in_val(:rst)

        # Get current PC from datapath (without triggering sequential updates)
        inst_addr = @datapath.get_output(:inst_addr)

        # Read instruction from memory (combinational, based on current PC)
        @inst_mem.set_input(:clk, clk)
        @inst_mem.set_input(:rst, rst)
        @inst_mem.set_input(:addr, inst_addr)
        @inst_mem.set_input(:write_data, 0)
        @inst_mem.set_input(:mem_write, 0)
        @inst_mem.set_input(:mem_read, 1)
        @inst_mem.set_input(:funct3, 0b010)  # Word access
        @inst_mem.propagate
        inst_data = @inst_mem.get_output(:read_data)

        # Read data memory with current addresses
        data_addr = @datapath.get_output(:data_addr)
        data_wdata = @datapath.get_output(:data_wdata)
        data_we = @datapath.get_output(:data_we)
        data_re = @datapath.get_output(:data_re)
        data_funct3 = @datapath.get_output(:data_funct3)

        @data_mem.set_input(:clk, clk)
        @data_mem.set_input(:rst, rst)
        @data_mem.set_input(:addr, data_addr)
        @data_mem.set_input(:write_data, data_wdata)
        @data_mem.set_input(:mem_write, data_we)
        @data_mem.set_input(:mem_read, data_re)
        @data_mem.set_input(:funct3, data_funct3)
        @data_mem.propagate
        data_rdata = @data_mem.get_output(:read_data)

        # Now run datapath with memory data available
        # This will latch values on rising edge and compute next cycle's inputs
        @datapath.set_input(:clk, clk)
        @datapath.set_input(:rst, rst)
        @datapath.set_input(:inst_data, inst_data)
        @datapath.set_input(:data_rdata, data_rdata)
        @datapath.propagate

        # Debug outputs
        out_set(:debug_pc, @datapath.get_output(:debug_pc))
        out_set(:debug_inst, @datapath.get_output(:debug_inst))
        out_set(:debug_x1, @datapath.get_output(:debug_x1))
        out_set(:debug_x2, @datapath.get_output(:debug_x2))
        out_set(:debug_x10, @datapath.get_output(:debug_x10))
        out_set(:debug_x11, @datapath.get_output(:debug_x11))
      end

      # Load program into instruction memory
      def load_program(instructions, start_addr = 0)
        instructions.each_with_index do |inst, i|
          @inst_mem.write_word(start_addr + i * 4, inst)
        end
      end

      # Initialize data memory
      def write_data(addr, value)
        @data_mem.write_word(addr, value)
      end

      # Read data memory
      def read_data(addr)
        @data_mem.read_word(addr)
      end

      # Read register value
      def read_reg(index)
        @datapath.instance_variable_get(:@regfile).read_reg(index)
      end

      # Write register value (for testing)
      def write_reg(index, value)
        @datapath.instance_variable_get(:@regfile).write_reg(index, value)
      end

      # Execute one clock cycle (low -> high -> low)
      def clock_cycle
        set_input(:clk, 0)
        propagate
        set_input(:clk, 1)
        propagate
        set_input(:clk, 0)
        propagate
      end

      # Reset the CPU
      def reset!
        set_input(:rst, 1)
        set_input(:clk, 0)
        propagate
        set_input(:clk, 1)
        propagate
        set_input(:clk, 0)
        propagate
        set_input(:rst, 0)
        propagate
      end

      # Run multiple clock cycles
      def run_cycles(n)
        n.times { clock_cycle }
      end

      # Get current PC
      def pc
        @datapath.get_output(:debug_pc)
      end

      # Get current instruction in ID stage
      def current_inst
        @datapath.get_output(:debug_inst)
      end

    end
  end
end
