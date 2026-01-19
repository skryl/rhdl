# RV32I Single-Cycle CPU
# Purely declarative implementation using the RHDL DSL
# Contains all datapath components and combinational control logic
#
# For testing, use the Harness class which provides a cleaner interface
# and interacts with the CPU only through ports.

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
  class CPU < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # External interface
    input :clk
    input :rst

    # Instruction memory interface
    output :inst_addr, width: 32    # Instruction address (PC)
    input :inst_data, width: 32     # Instruction data from memory

    # Data memory interface
    output :data_addr, width: 32    # Data address
    output :data_wdata, width: 32   # Write data
    input :data_rdata, width: 32    # Read data from memory
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

    # Internal signals - from sub-components
    wire :pc, width: 32
    wire :pc_next, width: 32
    wire :imm, width: 32
    wire :rs1_data, width: 32
    wire :rs2_data, width: 32
    wire :alu_result, width: 32
    wire :alu_zero
    wire :branch_taken

    # Decoded control signals from decoder
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

    # Internal signals - computed by behavior block
    wire :alu_a, width: 32
    wire :alu_b, width: 32
    wire :rd_data, width: 32
    wire :pc_plus4, width: 32
    wire :branch_target, width: 32
    wire :jalr_target, width: 32
    wire :pc_we  # PC write enable (always 1 for single-cycle)

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
    port :inst_data => [:decoder, :inst]
    port :inst_data => [:imm_gen, :inst]

    # Decoder outputs to internal wires
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

    # PC write enable connection
    port :pc_we => [:pc_reg, :pc_we]

    # Combinational control logic
    behavior do
      # PC write enable - always 1 for single-cycle CPU
      pc_we <= lit(1, width: 1)

      # PC + 4 for sequential execution and return address
      pc_plus4 <= pc + lit(4, width: 32)

      # Branch target = PC + immediate
      branch_target <= pc + imm

      # JALR target = rs1 + immediate with LSB cleared
      jalr_target <= (rs1_data + imm) & lit(0xFFFFFFFE, width: 32)

      # ALU A input mux: AUIPC uses PC, others use rs1_data
      alu_a <= mux(opcode == lit(Opcode::AUIPC, width: 7), pc, rs1_data)

      # ALU B input mux: alu_src=1 uses immediate, alu_src=0 uses rs2_data
      alu_b <= mux(alu_src, imm, rs2_data)

      # PC next selection:
      # - jump && jalr: jalr_target
      # - jump && !jalr: pc + imm (JAL target)
      # - branch && branch_taken: branch_target
      # - else: pc_plus4
      jal_target = local(:jal_target, pc + imm, width: 32)

      pc_next <= mux(jump,
                     mux(jalr, jalr_target, jal_target),
                     mux(branch & branch_taken, branch_target, pc_plus4))

      # Register write data selection:
      # - mem_to_reg: data from memory
      # - jump: return address (pc + 4)
      # - else: ALU result
      rd_data <= mux(mem_to_reg, data_rdata,
                     mux(jump, pc_plus4, alu_result))

      # Output connections
      inst_addr <= pc
      data_addr <= alu_result
      data_wdata <= rs2_data
      data_we <= mem_write
      data_re <= mem_read
      data_funct3 <= funct3
      debug_pc <= pc
      debug_inst <= inst_data
    end

    # Helper methods for testing - these access sub-component state directly
    # They are NOT part of the synthesizable design

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

      # Generate top-level last
      parts << to_verilog(top_name: top_name)

      parts.join("\n\n")
    end
  end
end
