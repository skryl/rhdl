# MOS 6502 CPU - Synthesizable System
# Combines Datapath and Memory into a complete synthesizable 6502 system
# Uses class-level instance/connect declarations for component instantiation and wiring

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
    port_input :clk
    port_input :rst
    port_input :rdy              # Ready/halt input
    port_input :irq              # Interrupt request
    port_input :nmi              # Non-maskable interrupt

    # Debug outputs (directly from datapath)
    port_output :reg_a, width: 8
    port_output :reg_x, width: 8
    port_output :reg_y, width: 8
    port_output :reg_sp, width: 8
    port_output :reg_pc, width: 16
    port_output :reg_p, width: 8
    port_output :opcode, width: 8
    port_output :state, width: 8
    port_output :halted
    port_output :cycle_count, width: 32

    # Memory bus outputs (directly from datapath)
    port_output :addr, width: 16
    port_output :data_out, width: 8
    port_output :rw
    port_output :sync

    # Internal signals for datapath <-> memory connection
    port_signal :mem_data_out, width: 8    # Memory read data -> datapath
    port_signal :dp_addr, width: 16        # Datapath address -> memory
    port_signal :dp_data_out, width: 8     # Datapath write data -> memory
    port_signal :dp_rw                     # Datapath read/write -> memory
    port_signal :dp_sync                   # Datapath sync signal
    port_signal :dp_reg_a, width: 8
    port_signal :dp_reg_x, width: 8
    port_signal :dp_reg_y, width: 8
    port_signal :dp_reg_sp, width: 8
    port_signal :dp_reg_pc, width: 16
    port_signal :dp_reg_p, width: 8
    port_signal :dp_opcode, width: 8
    port_signal :dp_state, width: 8
    port_signal :dp_halted
    port_signal :dp_cycle_count, width: 32

    # Component instances
    instance :datapath, Datapath
    instance :memory, Memory

    # Clock and reset to datapath
    wire :clk => [:datapath, :clk]
    wire :rst => [:datapath, :rst]
    wire :rdy => [:datapath, :rdy]
    wire :irq => [:datapath, :irq]
    wire :nmi => [:datapath, :nmi]

    # Clock to memory (memory uses clk for write timing)
    wire :clk => [:memory, :clk]

    # Datapath outputs -> internal signals
    wire [:datapath, :addr] => :dp_addr
    wire [:datapath, :data_out] => :dp_data_out
    wire [:datapath, :rw] => :dp_rw
    wire [:datapath, :sync] => :dp_sync
    wire [:datapath, :reg_a] => :dp_reg_a
    wire [:datapath, :reg_x] => :dp_reg_x
    wire [:datapath, :reg_y] => :dp_reg_y
    wire [:datapath, :reg_sp] => :dp_reg_sp
    wire [:datapath, :reg_pc] => :dp_reg_pc
    wire [:datapath, :reg_p] => :dp_reg_p
    wire [:datapath, :opcode] => :dp_opcode
    wire [:datapath, :state] => :dp_state
    wire [:datapath, :halted] => :dp_halted
    wire [:datapath, :cycle_count] => :dp_cycle_count

    # Memory inputs from datapath
    wire :dp_addr => [:memory, :addr]
    wire :dp_data_out => [:memory, :data_in]
    wire :dp_rw => [:memory, :rw]

    # Memory output -> datapath input
    wire [:memory, :data_out] => :mem_data_out
    wire :mem_data_out => [:datapath, :data_in]

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
