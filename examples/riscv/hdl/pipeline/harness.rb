# Harness class for testing the pipelined RISC-V CPU
# Provides memory and test helper methods

require_relative 'cpu'
require_relative '../memory'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class Harness
      attr_reader :clock_count

      def initialize(name = nil)
        @cpu = CPU.new(name || 'cpu')
        @inst_mem = Memory.new('inst_mem')
        @data_mem = Memory.new('data_mem')
        @clock_count = 0
        reset!
      end

      def reset!
        @clock_count = 0
        @cpu.set_input(:rst, 1)
        @cpu.set_input(:clk, 0)
        propagate_all
        @cpu.set_input(:clk, 1)
        propagate_all
        @cpu.set_input(:clk, 0)
        propagate_all
        @cpu.set_input(:rst, 0)
        propagate_all
      end

      def clock_cycle
        # Low phase - fetch instruction for current PC
        @cpu.set_input(:clk, 0)
        propagate_fetch_only  # Fetch instruction without clock edge

        # Rising edge - latch values including fetched instruction
        @cpu.set_input(:clk, 1)
        propagate_all

        # Low phase - let combinational logic settle
        @cpu.set_input(:clk, 0)
        propagate_all
        @clock_count += 1
      end

      def run_cycles(n)
        n.times { clock_cycle }
      end

      def load_program(instructions, start_addr = 0)
        instructions.each_with_index do |inst, i|
          @inst_mem.write_word(start_addr + i * 4, inst)
        end
      end

      def write_data(addr, value)
        @data_mem.write_word(addr, value)
      end

      def read_data(addr)
        @data_mem.read_word(addr)
      end

      def read_reg(index)
        @cpu.read_reg(index)
      end

      def write_reg(index, value)
        @cpu.write_reg(index, value)
      end

      def pc
        @cpu.get_output(:debug_pc)
      end

      def current_inst
        @cpu.get_output(:debug_inst)
      end

      private

      # Fetch instruction for current PC and feed to CPU (without triggering clock edge)
      def propagate_fetch_only
        clk = @cpu.inputs[:clk].get
        rst = @cpu.inputs[:rst].get

        # Propagate CPU to get current instruction address
        @cpu.propagate
        inst_addr = @cpu.get_output(:inst_addr)

        # Fetch instruction from memory
        @inst_mem.set_input(:clk, clk)
        @inst_mem.set_input(:rst, rst)
        @inst_mem.set_input(:addr, inst_addr)
        @inst_mem.set_input(:write_data, 0)
        @inst_mem.set_input(:mem_write, 0)
        @inst_mem.set_input(:mem_read, 1)
        @inst_mem.set_input(:funct3, 0b010)
        @inst_mem.propagate
        inst_data = @inst_mem.get_output(:read_data)

        # Feed instruction to CPU (so it's available for the rising edge)
        @cpu.set_input(:inst_data, inst_data)
        @cpu.propagate  # Propagate to update wires, but clk=0 so no edge
      end

      def propagate_all
        clk = @cpu.inputs[:clk].get
        rst = @cpu.inputs[:rst].get

        # First propagate CPU to get instruction address
        @cpu.propagate
        inst_addr = @cpu.get_output(:inst_addr)

        # Instruction memory fetch
        @inst_mem.set_input(:clk, clk)
        @inst_mem.set_input(:rst, rst)
        @inst_mem.set_input(:addr, inst_addr)
        @inst_mem.set_input(:write_data, 0)
        @inst_mem.set_input(:mem_write, 0)
        @inst_mem.set_input(:mem_read, 1)
        @inst_mem.set_input(:funct3, 0b010)
        @inst_mem.propagate
        inst_data = @inst_mem.get_output(:read_data)

        # Feed instruction to CPU
        @cpu.set_input(:inst_data, inst_data)
        @cpu.propagate

        # Data memory access
        data_addr = @cpu.get_output(:data_addr)
        data_wdata = @cpu.get_output(:data_wdata)
        data_we = @cpu.get_output(:data_we)
        data_re = @cpu.get_output(:data_re)
        data_funct3 = @cpu.get_output(:data_funct3)

        @data_mem.set_input(:clk, clk)
        @data_mem.set_input(:rst, rst)
        @data_mem.set_input(:addr, data_addr)
        @data_mem.set_input(:write_data, data_wdata)
        @data_mem.set_input(:mem_write, data_we)
        @data_mem.set_input(:mem_read, data_re)
        @data_mem.set_input(:funct3, data_funct3)
        @data_mem.propagate
        data_rdata = @data_mem.get_output(:read_data)

        # Feed memory data back to CPU
        @cpu.set_input(:data_rdata, data_rdata)
        @cpu.propagate
      end
        end

        # Keep the old class name for backwards compatibility with tests
        PipelinedCPU = Harness
      end
    end
  end
end
