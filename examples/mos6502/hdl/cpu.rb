# MOS 6502 CPU - Synthesizable System
# Combines Datapath and Memory into a complete synthesizable 6502 system
# Uses class-level instance/port declarations for component instantiation and wiring

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'datapath'
require_relative 'memory'

module MOS6502
  # Synthesizable CPU combining Datapath and Memory
  # This generates proper Verilog module instantiations for synthesis
  class CPU < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

    # External interface
    input :clk
    input :rst
    input :rdy              # Ready/halt input
    input :irq              # Interrupt request
    input :nmi              # Non-maskable interrupt

    # Debug outputs (directly from datapath)
    output :reg_a, width: 8
    output :reg_x, width: 8
    output :reg_y, width: 8
    output :reg_sp, width: 8
    output :reg_pc, width: 16
    output :reg_p, width: 8
    output :opcode, width: 8
    output :state, width: 8
    output :halted
    output :cycle_count, width: 32

    # Memory bus outputs (directly from datapath)
    output :addr, width: 16
    output :data_out, width: 8
    output :rw
    output :sync

    # Internal signals for datapath <-> memory connection
    wire :mem_data_out, width: 8    # Memory read data -> datapath
    wire :dp_addr, width: 16        # Datapath address -> memory
    wire :dp_data_out, width: 8     # Datapath write data -> memory
    wire :dp_rw                     # Datapath read/write -> memory
    wire :dp_sync                   # Datapath sync signal
    wire :dp_reg_a, width: 8
    wire :dp_reg_x, width: 8
    wire :dp_reg_y, width: 8
    wire :dp_reg_sp, width: 8
    wire :dp_reg_pc, width: 16
    wire :dp_reg_p, width: 8
    wire :dp_opcode, width: 8
    wire :dp_state, width: 8
    wire :dp_halted
    wire :dp_cycle_count, width: 32

    # Component instances
    instance :datapath, Datapath
    instance :memory, Memory

    # Clock and reset to datapath
    port :clk => [:datapath, :clk]
    port :rst => [:datapath, :rst]
    port :rdy => [:datapath, :rdy]
    port :irq => [:datapath, :irq]
    port :nmi => [:datapath, :nmi]

    # Clock to memory (memory uses clk for write timing)
    port :clk => [:memory, :clk]

    # Datapath outputs -> internal signals
    port [:datapath, :addr] => :dp_addr
    port [:datapath, :data_out] => :dp_data_out
    port [:datapath, :rw] => :dp_rw
    port [:datapath, :sync] => :dp_sync
    port [:datapath, :reg_a] => :dp_reg_a
    port [:datapath, :reg_x] => :dp_reg_x
    port [:datapath, :reg_y] => :dp_reg_y
    port [:datapath, :reg_sp] => :dp_reg_sp
    port [:datapath, :reg_pc] => :dp_reg_pc
    port [:datapath, :reg_p] => :dp_reg_p
    port [:datapath, :opcode] => :dp_opcode
    port [:datapath, :state] => :dp_state
    port [:datapath, :halted] => :dp_halted
    port [:datapath, :cycle_count] => :dp_cycle_count

    # Memory inputs from datapath
    port :dp_addr => [:memory, :addr]
    port :dp_data_out => [:memory, :data_in]
    port :dp_rw => [:memory, :rw]

    # Memory output -> datapath input
    port [:memory, :data_out] => :mem_data_out
    port :mem_data_out => [:datapath, :data_in]

    # Behavior block for combinational logic
    behavior do
      # Forward datapath outputs to CPU outputs
      reg_a <= dp_reg_a
      reg_x <= dp_reg_x
      reg_y <= dp_reg_y
      reg_sp <= dp_reg_sp
      reg_pc <= dp_reg_pc
      reg_p <= dp_reg_p
      opcode <= dp_opcode
      state <= dp_state
      halted <= dp_halted
      cycle_count <= dp_cycle_count
      addr <= dp_addr
      data_out <= dp_data_out
      rw <= dp_rw
      sync <= dp_sync
    end

    def self.verilog_module_name
      'mos6502_cpu'
    end

    def self.to_verilog(top_name: nil)
      name = top_name || verilog_module_name
      RHDL::Export::Verilog.generate(to_ir(top_name: name))
    end

    # Override to_ir to handle the memory chip select constant
    def self.to_ir(top_name: nil)
      ir = super(top_name: top_name)

      # Find memory instance and add cs = 1 connection
      mem_inst = ir.instances.find { |i| i.name == 'memory' }
      if mem_inst
        # Add chip select connection as constant 1
        mem_inst.connections << RHDL::Export::IR::PortConnection.new(
          port_name: :cs,
          signal: RHDL::Export::IR::Literal.new(value: 1, width: 1)
        )
      end

      ir
    end
  end
end
