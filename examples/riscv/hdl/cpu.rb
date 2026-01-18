# RV32I Single-Cycle CPU
# Top-level component combining Datapath and Memory
# Fully synthesizable - generates complete Verilog hierarchy
#
# For testing, use the Harness class which provides a cleaner interface
# and interacts with the CPU only through ports.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'
require_relative 'datapath'
require_relative 'memory'

module RISCV
  class CPU < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # External interface
    input :clk
    input :rst

    # Debug outputs
    output :pc, width: 32
    output :inst, width: 32
    output :x1, width: 32
    output :x2, width: 32
    output :x10, width: 32
    output :x11, width: 32

    # Memory bus outputs (for external access)
    output :mem_addr, width: 32
    output :mem_wdata, width: 32
    output :mem_we
    output :mem_re

    # Internal signals
    wire :inst_addr, width: 32
    wire :inst_data, width: 32
    wire :data_addr, width: 32
    wire :data_wdata, width: 32
    wire :data_rdata, width: 32
    wire :data_we
    wire :data_re
    wire :data_funct3, width: 3

    # Component instances
    instance :datapath, Datapath
    instance :inst_mem, Memory
    instance :data_mem, Memory

    # Clock and reset
    port :clk => [[:datapath, :clk], [:inst_mem, :clk], [:data_mem, :clk]]
    port :rst => [[:datapath, :rst], [:inst_mem, :rst], [:data_mem, :rst]]

    # Instruction memory connections
    port [:datapath, :inst_addr] => :inst_addr
    port :inst_addr => [:inst_mem, :addr]
    port [:inst_mem, :read_data] => :inst_data
    port :inst_data => [:datapath, :inst_data]

    # Data memory connections
    port [:datapath, :data_addr] => :data_addr
    port [:datapath, :data_wdata] => :data_wdata
    port [:datapath, :data_we] => :data_we
    port [:datapath, :data_re] => :data_re
    port [:datapath, :data_funct3] => :data_funct3

    port :data_addr => [:data_mem, :addr]
    port :data_wdata => [:data_mem, :write_data]
    port :data_we => [:data_mem, :mem_write]
    port :data_re => [:data_mem, :mem_read]
    port :data_funct3 => [:data_mem, :funct3]
    port [:data_mem, :read_data] => :data_rdata
    port :data_rdata => [:datapath, :data_rdata]

    # Debug outputs from datapath
    port [:datapath, :debug_pc] => :pc
    port [:datapath, :debug_inst] => :inst
    port [:datapath, :debug_x1] => :x1
    port [:datapath, :debug_x2] => :x2
    port [:datapath, :debug_x10] => :x10
    port [:datapath, :debug_x11] => :x11

    def initialize(name = nil, mem_size: Memory::DEFAULT_SIZE)
      @mem_size = mem_size
      super(name)
      create_subcomponents
    end

    def create_subcomponents
      @datapath = add_subcomponent(:datapath, Datapath.new('dp'))
      @inst_mem = add_subcomponent(:inst_mem, Memory.new('imem', size: @mem_size))
      @data_mem = add_subcomponent(:data_mem, Memory.new('dmem', size: @mem_size))
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)

      # Clock and reset to all components
      @datapath.set_input(:clk, clk)
      @datapath.set_input(:rst, rst)
      @inst_mem.set_input(:clk, clk)
      @inst_mem.set_input(:rst, rst)
      @data_mem.set_input(:clk, clk)
      @data_mem.set_input(:rst, rst)

      # First, propagate datapath to get instruction address
      @datapath.propagate

      inst_addr = @datapath.get_output(:inst_addr)

      # Instruction fetch (always read)
      @inst_mem.set_input(:addr, inst_addr)
      @inst_mem.set_input(:mem_read, 1)
      @inst_mem.set_input(:mem_write, 0)
      @inst_mem.set_input(:funct3, Funct3::WORD)  # Always word-aligned fetch
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

      # Debug outputs
      out_set(:pc, @datapath.get_output(:debug_pc))
      out_set(:inst, @datapath.get_output(:debug_inst))
      out_set(:x1, @datapath.get_output(:debug_x1))
      out_set(:x2, @datapath.get_output(:debug_x2))
      out_set(:x10, @datapath.get_output(:debug_x10))
      out_set(:x11, @datapath.get_output(:debug_x11))

      # Memory bus outputs
      out_set(:mem_addr, data_addr)
      out_set(:mem_wdata, data_wdata)
      out_set(:mem_we, data_we)
      out_set(:mem_re, data_re)
    end

    # Direct access methods for simulation test setup
    # These are simulation conveniences that directly manipulate internal state.
    # For normal testing, use the Harness class instead.

    def load_program(program, start_addr = 0)
      @inst_mem.load_program(program, start_addr)
    end

    # Load data into data memory
    def load_data(data, start_addr = 0)
      @data_mem.load_program(data, start_addr)
    end

    # Read instruction memory (for testing)
    def read_inst_word(addr)
      @inst_mem.read_word(addr)
    end

    # Read data memory (for testing)
    def read_data_word(addr)
      @data_mem.read_word(addr)
    end

    # Write data memory (for testing)
    def write_data_word(addr, value)
      @data_mem.write_word(addr, value)
    end

    # Read register (for testing)
    def read_reg(index)
      @datapath.read_reg(index)
    end

    # Write register (for testing)
    def write_reg(index, value)
      @datapath.write_reg(index, value)
    end

    # Read PC (for testing)
    def read_pc
      @datapath.read_pc
    end

    # Write PC (for testing)
    def write_pc(value)
      @datapath.write_pc(value)
    end

    # Run for specified number of clock cycles
    def run_cycles(cycles)
      cycles.times do
        clock_cycle
      end
    end

    # Execute one clock cycle
    def clock_cycle
      # Rising edge
      set_input(:clk, 0)
      propagate
      set_input(:clk, 1)
      propagate
    end

    # Reset the CPU
    def reset!
      set_input(:rst, 1)
      set_input(:clk, 0)
      propagate
      set_input(:clk, 1)
      propagate
      set_input(:rst, 0)
    end

    def self.verilog_module_name
      'riscv_cpu'
    end

    def self.to_verilog(top_name: nil)
      name = top_name || verilog_module_name
      RHDL::Export::Verilog.generate(to_ir(top_name: name))
    end

    # Generate complete Verilog hierarchy
    def self.to_verilog_hierarchy(top_name: nil)
      parts = []

      # Generate sub-modules first
      parts << ALU.to_verilog
      parts << RegisterFile.to_verilog
      parts << ImmGen.to_verilog
      parts << Decoder.to_verilog
      parts << BranchCond.to_verilog
      parts << ProgramCounter.to_verilog
      parts << Memory.to_verilog
      parts << Datapath.to_verilog

      # Generate top-level last
      parts << to_verilog(top_name: top_name)

      parts.join("\n\n")
    end
  end
end
