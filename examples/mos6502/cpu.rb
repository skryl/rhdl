# MOS 6502 CPU - Synthesizable System
# Combines Datapath and Memory into a complete synthesizable 6502 system
# Uses structure DSL for component instantiation and wiring

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative 'hdl/datapath'
require_relative 'hdl/memory'

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

    # Structure DSL - Wire datapath and memory together
    structure do
      # Instantiate components
      instance :datapath, Datapath
      instance :memory, Memory

      # Clock and reset to datapath
      connect :clk => [:datapath, :clk]
      connect :rst => [:datapath, :rst]
      connect :rdy => [:datapath, :rdy]
      connect :irq => [:datapath, :irq]
      connect :nmi => [:datapath, :nmi]

      # Clock to memory (memory uses clk for write timing)
      connect :clk => [:memory, :clk]

      # Datapath outputs -> internal signals
      connect [:datapath, :addr] => :dp_addr
      connect [:datapath, :data_out] => :dp_data_out
      connect [:datapath, :rw] => :dp_rw
      connect [:datapath, :sync] => :dp_sync
      connect [:datapath, :reg_a] => :dp_reg_a
      connect [:datapath, :reg_x] => :dp_reg_x
      connect [:datapath, :reg_y] => :dp_reg_y
      connect [:datapath, :reg_sp] => :dp_reg_sp
      connect [:datapath, :reg_pc] => :dp_reg_pc
      connect [:datapath, :reg_p] => :dp_reg_p
      connect [:datapath, :opcode] => :dp_opcode
      connect [:datapath, :state] => :dp_state
      connect [:datapath, :halted] => :dp_halted
      connect [:datapath, :cycle_count] => :dp_cycle_count

      # Memory inputs from datapath
      connect :dp_addr => [:memory, :addr]
      connect :dp_data_out => [:memory, :data_in]
      connect :dp_rw => [:memory, :rw]

      # Memory chip select always enabled
      # (handled in behavior block below)

      # Memory output -> datapath input
      connect [:memory, :data_out] => :mem_data_out
      connect :mem_data_out => [:datapath, :data_in]
    end

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
