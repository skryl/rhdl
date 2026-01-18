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
    input :clk
    input :rst

    # Instruction memory interface
    output :inst_addr, width: 32    # Instruction address
    input :inst_data, width: 32     # Instruction data

    # Data memory interface
    output :data_addr, width: 32    # Data address
    output :data_wdata, width: 32   # Write data
    input :data_rdata, width: 32    # Read data
    output :data_we                 # Write enable
    output :data_re                 # Read enable
    output :data_funct3, width: 3   # Memory access size

    # Debug outputs
    output :debug_pc, width: 32
    output :debug_inst, width: 32
    output :debug_x1, width: 32
    output :debug_x2, width: 32
    output :debug_x10, width: 32
    output :debug_x11, width: 32

    # Internal signals
    wire :pc, width: 32
    wire :pc_plus4, width: 32
    wire :pc_next, width: 32
    wire :inst, width: 32
    wire :imm, width: 32
    wire :rs1_data, width: 32
    wire :rs2_data, width: 32
    wire :alu_a, width: 32
    wire :alu_b, width: 32
    wire :alu_result, width: 32
    wire :alu_zero
    wire :rd_data, width: 32
    wire :branch_target, width: 32
    wire :jal_target, width: 32
    wire :jalr_target, width: 32
    wire :branch_taken

    # Decoded control signals
    wire :opcode, width: 7
    wire :rd, width: 5
    wire :funct3, width: 3
    wire :rs1, width: 5
    wire :rs2, width: 5
    wire :funct7, width: 7
    wire :reg_write
    wire :mem_read
    wire :mem_write
    wire :mem_to_reg
    wire :alu_src
    wire :branch
    wire :jump
    wire :jalr
    wire :alu_op, width: 4

    # Component instances
    instance :pc_reg, ProgramCounter
    instance :regfile, RegisterFile
    instance :decoder, Decoder
    instance :imm_gen, ImmGen
    instance :alu, ALU
    instance :branch_cond, BranchCond

    # Clock and reset to sequential components
    port :clk => [[:pc_reg, :clk], [:regfile, :clk]]
    port :rst => [[:pc_reg, :rst], [:regfile, :rst]]

    # PC connections
    port :pc_next => [:pc_reg, :pc_next]
    port [:pc_reg, :pc] => :pc

    # Instruction to decoder and immediate generator
    port :inst => [:decoder, :inst]
    port :inst => [:imm_gen, :inst]

    # Decoder outputs
    port [:decoder, :opcode] => :opcode
    port [:decoder, :rd] => :rd
    port [:decoder, :funct3] => :funct3
    port [:decoder, :rs1] => :rs1
    port [:decoder, :rs2] => :rs2
    port [:decoder, :funct7] => :funct7
    port [:decoder, :reg_write] => :reg_write
    port [:decoder, :mem_read] => :mem_read
    port [:decoder, :mem_write] => :mem_write
    port [:decoder, :mem_to_reg] => :mem_to_reg
    port [:decoder, :alu_src] => :alu_src
    port [:decoder, :branch] => :branch
    port [:decoder, :jump] => :jump
    port [:decoder, :jalr] => :jalr
    port [:decoder, :alu_op] => :alu_op

    # Immediate generator output
    port [:imm_gen, :imm] => :imm

    # Register file connections
    port :rs1 => [:regfile, :rs1_addr]
    port :rs2 => [:regfile, :rs2_addr]
    port :rd => [:regfile, :rd_addr]
    port :rd_data => [:regfile, :rd_data]
    port :reg_write => [:regfile, :rd_we]
    port [:regfile, :rs1_data] => :rs1_data
    port [:regfile, :rs2_data] => :rs2_data

    # ALU connections
    port :alu_a => [:alu, :a]
    port :alu_b => [:alu, :b]
    port :alu_op => [:alu, :op]
    port [:alu, :result] => :alu_result
    port [:alu, :zero] => :alu_zero

    # Branch condition connections
    port :rs1_data => [:branch_cond, :rs1_data]
    port :rs2_data => [:branch_cond, :rs2_data]
    port :funct3 => [:branch_cond, :funct3]
    port [:branch_cond, :branch_taken] => :branch_taken

    # Debug outputs from register file
    port [:regfile, :debug_x1] => :debug_x1
    port [:regfile, :debug_x2] => :debug_x2
    port [:regfile, :debug_x10] => :debug_x10
    port [:regfile, :debug_x11] => :debug_x11

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
