# Pipelined RISC-V RV32I CPU
# 5-stage pipeline: IF -> ID -> EX -> MEM -> WB
# Purely declarative implementation using the RHDL DSL
# Includes forwarding and hazard detection
#
# IMPORTANT: Pipeline register inputs are set via behavior block (not direct wire connections)
# to ensure correct timing. The behavior block runs BEFORE sequential propagation,
# so inputs are "frozen" at the right values when registers latch.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'
require_relative '../alu'
require_relative '../decoder'
require_relative '../imm_gen'
require_relative '../program_counter'
require_relative '../register_file'
require_relative '../memory'
require_relative 'if_id_reg'
require_relative 'id_ex_reg'
require_relative 'ex_mem_reg'
require_relative 'mem_wb_reg'
require_relative 'hazard_unit'
require_relative 'forwarding_unit'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class CPU < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      # External interface
      input :clk
      input :rst

      # Instruction memory interface
      output :inst_addr, width: 32
      input :inst_data, width: 32

      # Data memory interface
      output :data_addr, width: 32
      output :data_wdata, width: 32
      input :data_rdata, width: 32
      output :data_we
      output :data_re
      output :data_funct3, width: 3

      # Debug outputs
      output :debug_pc, width: 32
      output :debug_inst, width: 32
      output :debug_x1, width: 32
      output :debug_x2, width: 32
      output :debug_x10, width: 32
      output :debug_x11, width: 32

      # ========================================
      # Internal signals - IF Stage
      # ========================================
      wire :current_pc, width: 32
      wire :next_pc, width: 32
      wire :pc_we

      # ========================================
      # Internal signals - IF/ID Register outputs
      # ========================================
      wire :id_pc, width: 32
      wire :id_inst, width: 32
      wire :id_pc_plus4, width: 32

      # ========================================
      # Internal signals - ID Stage (Decode)
      # ========================================
      wire :id_rs1_addr, width: 5
      wire :id_rs2_addr, width: 5
      wire :id_rd_addr, width: 5
      wire :id_funct3, width: 3
      wire :id_funct7, width: 7
      wire :id_alu_op, width: 4
      wire :id_alu_src
      wire :id_reg_write
      wire :id_mem_read
      wire :id_mem_write
      wire :id_mem_to_reg
      wire :id_branch
      wire :id_jump
      wire :id_jalr
      wire :id_imm, width: 32
      wire :id_rs1_data, width: 32
      wire :id_rs2_data, width: 32

      # ========================================
      # Internal signals - Hazard Unit
      # ========================================
      wire :stall
      wire :flush_if_id
      wire :flush_id_ex

      # ========================================
      # Internal signals - ID/EX Register INPUTS (latch wires)
      # These are set by behavior block to break the callback chain
      # ========================================
      wire :id_ex_pc_in, width: 32
      wire :id_ex_pc_plus4_in, width: 32
      wire :id_ex_rs1_data_in, width: 32
      wire :id_ex_rs2_data_in, width: 32
      wire :id_ex_imm_in, width: 32
      wire :id_ex_rs1_addr_in, width: 5
      wire :id_ex_rs2_addr_in, width: 5
      wire :id_ex_rd_addr_in, width: 5
      wire :id_ex_funct3_in, width: 3
      wire :id_ex_funct7_in, width: 7
      wire :id_ex_alu_op_in, width: 4
      wire :id_ex_alu_src_in
      wire :id_ex_reg_write_in
      wire :id_ex_mem_read_in
      wire :id_ex_mem_write_in
      wire :id_ex_mem_to_reg_in
      wire :id_ex_branch_in
      wire :id_ex_jump_in
      wire :id_ex_jalr_in

      # ========================================
      # Internal signals - ID/EX Register outputs
      # ========================================
      wire :ex_pc, width: 32
      wire :ex_pc_plus4, width: 32
      wire :ex_rs1_data, width: 32
      wire :ex_rs2_data, width: 32
      wire :ex_imm, width: 32
      wire :ex_rs1_addr, width: 5
      wire :ex_rs2_addr, width: 5
      wire :ex_rd_addr, width: 5
      wire :ex_funct3, width: 3
      wire :ex_funct7, width: 7
      wire :ex_alu_op, width: 4
      wire :ex_alu_src
      wire :ex_reg_write
      wire :ex_mem_read
      wire :ex_mem_write
      wire :ex_mem_to_reg
      wire :ex_branch
      wire :ex_jump
      wire :ex_jalr

      # ========================================
      # Internal signals - EX Stage (Execute)
      # ========================================
      wire :forward_a, width: 2
      wire :forward_b, width: 2
      wire :alu_a, width: 32
      wire :alu_b, width: 32
      wire :forwarded_rs2, width: 32
      wire :alu_result, width: 32
      wire :alu_zero
      wire :branch_cond_taken
      wire :branch_target, width: 32
      wire :jalr_target, width: 32
      wire :jump_target, width: 32
      wire :take_branch

      # ========================================
      # Internal signals - EX/MEM Register INPUTS (latch wires)
      # ========================================
      wire :ex_mem_alu_result_in, width: 32
      wire :ex_mem_rs2_data_in, width: 32
      wire :ex_mem_rd_addr_in, width: 5
      wire :ex_mem_pc_plus4_in, width: 32
      wire :ex_mem_funct3_in, width: 3
      wire :ex_mem_reg_write_in
      wire :ex_mem_mem_read_in
      wire :ex_mem_mem_write_in
      wire :ex_mem_mem_to_reg_in
      wire :ex_mem_jump_in

      # ========================================
      # Internal signals - EX/MEM Register outputs
      # ========================================
      wire :mem_alu_result, width: 32
      wire :mem_rs2_data, width: 32
      wire :mem_rd_addr, width: 5
      wire :mem_funct3, width: 3
      wire :mem_reg_write
      wire :mem_mem_read
      wire :mem_mem_write
      wire :mem_mem_to_reg
      wire :mem_jump
      wire :mem_pc_plus4, width: 32

      # ========================================
      # Internal signals - MEM/WB Register INPUTS (latch wires)
      # ========================================
      wire :mem_wb_alu_result_in, width: 32
      wire :mem_wb_mem_data_in, width: 32
      wire :mem_wb_rd_addr_in, width: 5
      wire :mem_wb_pc_plus4_in, width: 32
      wire :mem_wb_reg_write_in
      wire :mem_wb_mem_to_reg_in
      wire :mem_wb_jump_in

      # ========================================
      # Internal signals - MEM/WB Register outputs
      # ========================================
      wire :wb_alu_result, width: 32
      wire :wb_mem_data, width: 32
      wire :wb_rd_addr, width: 5
      wire :wb_pc_plus4, width: 32
      wire :wb_reg_write
      wire :wb_mem_to_reg
      wire :wb_jump

      # ========================================
      # Internal signals - WB Stage
      # ========================================
      wire :wb_data, width: 32

      # ========================================
      # Sub-component instances
      # ORDER MATTERS: Pipeline registers must propagate BEFORE combinational
      # components that depend on their outputs. This ensures decoder/imm_gen
      # see the current instruction, not the previous one.
      # ========================================
      # Pipeline registers first (output instruction/data for this stage)
      instance :pc_reg, ProgramCounter
      instance :if_id, IF_ID_Reg
      instance :id_ex, ID_EX_Reg
      instance :ex_mem, EX_MEM_Reg
      instance :mem_wb, MEM_WB_Reg

      # Combinational components (depend on pipeline register outputs)
      instance :decoder, Decoder
      instance :imm_gen, ImmGen
      instance :regfile, RegisterFile, forwarding: true
      instance :alu, ALU
      # Note: branch_cond logic is computed inline in behavior block
      # to ensure it uses properly forwarded values
      instance :hazard_unit, HazardUnit
      instance :forward_unit, ForwardingUnit

      # ========================================
      # Clock and reset connections
      # ========================================
      port :clk => [[:pc_reg, :clk], [:regfile, :clk], [:if_id, :clk],
                    [:id_ex, :clk], [:ex_mem, :clk], [:mem_wb, :clk]]
      port :rst => [[:pc_reg, :rst], [:regfile, :rst], [:if_id, :rst],
                    [:id_ex, :rst], [:ex_mem, :rst], [:mem_wb, :rst]]

      # ========================================
      # PC connections
      # ========================================
      port :next_pc => [:pc_reg, :pc_next]
      port :pc_we => [:pc_reg, :pc_we]
      port [:pc_reg, :pc] => :current_pc

      # ========================================
      # IF/ID Register connections
      # ========================================
      port :stall => [:if_id, :stall]
      port :flush_if_id => [:if_id, :flush]
      port :current_pc => [:if_id, :pc_in]
      port :inst_data => [:if_id, :inst_in]
      # pc_plus4_in is set via behavior block through if_id_pc_plus4_in wire
      wire :if_id_pc_plus4_in, width: 32
      port :if_id_pc_plus4_in => [:if_id, :pc_plus4_in]
      port [:if_id, :pc_out] => :id_pc
      port [:if_id, :inst_out] => :id_inst
      port [:if_id, :pc_plus4_out] => :id_pc_plus4

      # ========================================
      # Decoder connections
      # ========================================
      port :id_inst => [:decoder, :inst]
      port [:decoder, :rs1] => :id_rs1_addr
      port [:decoder, :rs2] => :id_rs2_addr
      port [:decoder, :rd] => :id_rd_addr
      port [:decoder, :funct3] => :id_funct3
      port [:decoder, :funct7] => :id_funct7
      port [:decoder, :alu_op] => :id_alu_op
      port [:decoder, :alu_src] => :id_alu_src
      port [:decoder, :reg_write] => :id_reg_write
      port [:decoder, :mem_read] => :id_mem_read
      port [:decoder, :mem_write] => :id_mem_write
      port [:decoder, :mem_to_reg] => :id_mem_to_reg
      port [:decoder, :branch] => :id_branch
      port [:decoder, :jump] => :id_jump
      port [:decoder, :jalr] => :id_jalr

      # ========================================
      # Immediate generator connections
      # ========================================
      port :id_inst => [:imm_gen, :inst]
      port [:imm_gen, :imm] => :id_imm

      # ========================================
      # Register file connections
      # ========================================
      port :id_rs1_addr => [:regfile, :rs1_addr]
      port :id_rs2_addr => [:regfile, :rs2_addr]
      port :wb_rd_addr => [:regfile, :rd_addr]
      port :wb_data => [:regfile, :rd_data]
      port :wb_reg_write => [:regfile, :rd_we]
      port [:regfile, :rs1_data] => :id_rs1_data
      port [:regfile, :rs2_data] => :id_rs2_data
      port [:regfile, :debug_x1] => :debug_x1
      port [:regfile, :debug_x2] => :debug_x2
      port [:regfile, :debug_x10] => :debug_x10
      port [:regfile, :debug_x11] => :debug_x11

      # ========================================
      # Hazard unit connections
      # ========================================
      port :id_rs1_addr => [:hazard_unit, :id_rs1_addr]
      port :id_rs2_addr => [:hazard_unit, :id_rs2_addr]
      port :ex_rd_addr => [:hazard_unit, :ex_rd_addr]
      port :ex_mem_read => [:hazard_unit, :ex_mem_read]
      port :mem_rd_addr => [:hazard_unit, :mem_rd_addr]
      port :mem_mem_read => [:hazard_unit, :mem_mem_read]
      port :take_branch => [:hazard_unit, :branch_taken]
      port :ex_jump => [:hazard_unit, :jump]
      port [:hazard_unit, :stall] => :stall
      port [:hazard_unit, :flush_if_id] => :flush_if_id
      port [:hazard_unit, :flush_id_ex] => :flush_id_ex

      # ========================================
      # ID/EX Register connections - USING LATCH WIRES
      # Inputs come from latch wires (set by behavior block)
      # ========================================
      port :flush_id_ex => [:id_ex, :flush]
      port :id_ex_pc_in => [:id_ex, :pc_in]
      port :id_ex_pc_plus4_in => [:id_ex, :pc_plus4_in]
      port :id_ex_rs1_data_in => [:id_ex, :rs1_data_in]
      port :id_ex_rs2_data_in => [:id_ex, :rs2_data_in]
      port :id_ex_imm_in => [:id_ex, :imm_in]
      port :id_ex_rs1_addr_in => [:id_ex, :rs1_addr_in]
      port :id_ex_rs2_addr_in => [:id_ex, :rs2_addr_in]
      port :id_ex_rd_addr_in => [:id_ex, :rd_addr_in]
      port :id_ex_funct3_in => [:id_ex, :funct3_in]
      port :id_ex_funct7_in => [:id_ex, :funct7_in]
      port :id_ex_alu_op_in => [:id_ex, :alu_op_in]
      port :id_ex_alu_src_in => [:id_ex, :alu_src_in]
      port :id_ex_reg_write_in => [:id_ex, :reg_write_in]
      port :id_ex_mem_read_in => [:id_ex, :mem_read_in]
      port :id_ex_mem_write_in => [:id_ex, :mem_write_in]
      port :id_ex_mem_to_reg_in => [:id_ex, :mem_to_reg_in]
      port :id_ex_branch_in => [:id_ex, :branch_in]
      port :id_ex_jump_in => [:id_ex, :jump_in]
      port :id_ex_jalr_in => [:id_ex, :jalr_in]
      # Outputs go to stage wires
      port [:id_ex, :pc_out] => :ex_pc
      port [:id_ex, :pc_plus4_out] => :ex_pc_plus4
      port [:id_ex, :rs1_data_out] => :ex_rs1_data
      port [:id_ex, :rs2_data_out] => :ex_rs2_data
      port [:id_ex, :imm_out] => :ex_imm
      port [:id_ex, :rs1_addr_out] => :ex_rs1_addr
      port [:id_ex, :rs2_addr_out] => :ex_rs2_addr
      port [:id_ex, :rd_addr_out] => :ex_rd_addr
      port [:id_ex, :funct3_out] => :ex_funct3
      port [:id_ex, :funct7_out] => :ex_funct7
      port [:id_ex, :alu_op_out] => :ex_alu_op
      port [:id_ex, :alu_src_out] => :ex_alu_src
      port [:id_ex, :reg_write_out] => :ex_reg_write
      port [:id_ex, :mem_read_out] => :ex_mem_read
      port [:id_ex, :mem_write_out] => :ex_mem_write
      port [:id_ex, :mem_to_reg_out] => :ex_mem_to_reg
      port [:id_ex, :branch_out] => :ex_branch
      port [:id_ex, :jump_out] => :ex_jump
      port [:id_ex, :jalr_out] => :ex_jalr

      # ========================================
      # Forwarding unit connections
      # ========================================
      port :ex_rs1_addr => [:forward_unit, :ex_rs1_addr]
      port :ex_rs2_addr => [:forward_unit, :ex_rs2_addr]
      port :mem_rd_addr => [:forward_unit, :mem_rd_addr]
      port :mem_reg_write => [:forward_unit, :mem_reg_write]
      port :wb_rd_addr => [:forward_unit, :wb_rd_addr]
      port :wb_reg_write => [:forward_unit, :wb_reg_write]
      port [:forward_unit, :forward_a] => :forward_a
      port [:forward_unit, :forward_b] => :forward_b

      # ========================================
      # ALU connections
      # ========================================
      port :alu_a => [:alu, :a]
      port :alu_b => [:alu, :b]
      port :ex_alu_op => [:alu, :op]
      port [:alu, :result] => :alu_result
      port [:alu, :zero] => :alu_zero

      # ========================================
      # Branch condition - computed in behavior block for correct forwarding
      # (The branch_cond subcomponent runs before behavior block, so it
      # would see stale forwarded values. We compute inline instead.)
      # ========================================

      # ========================================
      # EX/MEM Register connections - USING LATCH WIRES
      # ========================================
      port :ex_mem_alu_result_in => [:ex_mem, :alu_result_in]
      port :ex_mem_rs2_data_in => [:ex_mem, :rs2_data_in]
      port :ex_mem_rd_addr_in => [:ex_mem, :rd_addr_in]
      port :ex_mem_pc_plus4_in => [:ex_mem, :pc_plus4_in]
      port :ex_mem_funct3_in => [:ex_mem, :funct3_in]
      port :ex_mem_reg_write_in => [:ex_mem, :reg_write_in]
      port :ex_mem_mem_read_in => [:ex_mem, :mem_read_in]
      port :ex_mem_mem_write_in => [:ex_mem, :mem_write_in]
      port :ex_mem_mem_to_reg_in => [:ex_mem, :mem_to_reg_in]
      port :ex_mem_jump_in => [:ex_mem, :jump_in]
      # Outputs
      port [:ex_mem, :alu_result_out] => :mem_alu_result
      port [:ex_mem, :rs2_data_out] => :mem_rs2_data
      port [:ex_mem, :rd_addr_out] => :mem_rd_addr
      port [:ex_mem, :funct3_out] => :mem_funct3
      port [:ex_mem, :reg_write_out] => :mem_reg_write
      port [:ex_mem, :mem_read_out] => :mem_mem_read
      port [:ex_mem, :mem_write_out] => :mem_mem_write
      port [:ex_mem, :mem_to_reg_out] => :mem_mem_to_reg
      port [:ex_mem, :jump_out] => :mem_jump
      port [:ex_mem, :pc_plus4_out] => :mem_pc_plus4

      # ========================================
      # MEM/WB Register connections - USING LATCH WIRES
      # ========================================
      port :mem_wb_alu_result_in => [:mem_wb, :alu_result_in]
      port :mem_wb_mem_data_in => [:mem_wb, :mem_data_in]
      port :mem_wb_rd_addr_in => [:mem_wb, :rd_addr_in]
      port :mem_wb_pc_plus4_in => [:mem_wb, :pc_plus4_in]
      port :mem_wb_reg_write_in => [:mem_wb, :reg_write_in]
      port :mem_wb_mem_to_reg_in => [:mem_wb, :mem_to_reg_in]
      port :mem_wb_jump_in => [:mem_wb, :jump_in]
      # Outputs
      port [:mem_wb, :alu_result_out] => :wb_alu_result
      port [:mem_wb, :mem_data_out] => :wb_mem_data
      port [:mem_wb, :rd_addr_out] => :wb_rd_addr
      port [:mem_wb, :pc_plus4_out] => :wb_pc_plus4
      port [:mem_wb, :reg_write_out] => :wb_reg_write
      port [:mem_wb, :mem_to_reg_out] => :wb_mem_to_reg
      port [:mem_wb, :jump_out] => :wb_jump
      port [:mem_wb, :wb_data_out] => :wb_data

      # ========================================
      # Combinational control logic
      # Two-phase propagation ensures correct pipeline timing:
      # 1. Combinational components propagate first
      # 2. All sequential components sample inputs simultaneously
      # 3. All sequential components update outputs
      # ========================================
      behavior do
        # -----------------------------------------
        # IF Stage: PC calculation and IF/ID inputs
        # -----------------------------------------
        pc_plus4_if = local(:pc_plus4_if, current_pc + lit(4, width: 32), width: 32)
        if_id_pc_plus4_in <= pc_plus4_if

        # Next PC: branch/jump target or sequential
        next_pc <= mux(take_branch, jump_target,
                    mux(stall, current_pc, pc_plus4_if))

        # PC write enable: disabled on stall
        pc_we <= ~stall

        # -----------------------------------------
        # ID/EX Register inputs (latch wires)
        # These values are captured BEFORE sequential propagation
        # -----------------------------------------
        id_ex_pc_in <= id_pc
        id_ex_pc_plus4_in <= id_pc_plus4
        id_ex_rs1_data_in <= id_rs1_data
        id_ex_rs2_data_in <= id_rs2_data
        id_ex_imm_in <= id_imm
        id_ex_rs1_addr_in <= id_rs1_addr
        id_ex_rs2_addr_in <= id_rs2_addr
        id_ex_rd_addr_in <= id_rd_addr
        id_ex_funct3_in <= id_funct3
        id_ex_funct7_in <= id_funct7
        id_ex_alu_op_in <= id_alu_op
        id_ex_alu_src_in <= id_alu_src
        id_ex_reg_write_in <= id_reg_write
        id_ex_mem_read_in <= id_mem_read
        id_ex_mem_write_in <= id_mem_write
        id_ex_mem_to_reg_in <= id_mem_to_reg
        id_ex_branch_in <= id_branch
        id_ex_jump_in <= id_jump
        id_ex_jalr_in <= id_jalr

        # -----------------------------------------
        # EX Stage: Forwarding muxes
        # -----------------------------------------
        # Forward A (rs1) - priority: EX/MEM > MEM/WB > register file
        alu_a <= mux(forward_a == lit(ForwardSel::EX_MEM, width: 2), mem_alu_result,
                  mux(forward_a == lit(ForwardSel::MEM_WB, width: 2), wb_data,
                    ex_rs1_data))

        # Forward B (rs2) for store and branch comparison
        forwarded_rs2 <= mux(forward_b == lit(ForwardSel::EX_MEM, width: 2), mem_alu_result,
                          mux(forward_b == lit(ForwardSel::MEM_WB, width: 2), wb_data,
                            ex_rs2_data))

        # ALU B input: immediate or forwarded rs2
        alu_b <= mux(ex_alu_src, ex_imm, forwarded_rs2)

        # -----------------------------------------
        # EX Stage: Branch condition evaluation (inline)
        # Uses forwarded values alu_a and forwarded_rs2
        # -----------------------------------------
        branch_eq = alu_a == forwarded_rs2

        # Signed comparison: check signs, then magnitudes
        rs1_sign = alu_a[31]
        rs2_sign = forwarded_rs2[31]
        # Signed less than: if signs differ, negative is less; else unsigned compare
        branch_slt = local(:branch_slt,
          mux(rs1_sign != rs2_sign,
            rs1_sign,  # Different signs: rs1 < rs2 if rs1 is negative
            alu_a < forwarded_rs2  # Same signs: unsigned compare
          ), width: 1)

        # Unsigned less than
        branch_ult = alu_a < forwarded_rs2

        # Branch condition based on funct3
        # BEQ=0, BNE=1, BLT=4, BGE=5, BLTU=6, BGEU=7
        branch_cond_taken <= case_select(ex_funct3, {
          Funct3::BEQ  => branch_eq,           # Equal
          Funct3::BNE  => ~branch_eq,          # Not equal
          Funct3::BLT  => branch_slt,          # Less than (signed)
          Funct3::BGE  => ~branch_slt,         # Greater or equal (signed)
          Funct3::BLTU => branch_ult,          # Less than (unsigned)
          Funct3::BGEU => ~branch_ult          # Greater or equal (unsigned)
        }, default: lit(0, width: 1))

        # -----------------------------------------
        # EX Stage: Branch/Jump target calculation
        # -----------------------------------------
        branch_target <= ex_pc + ex_imm
        jalr_target <= (alu_a + ex_imm) & lit(0xFFFFFFFE, width: 32)
        jump_target <= mux(ex_jalr, jalr_target, branch_target)

        # Branch taken = branch instruction AND condition met
        take_branch <= (branch_cond_taken & ex_branch) | ex_jump

        # -----------------------------------------
        # EX/MEM Register inputs (latch wires)
        # -----------------------------------------
        ex_mem_alu_result_in <= alu_result
        ex_mem_rs2_data_in <= forwarded_rs2
        ex_mem_rd_addr_in <= ex_rd_addr
        ex_mem_pc_plus4_in <= ex_pc_plus4
        ex_mem_funct3_in <= ex_funct3
        ex_mem_reg_write_in <= ex_reg_write
        ex_mem_mem_read_in <= ex_mem_read
        ex_mem_mem_write_in <= ex_mem_write
        ex_mem_mem_to_reg_in <= ex_mem_to_reg
        ex_mem_jump_in <= ex_jump

        # -----------------------------------------
        # MEM Stage: Memory interface outputs
        # -----------------------------------------
        data_addr <= mem_alu_result
        data_wdata <= mem_rs2_data
        data_we <= mem_mem_write
        data_re <= mem_mem_read
        data_funct3 <= mem_funct3

        # -----------------------------------------
        # MEM/WB Register inputs (latch wires)
        # -----------------------------------------
        mem_wb_alu_result_in <= mem_alu_result
        mem_wb_mem_data_in <= data_rdata
        mem_wb_rd_addr_in <= mem_rd_addr
        mem_wb_pc_plus4_in <= mem_pc_plus4
        mem_wb_reg_write_in <= mem_reg_write
        mem_wb_mem_to_reg_in <= mem_mem_to_reg
        mem_wb_jump_in <= mem_jump

        # -----------------------------------------
        # Output connections
        # -----------------------------------------
        inst_addr <= current_pc
        debug_pc <= current_pc
        debug_inst <= id_inst
      end

      # ========================================
      # Helper methods for testing
      # ========================================

      def read_reg(index)
        @regfile.read_reg(index)
      end

      def write_reg(index, value)
        @regfile.write_reg(index, value)
      end

      def self.verilog_module_name
        'riscv_pipelined_cpu'
      end

      def self.to_verilog(top_name: nil)
        name = top_name || verilog_module_name
        RHDL::Export::Verilog.generate(to_ir(top_name: name))
      end
        end
      end
    end
  end
end

# Load the harness after CPU is defined
require_relative 'harness'
