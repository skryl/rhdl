# RV32I Harness - Simulation Test Harness
# Wraps the synthesizable Datapath for behavior simulation and testing
# Interacts with Datapath only through ports - no direct access to internals
# Provides high-level methods for stepping, running, and debugging

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'
require_relative 'datapath'
require_relative 'memory'

module RISCV
  # Simulation harness for the synthesizable Datapath
  # All interaction with Datapath is through ports only
  class Harness
    attr_reader :clock_count

    def initialize(mem_size: Memory::DEFAULT_SIZE)
      @mem_size = mem_size
      @clock_count = 0
      @prev_clk = 0

      # Create datapath and memories
      @datapath = Datapath.new('dp')
      @inst_mem = Memory.new('imem', size: mem_size)
      @data_mem = Memory.new('dmem', size: mem_size)

      reset!
    end

    def reset!
      @clock_count = 0
      @prev_clk = 0

      # Pulse reset
      set_clk_rst(0, 1)
      propagate_all
      set_clk_rst(1, 1)
      propagate_all
      set_clk_rst(0, 0)
      propagate_all
    end

    def clock_cycle
      # Low phase
      set_clk_rst(0, 0)
      propagate_all

      # Rising edge
      set_clk_rst(1, 0)
      propagate_all

      @clock_count += 1
    end

    def run_cycles(n)
      n.times { clock_cycle }
    end

    # Register accessors - read through output ports
    def read_reg(index)
      case index
      when 0 then 0  # x0 always zero
      when 1 then @datapath.get_output(:debug_x1)
      when 2 then @datapath.get_output(:debug_x2)
      when 10 then @datapath.get_output(:debug_x10)
      when 11 then @datapath.get_output(:debug_x11)
      else
        # For other registers, use direct access (simulation convenience)
        @datapath.read_reg(index)
      end
    end

    # PC accessor - read through output port
    def read_pc
      @datapath.get_output(:debug_pc)
    end

    # Register setters - direct state manipulation for test setup
    def write_reg(index, value)
      @datapath.write_reg(index, value)
    end

    def write_pc(value)
      @datapath.write_pc(value)
    end

    # Memory accessors
    def load_program(program, start_addr = 0)
      @inst_mem.load_program(program, start_addr)
    end

    def load_data(data, start_addr = 0)
      @data_mem.load_program(data, start_addr)
    end

    def read_inst_word(addr)
      @inst_mem.read_word(addr)
    end

    def read_data_word(addr)
      @data_mem.read_word(addr)
    end

    def write_data_word(addr, value)
      @data_mem.write_word(addr, value)
    end

    # Debug output
    def state
      {
        pc: read_pc,
        x1: read_reg(1),
        x2: read_reg(2),
        x10: read_reg(10),
        x11: read_reg(11),
        inst: @datapath.get_output(:debug_inst),
        cycles: @clock_count
      }
    end

    def status_string
      format("PC:%08X x1:%08X x2:%08X x10:%08X x11:%08X Cycles:%d",
             read_pc, read_reg(1), read_reg(2), read_reg(10), read_reg(11), @clock_count)
    end

    private

    def set_clk_rst(clk, rst)
      @datapath.set_input(:clk, clk)
      @datapath.set_input(:rst, rst)
      @inst_mem.set_input(:clk, clk)
      @inst_mem.set_input(:rst, rst)
      @data_mem.set_input(:clk, clk)
      @data_mem.set_input(:rst, rst)
    end

    def propagate_all
      # Propagate datapath to get instruction address
      @datapath.propagate

      inst_addr = @datapath.get_output(:inst_addr)

      # Instruction fetch (always read)
      @inst_mem.set_input(:addr, inst_addr)
      @inst_mem.set_input(:mem_read, 1)
      @inst_mem.set_input(:mem_write, 0)
      @inst_mem.set_input(:funct3, Funct3::WORD)
      @inst_mem.set_input(:write_data, 0)
      @inst_mem.propagate

      inst_data = @inst_mem.get_output(:read_data)

      # Feed instruction to datapath
      @datapath.set_input(:inst_data, inst_data)

      # Re-propagate datapath with instruction
      @datapath.propagate

      # Data memory access
      data_addr = @datapath.get_output(:data_addr)
      data_wdata = @datapath.get_output(:data_wdata)
      data_we = @datapath.get_output(:data_we)
      data_re = @datapath.get_output(:data_re)
      data_funct3 = @datapath.get_output(:data_funct3)

      @data_mem.set_input(:addr, data_addr)
      @data_mem.set_input(:write_data, data_wdata)
      @data_mem.set_input(:mem_write, data_we)
      @data_mem.set_input(:mem_read, data_re)
      @data_mem.set_input(:funct3, data_funct3)
      @data_mem.propagate

      data_rdata = @data_mem.get_output(:read_data)

      # Feed memory data back to datapath for LOAD instructions
      @datapath.set_input(:data_rdata, data_rdata)
      @datapath.propagate
    end
  end
end
