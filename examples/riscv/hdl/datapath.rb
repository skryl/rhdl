# RV32I Single-Cycle Datapath
# Integrates all CPU components into a complete datapath
# Uses structure DSL for component instantiation and wiring
# Fully synthesizable using behavior DSL for control logic

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'
require_relative 'alu'
require_relative 'register_file'
require_relative 'imm_gen'
require_relative 'decoder'
require_relative 'branch_cond'
require_relative 'program_counter'

module RISCV
  class Datapath < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # External interface
    port_input :clk
    port_input :rst

    # Instruction memory interface
    port_output :inst_addr, width: 32    # Instruction address
    port_input :inst_data, width: 32     # Instruction data

    # Data memory interface
    port_output :data_addr, width: 32    # Data address
    port_output :data_wdata, width: 32   # Write data
    port_input :data_rdata, width: 32    # Read data
    port_output :data_we                 # Write enable
    port_output :data_re                 # Read enable
    port_output :data_funct3, width: 3   # Memory access size

    # Debug outputs
    port_output :debug_pc, width: 32
    port_output :debug_inst, width: 32
    port_output :debug_x1, width: 32
    port_output :debug_x2, width: 32
    port_output :debug_x10, width: 32
    port_output :debug_x11, width: 32

    # Internal signals
    port_signal :pc, width: 32
    port_signal :pc_plus4, width: 32
    port_signal :pc_next, width: 32
    port_signal :inst, width: 32
    port_signal :imm, width: 32
    port_signal :rs1_data, width: 32
    port_signal :rs2_data, width: 32
    port_signal :alu_a, width: 32
    port_signal :alu_b, width: 32
    port_signal :alu_result, width: 32
    port_signal :alu_zero
    port_signal :rd_data, width: 32
    port_signal :branch_target, width: 32
    port_signal :jal_target, width: 32
    port_signal :jalr_target, width: 32
    port_signal :branch_taken

    # Decoded control signals
    port_signal :opcode, width: 7
    port_signal :rd, width: 5
    port_signal :funct3, width: 3
    port_signal :rs1, width: 5
    port_signal :rs2, width: 5
    port_signal :funct7, width: 7
    port_signal :reg_write
    port_signal :mem_read
    port_signal :mem_write
    port_signal :mem_to_reg
    port_signal :alu_src
    port_signal :branch
    port_signal :jump
    port_signal :jalr
    port_signal :alu_op, width: 4

    # Structure DSL - Declarative component instantiation
    structure do
      instance :pc_reg, ProgramCounter
      instance :regfile, RegisterFile
      instance :decoder, Decoder
      instance :imm_gen, ImmGen
      instance :alu, ALU
      instance :branch_cond, BranchCond

      # Clock and reset to sequential components
      connect :clk => [[:pc_reg, :clk], [:regfile, :clk]]
      connect :rst => [[:pc_reg, :rst], [:regfile, :rst]]

      # PC connections
      connect :pc_next => [:pc_reg, :pc_next]
      connect [:pc_reg, :pc] => :pc

      # Instruction to decoder and immediate generator
      connect :inst => [:decoder, :inst]
      connect :inst => [:imm_gen, :inst]

      # Decoder outputs
      connect [:decoder, :opcode] => :opcode
      connect [:decoder, :rd] => :rd
      connect [:decoder, :funct3] => :funct3
      connect [:decoder, :rs1] => :rs1
      connect [:decoder, :rs2] => :rs2
      connect [:decoder, :funct7] => :funct7
      connect [:decoder, :reg_write] => :reg_write
      connect [:decoder, :mem_read] => :mem_read
      connect [:decoder, :mem_write] => :mem_write
      connect [:decoder, :mem_to_reg] => :mem_to_reg
      connect [:decoder, :alu_src] => :alu_src
      connect [:decoder, :branch] => :branch
      connect [:decoder, :jump] => :jump
      connect [:decoder, :jalr] => :jalr
      connect [:decoder, :alu_op] => :alu_op

      # Immediate generator output
      connect [:imm_gen, :imm] => :imm

      # Register file connections
      connect :rs1 => [:regfile, :rs1_addr]
      connect :rs2 => [:regfile, :rs2_addr]
      connect :rd => [:regfile, :rd_addr]
      connect :rd_data => [:regfile, :rd_data]
      connect :reg_write => [:regfile, :rd_we]
      connect [:regfile, :rs1_data] => :rs1_data
      connect [:regfile, :rs2_data] => :rs2_data

      # ALU connections
      connect :alu_a => [:alu, :a]
      connect :alu_b => [:alu, :b]
      connect :alu_op => [:alu, :op]
      connect [:alu, :result] => :alu_result
      connect [:alu, :zero] => :alu_zero

      # Branch condition connections
      connect :rs1_data => [:branch_cond, :rs1_data]
      connect :rs2_data => [:branch_cond, :rs2_data]
      connect :funct3 => [:branch_cond, :funct3]
      connect [:branch_cond, :branch_taken] => :branch_taken

      # Debug outputs from register file
      connect [:regfile, :debug_x1] => :debug_x1
      connect [:regfile, :debug_x2] => :debug_x2
      connect [:regfile, :debug_x10] => :debug_x10
      connect [:regfile, :debug_x11] => :debug_x11
    end

    def initialize(name = nil)
      super(name)
      create_subcomponents
    end

    def create_subcomponents
      @pc_reg = add_subcomponent(:pc_reg, ProgramCounter.new('pc'))
      @regfile = add_subcomponent(:regfile, RegisterFile.new('regfile'))
      @decoder = add_subcomponent(:decoder, Decoder.new('decoder'))
      @imm_gen = add_subcomponent(:imm_gen, ImmGen.new('imm_gen'))
      @alu = add_subcomponent(:alu, ALU.new('alu'))
      @branch_cond = add_subcomponent(:branch_cond, BranchCond.new('branch_cond'))
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      inst_data = in_val(:inst_data)
      data_rdata = in_val(:data_rdata)

      # Clock and reset to sequential components
      @pc_reg.set_input(:clk, clk)
      @pc_reg.set_input(:rst, rst)
      @regfile.set_input(:clk, clk)
      @regfile.set_input(:rst, rst)

      # CRITICAL: On rising edge, sequential components should update based on
      # their CURRENT inputs (set during previous propagation), not new values.
      # This simulates how real hardware latches at the clock edge.
      @prev_clk ||= 0
      is_rising_edge = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if is_rising_edge && rst == 0
        # Let sequential components latch their current inputs
        # PC and register file will update based on what was set up last cycle
        @pc_reg.propagate
        @regfile.propagate
      end

      # Get current PC (may have been updated on rising edge)
      if !is_rising_edge
        @pc_reg.propagate
      end
      pc_val = @pc_reg.get_output(:pc)

      # Output instruction address
      out_set(:inst_addr, pc_val)

      # Use instruction from input
      inst = inst_data

      # Decode instruction
      @decoder.set_input(:inst, inst)
      @decoder.propagate

      opcode = @decoder.get_output(:opcode)
      rd = @decoder.get_output(:rd)
      funct3 = @decoder.get_output(:funct3)
      rs1 = @decoder.get_output(:rs1)
      rs2 = @decoder.get_output(:rs2)
      funct7 = @decoder.get_output(:funct7)
      reg_write = @decoder.get_output(:reg_write)
      mem_read = @decoder.get_output(:mem_read)
      mem_write = @decoder.get_output(:mem_write)
      mem_to_reg = @decoder.get_output(:mem_to_reg)
      alu_src = @decoder.get_output(:alu_src)
      branch = @decoder.get_output(:branch)
      jump = @decoder.get_output(:jump)
      jalr = @decoder.get_output(:jalr)
      alu_op = @decoder.get_output(:alu_op)

      # Generate immediate
      @imm_gen.set_input(:inst, inst)
      @imm_gen.propagate
      imm = @imm_gen.get_output(:imm)

      # Read registers
      @regfile.set_input(:rs1_addr, rs1)
      @regfile.set_input(:rs2_addr, rs2)
      @regfile.propagate

      rs1_data = @regfile.get_output(:rs1_data)
      rs2_data = @regfile.get_output(:rs2_data)

      # ALU input A selection:
      # - AUIPC: PC
      # - Others: rs1_data
      alu_a = (opcode == Opcode::AUIPC) ? pc_val : rs1_data

      # ALU input B selection:
      # - alu_src=1: immediate
      # - alu_src=0: rs2_data
      alu_b = (alu_src == 1) ? imm : rs2_data

      # Execute ALU operation
      @alu.set_input(:a, alu_a)
      @alu.set_input(:b, alu_b)
      @alu.set_input(:op, alu_op)
      @alu.propagate

      alu_result = @alu.get_output(:result)
      alu_zero = @alu.get_output(:zero)

      # Evaluate branch condition
      @branch_cond.set_input(:rs1_data, rs1_data)
      @branch_cond.set_input(:rs2_data, rs2_data)
      @branch_cond.set_input(:funct3, funct3)
      @branch_cond.propagate
      branch_taken_val = @branch_cond.get_output(:branch_taken)

      # Compute targets
      pc_plus4 = (pc_val + 4) & 0xFFFFFFFF
      branch_target = (pc_val + imm) & 0xFFFFFFFF
      jal_target = (pc_val + imm) & 0xFFFFFFFF
      jalr_target = (rs1_data + imm) & 0xFFFFFFFE  # Clear LSB for JALR

      # PC write enable - always update PC in single-cycle
      @pc_reg.set_input(:pc_we, 1)

      # PC next selection
      if jump == 1
        if jalr == 1
          @pc_reg.set_input(:pc_next, jalr_target)
        else
          @pc_reg.set_input(:pc_next, jal_target)
        end
      elsif branch == 1 && branch_taken_val == 1
        @pc_reg.set_input(:pc_next, branch_target)
      else
        @pc_reg.set_input(:pc_next, pc_plus4)
      end

      # Data memory interface
      out_set(:data_addr, alu_result)
      out_set(:data_wdata, rs2_data)
      out_set(:data_we, mem_write)
      out_set(:data_re, mem_read)
      out_set(:data_funct3, funct3)

      # Register write data selection
      rd_data_val = if mem_to_reg == 1
        data_rdata
      elsif jump == 1
        pc_plus4  # Return address for JAL/JALR
      else
        alu_result
      end

      # Write to register file (on rising edge only, handled by regfile)
      @regfile.set_input(:rd_addr, rd)
      @regfile.set_input(:rd_data, rd_data_val)
      @regfile.set_input(:rd_we, reg_write)

      # Debug outputs
      out_set(:debug_pc, pc_val)
      out_set(:debug_inst, inst)
      out_set(:debug_x1, @regfile.get_output(:debug_x1))
      out_set(:debug_x2, @regfile.get_output(:debug_x2))
      out_set(:debug_x10, @regfile.get_output(:debug_x10))
      out_set(:debug_x11, @regfile.get_output(:debug_x11))
    end

    # Helper methods for testing
    def read_pc
      @pc_reg.read_pc
    end

    def write_pc(value)
      @pc_reg.write_pc(value)
    end

    def read_reg(index)
      @regfile.read_reg(index)
    end

    def write_reg(index, value)
      @regfile.write_reg(index, value)
    end

    def self.verilog_module_name
      'riscv_datapath'
    end

    def self.to_verilog(top_name: nil)
      name = top_name || verilog_module_name
      RHDL::Export::Verilog.generate(to_ir(top_name: name))
    end
  end
end
