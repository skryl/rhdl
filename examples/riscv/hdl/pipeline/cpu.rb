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
require_relative '../compressed_decoder'
require_relative '../program_counter'
require_relative '../register_file'
require_relative '../fp_register_file'
require_relative '../vector_register_file'
require_relative '../vector_csr_file'
require_relative '../csr_file'
require_relative '../atomic_reservation'
require_relative '../priv_mode_reg'
require_relative '../sv32_tlb'
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
      input :irq_software
      input :irq_timer
      input :irq_external

      # Instruction memory interface
      output :inst_addr, width: 32
      input :inst_data, width: 32
      output :inst_ptw_addr1, width: 32
      output :inst_ptw_addr0, width: 32
      input :inst_ptw_pte1, width: 32
      input :inst_ptw_pte0, width: 32

      # Data memory interface
      output :data_addr, width: 32
      output :data_wdata, width: 32
      input :data_rdata, width: 32
      output :data_we
      output :data_re
      output :data_funct3, width: 3
      output :data_ptw_addr1, width: 32
      output :data_ptw_addr0, width: 32
      input :data_ptw_pte1, width: 32
      input :data_ptw_pte0, width: 32

      # Debug outputs
      output :debug_pc, width: 32
      output :debug_inst, width: 32
      output :debug_x1, width: 32
      output :debug_x2, width: 32
      output :debug_x10, width: 32
      output :debug_x11, width: 32
      input :debug_reg_addr, width: 5
      output :debug_reg_data, width: 32

      # ========================================
      # Internal signals - IF Stage
      # ========================================
      wire :current_pc, width: 32
      wire :next_pc, width: 32
      wire :pc_we
      wire :if_inst_decoded, width: 32
      wire :if_inst_pc_step, width: 32
      wire :if_id_inst_in, width: 32

      # ========================================
      # Internal signals - IF/ID Register outputs
      # ========================================
      wire :id_pc, width: 32
      wire :id_inst, width: 32
      wire :id_pc_plus4, width: 32
      wire :id_inst_page_fault

      # ========================================
      # Internal signals - ID Stage (Decode)
      # ========================================
      wire :id_rs1_addr, width: 5
      wire :id_rs2_addr, width: 5
      wire :id_rs3_addr, width: 5
      wire :id_rd_addr, width: 5
      wire :id_opcode, width: 7
      wire :id_funct3, width: 3
      wire :id_funct7, width: 7
      wire :id_alu_op, width: 6
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
      wire :id_rs3_data, width: 32
      wire :id_fp_rs1_data, width: 32
      wire :id_fp_rs2_data, width: 32
      wire :id_fp_rs3_data, width: 32
      wire :id_fp_rs1_data64, width: 64
      wire :id_fp_rs2_data64, width: 64
      wire :id_fp_rs3_data64, width: 64
      wire :regfile_forwarding_en

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
      wire :id_ex_rs2_hi_data_in, width: 32
      wire :id_ex_rs3_data_in, width: 32
      wire :id_ex_rs3_hi_data_in, width: 32
      wire :id_ex_rd_src_data_in, width: 32
      wire :id_ex_imm_in, width: 32
      wire :id_ex_rs1_addr_in, width: 5
      wire :id_ex_rs2_addr_in, width: 5
      wire :id_ex_rd_addr_in, width: 5
      wire :id_ex_opcode_in, width: 7
      wire :id_ex_funct3_in, width: 3
      wire :id_ex_funct7_in, width: 7
      wire :id_ex_alu_op_in, width: 6
      wire :id_ex_alu_src_in
      wire :id_ex_reg_write_in
      wire :id_ex_mem_read_in
      wire :id_ex_mem_write_in
      wire :id_ex_mem_to_reg_in
      wire :id_ex_branch_in
      wire :id_ex_jump_in
      wire :id_ex_jalr_in
      wire :id_ex_inst_page_fault_in

      # ========================================
      # Internal signals - ID/EX Register outputs
      # ========================================
      wire :ex_pc, width: 32
      wire :ex_pc_plus4, width: 32
      wire :ex_rs1_data, width: 32
      wire :ex_rs2_data, width: 32
      wire :ex_rs2_hi_data, width: 32
      wire :ex_rs3_data, width: 32
      wire :ex_rs3_hi_data, width: 32
      wire :ex_rd_src_data, width: 32
      wire :ex_imm, width: 32
      wire :ex_rs1_addr, width: 5
      wire :ex_rs2_addr, width: 5
      wire :ex_rd_addr, width: 5
      wire :ex_opcode, width: 7
      wire :ex_funct3, width: 3
      wire :ex_funct7, width: 7
      wire :ex_alu_op, width: 6
      wire :ex_alu_src
      wire :ex_reg_write
      wire :ex_mem_read
      wire :ex_mem_write
      wire :ex_mem_to_reg
      wire :ex_branch
      wire :ex_jump
      wire :ex_jalr
      wire :ex_inst_page_fault
      wire :ex_v_rs1_lane0, width: 32
      wire :ex_v_rs1_lane1, width: 32
      wire :ex_v_rs1_lane2, width: 32
      wire :ex_v_rs1_lane3, width: 32
      wire :ex_v_rs2_lane0, width: 32
      wire :ex_v_rs2_lane1, width: 32
      wire :ex_v_rs2_lane2, width: 32
      wire :ex_v_rs2_lane3, width: 32
      wire :ex_v_rd_lane0, width: 32
      wire :ex_v_rd_lane1, width: 32
      wire :ex_v_rd_lane2, width: 32
      wire :ex_v_rd_lane3, width: 32
      wire :ex_v_rd_lane0_in, width: 32
      wire :ex_v_rd_lane1_in, width: 32
      wire :ex_v_rd_lane2_in, width: 32
      wire :ex_v_rd_lane3_in, width: 32
      wire :ex_v_rd_we
      wire :vec_vl, width: 32
      wire :vec_vtype, width: 32
      wire :vec_vl_write_data, width: 32
      wire :vec_vtype_write_data, width: 32
      wire :vec_vl_write_we
      wire :vec_vtype_write_we

      # ========================================
      # Internal signals - EX Stage (Execute)
      # ========================================
      wire :forward_a, width: 2
      wire :forward_b, width: 2
      wire :forwarded_rs1, width: 32
      wire :alu_a, width: 32
      wire :alu_b, width: 32
      wire :forwarded_rs2, width: 32
      wire :forwarded_rd_src, width: 32
      wire :alu_result, width: 32
      wire :ex_result, width: 32
      wire :alu_zero
      wire :branch_cond_taken
      wire :branch_target, width: 32
      wire :jalr_target, width: 32
      wire :jump_target, width: 32
      wire :trap_target, width: 32
      wire :mret_target, width: 32
      wire :control_target, width: 32
      wire :take_branch
      wire :csr_read_addr, width: 12
      wire :csr_read_addr2, width: 12
      wire :csr_read_addr3, width: 12
      wire :csr_read_addr4, width: 12
      wire :csr_read_addr5, width: 12
      wire :csr_read_addr6, width: 12
      wire :csr_read_addr7, width: 12
      wire :csr_read_addr8, width: 12
      wire :csr_read_addr9, width: 12
      wire :csr_read_addr10, width: 12
      wire :csr_read_addr11, width: 12
      wire :csr_read_addr12, width: 12
      wire :csr_read_addr13, width: 12
      wire :csr_write_addr, width: 12
      wire :csr_read_data, width: 32
      wire :csr_read_data2, width: 32
      wire :csr_read_data3, width: 32
      wire :csr_read_data4, width: 32
      wire :csr_read_data5, width: 32
      wire :csr_read_data6, width: 32
      wire :csr_read_data7, width: 32
      wire :csr_read_data8, width: 32
      wire :csr_read_data9, width: 32
      wire :csr_read_data10, width: 32
      wire :csr_read_data11, width: 32
      wire :csr_read_data12, width: 32
      wire :csr_read_data13, width: 32
      wire :csr_write_data, width: 32
      wire :csr_write_we
      wire :csr_write_addr2, width: 12
      wire :csr_write_data2, width: 32
      wire :csr_write_we2
      wire :csr_write_addr3, width: 12
      wire :csr_write_data3, width: 32
      wire :csr_write_we3
      wire :csr_write_addr4, width: 12
      wire :csr_write_data4, width: 32
      wire :csr_write_we4

      # ========================================
      # Internal signals - EX/MEM Register INPUTS (latch wires)
      # ========================================
      wire :ex_mem_alu_result_in, width: 32
      wire :ex_mem_rs2_data_in, width: 32
      wire :ex_mem_rd_src_data_in, width: 32
      wire :ex_mem_rd_addr_in, width: 5
      wire :ex_mem_pc_plus4_in, width: 32
      wire :ex_mem_funct3_in, width: 3
      wire :ex_mem_funct7_in, width: 7
      wire :ex_mem_opcode_in, width: 7
      wire :ex_mem_rs2_addr_in, width: 5
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
      wire :mem_rd_src_data, width: 32
      wire :mem_rd_addr, width: 5
      wire :mem_funct3, width: 3
      wire :mem_funct7, width: 7
      wire :mem_opcode, width: 7
      wire :mem_rs2_addr, width: 5
      wire :mem_reg_write
      wire :mem_mem_read
      wire :mem_mem_write
      wire :mem_mem_to_reg
      wire :mem_jump
      wire :mem_pc_plus4, width: 32
      wire :mem_forward_data, width: 32
      wire :reservation_set
      wire :reservation_clear
      wire :reservation_set_addr, width: 32
      wire :reservation_valid
      wire :reservation_addr, width: 32
      wire :priv_mode_next, width: 2
      wire :priv_mode_we
      wire :priv_mode, width: 2
      wire :tlb_flush_all
      wire :inst_tlb_lookup_en
      wire :inst_tlb_lookup_vpn, width: 20
      wire :inst_tlb_lookup_root, width: 20
      wire :inst_tlb_hit
      wire :inst_tlb_ppn, width: 20
      wire :inst_tlb_perm_r
      wire :inst_tlb_perm_w
      wire :inst_tlb_perm_x
      wire :inst_tlb_perm_u
      wire :inst_tlb_fill_en
      wire :inst_tlb_fill_vpn, width: 20
      wire :inst_tlb_fill_root, width: 20
      wire :inst_tlb_fill_ppn, width: 20
      wire :inst_tlb_fill_perm_r
      wire :inst_tlb_fill_perm_w
      wire :inst_tlb_fill_perm_x
      wire :inst_tlb_fill_perm_u
      wire :data_tlb_lookup_en
      wire :data_tlb_lookup_vpn, width: 20
      wire :data_tlb_lookup_root, width: 20
      wire :data_tlb_hit
      wire :data_tlb_ppn, width: 20
      wire :data_tlb_perm_r
      wire :data_tlb_perm_w
      wire :data_tlb_perm_x
      wire :data_tlb_perm_u
      wire :data_tlb_fill_en
      wire :data_tlb_fill_vpn, width: 20
      wire :data_tlb_fill_root, width: 20
      wire :data_tlb_fill_ppn, width: 20
      wire :data_tlb_fill_perm_r
      wire :data_tlb_fill_perm_w
      wire :data_tlb_fill_perm_x
      wire :data_tlb_fill_perm_u

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
      wire :fp_rd_data, width: 32
      wire :fp_rd_data64, width: 64
      wire :fp_reg_write
      wire :fp_reg_write64

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
      instance :c_decoder, CompressedDecoder
      instance :decoder, Decoder
      instance :imm_gen, ImmGen
      instance :regfile, RegisterFile, forwarding: true
      instance :fp_regfile, FPRegisterFile
      instance :vregfile, VectorRegisterFile
      instance :vec_csrfile, VectorCSRFile
      instance :csrfile, CSRFile
      instance :reservation, AtomicReservation
      instance :priv_mode_reg, PrivModeReg
      instance :itlb, Sv32Tlb
      instance :dtlb, Sv32Tlb
      instance :alu, ALU
      # Note: branch_cond logic is computed inline in behavior block
      # to ensure it uses properly forwarded values
      instance :hazard_unit, HazardUnit
      instance :forward_unit, ForwardingUnit

      # ========================================
      # Clock and reset connections
      # ========================================
      port :clk => [[:pc_reg, :clk], [:regfile, :clk], [:fp_regfile, :clk], [:vregfile, :clk], [:vec_csrfile, :clk],
                    [:csrfile, :clk], [:if_id, :clk],
                    [:id_ex, :clk], [:ex_mem, :clk], [:mem_wb, :clk], [:reservation, :clk], [:priv_mode_reg, :clk],
                    [:itlb, :clk], [:dtlb, :clk]]
      port :rst => [[:pc_reg, :rst], [:regfile, :rst], [:fp_regfile, :rst], [:vregfile, :rst], [:vec_csrfile, :rst],
                    [:csrfile, :rst], [:if_id, :rst],
                    [:id_ex, :rst], [:ex_mem, :rst], [:mem_wb, :rst], [:reservation, :rst], [:priv_mode_reg, :rst],
                    [:itlb, :rst], [:dtlb, :rst]]

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
      port :if_id_inst_in => [:if_id, :inst_in]
      # pc_plus4_in is set via behavior block through if_id_pc_plus4_in wire
      wire :if_id_pc_plus4_in, width: 32
      wire :if_id_inst_page_fault_in
      port :if_id_pc_plus4_in => [:if_id, :pc_plus4_in]
      port :if_id_inst_page_fault_in => [:if_id, :inst_page_fault_in]
      port [:if_id, :pc_out] => :id_pc
      port [:if_id, :inst_out] => :id_inst
      port [:if_id, :pc_plus4_out] => :id_pc_plus4
      port [:if_id, :inst_page_fault_out] => :id_inst_page_fault

      # ========================================
      # Compressed decoder connections (IF-stage predecode)
      # ========================================
      port :inst_data => [:c_decoder, :inst_word]
      port [:c_decoder, :inst_out] => :if_inst_decoded
      port [:c_decoder, :pc_step] => :if_inst_pc_step

      # ========================================
      # Decoder connections
      # ========================================
      port :id_inst => [:decoder, :inst]
      port [:decoder, :rs1] => :id_rs1_addr
      port [:decoder, :rs2] => :id_rs2_addr
      port [:decoder, :rd] => :id_rd_addr
      port [:decoder, :opcode] => :id_opcode
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
      port :id_rd_addr => [:regfile, :rs3_addr]
      port :wb_rd_addr => [:regfile, :rd_addr]
      port :wb_data => [:regfile, :rd_data]
      port :wb_reg_write => [:regfile, :rd_we]
      port :regfile_forwarding_en => [:regfile, :forwarding_en]
      port :debug_reg_addr => [:regfile, :debug_raddr]
      port [:regfile, :rs1_data] => :id_rs1_data
      port [:regfile, :rs2_data] => :id_rs2_data
      port [:regfile, :rs3_data] => :id_rs3_data
      port [:regfile, :debug_x1] => :debug_x1
      port [:regfile, :debug_x2] => :debug_x2
      port [:regfile, :debug_x10] => :debug_x10
      port [:regfile, :debug_x11] => :debug_x11
      port [:regfile, :debug_rdata] => :debug_reg_data

      # ========================================
      # FP register file connections
      # ========================================
      port :id_rs1_addr => [:fp_regfile, :rs1_addr]
      port :id_rs2_addr => [:fp_regfile, :rs2_addr]
      port :id_rs3_addr => [:fp_regfile, :rs3_addr]
      port :mem_rd_addr => [:fp_regfile, :rd_addr]
      port :fp_rd_data => [:fp_regfile, :rd_data]
      port :fp_reg_write => [:fp_regfile, :rd_we]
      port :fp_rd_data64 => [:fp_regfile, :rd_data64]
      port :fp_reg_write64 => [:fp_regfile, :rd_we64]
      port [:fp_regfile, :rs1_data] => :id_fp_rs1_data
      port [:fp_regfile, :rs2_data] => :id_fp_rs2_data
      port [:fp_regfile, :rs3_data] => :id_fp_rs3_data
      port [:fp_regfile, :rs1_data64] => :id_fp_rs1_data64
      port [:fp_regfile, :rs2_data64] => :id_fp_rs2_data64
      port [:fp_regfile, :rs3_data64] => :id_fp_rs3_data64

      # ========================================
      # Vector register file connections
      # ========================================
      port :ex_rs1_addr => [:vregfile, :rs1_addr]
      port :ex_rs2_addr => [:vregfile, :rs2_addr]
      port :ex_rd_addr => [:vregfile, :rd_addr_read]
      port :ex_rd_addr => [:vregfile, :rd_addr]
      port :ex_v_rd_lane0_in => [:vregfile, :rd_lane0_in]
      port :ex_v_rd_lane1_in => [:vregfile, :rd_lane1_in]
      port :ex_v_rd_lane2_in => [:vregfile, :rd_lane2_in]
      port :ex_v_rd_lane3_in => [:vregfile, :rd_lane3_in]
      port :ex_v_rd_we => [:vregfile, :rd_we]
      port [:vregfile, :rs1_lane0] => :ex_v_rs1_lane0
      port [:vregfile, :rs1_lane1] => :ex_v_rs1_lane1
      port [:vregfile, :rs1_lane2] => :ex_v_rs1_lane2
      port [:vregfile, :rs1_lane3] => :ex_v_rs1_lane3
      port [:vregfile, :rs2_lane0] => :ex_v_rs2_lane0
      port [:vregfile, :rs2_lane1] => :ex_v_rs2_lane1
      port [:vregfile, :rs2_lane2] => :ex_v_rs2_lane2
      port [:vregfile, :rs2_lane3] => :ex_v_rs2_lane3
      port [:vregfile, :rd_lane0] => :ex_v_rd_lane0
      port [:vregfile, :rd_lane1] => :ex_v_rd_lane1
      port [:vregfile, :rd_lane2] => :ex_v_rd_lane2
      port [:vregfile, :rd_lane3] => :ex_v_rd_lane3

      # ========================================
      # Vector control CSR state
      # ========================================
      port :vec_vl_write_data => [:vec_csrfile, :vl_write_data]
      port :vec_vl_write_we => [:vec_csrfile, :vl_write_we]
      port :vec_vtype_write_data => [:vec_csrfile, :vtype_write_data]
      port :vec_vtype_write_we => [:vec_csrfile, :vtype_write_we]
      port [:vec_csrfile, :vl] => :vec_vl
      port [:vec_csrfile, :vtype] => :vec_vtype

      # ========================================
      # CSR file connections
      # ========================================
      port :csr_read_addr => [:csrfile, :read_addr]
      port :csr_read_addr2 => [:csrfile, :read_addr2]
      port :csr_read_addr3 => [:csrfile, :read_addr3]
      port :csr_read_addr4 => [:csrfile, :read_addr4]
      port :csr_read_addr5 => [:csrfile, :read_addr5]
      port :csr_read_addr6 => [:csrfile, :read_addr6]
      port :csr_read_addr7 => [:csrfile, :read_addr7]
      port :csr_read_addr8 => [:csrfile, :read_addr8]
      port :csr_read_addr9 => [:csrfile, :read_addr9]
      port :csr_read_addr10 => [:csrfile, :read_addr10]
      port :csr_read_addr11 => [:csrfile, :read_addr11]
      port :csr_read_addr12 => [:csrfile, :read_addr12]
      port :csr_read_addr13 => [:csrfile, :read_addr13]
      port [:csrfile, :read_data] => :csr_read_data
      port [:csrfile, :read_data2] => :csr_read_data2
      port [:csrfile, :read_data3] => :csr_read_data3
      port [:csrfile, :read_data4] => :csr_read_data4
      port [:csrfile, :read_data5] => :csr_read_data5
      port [:csrfile, :read_data6] => :csr_read_data6
      port [:csrfile, :read_data7] => :csr_read_data7
      port [:csrfile, :read_data8] => :csr_read_data8
      port [:csrfile, :read_data9] => :csr_read_data9
      port [:csrfile, :read_data10] => :csr_read_data10
      port [:csrfile, :read_data11] => :csr_read_data11
      port [:csrfile, :read_data12] => :csr_read_data12
      port [:csrfile, :read_data13] => :csr_read_data13
      port :csr_write_addr => [:csrfile, :write_addr]
      port :csr_write_data => [:csrfile, :write_data]
      port :csr_write_we => [:csrfile, :write_we]
      port :csr_write_addr2 => [:csrfile, :write_addr2]
      port :csr_write_data2 => [:csrfile, :write_data2]
      port :csr_write_we2 => [:csrfile, :write_we2]
      port :csr_write_addr3 => [:csrfile, :write_addr3]
      port :csr_write_data3 => [:csrfile, :write_data3]
      port :csr_write_we3 => [:csrfile, :write_we3]
      port :csr_write_addr4 => [:csrfile, :write_addr4]
      port :csr_write_data4 => [:csrfile, :write_data4]
      port :csr_write_we4 => [:csrfile, :write_we4]

      # Atomic reservation state
      port :reservation_set => [:reservation, :set]
      port :reservation_clear => [:reservation, :clear]
      port :reservation_set_addr => [:reservation, :set_addr]
      port [:reservation, :valid] => :reservation_valid
      port [:reservation, :addr] => :reservation_addr
      port :priv_mode_next => [:priv_mode_reg, :mode_next]
      port :priv_mode_we => [:priv_mode_reg, :mode_we]
      port [:priv_mode_reg, :mode] => :priv_mode

      # Sv32 TLBs
      port :inst_tlb_lookup_en => [:itlb, :lookup_en]
      port :inst_tlb_lookup_vpn => [:itlb, :lookup_vpn]
      port :inst_tlb_lookup_root => [:itlb, :lookup_root_ppn]
      port :inst_tlb_fill_en => [:itlb, :fill_en]
      port :inst_tlb_fill_vpn => [:itlb, :fill_vpn]
      port :inst_tlb_fill_root => [:itlb, :fill_root_ppn]
      port :inst_tlb_fill_ppn => [:itlb, :fill_ppn]
      port :inst_tlb_fill_perm_r => [:itlb, :fill_perm_r]
      port :inst_tlb_fill_perm_w => [:itlb, :fill_perm_w]
      port :inst_tlb_fill_perm_x => [:itlb, :fill_perm_x]
      port :inst_tlb_fill_perm_u => [:itlb, :fill_perm_u]
      port :tlb_flush_all => [:itlb, :flush]
      port [:itlb, :hit] => :inst_tlb_hit
      port [:itlb, :ppn] => :inst_tlb_ppn
      port [:itlb, :perm_r] => :inst_tlb_perm_r
      port [:itlb, :perm_w] => :inst_tlb_perm_w
      port [:itlb, :perm_x] => :inst_tlb_perm_x
      port [:itlb, :perm_u] => :inst_tlb_perm_u

      port :data_tlb_lookup_en => [:dtlb, :lookup_en]
      port :data_tlb_lookup_vpn => [:dtlb, :lookup_vpn]
      port :data_tlb_lookup_root => [:dtlb, :lookup_root_ppn]
      port :data_tlb_fill_en => [:dtlb, :fill_en]
      port :data_tlb_fill_vpn => [:dtlb, :fill_vpn]
      port :data_tlb_fill_root => [:dtlb, :fill_root_ppn]
      port :data_tlb_fill_ppn => [:dtlb, :fill_ppn]
      port :data_tlb_fill_perm_r => [:dtlb, :fill_perm_r]
      port :data_tlb_fill_perm_w => [:dtlb, :fill_perm_w]
      port :data_tlb_fill_perm_x => [:dtlb, :fill_perm_x]
      port :data_tlb_fill_perm_u => [:dtlb, :fill_perm_u]
      port :tlb_flush_all => [:dtlb, :flush]
      port [:dtlb, :hit] => :data_tlb_hit
      port [:dtlb, :ppn] => :data_tlb_ppn
      port [:dtlb, :perm_r] => :data_tlb_perm_r
      port [:dtlb, :perm_w] => :data_tlb_perm_w
      port [:dtlb, :perm_x] => :data_tlb_perm_x
      port [:dtlb, :perm_u] => :data_tlb_perm_u

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
      port :id_ex_rs2_hi_data_in => [:id_ex, :rs2_hi_data_in]
      port :id_ex_rs3_data_in => [:id_ex, :rs3_data_in]
      port :id_ex_rs3_hi_data_in => [:id_ex, :rs3_hi_data_in]
      port :id_ex_rd_src_data_in => [:id_ex, :rd_src_data_in]
      port :id_ex_imm_in => [:id_ex, :imm_in]
      port :id_ex_rs1_addr_in => [:id_ex, :rs1_addr_in]
      port :id_ex_rs2_addr_in => [:id_ex, :rs2_addr_in]
      port :id_ex_rd_addr_in => [:id_ex, :rd_addr_in]
      port :id_ex_opcode_in => [:id_ex, :opcode_in]
      port :id_ex_inst_page_fault_in => [:id_ex, :inst_page_fault_in]
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
      port [:id_ex, :rs2_hi_data_out] => :ex_rs2_hi_data
      port [:id_ex, :rs3_data_out] => :ex_rs3_data
      port [:id_ex, :rs3_hi_data_out] => :ex_rs3_hi_data
      port [:id_ex, :rd_src_data_out] => :ex_rd_src_data
      port [:id_ex, :imm_out] => :ex_imm
      port [:id_ex, :rs1_addr_out] => :ex_rs1_addr
      port [:id_ex, :rs2_addr_out] => :ex_rs2_addr
      port [:id_ex, :rd_addr_out] => :ex_rd_addr
      port [:id_ex, :opcode_out] => :ex_opcode
      port [:id_ex, :inst_page_fault_out] => :ex_inst_page_fault
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
      port :ex_mem_rd_src_data_in => [:ex_mem, :rd_src_data_in]
      port :ex_mem_rd_addr_in => [:ex_mem, :rd_addr_in]
      port :ex_mem_pc_plus4_in => [:ex_mem, :pc_plus4_in]
      port :ex_mem_funct3_in => [:ex_mem, :funct3_in]
      port :ex_mem_funct7_in => [:ex_mem, :funct7_in]
      port :ex_mem_opcode_in => [:ex_mem, :opcode_in]
      port :ex_mem_rs2_addr_in => [:ex_mem, :rs2_addr_in]
      port :ex_mem_reg_write_in => [:ex_mem, :reg_write_in]
      port :ex_mem_mem_read_in => [:ex_mem, :mem_read_in]
      port :ex_mem_mem_write_in => [:ex_mem, :mem_write_in]
      port :ex_mem_mem_to_reg_in => [:ex_mem, :mem_to_reg_in]
      port :ex_mem_jump_in => [:ex_mem, :jump_in]
      # Outputs
      port [:ex_mem, :alu_result_out] => :mem_alu_result
      port [:ex_mem, :rs2_data_out] => :mem_rs2_data
      port [:ex_mem, :rd_src_data_out] => :mem_rd_src_data
      port [:ex_mem, :rd_addr_out] => :mem_rd_addr
      port [:ex_mem, :funct3_out] => :mem_funct3
      port [:ex_mem, :funct7_out] => :mem_funct7
      port [:ex_mem, :opcode_out] => :mem_opcode
      port [:ex_mem, :rs2_addr_out] => :mem_rs2_addr
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
        regfile_forwarding_en <= lit(1, width: 1)
        pc_plus4_if = local(:pc_plus4_if, current_pc + if_inst_pc_step, width: 32)
        if_id_inst_in <= if_inst_decoded
        if_id_pc_plus4_in <= pc_plus4_if

        # Sv32 instruction translation for IF fetch address.
        if_satp_mode_sv32 = local(:if_satp_mode_sv32, csr_read_data8[31], width: 1)
        if_priv_is_u = local(:if_priv_is_u, priv_mode == lit(PrivMode::USER, width: 2), width: 1)
        if_priv_is_s = local(:if_priv_is_s, priv_mode == lit(PrivMode::SUPERVISOR, width: 2), width: 1)
        if_priv_is_m = local(:if_priv_is_m, priv_mode == lit(PrivMode::MACHINE, width: 2), width: 1)
        if_satp_translate = local(:if_satp_translate, if_satp_mode_sv32 & ~if_priv_is_m, width: 1)
        if_satp_root_ppn = csr_read_data8[19..0]
        if_satp_root_base = local(:if_satp_root_base, cat(if_satp_root_ppn, lit(0, width: 12)), width: 32)
        if_vpn = current_pc[31..12]
        if_vpn1 = current_pc[31..22]
        if_vpn0 = current_pc[21..12]
        if_page_off = current_pc[11..0]
        inst_tlb_lookup_en <= if_satp_translate
        inst_tlb_lookup_vpn <= if_vpn
        inst_tlb_lookup_root <= if_satp_root_ppn
        if_ptw_addr1_calc = local(:if_ptw_addr1_calc,
                                  if_satp_root_base + cat(lit(0, width: 20), if_vpn1, lit(0, width: 2)),
                                  width: 32)
        if_l0_base = local(:if_l0_base, cat(inst_ptw_pte1[29..10], lit(0, width: 12)), width: 32)
        if_ptw_addr0_calc = local(:if_ptw_addr0_calc,
                                  if_l0_base + cat(lit(0, width: 20), if_vpn0, lit(0, width: 2)),
                                  width: 32)
        if_pte1_leaf = local(:if_pte1_leaf,
                             inst_ptw_pte1[0] & (inst_ptw_pte1[1] | inst_ptw_pte1[3]),
                             width: 1)
        if_pte1_next = local(:if_pte1_next,
                             inst_ptw_pte1[0] & ~(inst_ptw_pte1[1] | inst_ptw_pte1[3]),
                             width: 1)
        if_pte0_leaf = local(:if_pte0_leaf,
                             if_pte1_next & inst_ptw_pte0[0] & (inst_ptw_pte0[1] | inst_ptw_pte0[3]),
                             width: 1)
        if_walk_ok = local(:if_walk_ok, if_pte1_leaf | if_pte0_leaf, width: 1)
        if_walk_pte = local(:if_walk_pte, mux(if_pte1_leaf, inst_ptw_pte1, inst_ptw_pte0), width: 32)
        if_walk_ppn = local(:if_walk_ppn,
                            mux(if_pte1_leaf, cat(inst_ptw_pte1[29..20], if_vpn0), inst_ptw_pte0[29..10]),
                            width: 20)
        if_walk_perm_r = if_walk_pte[1]
        if_walk_perm_w = if_walk_pte[2]
        if_walk_perm_x = if_walk_pte[3]
        if_walk_perm_u = if_walk_pte[4]
        inst_tlb_fill_en <= if_satp_translate & ~inst_tlb_hit & if_walk_ok
        inst_tlb_fill_vpn <= if_vpn
        inst_tlb_fill_root <= if_satp_root_ppn
        inst_tlb_fill_ppn <= if_walk_ppn
        inst_tlb_fill_perm_r <= if_walk_perm_r
        inst_tlb_fill_perm_w <= if_walk_perm_w
        inst_tlb_fill_perm_x <= if_walk_perm_x
        inst_tlb_fill_perm_u <= if_walk_perm_u
        if_translated = local(:if_translated, inst_tlb_hit | if_walk_ok, width: 1)
        if_eff_ppn = local(:if_eff_ppn, mux(inst_tlb_hit, inst_tlb_ppn, if_walk_ppn), width: 20)
        if_eff_perm_x = local(:if_eff_perm_x, mux(inst_tlb_hit, inst_tlb_perm_x, if_walk_perm_x), width: 1)
        if_eff_perm_u = local(:if_eff_perm_u, mux(inst_tlb_hit, inst_tlb_perm_u, if_walk_perm_u), width: 1)
        if_u_ok = local(:if_u_ok,
                        mux(if_priv_is_u, if_eff_perm_u,
                            mux(if_priv_is_s, ~if_eff_perm_u, lit(1, width: 1))),
                        width: 1)
        if_perm_ok = local(:if_perm_ok, if_translated & if_eff_perm_x & if_u_ok, width: 1)
        if_paddr = local(:if_paddr, cat(if_eff_ppn, if_page_off), width: 32)
        if_inst_page_fault = local(:if_inst_page_fault, if_satp_translate & ~if_perm_ok, width: 1)
        inst_ptw_addr1 <= if_ptw_addr1_calc
        inst_ptw_addr0 <= if_ptw_addr0_calc
        if_id_inst_page_fault_in <= if_inst_page_fault

        # Next PC: control-transfer target or sequential
        next_pc <= mux(take_branch, control_target,
                    mux(stall, current_pc, pc_plus4_if))

        # PC write enable: disabled on stall
        pc_we <= ~stall

        # -----------------------------------------
        # ID/EX Register inputs (latch wires)
        # These values are captured BEFORE sequential propagation
        # -----------------------------------------
        id_is_fp_store = local(:id_is_fp_store,
                               (id_opcode == lit(Opcode::STORE_FP, width: 7)) &
                               ((id_funct3 == lit(Funct3::WORD, width: 3)) | (id_funct3 == lit(Funct3::DOUBLE, width: 3))),
                               width: 1)
        id_is_fmv_w_x = local(:id_is_fmv_w_x,
                              (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (id_funct7 == lit(0b1111000, width: 7)) &
                              (id_funct3 == lit(0, width: 3)) &
                              (id_rs2_addr == lit(0, width: 5)),
                              width: 1)
        id_is_fsgnj_d = local(:id_is_fsgnj_d,
                              (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (id_funct7 == lit(0b0010001, width: 7)),
                              width: 1)
        id_is_fminmax_d = local(:id_is_fminmax_d,
                                (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (id_funct7 == lit(0b0010101, width: 7)),
                                width: 1)
        id_is_fcmp_d = local(:id_is_fcmp_d,
                             (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (id_funct7 == lit(0b1010001, width: 7)),
                             width: 1)
        id_is_fadd_d = local(:id_is_fadd_d,
                             (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (id_funct7 == lit(0b0000001, width: 7)),
                             width: 1)
        id_is_fsub_d = local(:id_is_fsub_d,
                             (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (id_funct7 == lit(0b0000101, width: 7)),
                             width: 1)
        id_is_fmul_d = local(:id_is_fmul_d,
                             (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (id_funct7 == lit(0b0001001, width: 7)),
                             width: 1)
        id_is_fdiv_d = local(:id_is_fdiv_d,
                             (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (id_funct7 == lit(0b0001101, width: 7)),
                             width: 1)
        id_is_fsqrt_d = local(:id_is_fsqrt_d,
                              (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (id_funct7 == lit(0b0101101, width: 7)) &
                              (id_rs2_addr == lit(0, width: 5)),
                              width: 1)
        id_is_fmadd_d = local(:id_is_fmadd_d,
                              (id_opcode == lit(Opcode::MADD, width: 7)) &
                              (id_inst[26..25] == lit(0b01, width: 2)),
                              width: 1)
        id_is_fmsub_d = local(:id_is_fmsub_d,
                              (id_opcode == lit(Opcode::MSUB, width: 7)) &
                              (id_inst[26..25] == lit(0b01, width: 2)),
                              width: 1)
        id_is_fnmsub_d = local(:id_is_fnmsub_d,
                               (id_opcode == lit(Opcode::NMSUB, width: 7)) &
                               (id_inst[26..25] == lit(0b01, width: 2)),
                               width: 1)
        id_is_fnmadd_d = local(:id_is_fnmadd_d,
                               (id_opcode == lit(Opcode::NMADD, width: 7)) &
                               (id_inst[26..25] == lit(0b01, width: 2)),
                               width: 1)
        id_is_d_arith = local(:id_is_d_arith,
                              id_is_fadd_d | id_is_fsub_d | id_is_fmul_d | id_is_fdiv_d | id_is_fsqrt_d |
                              id_is_fmadd_d | id_is_fmsub_d | id_is_fnmsub_d | id_is_fnmadd_d,
                              width: 1)
        id_is_fcvt_s_w = local(:id_is_fcvt_s_w,
                               (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (id_funct7 == lit(0b1101000, width: 7)) &
                               (id_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        id_is_fcvt_s_wu = local(:id_is_fcvt_s_wu,
                                (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (id_funct7 == lit(0b1101000, width: 7)) &
                                (id_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        id_is_fcvt_w_d = local(:id_is_fcvt_w_d,
                               (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (id_funct7 == lit(0b1100001, width: 7)) &
                               (id_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        id_is_fcvt_wu_d = local(:id_is_fcvt_wu_d,
                                (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (id_funct7 == lit(0b1100001, width: 7)) &
                                (id_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        id_is_fcvt_s_d = local(:id_is_fcvt_s_d,
                               (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (id_funct7 == lit(0b0100000, width: 7)) &
                               (id_rs2_addr == lit(0b00001, width: 5)),
                               width: 1)
        id_is_fcvt_d_w = local(:id_is_fcvt_d_w,
                               (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (id_funct7 == lit(0b1101001, width: 7)) &
                               (id_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        id_is_fcvt_d_wu = local(:id_is_fcvt_d_wu,
                                (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (id_funct7 == lit(0b1101001, width: 7)) &
                                (id_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        id_is_fp_op_from_fpreg = local(:id_is_fp_op_from_fpreg,
                                       ((id_opcode == lit(Opcode::OP_FP, width: 7)) &
                                       ~(id_is_fmv_w_x | id_is_fcvt_s_w | id_is_fcvt_s_wu | id_is_fcvt_d_w | id_is_fcvt_d_wu)) |
                                       id_is_fmadd_d | id_is_fmsub_d | id_is_fnmsub_d | id_is_fnmadd_d,
                                       width: 1)
        id_is_fmv_x_w = local(:id_is_fmv_x_w,
                              (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (id_funct7 == lit(0b1110000, width: 7)) &
                              (id_funct3 == lit(0, width: 3)) &
                              (id_rs2_addr == lit(0, width: 5)),
                              width: 1)
        id_is_fclass_d = local(:id_is_fclass_d,
                               (id_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (id_funct7 == lit(0b1110001, width: 7)) &
                               (id_funct3 == lit(0b001, width: 3)) &
                               (id_rs2_addr == lit(0, width: 5)),
                               width: 1)
        id_ex_pc_in <= id_pc
        id_ex_pc_plus4_in <= id_pc_plus4
        id_rs3_addr <= id_inst[31..27]
        id_ex_rs1_data_in <= mux(id_is_fp_op_from_fpreg, id_fp_rs1_data, id_rs1_data)
        id_ex_rs2_data_in <= mux(id_is_fp_store | id_is_fp_op_from_fpreg, id_fp_rs2_data, id_rs2_data)
        id_ex_rs2_hi_data_in <= mux(id_is_fp_store | id_is_fp_op_from_fpreg, id_fp_rs2_data64[63..32], lit(0, width: 32))
        id_ex_rs3_data_in <= mux(id_is_fmadd_d | id_is_fmsub_d | id_is_fnmsub_d | id_is_fnmadd_d, id_fp_rs3_data, lit(0, width: 32))
        id_ex_rs3_hi_data_in <= mux(id_is_fmadd_d | id_is_fmsub_d | id_is_fnmsub_d | id_is_fnmadd_d, id_fp_rs3_data64[63..32], lit(0, width: 32))
        id_ex_rd_src_data_in <= mux(id_is_fcvt_s_d | id_is_fcvt_w_d | id_is_fcvt_wu_d | id_is_fclass_d |
                                    id_is_fsgnj_d | id_is_fminmax_d | id_is_fcmp_d,
                                    id_fp_rs1_data64[63..32],
                                    mux(id_is_d_arith,
                                    id_fp_rs1_data64[63..32],
                                    id_rs3_data))
        id_ex_imm_in <= id_imm
        id_ex_rs1_addr_in <= id_rs1_addr
        id_ex_rs2_addr_in <= id_rs2_addr
        id_ex_rd_addr_in <= id_rd_addr
        id_ex_opcode_in <= id_opcode
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
        id_ex_inst_page_fault_in <= id_inst_page_fault

        # -----------------------------------------
        # EX Stage: Forwarding muxes
        # -----------------------------------------
        ex_is_fp_store = local(:ex_is_fp_store,
                               (ex_opcode == lit(Opcode::STORE_FP, width: 7)) &
                               ((ex_funct3 == lit(Funct3::WORD, width: 3)) | (ex_funct3 == lit(Funct3::DOUBLE, width: 3))),
                               width: 1)
        ex_is_fmv_x_w = local(:ex_is_fmv_x_w,
                              (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (ex_funct7 == lit(0b1110000, width: 7)) &
                              (ex_funct3 == lit(0, width: 3)) &
                              (ex_rs2_addr == lit(0, width: 5)),
                              width: 1)
        ex_is_fmv_w_x = local(:ex_is_fmv_w_x,
                              (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (ex_funct7 == lit(0b1111000, width: 7)) &
                              (ex_funct3 == lit(0, width: 3)) &
                              (ex_rs2_addr == lit(0, width: 5)),
                              width: 1)
        ex_is_fsgnj_s = local(:ex_is_fsgnj_s,
                              (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (ex_funct7 == lit(0b0010000, width: 7)),
                              width: 1)
        ex_is_fsgnj_d = local(:ex_is_fsgnj_d,
                              (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (ex_funct7 == lit(0b0010001, width: 7)),
                              width: 1)
        ex_is_fminmax_s = local(:ex_is_fminmax_s,
                                (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (ex_funct7 == lit(0b0010100, width: 7)),
                                width: 1)
        ex_is_fminmax_d = local(:ex_is_fminmax_d,
                                (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (ex_funct7 == lit(0b0010101, width: 7)),
                                width: 1)
        ex_is_fcmp_s = local(:ex_is_fcmp_s,
                             (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (ex_funct7 == lit(0b1010000, width: 7)),
                             width: 1)
        ex_is_fcmp_d = local(:ex_is_fcmp_d,
                             (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (ex_funct7 == lit(0b1010001, width: 7)),
                             width: 1)
        ex_is_fadd_d = local(:ex_is_fadd_d,
                             (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (ex_funct7 == lit(0b0000001, width: 7)),
                             width: 1)
        ex_is_fsub_d = local(:ex_is_fsub_d,
                             (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (ex_funct7 == lit(0b0000101, width: 7)),
                             width: 1)
        ex_is_fmul_d = local(:ex_is_fmul_d,
                             (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (ex_funct7 == lit(0b0001001, width: 7)),
                             width: 1)
        ex_is_fdiv_d = local(:ex_is_fdiv_d,
                             (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                             (ex_funct7 == lit(0b0001101, width: 7)),
                             width: 1)
        ex_is_fsqrt_d = local(:ex_is_fsqrt_d,
                              (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (ex_funct7 == lit(0b0101101, width: 7)) &
                              (ex_rs2_addr == lit(0, width: 5)),
                              width: 1)
        ex_is_fmadd_d = local(:ex_is_fmadd_d,
                              (ex_opcode == lit(Opcode::MADD, width: 7)) &
                              (ex_funct7[1..0] == lit(0b01, width: 2)),
                              width: 1)
        ex_is_fmsub_d = local(:ex_is_fmsub_d,
                              (ex_opcode == lit(Opcode::MSUB, width: 7)) &
                              (ex_funct7[1..0] == lit(0b01, width: 2)),
                              width: 1)
        ex_is_fnmsub_d = local(:ex_is_fnmsub_d,
                               (ex_opcode == lit(Opcode::NMSUB, width: 7)) &
                               (ex_funct7[1..0] == lit(0b01, width: 2)),
                               width: 1)
        ex_is_fnmadd_d = local(:ex_is_fnmadd_d,
                               (ex_opcode == lit(Opcode::NMADD, width: 7)) &
                               (ex_funct7[1..0] == lit(0b01, width: 2)),
                               width: 1)
        ex_is_d_arith = local(:ex_is_d_arith,
                              ex_is_fadd_d | ex_is_fsub_d | ex_is_fmul_d | ex_is_fdiv_d | ex_is_fsqrt_d |
                              ex_is_fmadd_d | ex_is_fmsub_d | ex_is_fnmsub_d | ex_is_fnmadd_d,
                              width: 1)
        ex_is_fclass_s = local(:ex_is_fclass_s,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b1110000, width: 7)) &
                               (ex_funct3 == lit(0b001, width: 3)) &
                               (ex_rs2_addr == lit(0, width: 5)),
                               width: 1)
        ex_is_fclass_d = local(:ex_is_fclass_d,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b1110001, width: 7)) &
                               (ex_funct3 == lit(0b001, width: 3)) &
                               (ex_rs2_addr == lit(0, width: 5)),
                               width: 1)
        ex_is_fcvt_w_s = local(:ex_is_fcvt_w_s,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b1100000, width: 7)) &
                               (ex_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        ex_is_fcvt_wu_s = local(:ex_is_fcvt_wu_s,
                                (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (ex_funct7 == lit(0b1100000, width: 7)) &
                                (ex_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        ex_is_fcvt_w_d = local(:ex_is_fcvt_w_d,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b1100001, width: 7)) &
                               (ex_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        ex_is_fcvt_wu_d = local(:ex_is_fcvt_wu_d,
                                (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (ex_funct7 == lit(0b1100001, width: 7)) &
                                (ex_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        ex_is_fcvt_s_w = local(:ex_is_fcvt_s_w,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b1101000, width: 7)) &
                               (ex_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        ex_is_fcvt_s_wu = local(:ex_is_fcvt_s_wu,
                                (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (ex_funct7 == lit(0b1101000, width: 7)) &
                                (ex_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        ex_is_fcvt_s_d = local(:ex_is_fcvt_s_d,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b0100000, width: 7)) &
                               (ex_rs2_addr == lit(0b00001, width: 5)),
                               width: 1)
        ex_is_fcvt_d_s = local(:ex_is_fcvt_d_s,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b0100001, width: 7)) &
                               (ex_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        ex_is_fcvt_d_w = local(:ex_is_fcvt_d_w,
                               (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (ex_funct7 == lit(0b1101001, width: 7)) &
                               (ex_rs2_addr == lit(0b00000, width: 5)),
                               width: 1)
        ex_is_fcvt_d_wu = local(:ex_is_fcvt_d_wu,
                                (ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (ex_funct7 == lit(0b1101001, width: 7)) &
                                (ex_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        ex_is_fp_op_from_fpreg = local(:ex_is_fp_op_from_fpreg,
                                       ((ex_opcode == lit(Opcode::OP_FP, width: 7)) &
                                       ~(ex_is_fmv_w_x | ex_is_fcvt_s_w | ex_is_fcvt_s_wu | ex_is_fcvt_d_w | ex_is_fcvt_d_wu)) |
                                       ex_is_fmadd_d | ex_is_fmsub_d | ex_is_fnmsub_d | ex_is_fnmadd_d,
                                       width: 1)
        ex_v_funct6 = ex_funct7[6..1]
        ex_v_vm = ex_funct7[0]
        ex_is_vsetvli = local(:ex_is_vsetvli,
                              (ex_opcode == lit(Opcode::OP_V, width: 7)) &
                              (ex_funct3 == lit(0b111, width: 3)) &
                              (ex_funct7[6] == lit(0, width: 1)),
                              width: 1)
        ex_is_vadd_vv = local(:ex_is_vadd_vv,
                              (ex_opcode == lit(Opcode::OP_V, width: 7)) &
                              (ex_funct3 == lit(0b000, width: 3)) &
                              (ex_v_funct6 == lit(0b000000, width: 6)) &
                              ex_v_vm,
                              width: 1)
        ex_is_vadd_vx = local(:ex_is_vadd_vx,
                              (ex_opcode == lit(Opcode::OP_V, width: 7)) &
                              (ex_funct3 == lit(0b100, width: 3)) &
                              (ex_v_funct6 == lit(0b000000, width: 6)) &
                              ex_v_vm,
                              width: 1)
        ex_is_vmv_v_x = local(:ex_is_vmv_v_x,
                              (ex_opcode == lit(Opcode::OP_V, width: 7)) &
                              (ex_funct3 == lit(0b100, width: 3)) &
                              (ex_v_funct6 == lit(0b010111, width: 6)) &
                              ex_v_vm &
                              (ex_rs2_addr == lit(0, width: 5)),
                              width: 1)
        ex_is_vmv_x_s = local(:ex_is_vmv_x_s,
                              (ex_opcode == lit(Opcode::OP_V, width: 7)) &
                              (ex_funct3 == lit(0b010, width: 3)) &
                              (ex_v_funct6 == lit(0b010000, width: 6)) &
                              ex_v_vm &
                              (ex_rs1_addr == lit(0, width: 5)),
                              width: 1)
        ex_is_vmv_s_x = local(:ex_is_vmv_s_x,
                              (ex_opcode == lit(Opcode::OP_V, width: 7)) &
                              (ex_funct3 == lit(0b110, width: 3)) &
                              (ex_v_funct6 == lit(0b010000, width: 6)) &
                              ex_v_vm &
                              (ex_rs2_addr == lit(0, width: 5)),
                              width: 1)
        ex_vsetvli_avl = local(:ex_vsetvli_avl,
                               mux(ex_rs1_addr == lit(0, width: 5), lit(4, width: 32), forwarded_rs1),
                               width: 32)
        ex_vsetvli_new_vl = local(:ex_vsetvli_new_vl,
                                  mux(ex_vsetvli_avl > lit(4, width: 32), lit(4, width: 32), ex_vsetvli_avl),
                                  width: 32)
        ex_vsetvli_new_vtype = local(:ex_vsetvli_new_vtype,
                                     cat(lit(0, width: 21), ex_funct7[5..0], ex_rs2_addr),
                                     width: 32)

        # Forward A (rs1) - priority: EX/MEM > MEM/WB > register file
        forwarded_rs1 <= mux(ex_is_fp_op_from_fpreg, ex_rs1_data,
                             mux(forward_a == lit(ForwardSel::EX_MEM, width: 2), mem_forward_data,
                                 mux(forward_a == lit(ForwardSel::MEM_WB, width: 2), wb_data,
                                     ex_rs1_data)))

        # AUIPC uses PC as ALU A operand (not rs1)
        alu_a <= mux(ex_opcode == lit(Opcode::AUIPC, width: 7), ex_pc, forwarded_rs1)

        # Forward B (rs2) for store and branch comparison
        forwarded_rs2 <= mux(ex_is_fp_store | ex_is_fp_op_from_fpreg, ex_rs2_data,
                             mux(forward_b == lit(ForwardSel::EX_MEM, width: 2), mem_forward_data,
                                 mux(forward_b == lit(ForwardSel::MEM_WB, width: 2), wb_data,
                                     ex_rs2_data)))

        # ALU B input: immediate or forwarded rs2
        alu_b <= mux(ex_alu_src, ex_imm, forwarded_rs2)

        # Forward rd source (used by AMOCAS expected-value semantics)
        forwarded_rd_src <= mux((mem_reg_write & (mem_rd_addr != lit(0, width: 5)) & (mem_rd_addr == ex_rd_addr)),
                                mem_forward_data,
                                mux((wb_reg_write & (wb_rd_addr != lit(0, width: 5)) & (wb_rd_addr == ex_rd_addr)),
                                    wb_data,
                                    ex_rd_src_data))

        ex_fp_rs1_sign = forwarded_rs1[31]
        ex_fp_rs2_sign = forwarded_rs2[31]
        ex_fp_rs1_exp = forwarded_rs1[30..23]
        ex_fp_rs2_exp = forwarded_rs2[30..23]
        ex_fp_rs1_frac = forwarded_rs1[22..0]
        ex_fp_rs2_frac = forwarded_rs2[22..0]
        ex_fp_rs1_is_zero = local(:ex_fp_rs1_is_zero,
                                  (ex_fp_rs1_exp == lit(0, width: 8)) & (ex_fp_rs1_frac == lit(0, width: 23)),
                                  width: 1)
        ex_fp_rs2_is_zero = local(:ex_fp_rs2_is_zero,
                                  (ex_fp_rs2_exp == lit(0, width: 8)) & (ex_fp_rs2_frac == lit(0, width: 23)),
                                  width: 1)
        ex_fp_both_zero = local(:ex_fp_both_zero, ex_fp_rs1_is_zero & ex_fp_rs2_is_zero, width: 1)
        ex_fp_rs1_is_nan = local(:ex_fp_rs1_is_nan,
                                 (ex_fp_rs1_exp == lit(0xFF, width: 8)) & (ex_fp_rs1_frac != lit(0, width: 23)),
                                 width: 1)
        ex_fp_rs2_is_nan = local(:ex_fp_rs2_is_nan,
                                 (ex_fp_rs2_exp == lit(0xFF, width: 8)) & (ex_fp_rs2_frac != lit(0, width: 23)),
                                 width: 1)
        ex_fp_any_nan = local(:ex_fp_any_nan, ex_fp_rs1_is_nan | ex_fp_rs2_is_nan, width: 1)
        ex_fp_both_nan = local(:ex_fp_both_nan, ex_fp_rs1_is_nan & ex_fp_rs2_is_nan, width: 1)
        ex_fp_ordered_lt = local(:ex_fp_ordered_lt,
                                 mux(ex_fp_both_zero,
                                     lit(0, width: 1),
                                     mux(ex_fp_rs1_sign != ex_fp_rs2_sign,
                                         ex_fp_rs1_sign,
                                         mux(ex_fp_rs1_sign == lit(0, width: 1),
                                             forwarded_rs1 < forwarded_rs2,
                                             forwarded_rs1 > forwarded_rs2))),
                                 width: 1)
        ex_fp_ordered_eq = local(:ex_fp_ordered_eq,
                                 (forwarded_rs1 == forwarded_rs2) | ex_fp_both_zero,
                                 width: 1)
        ex_fp_lt = local(:ex_fp_lt, mux(ex_fp_any_nan, lit(0, width: 1), ex_fp_ordered_lt), width: 1)
        ex_fp_eq = local(:ex_fp_eq, mux(ex_fp_any_nan, lit(0, width: 1), ex_fp_ordered_eq), width: 1)
        ex_fp_le = local(:ex_fp_le, ex_fp_lt | ex_fp_eq, width: 1)

        ex_fsgnj_sign = local(:ex_fsgnj_sign,
                              case_select(ex_funct3, {
                                0b000 => ex_fp_rs2_sign,
                                0b001 => ~ex_fp_rs2_sign,
                                0b010 => ex_fp_rs1_sign ^ ex_fp_rs2_sign
                              }, default: ex_fp_rs2_sign),
                              width: 1)
        ex_fsgnj_result = local(:ex_fsgnj_result, cat(ex_fsgnj_sign, forwarded_rs1[30..0]), width: 32)

        ex_fp_canonical_nan = local(:ex_fp_canonical_nan, lit(0x7FC00000, width: 32), width: 32)
        ex_fp_min_zero = local(:ex_fp_min_zero,
                               mux(ex_fp_rs1_sign | ex_fp_rs2_sign, lit(0x80000000, width: 32), lit(0, width: 32)),
                               width: 32)
        ex_fp_max_zero = local(:ex_fp_max_zero,
                               mux(ex_fp_rs1_sign & ex_fp_rs2_sign, lit(0x80000000, width: 32), lit(0, width: 32)),
                               width: 32)
        ex_fp_min_result = local(:ex_fp_min_result,
                                 mux(ex_fp_both_nan,
                                     ex_fp_canonical_nan,
                                     mux(ex_fp_rs1_is_nan,
                                         forwarded_rs2,
                                         mux(ex_fp_rs2_is_nan,
                                             forwarded_rs1,
                                             mux(ex_fp_both_zero,
                                                 ex_fp_min_zero,
                                                 mux(ex_fp_lt, forwarded_rs1, forwarded_rs2))))),
                                 width: 32)
        ex_fp_max_result = local(:ex_fp_max_result,
                                 mux(ex_fp_both_nan,
                                     ex_fp_canonical_nan,
                                     mux(ex_fp_rs1_is_nan,
                                         forwarded_rs2,
                                         mux(ex_fp_rs2_is_nan,
                                             forwarded_rs1,
                                             mux(ex_fp_both_zero,
                                                 ex_fp_max_zero,
                                                 mux(ex_fp_lt, forwarded_rs2, forwarded_rs1))))),
                                 width: 32)
        ex_fp_minmax_result = local(:ex_fp_minmax_result,
                                    mux(ex_funct3 == lit(0b000, width: 3), ex_fp_min_result, ex_fp_max_result),
                                    width: 32)
        ex_fp_is_inf = local(:ex_fp_is_inf,
                             (ex_fp_rs1_exp == lit(0xFF, width: 8)) & (ex_fp_rs1_frac == lit(0, width: 23)),
                             width: 1)
        ex_fp_is_subnormal = local(:ex_fp_is_subnormal,
                                   (ex_fp_rs1_exp == lit(0, width: 8)) & (ex_fp_rs1_frac != lit(0, width: 23)),
                                   width: 1)
        ex_fp_is_normal = local(:ex_fp_is_normal,
                                (ex_fp_rs1_exp != lit(0, width: 8)) & (ex_fp_rs1_exp != lit(0xFF, width: 8)),
                                width: 1)
        ex_fp_is_snan = local(:ex_fp_is_snan, ex_fp_rs1_is_nan & (ex_fp_rs1_frac[22] == lit(0, width: 1)), width: 1)
        ex_fp_is_qnan = local(:ex_fp_is_qnan, ex_fp_rs1_is_nan & (ex_fp_rs1_frac[22] == lit(1, width: 1)), width: 1)
        ex_fp_class_result = local(:ex_fp_class_result,
                                   mux(ex_fp_is_inf & ex_fp_rs1_sign, lit(1 << 0, width: 32),
                                       mux(ex_fp_is_normal & ex_fp_rs1_sign, lit(1 << 1, width: 32),
                                           mux(ex_fp_is_subnormal & ex_fp_rs1_sign, lit(1 << 2, width: 32),
                                               mux(ex_fp_rs1_is_zero & ex_fp_rs1_sign, lit(1 << 3, width: 32),
                                                   mux(ex_fp_rs1_is_zero & ~ex_fp_rs1_sign, lit(1 << 4, width: 32),
                                                       mux(ex_fp_is_subnormal & ~ex_fp_rs1_sign, lit(1 << 5, width: 32),
                                                           mux(ex_fp_is_normal & ~ex_fp_rs1_sign, lit(1 << 6, width: 32),
                                                               mux(ex_fp_is_inf & ~ex_fp_rs1_sign, lit(1 << 7, width: 32),
                                                                   mux(ex_fp_is_snan, lit(1 << 8, width: 32),
                                                                       mux(ex_fp_is_qnan, lit(1 << 9, width: 32),
                                                                           lit(0, width: 32))))))))))),
                                   width: 32)
        ex_fp_cmp_result = local(:ex_fp_cmp_result,
                                 case_select(ex_funct3, {
                                   0b010 => cat(lit(0, width: 31), ex_fp_eq),
                                   0b001 => cat(lit(0, width: 31), ex_fp_lt),
                                   0b000 => cat(lit(0, width: 31), ex_fp_le)
                                 }, default: lit(0, width: 32)),
                                 width: 32)
        ex_fp_exp_ge_127 = local(:ex_fp_exp_ge_127, ex_fp_rs1_exp >= lit(127, width: 8), width: 1)
        ex_fp_exp_gt_157 = local(:ex_fp_exp_gt_157, ex_fp_rs1_exp > lit(157, width: 8), width: 1)
        ex_fp_exp_ge_150 = local(:ex_fp_exp_ge_150, ex_fp_rs1_exp >= lit(150, width: 8), width: 1)
        ex_fp_shift_left_amt = local(:ex_fp_shift_left_amt, ex_fp_rs1_exp - lit(150, width: 8), width: 8)
        ex_fp_shift_right_amt = local(:ex_fp_shift_right_amt, lit(150, width: 8) - ex_fp_rs1_exp, width: 8)
        ex_fp_mantissa = local(:ex_fp_mantissa, cat(lit(1, width: 1), ex_fp_rs1_frac), width: 24)
        ex_fp_abs_int_from_float = local(:ex_fp_abs_int_from_float,
                                         mux(ex_fp_exp_ge_150,
                                             cat(lit(0, width: 8), ex_fp_mantissa) << ex_fp_shift_left_amt,
                                             cat(lit(0, width: 8), ex_fp_mantissa) >> ex_fp_shift_right_amt),
                                         width: 32)
        ex_fp_signed_int_from_float = local(:ex_fp_signed_int_from_float,
                                            mux(ex_fp_rs1_sign, ~ex_fp_abs_int_from_float + lit(1, width: 32), ex_fp_abs_int_from_float),
                                            width: 32)
        ex_fcvt_w_s_result = local(:ex_fcvt_w_s_result,
                                   mux(ex_fp_rs1_is_nan | ex_fp_exp_gt_157,
                                       lit(0x80000000, width: 32),
                                       mux(~ex_fp_exp_ge_127,
                                           lit(0, width: 32),
                                           ex_fp_signed_int_from_float)),
                                   width: 32)
        ex_fcvt_wu_s_result = local(:ex_fcvt_wu_s_result,
                                    mux(ex_fp_rs1_is_nan | ex_fp_exp_gt_157 | ex_fp_rs1_sign,
                                        lit(0xFFFFFFFF, width: 32),
                                        mux(~ex_fp_exp_ge_127,
                                            lit(0, width: 32),
                                            ex_fp_abs_int_from_float)),
                                    width: 32)

        ex_fcvt_sw_sign = local(:ex_fcvt_sw_sign,
                                mux(ex_is_fcvt_s_w, forwarded_rs1[31], lit(0, width: 1)),
                                width: 1)
        ex_fcvt_sw_abs = local(:ex_fcvt_sw_abs,
                               mux(ex_is_fcvt_s_w & forwarded_rs1[31], ~forwarded_rs1 + lit(1, width: 32), forwarded_rs1),
                               width: 32)
        ex_fcvt_sw_msb_expr = local(:ex_fcvt_sw_msb_seed, lit(0, width: 6), width: 6)
        32.times do |i|
          ex_fcvt_sw_msb_expr = local(:"ex_fcvt_sw_msb_stage_#{i}",
                                      mux(ex_fcvt_sw_abs[i], lit(i, width: 6), ex_fcvt_sw_msb_expr),
                                      width: 6)
        end
        ex_fcvt_sw_msb = local(:ex_fcvt_sw_msb, ex_fcvt_sw_msb_expr, width: 6)
        ex_fcvt_sw_nonzero = local(:ex_fcvt_sw_nonzero, ex_fcvt_sw_abs != lit(0, width: 32), width: 1)
        ex_fcvt_sw_shift_left_amt = local(:ex_fcvt_sw_shift_left_amt, lit(23, width: 6) - ex_fcvt_sw_msb, width: 6)
        ex_fcvt_sw_shift_right_amt = local(:ex_fcvt_sw_shift_right_amt, ex_fcvt_sw_msb - lit(23, width: 6), width: 6)
        ex_fcvt_sw_norm = local(:ex_fcvt_sw_norm,
                                mux(ex_fcvt_sw_msb > lit(23, width: 6),
                                    ex_fcvt_sw_abs >> ex_fcvt_sw_shift_right_amt,
                                    ex_fcvt_sw_abs << ex_fcvt_sw_shift_left_amt),
                                width: 32)
        ex_fcvt_sw_frac = ex_fcvt_sw_norm[22..0]
        ex_fcvt_sw_exp = local(:ex_fcvt_sw_exp, cat(lit(0, width: 2), ex_fcvt_sw_msb) + lit(127, width: 8), width: 8)
        ex_fcvt_s_w_result = local(:ex_fcvt_s_w_result,
                                   mux(ex_fcvt_sw_nonzero,
                                       cat(ex_fcvt_sw_sign, ex_fcvt_sw_exp, ex_fcvt_sw_frac),
                                       lit(0, width: 32)),
                                   width: 32)
        ex_fp_rs1_data64 = local(:ex_fp_rs1_data64, cat(ex_rd_src_data, forwarded_rs1), width: 64)
        ex_fp_rs2_data64 = local(:ex_fp_rs2_data64, cat(ex_rs2_hi_data, forwarded_rs2), width: 64)
        ex_fp_rs3_data64 = local(:ex_fp_rs3_data64, cat(ex_rs3_hi_data, ex_rs3_data), width: 64)
        ex_fp64_rs1_sign = ex_fp_rs1_data64[63]
        ex_fp64_rs1_exp = ex_fp_rs1_data64[62..52]
        ex_fp64_rs1_frac = ex_fp_rs1_data64[51..0]
        ex_fp64_rs2_sign = ex_fp_rs2_data64[63]
        ex_fp64_rs2_exp = ex_fp_rs2_data64[62..52]
        ex_fp64_rs2_frac = ex_fp_rs2_data64[51..0]
        ex_fp64_rs3_sign = ex_fp_rs3_data64[63]
        ex_fp64_rs3_exp = ex_fp_rs3_data64[62..52]
        ex_fp64_rs3_frac = ex_fp_rs3_data64[51..0]
        ex_fp64_rs1_is_zero = local(:ex_fp64_rs1_is_zero,
                                    (ex_fp64_rs1_exp == lit(0, width: 11)) & (ex_fp64_rs1_frac == lit(0, width: 52)),
                                    width: 1)
        ex_fp64_rs2_is_zero = local(:ex_fp64_rs2_is_zero,
                                    (ex_fp64_rs2_exp == lit(0, width: 11)) & (ex_fp64_rs2_frac == lit(0, width: 52)),
                                    width: 1)
        ex_fp64_rs1_is_inf = local(:ex_fp64_rs1_is_inf,
                                   (ex_fp64_rs1_exp == lit(0x7FF, width: 11)) & (ex_fp64_rs1_frac == lit(0, width: 52)),
                                   width: 1)
        ex_fp64_rs1_is_nan = local(:ex_fp64_rs1_is_nan,
                                   (ex_fp64_rs1_exp == lit(0x7FF, width: 11)) & (ex_fp64_rs1_frac != lit(0, width: 52)),
                                   width: 1)
        ex_fp64_rs2_is_nan = local(:ex_fp64_rs2_is_nan,
                                   (ex_fp64_rs2_exp == lit(0x7FF, width: 11)) & (ex_fp64_rs2_frac != lit(0, width: 52)),
                                   width: 1)
        ex_fp64_rs3_is_nan = local(:ex_fp64_rs3_is_nan,
                                   (ex_fp64_rs3_exp == lit(0x7FF, width: 11)) & (ex_fp64_rs3_frac != lit(0, width: 52)),
                                   width: 1)
        ex_fp64_both_zero = local(:ex_fp64_both_zero, ex_fp64_rs1_is_zero & ex_fp64_rs2_is_zero, width: 1)
        ex_fp64_any_nan = local(:ex_fp64_any_nan, ex_fp64_rs1_is_nan | ex_fp64_rs2_is_nan, width: 1)
        ex_fp64_both_nan = local(:ex_fp64_both_nan, ex_fp64_rs1_is_nan & ex_fp64_rs2_is_nan, width: 1)
        ex_fp64_ordered_lt = local(:ex_fp64_ordered_lt,
                                   mux(ex_fp64_both_zero,
                                       lit(0, width: 1),
                                       mux(ex_fp64_rs1_sign != ex_fp64_rs2_sign,
                                           ex_fp64_rs1_sign,
                                           mux(ex_fp64_rs1_sign == lit(0, width: 1),
                                               ex_fp_rs1_data64 < ex_fp_rs2_data64,
                                               ex_fp_rs1_data64 > ex_fp_rs2_data64))),
                                   width: 1)
        ex_fp64_ordered_eq = local(:ex_fp64_ordered_eq,
                                   (ex_fp_rs1_data64 == ex_fp_rs2_data64) | ex_fp64_both_zero,
                                   width: 1)
        ex_fp64_lt = local(:ex_fp64_lt, mux(ex_fp64_any_nan, lit(0, width: 1), ex_fp64_ordered_lt), width: 1)
        ex_fp64_eq = local(:ex_fp64_eq, mux(ex_fp64_any_nan, lit(0, width: 1), ex_fp64_ordered_eq), width: 1)
        ex_fp64_le = local(:ex_fp64_le, ex_fp64_lt | ex_fp64_eq, width: 1)
        ex_fsgnj_d_sign = local(:ex_fsgnj_d_sign,
                                case_select(ex_funct3, {
                                  0b000 => ex_fp64_rs2_sign,
                                  0b001 => ~ex_fp64_rs2_sign,
                                  0b010 => ex_fp64_rs1_sign ^ ex_fp64_rs2_sign
                                }, default: ex_fp64_rs2_sign),
                                width: 1)
        ex_fsgnj_d_result64 = local(:ex_fsgnj_d_result64, cat(ex_fsgnj_d_sign, ex_fp_rs1_data64[62..0]), width: 64)
        ex_fp64_canonical_nan = local(:ex_fp64_canonical_nan, lit(0x7FF8_0000_0000_0000, width: 64), width: 64)
        ex_fp64_min_zero = local(:ex_fp64_min_zero,
                                 mux(ex_fp64_rs1_sign | ex_fp64_rs2_sign, cat(lit(1, width: 1), lit(0, width: 63)), lit(0, width: 64)),
                                 width: 64)
        ex_fp64_max_zero = local(:ex_fp64_max_zero,
                                 mux(ex_fp64_rs1_sign & ex_fp64_rs2_sign, cat(lit(1, width: 1), lit(0, width: 63)), lit(0, width: 64)),
                                 width: 64)
        ex_fp64_min_result = local(:ex_fp64_min_result,
                                   mux(ex_fp64_both_nan,
                                       ex_fp64_canonical_nan,
                                       mux(ex_fp64_rs1_is_nan,
                                           ex_fp_rs2_data64,
                                           mux(ex_fp64_rs2_is_nan,
                                               ex_fp_rs1_data64,
                                               mux(ex_fp64_both_zero,
                                                   ex_fp64_min_zero,
                                                   mux(ex_fp64_lt, ex_fp_rs1_data64, ex_fp_rs2_data64))))),
                                   width: 64)
        ex_fp64_max_result = local(:ex_fp64_max_result,
                                   mux(ex_fp64_both_nan,
                                       ex_fp64_canonical_nan,
                                       mux(ex_fp64_rs1_is_nan,
                                           ex_fp_rs2_data64,
                                           mux(ex_fp64_rs2_is_nan,
                                               ex_fp_rs1_data64,
                                               mux(ex_fp64_both_zero,
                                                   ex_fp64_max_zero,
                                                   mux(ex_fp64_lt, ex_fp_rs2_data64, ex_fp_rs1_data64))))),
                                   width: 64)
        ex_fp64_minmax_result = local(:ex_fp64_minmax_result,
                                      mux(ex_funct3 == lit(0b000, width: 3), ex_fp64_min_result, ex_fp64_max_result),
                                      width: 64)
        ex_fp_cmp_d_result = local(:ex_fp_cmp_d_result,
                                   case_select(ex_funct3, {
                                     0b010 => cat(lit(0, width: 31), ex_fp64_eq),
                                     0b001 => cat(lit(0, width: 31), ex_fp64_lt),
                                     0b000 => cat(lit(0, width: 31), ex_fp64_le)
                                   }, default: lit(0, width: 32)),
                                   width: 32)
        ex_fp64_rs1_is_subnormal = local(:ex_fp64_rs1_is_subnormal,
                                         (ex_fp64_rs1_exp == lit(0, width: 11)) & (ex_fp64_rs1_frac != lit(0, width: 52)),
                                         width: 1)
        ex_fp64_rs1_is_normal = local(:ex_fp64_rs1_is_normal,
                                      (ex_fp64_rs1_exp != lit(0, width: 11)) & (ex_fp64_rs1_exp != lit(0x7FF, width: 11)),
                                      width: 1)
        ex_fp64_rs1_is_snan = local(:ex_fp64_rs1_is_snan, ex_fp64_rs1_is_nan & (ex_fp64_rs1_frac[51] == lit(0, width: 1)), width: 1)
        ex_fp64_rs1_is_qnan = local(:ex_fp64_rs1_is_qnan, ex_fp64_rs1_is_nan & (ex_fp64_rs1_frac[51] == lit(1, width: 1)), width: 1)
        ex_fp64_class_result = local(:ex_fp64_class_result,
                                     mux(ex_fp64_rs1_is_inf & ex_fp64_rs1_sign, lit(1 << 0, width: 32),
                                         mux(ex_fp64_rs1_is_normal & ex_fp64_rs1_sign, lit(1 << 1, width: 32),
                                             mux(ex_fp64_rs1_is_subnormal & ex_fp64_rs1_sign, lit(1 << 2, width: 32),
                                                 mux(ex_fp64_rs1_is_zero & ex_fp64_rs1_sign, lit(1 << 3, width: 32),
                                                     mux(ex_fp64_rs1_is_zero & ~ex_fp64_rs1_sign, lit(1 << 4, width: 32),
                                                         mux(ex_fp64_rs1_is_subnormal & ~ex_fp64_rs1_sign, lit(1 << 5, width: 32),
                                                             mux(ex_fp64_rs1_is_normal & ~ex_fp64_rs1_sign, lit(1 << 6, width: 32),
                                                                 mux(ex_fp64_rs1_is_inf & ~ex_fp64_rs1_sign, lit(1 << 7, width: 32),
                                                                     mux(ex_fp64_rs1_is_snan, lit(1 << 8, width: 32),
                                                                         mux(ex_fp64_rs1_is_qnan, lit(1 << 9, width: 32),
                                                                             lit(0, width: 32))))))))))),
                                     width: 32)
        ex_fp64_rs1_exp_le_896 = local(:ex_fp64_rs1_exp_le_896, ex_fp64_rs1_exp <= lit(896, width: 11), width: 1)
        ex_fp64_rs1_exp_gt_1150 = local(:ex_fp64_rs1_exp_gt_1150, ex_fp64_rs1_exp > lit(1150, width: 11), width: 1)
        ex_fcvt_sd_exp11 = local(:ex_fcvt_sd_exp11, ex_fp64_rs1_exp - lit(896, width: 11), width: 11)
        ex_fcvt_sd_frac = ex_fp64_rs1_frac[51..29]
        ex_fcvt_s_d_zero = local(:ex_fcvt_s_d_zero, cat(ex_fp64_rs1_sign, lit(0, width: 31)), width: 32)
        ex_fcvt_s_d_inf = local(:ex_fcvt_s_d_inf, cat(ex_fp64_rs1_sign, lit(0xFF, width: 8), lit(0, width: 23)), width: 32)
        ex_fcvt_s_d_norm = local(:ex_fcvt_s_d_norm, cat(ex_fp64_rs1_sign, ex_fcvt_sd_exp11[7..0], ex_fcvt_sd_frac), width: 32)
        ex_fcvt_s_d_result = local(:ex_fcvt_s_d_result,
                                   mux(ex_fp64_rs1_is_zero,
                                       ex_fcvt_s_d_zero,
                                       mux(ex_fp64_rs1_is_nan,
                                           lit(0x7FC0_0000, width: 32),
                                           mux(ex_fp64_rs1_is_inf,
                                               ex_fcvt_s_d_inf,
                                               mux(ex_fp64_rs1_exp_le_896,
                                                   ex_fcvt_s_d_zero,
                                                   mux(ex_fp64_rs1_exp_gt_1150,
                                                       ex_fcvt_s_d_inf,
                                                       ex_fcvt_s_d_norm))))),
                                   width: 32)
        ex_fp64_exp_ge_1023 = local(:ex_fp64_exp_ge_1023, ex_fp64_rs1_exp >= lit(1023, width: 11), width: 1)
        ex_fp64_exp_gt_1053 = local(:ex_fp64_exp_gt_1053, ex_fp64_rs1_exp > lit(1053, width: 11), width: 1)
        ex_fp64_exp_ge_1075 = local(:ex_fp64_exp_ge_1075, ex_fp64_rs1_exp >= lit(1075, width: 11), width: 1)
        ex_fp64_shift_left_amt = local(:ex_fp64_shift_left_amt, ex_fp64_rs1_exp - lit(1075, width: 11), width: 11)
        ex_fp64_shift_right_amt = local(:ex_fp64_shift_right_amt, lit(1075, width: 11) - ex_fp64_rs1_exp, width: 11)
        ex_fp64_mantissa = local(:ex_fp64_mantissa, cat(lit(1, width: 1), ex_fp64_rs1_frac), width: 53)
        ex_fp64_abs_int_from_double = local(:ex_fp64_abs_int_from_double,
                                            mux(ex_fp64_exp_ge_1075,
                                                cat(lit(0, width: 11), ex_fp64_mantissa) << ex_fp64_shift_left_amt,
                                                cat(lit(0, width: 11), ex_fp64_mantissa) >> ex_fp64_shift_right_amt),
                                            width: 64)
        ex_fp64_signed_int_from_double = local(:ex_fp64_signed_int_from_double,
                                               mux(ex_fp64_rs1_sign,
                                                   ~ex_fp64_abs_int_from_double + lit(1, width: 64),
                                                   ex_fp64_abs_int_from_double),
                                               width: 64)
        ex_fcvt_w_d_result = local(:ex_fcvt_w_d_result,
                                   mux(ex_fp64_rs1_is_nan | ex_fp64_exp_gt_1053,
                                       lit(0x80000000, width: 32),
                                       mux(~ex_fp64_exp_ge_1023,
                                           lit(0, width: 32),
                                           ex_fp64_signed_int_from_double[31..0])),
                                   width: 32)
        ex_fcvt_wu_d_result = local(:ex_fcvt_wu_d_result,
                                    mux(ex_fp64_rs1_is_nan | ex_fp64_exp_gt_1053 | ex_fp64_rs1_sign,
                                        lit(0xFFFFFFFF, width: 32),
                                        mux(~ex_fp64_exp_ge_1023,
                                            lit(0, width: 32),
                                            ex_fp64_abs_int_from_double[31..0])),
                                    width: 32)
        ex_fp64_rs2_exp_ge_1023 = local(:ex_fp64_rs2_exp_ge_1023, ex_fp64_rs2_exp >= lit(1023, width: 11), width: 1)
        ex_fp64_rs2_exp_gt_1053 = local(:ex_fp64_rs2_exp_gt_1053, ex_fp64_rs2_exp > lit(1053, width: 11), width: 1)
        ex_fp64_rs2_exp_ge_1075 = local(:ex_fp64_rs2_exp_ge_1075, ex_fp64_rs2_exp >= lit(1075, width: 11), width: 1)
        ex_fp64_rs2_shift_left_amt = local(:ex_fp64_rs2_shift_left_amt, ex_fp64_rs2_exp - lit(1075, width: 11), width: 11)
        ex_fp64_rs2_shift_right_amt = local(:ex_fp64_rs2_shift_right_amt, lit(1075, width: 11) - ex_fp64_rs2_exp, width: 11)
        ex_fp64_rs2_mantissa = local(:ex_fp64_rs2_mantissa, cat(lit(1, width: 1), ex_fp64_rs2_frac), width: 53)
        ex_fp64_rs2_abs_int_from_double = local(:ex_fp64_rs2_abs_int_from_double,
                                                mux(ex_fp64_rs2_exp_ge_1075,
                                                    cat(lit(0, width: 11), ex_fp64_rs2_mantissa) << ex_fp64_rs2_shift_left_amt,
                                                    cat(lit(0, width: 11), ex_fp64_rs2_mantissa) >> ex_fp64_rs2_shift_right_amt),
                                                width: 64)
        ex_fp64_rs2_signed_int_from_double = local(:ex_fp64_rs2_signed_int_from_double,
                                                   mux(ex_fp64_rs2_sign,
                                                       ~ex_fp64_rs2_abs_int_from_double + lit(1, width: 64),
                                                       ex_fp64_rs2_abs_int_from_double),
                                                   width: 64)
        ex_fcvt_w_d_rs2_result = local(:ex_fcvt_w_d_rs2_result,
                                       mux(ex_fp64_rs2_is_nan | ex_fp64_rs2_exp_gt_1053,
                                           lit(0x80000000, width: 32),
                                           mux(~ex_fp64_rs2_exp_ge_1023,
                                               lit(0, width: 32),
                                               ex_fp64_rs2_signed_int_from_double[31..0])),
                                       width: 32)
        ex_fp64_rs3_exp_ge_1023 = local(:ex_fp64_rs3_exp_ge_1023, ex_fp64_rs3_exp >= lit(1023, width: 11), width: 1)
        ex_fp64_rs3_exp_gt_1053 = local(:ex_fp64_rs3_exp_gt_1053, ex_fp64_rs3_exp > lit(1053, width: 11), width: 1)
        ex_fp64_rs3_exp_ge_1075 = local(:ex_fp64_rs3_exp_ge_1075, ex_fp64_rs3_exp >= lit(1075, width: 11), width: 1)
        ex_fp64_rs3_shift_left_amt = local(:ex_fp64_rs3_shift_left_amt, ex_fp64_rs3_exp - lit(1075, width: 11), width: 11)
        ex_fp64_rs3_shift_right_amt = local(:ex_fp64_rs3_shift_right_amt, lit(1075, width: 11) - ex_fp64_rs3_exp, width: 11)
        ex_fp64_rs3_mantissa = local(:ex_fp64_rs3_mantissa, cat(lit(1, width: 1), ex_fp64_rs3_frac), width: 53)
        ex_fp64_rs3_abs_int_from_double = local(:ex_fp64_rs3_abs_int_from_double,
                                                mux(ex_fp64_rs3_exp_ge_1075,
                                                    cat(lit(0, width: 11), ex_fp64_rs3_mantissa) << ex_fp64_rs3_shift_left_amt,
                                                    cat(lit(0, width: 11), ex_fp64_rs3_mantissa) >> ex_fp64_rs3_shift_right_amt),
                                                width: 64)
        ex_fp64_rs3_signed_int_from_double = local(:ex_fp64_rs3_signed_int_from_double,
                                                   mux(ex_fp64_rs3_sign,
                                                       ~ex_fp64_rs3_abs_int_from_double + lit(1, width: 64),
                                                       ex_fp64_rs3_abs_int_from_double),
                                                   width: 64)
        ex_fcvt_w_d_rs3_result = local(:ex_fcvt_w_d_rs3_result,
                                       mux(ex_fp64_rs3_is_nan | ex_fp64_rs3_exp_gt_1053,
                                           lit(0x80000000, width: 32),
                                           mux(~ex_fp64_rs3_exp_ge_1023,
                                               lit(0, width: 32),
                                               ex_fp64_rs3_signed_int_from_double[31..0])),
                                       width: 32)
        ex_d_add_i32 = local(:ex_d_add_i32, ex_fcvt_w_d_result + ex_fcvt_w_d_rs2_result, width: 32)
        ex_d_sub_i32 = local(:ex_d_sub_i32, ex_fcvt_w_d_result - ex_fcvt_w_d_rs2_result, width: 32)
        ex_d_mul_a_sign = ex_fcvt_w_d_result[31]
        ex_d_mul_b_sign = ex_fcvt_w_d_rs2_result[31]
        ex_d_mul_a_abs = local(:ex_d_mul_a_abs,
                               mux(ex_d_mul_a_sign, ~ex_fcvt_w_d_result + lit(1, width: 32), ex_fcvt_w_d_result),
                               width: 32)
        ex_d_mul_b_abs = local(:ex_d_mul_b_abs,
                               mux(ex_d_mul_b_sign, ~ex_fcvt_w_d_rs2_result + lit(1, width: 32), ex_fcvt_w_d_rs2_result),
                               width: 32)
        ex_d_mul_abs64 = local(:ex_d_mul_abs64, cat(lit(0, width: 32), ex_d_mul_a_abs) * cat(lit(0, width: 32), ex_d_mul_b_abs), width: 64)
        ex_d_mul_neg = local(:ex_d_mul_neg, ex_d_mul_a_sign ^ ex_d_mul_b_sign, width: 1)
        ex_d_mul_i64 = local(:ex_d_mul_i64,
                             mux(ex_d_mul_neg, ~ex_d_mul_abs64 + lit(1, width: 64), ex_d_mul_abs64),
                             width: 64)
        ex_d_mul_i32 = ex_d_mul_i64[31..0]
        ex_d_fmadd_i32 = local(:ex_d_fmadd_i32, ex_d_mul_i32 + ex_fcvt_w_d_rs3_result, width: 32)
        ex_d_fmsub_i32 = local(:ex_d_fmsub_i32, ex_d_mul_i32 - ex_fcvt_w_d_rs3_result, width: 32)
        ex_d_fnmsub_i32 = local(:ex_d_fnmsub_i32, (~ex_d_mul_i32 + lit(1, width: 32)) + ex_fcvt_w_d_rs3_result, width: 32)
        ex_d_fnmadd_i32 = local(:ex_d_fnmadd_i32, (~ex_d_mul_i32 + lit(1, width: 32)) - ex_fcvt_w_d_rs3_result, width: 32)
        ex_d_div_a_sign = ex_fcvt_w_d_result[31]
        ex_d_div_b_sign = ex_fcvt_w_d_rs2_result[31]
        ex_d_div_a_abs = local(:ex_d_div_a_abs,
                               mux(ex_d_div_a_sign, ~ex_fcvt_w_d_result + lit(1, width: 32), ex_fcvt_w_d_result),
                               width: 32)
        ex_d_div_b_abs = local(:ex_d_div_b_abs,
                               mux(ex_d_div_b_sign, ~ex_fcvt_w_d_rs2_result + lit(1, width: 32), ex_fcvt_w_d_rs2_result),
                               width: 32)
        ex_d_div_abs = local(:ex_d_div_abs,
                             mux(ex_d_div_b_abs == lit(0, width: 32), lit(0, width: 32), ex_d_div_a_abs / ex_d_div_b_abs),
                             width: 32)
        ex_d_div_neg = local(:ex_d_div_neg, ex_d_div_a_sign ^ ex_d_div_b_sign, width: 1)
        ex_d_div_i32 = local(:ex_d_div_i32,
                             mux(ex_d_div_neg, ~ex_d_div_abs + lit(1, width: 32), ex_d_div_abs),
                             width: 32)
        ex_d_sqrt_input_abs = local(:ex_d_sqrt_input_abs,
                                    mux(ex_fcvt_w_d_result[31], ~ex_fcvt_w_d_result + lit(1, width: 32), ex_fcvt_w_d_result),
                                    width: 32)
        ex_d_sqrt_result_expr = local(:ex_d_sqrt_result_seed, lit(0, width: 32), width: 32)
        16.times do |k|
          bit = 15 - k
          trial = local(:"ex_d_sqrt_trial_#{bit}", ex_d_sqrt_result_expr | lit(1 << bit, width: 32), width: 32)
          trial_sq = local(:"ex_d_sqrt_trial_sq_#{bit}", cat(lit(0, width: 32), trial) * cat(lit(0, width: 32), trial), width: 64)
          ex_d_sqrt_result_expr = local(:"ex_d_sqrt_result_stage_#{bit}",
                                        mux(trial_sq <= cat(lit(0, width: 32), ex_d_sqrt_input_abs), trial, ex_d_sqrt_result_expr),
                                        width: 32)
        end
        ex_d_sqrt_i32 = local(:ex_d_sqrt_i32,
                              mux(ex_fcvt_w_d_result[31], lit(0, width: 32), ex_d_sqrt_result_expr),
                              width: 32)
        ex_d_alu_i32 = local(:ex_d_alu_i32,
                             mux(ex_is_fadd_d, ex_d_add_i32,
                                 mux(ex_is_fsub_d, ex_d_sub_i32,
                                     mux(ex_is_fmul_d, ex_d_mul_i32,
                                         mux(ex_is_fmadd_d, ex_d_fmadd_i32,
                                             mux(ex_is_fmsub_d, ex_d_fmsub_i32,
                                                 mux(ex_is_fnmsub_d, ex_d_fnmsub_i32,
                                                     mux(ex_is_fnmadd_d, ex_d_fnmadd_i32,
                                                         mux(ex_is_fdiv_d, ex_d_div_i32,
                                                             mux(ex_is_fsqrt_d, ex_d_sqrt_i32, lit(0, width: 32)))))))))),
                             width: 32)
        ex_d_alu_sign = ex_d_alu_i32[31]
        ex_d_alu_abs = local(:ex_d_alu_abs,
                             mux(ex_d_alu_i32[31], ~ex_d_alu_i32 + lit(1, width: 32), ex_d_alu_i32),
                             width: 32)
        ex_d_alu_msb_expr = local(:ex_d_alu_msb_seed, lit(0, width: 6), width: 6)
        32.times do |i|
          ex_d_alu_msb_expr = local(:"ex_d_alu_msb_stage_#{i}",
                                    mux(ex_d_alu_abs[i], lit(i, width: 6), ex_d_alu_msb_expr),
                                    width: 6)
        end
        ex_d_alu_msb = local(:ex_d_alu_msb, ex_d_alu_msb_expr, width: 6)
        ex_d_alu_nonzero = local(:ex_d_alu_nonzero, ex_d_alu_abs != lit(0, width: 32), width: 1)
        ex_d_alu_shift_left_amt = local(:ex_d_alu_shift_left_amt, lit(52, width: 6) - ex_d_alu_msb, width: 6)
        ex_d_alu_norm = local(:ex_d_alu_norm, cat(lit(0, width: 32), ex_d_alu_abs) << ex_d_alu_shift_left_amt, width: 64)
        ex_d_alu_frac52 = ex_d_alu_norm[51..0]
        ex_d_alu_exp11 = local(:ex_d_alu_exp11, cat(lit(0, width: 5), ex_d_alu_msb) + lit(1023, width: 11), width: 11)
        ex_d_alu_result64 = local(:ex_d_alu_result64,
                                  mux(ex_d_alu_nonzero,
                                      cat(ex_d_alu_sign, ex_d_alu_exp11, ex_d_alu_frac52),
                                      lit(0, width: 64)),
                                  width: 64)
        ex_fp_int_result = local(:ex_fp_int_result,
                                 mux(ex_is_fcmp_s, ex_fp_cmp_result,
                                     mux(ex_is_fclass_s, ex_fp_class_result,
                                         mux(ex_is_fclass_d, ex_fp64_class_result,
                                             mux(ex_is_fcmp_d, ex_fp_cmp_d_result,
                                         mux(ex_is_fcvt_w_s, ex_fcvt_w_s_result,
                                             mux(ex_is_fcvt_wu_s, ex_fcvt_wu_s_result,
                                                 mux(ex_is_fcvt_w_d, ex_fcvt_w_d_result,
                                                     mux(ex_is_fcvt_wu_d, ex_fcvt_wu_d_result, forwarded_rs1)))))))),
                                 width: 32)
        ex_fp_result = local(:ex_fp_result,
                             mux(ex_is_fsgnj_s, ex_fsgnj_result,
                                 mux(ex_is_fminmax_s, ex_fp_minmax_result,
                                     mux(ex_is_fsgnj_d, ex_fsgnj_d_result64[31..0],
                                         mux(ex_is_fminmax_d, ex_fp64_minmax_result[31..0],
                                             mux(ex_is_d_arith, ex_d_alu_result64[31..0],
                                     mux(ex_is_fcvt_s_d, ex_fcvt_s_d_result,
                                         mux(ex_is_fcvt_d_w | ex_is_fcvt_d_wu, forwarded_rs1,
                                             mux(ex_is_fcvt_s_w | ex_is_fcvt_s_wu, ex_fcvt_s_w_result, forwarded_rs1)))))))),
                             width: 32)
        ex_fp_result_hi = local(:ex_fp_result_hi,
                                mux(ex_is_fsgnj_d, ex_fsgnj_d_result64[63..32],
                                    mux(ex_is_fminmax_d, ex_fp64_minmax_result[63..32],
                                        mux(ex_is_d_arith, ex_d_alu_result64[63..32], ex_rd_src_data))),
                                width: 32)
        ex_is_fp_int_write = local(:ex_is_fp_int_write,
                                   ex_is_fmv_x_w | ex_is_fcmp_s | ex_is_fcmp_d | ex_is_fclass_s | ex_is_fclass_d |
                                   ex_is_fcvt_w_s | ex_is_fcvt_wu_s | ex_is_fcvt_w_d | ex_is_fcvt_wu_d,
                                   width: 1)
        ex_is_fp_reg_write_op = local(:ex_is_fp_reg_write_op,
                                      ex_is_fmv_w_x | ex_is_fsgnj_s | ex_is_fminmax_s |
                                      ex_is_fsgnj_d | ex_is_fminmax_d |
                                      ex_is_fcvt_s_w | ex_is_fcvt_s_wu | ex_is_fcvt_s_d |
                                      ex_is_fcvt_d_s | ex_is_fcvt_d_w | ex_is_fcvt_d_wu | ex_is_d_arith,
                                      width: 1)

        ex_v_lane0_active = local(:ex_v_lane0_active, vec_vl > lit(0, width: 32), width: 1)
        ex_v_lane1_active = local(:ex_v_lane1_active, vec_vl > lit(1, width: 32), width: 1)
        ex_v_lane2_active = local(:ex_v_lane2_active, vec_vl > lit(2, width: 32), width: 1)
        ex_v_lane3_active = local(:ex_v_lane3_active, vec_vl > lit(3, width: 32), width: 1)
        ex_v_lane0_vadd_vv = local(:ex_v_lane0_vadd_vv, ex_v_rs2_lane0 + ex_v_rs1_lane0, width: 32)
        ex_v_lane1_vadd_vv = local(:ex_v_lane1_vadd_vv, ex_v_rs2_lane1 + ex_v_rs1_lane1, width: 32)
        ex_v_lane2_vadd_vv = local(:ex_v_lane2_vadd_vv, ex_v_rs2_lane2 + ex_v_rs1_lane2, width: 32)
        ex_v_lane3_vadd_vv = local(:ex_v_lane3_vadd_vv, ex_v_rs2_lane3 + ex_v_rs1_lane3, width: 32)
        ex_v_lane0_vadd_vx = local(:ex_v_lane0_vadd_vx, ex_v_rs2_lane0 + forwarded_rs1, width: 32)
        ex_v_lane1_vadd_vx = local(:ex_v_lane1_vadd_vx, ex_v_rs2_lane1 + forwarded_rs1, width: 32)
        ex_v_lane2_vadd_vx = local(:ex_v_lane2_vadd_vx, ex_v_rs2_lane2 + forwarded_rs1, width: 32)
        ex_v_lane3_vadd_vx = local(:ex_v_lane3_vadd_vx, ex_v_rs2_lane3 + forwarded_rs1, width: 32)
        ex_v_all_lane_write = local(:ex_v_all_lane_write, ex_is_vmv_v_x | ex_is_vadd_vv | ex_is_vadd_vx, width: 1)
        ex_v_lane0_all_next = local(:ex_v_lane0_all_next,
                                    mux(ex_is_vmv_v_x, forwarded_rs1,
                                        mux(ex_is_vadd_vv, ex_v_lane0_vadd_vv,
                                            mux(ex_is_vadd_vx, ex_v_lane0_vadd_vx, ex_v_rd_lane0))),
                                    width: 32)
        ex_v_lane1_all_next = local(:ex_v_lane1_all_next,
                                    mux(ex_is_vmv_v_x, forwarded_rs1,
                                        mux(ex_is_vadd_vv, ex_v_lane1_vadd_vv,
                                            mux(ex_is_vadd_vx, ex_v_lane1_vadd_vx, ex_v_rd_lane1))),
                                    width: 32)
        ex_v_lane2_all_next = local(:ex_v_lane2_all_next,
                                    mux(ex_is_vmv_v_x, forwarded_rs1,
                                        mux(ex_is_vadd_vv, ex_v_lane2_vadd_vv,
                                            mux(ex_is_vadd_vx, ex_v_lane2_vadd_vx, ex_v_rd_lane2))),
                                    width: 32)
        ex_v_lane3_all_next = local(:ex_v_lane3_all_next,
                                    mux(ex_is_vmv_v_x, forwarded_rs1,
                                        mux(ex_is_vadd_vv, ex_v_lane3_vadd_vv,
                                            mux(ex_is_vadd_vx, ex_v_lane3_vadd_vx, ex_v_rd_lane3))),
                                    width: 32)
        ex_v_scalar_result = local(:ex_v_scalar_result,
                                   mux(ex_is_vsetvli, ex_vsetvli_new_vl, ex_v_rs2_lane0),
                                   width: 32)

        # -----------------------------------------
        # EX Stage: CSR and SYSTEM (trap/return) path
        # -----------------------------------------
        ex_is_csr_instr = local(:ex_is_csr_instr,
                                (ex_opcode == lit(Opcode::SYSTEM, width: 7)) & (ex_funct3 != lit(0, width: 3)),
                                width: 1)
        ex_is_system_plain = local(:ex_is_system_plain,
                                   (ex_opcode == lit(Opcode::SYSTEM, width: 7)) & (ex_funct3 == lit(0, width: 3)),
                                   width: 1)
        ex_sys_imm = ex_imm[11..0]
        ex_is_ecall = local(:ex_is_ecall, ex_is_system_plain & (ex_sys_imm == lit(0x000, width: 12)), width: 1)
        ex_is_ebreak = local(:ex_is_ebreak, ex_is_system_plain & (ex_sys_imm == lit(0x001, width: 12)), width: 1)
        ex_is_sret = local(:ex_is_sret, ex_is_system_plain & (ex_sys_imm == lit(0x102, width: 12)), width: 1)
        ex_is_mret = local(:ex_is_mret, ex_is_system_plain & (ex_sys_imm == lit(0x302, width: 12)), width: 1)
        ex_is_amo_word = local(:ex_is_amo_word,
                               (ex_opcode == lit(Opcode::AMO, width: 7)) & (ex_funct3 == lit(Funct3::WORD, width: 3)),
                               width: 1)
        ex_amo_funct5 = ex_funct7[6..2]
        ex_is_lr = local(:ex_is_lr,
                         ex_is_amo_word & (ex_amo_funct5 == lit(0b00010, width: 5)) & (ex_rs2_addr == lit(0, width: 5)),
                         width: 1)
        ex_is_sc = local(:ex_is_sc, ex_is_amo_word & (ex_amo_funct5 == lit(0b00011, width: 5)), width: 1)
        ex_is_amocas = local(:ex_is_amocas, ex_is_amo_word & (ex_amo_funct5 == lit(0b00101, width: 5)), width: 1)
        ex_is_amo_rmw = local(:ex_is_amo_rmw,
                              ex_is_amo_word & (
                                (ex_amo_funct5 == lit(0b00000, width: 5)) |
                                (ex_amo_funct5 == lit(0b00001, width: 5)) |
                                (ex_amo_funct5 == lit(0b00101, width: 5)) |
                                (ex_amo_funct5 == lit(0b00100, width: 5)) |
                                (ex_amo_funct5 == lit(0b01000, width: 5)) |
                                (ex_amo_funct5 == lit(0b01100, width: 5)) |
                                (ex_amo_funct5 == lit(0b10000, width: 5)) |
                                (ex_amo_funct5 == lit(0b10100, width: 5)) |
                                (ex_amo_funct5 == lit(0b11000, width: 5)) |
                                (ex_amo_funct5 == lit(0b11100, width: 5))
                              ),
                              width: 1)
        ex_is_amo = local(:ex_is_amo, ex_is_lr | ex_is_sc | ex_is_amo_rmw, width: 1)
        ex_is_wfi = local(:ex_is_wfi, ex_is_system_plain & (ex_sys_imm == lit(0x105, width: 12)), width: 1)
        ex_is_wrs_nto = local(:ex_is_wrs_nto, ex_is_system_plain & (ex_sys_imm == lit(0x00D, width: 12)), width: 1)
        ex_is_wrs_sto = local(:ex_is_wrs_sto, ex_is_system_plain & (ex_sys_imm == lit(0x01D, width: 12)), width: 1)
        ex_is_sfence_vma = local(:ex_is_sfence_vma,
                                 ex_is_system_plain & (ex_funct7 == lit(0b0001001, width: 7)) & (ex_rd_addr == lit(0, width: 5)),
                                 width: 1)
        ex_is_illegal_system = local(:ex_is_illegal_system,
                                     ex_is_system_plain & ~(ex_is_ecall | ex_is_ebreak | ex_is_mret | ex_is_sret |
                                                            ex_is_wfi | ex_is_wrs_nto | ex_is_wrs_sto | ex_is_sfence_vma),
                                     width: 1)
        # Hardware interrupt pending bits at RISC-V standard positions.
        # External timer input is mirrored to both MTIP (bit 7) and STIP (bit 5):
        # - MTIP keeps M-mode timer semantics for xv6/machine-mode paths.
        # - STIP allows S-mode Linux timer delivery through mideleg/sie.
        # Software-writable SSIP (bit 1) is merged from CSR store (SIP register).
        ex_irq_pending_bits = local(:ex_irq_pending_bits,
                                    (csr_read_data13 & lit(0x2, width: 32)) |
                                    mux(irq_software, lit(0x8, width: 32), lit(0, width: 32)) |
                                    mux(irq_timer, lit(0xA0, width: 32), lit(0, width: 32)) |
                                    mux(irq_external, lit(0x200, width: 32), lit(0, width: 32)),
                                    width: 32)
        ex_csr_src = local(:ex_csr_src,
                           mux(ex_funct3[2], cat(lit(0, width: 27), ex_rs1_addr), forwarded_rs1),
                           width: 32)
        ex_csr_rs1_nonzero = local(:ex_csr_rs1_nonzero, ex_rs1_addr != lit(0, width: 5), width: 1)
        ex_data_vaddr = local(:ex_data_vaddr, mux(ex_is_amo, forwarded_rs1, alu_result), width: 32)
        ex_data_access_req = local(:ex_data_access_req, ex_mem_read | ex_mem_write | ex_is_amo, width: 1)
        ex_data_store_access = local(:ex_data_store_access, ex_mem_write | ex_is_sc | ex_is_amo_rmw, width: 1)

        # Sv32 data translation (page-table entries are supplied through dedicated inputs).
        ex_satp_mode_sv32 = local(:ex_satp_mode_sv32, csr_read_data8[31], width: 1)
        ex_priv_is_u = local(:ex_priv_is_u, priv_mode == lit(PrivMode::USER, width: 2), width: 1)
        ex_priv_is_s = local(:ex_priv_is_s, priv_mode == lit(PrivMode::SUPERVISOR, width: 2), width: 1)
        ex_priv_is_m = local(:ex_priv_is_m, priv_mode == lit(PrivMode::MACHINE, width: 2), width: 1)
        ex_delegate_allowed = local(:ex_delegate_allowed, lit(1, width: 1), width: 1)
        ex_satp_translate = local(:ex_satp_translate, ex_satp_mode_sv32 & ~ex_priv_is_m, width: 1)
        ex_sum_enabled = local(:ex_sum_enabled,
                               (((csr_read_data2 | csr_read_data4) & lit(0x40000, width: 32)) != lit(0, width: 32)),
                               width: 1)
        ex_mxr_enabled = local(:ex_mxr_enabled,
                               (((csr_read_data2 | csr_read_data4) & lit(0x80000, width: 32)) != lit(0, width: 32)),
                               width: 1)
        ex_satp_root_ppn = csr_read_data8[19..0]
        ex_satp_root_base = local(:ex_satp_root_base, cat(ex_satp_root_ppn, lit(0, width: 12)), width: 32)
        ex_data_vpn = ex_data_vaddr[31..12]
        ex_data_vpn1 = ex_data_vaddr[31..22]
        ex_data_vpn0 = ex_data_vaddr[21..12]
        ex_data_page_off = ex_data_vaddr[11..0]
        data_tlb_lookup_en <= ex_satp_translate & ex_data_access_req
        data_tlb_lookup_vpn <= ex_data_vpn
        data_tlb_lookup_root <= ex_satp_root_ppn
        ex_data_ptw_addr1_calc = local(:ex_data_ptw_addr1_calc,
                                       ex_satp_root_base + cat(lit(0, width: 20), ex_data_vpn1, lit(0, width: 2)),
                                       width: 32)
        ex_data_l0_base = local(:ex_data_l0_base, cat(data_ptw_pte1[29..10], lit(0, width: 12)), width: 32)
        ex_data_ptw_addr0_calc = local(:ex_data_ptw_addr0_calc,
                                       ex_data_l0_base + cat(lit(0, width: 20), ex_data_vpn0, lit(0, width: 2)),
                                       width: 32)
        ex_data_pte1_leaf = local(:ex_data_pte1_leaf,
                                  data_ptw_pte1[0] & (data_ptw_pte1[1] | data_ptw_pte1[3]),
                                  width: 1)
        ex_data_pte1_next = local(:ex_data_pte1_next,
                                  data_ptw_pte1[0] & ~(data_ptw_pte1[1] | data_ptw_pte1[3]),
                                  width: 1)
        ex_data_pte0_leaf = local(:ex_data_pte0_leaf,
                                  ex_data_pte1_next & data_ptw_pte0[0] & (data_ptw_pte0[1] | data_ptw_pte0[3]),
                                  width: 1)
        ex_data_walk_ok = local(:ex_data_walk_ok, ex_data_pte1_leaf | ex_data_pte0_leaf, width: 1)
        ex_data_walk_pte = local(:ex_data_walk_pte, mux(ex_data_pte1_leaf, data_ptw_pte1, data_ptw_pte0), width: 32)
        ex_data_walk_ppn = local(:ex_data_walk_ppn,
                                 mux(ex_data_pte1_leaf, cat(data_ptw_pte1[29..20], ex_data_vpn0), data_ptw_pte0[29..10]),
                                 width: 20)
        ex_data_walk_perm_r = ex_data_walk_pte[1]
        ex_data_walk_perm_w = ex_data_walk_pte[2]
        ex_data_walk_perm_x = ex_data_walk_pte[3]
        ex_data_walk_perm_u = ex_data_walk_pte[4]
        data_tlb_fill_en <= ex_satp_translate & ex_data_access_req & ~data_tlb_hit & ex_data_walk_ok
        data_tlb_fill_vpn <= ex_data_vpn
        data_tlb_fill_root <= ex_satp_root_ppn
        data_tlb_fill_ppn <= ex_data_walk_ppn
        data_tlb_fill_perm_r <= ex_data_walk_perm_r
        data_tlb_fill_perm_w <= ex_data_walk_perm_w
        data_tlb_fill_perm_x <= ex_data_walk_perm_x
        data_tlb_fill_perm_u <= ex_data_walk_perm_u
        ex_data_translated = local(:ex_data_translated, data_tlb_hit | ex_data_walk_ok, width: 1)
        ex_data_eff_ppn = local(:ex_data_eff_ppn, mux(data_tlb_hit, data_tlb_ppn, ex_data_walk_ppn), width: 20)
        ex_data_eff_perm_r = local(:ex_data_eff_perm_r, mux(data_tlb_hit, data_tlb_perm_r, ex_data_walk_perm_r), width: 1)
        ex_data_eff_perm_w = local(:ex_data_eff_perm_w, mux(data_tlb_hit, data_tlb_perm_w, ex_data_walk_perm_w), width: 1)
        ex_data_eff_perm_x = local(:ex_data_eff_perm_x, mux(data_tlb_hit, data_tlb_perm_x, ex_data_walk_perm_x), width: 1)
        ex_data_eff_perm_u = local(:ex_data_eff_perm_u, mux(data_tlb_hit, data_tlb_perm_u, ex_data_walk_perm_u), width: 1)
        ex_data_need_read = local(:ex_data_need_read, ex_mem_read | ex_is_lr | ex_is_amo_rmw, width: 1)
        ex_data_need_write = local(:ex_data_need_write, ex_mem_write | ex_is_sc | ex_is_amo_rmw, width: 1)
        ex_data_read_ok = local(:ex_data_read_ok, ex_data_eff_perm_r | (ex_mxr_enabled & ex_data_eff_perm_x), width: 1)
        ex_data_write_ok = local(:ex_data_write_ok, ex_data_eff_perm_w, width: 1)
        ex_data_rw_ok = local(:ex_data_rw_ok,
                              (~ex_data_need_read | ex_data_read_ok) & (~ex_data_need_write | ex_data_write_ok),
                              width: 1)
        ex_data_u_ok = local(:ex_data_u_ok,
                             mux(ex_priv_is_u, ex_data_eff_perm_u,
                                 mux(ex_priv_is_s, mux(ex_data_eff_perm_u, ex_sum_enabled, lit(1, width: 1)), lit(1, width: 1))),
                             width: 1)
        ex_data_perm_ok = local(:ex_data_perm_ok, ex_data_translated & ex_data_rw_ok & ex_data_u_ok, width: 1)
        ex_data_paddr = local(:ex_data_paddr, cat(ex_data_eff_ppn, ex_data_page_off), width: 32)
        ex_data_page_fault = local(:ex_data_page_fault,
                                   ex_satp_translate & ex_data_access_req & ~ex_data_perm_ok,
                                   width: 1)
        ex_data_page_fault_cause = local(:ex_data_page_fault_cause,
                                         mux(ex_data_store_access, lit(15, width: 32), lit(13, width: 32)),
                                         width: 32)

        # Per RISC-V spec, machine-level interrupt bits (MSIP=3, MTIP=7, MEIP=11) are
        # not delegable to S-mode. Mask them out of mideleg (csr_read_data7).
        ex_effective_mideleg = local(:ex_effective_mideleg, csr_read_data7 & lit(0xFFFFF777, width: 32), width: 32)
        ex_machine_irq_masked = local(:ex_machine_irq_masked, ex_irq_pending_bits & ~ex_effective_mideleg, width: 32)
        ex_super_irq_masked = local(:ex_super_irq_masked, ex_irq_pending_bits & ex_effective_mideleg, width: 32)
        ex_super_sie_machine_alias = local(
          :ex_super_sie_machine_alias,
          mux((csr_read_data5 & lit(0x002, width: 32)) != lit(0, width: 32), lit(0x008, width: 32), lit(0, width: 32)) |
          mux((csr_read_data5 & lit(0x020, width: 32)) != lit(0, width: 32), lit(0x080, width: 32), lit(0, width: 32)) |
          mux((csr_read_data5 & lit(0x200, width: 32)) != lit(0, width: 32), lit(0x800, width: 32), lit(0, width: 32)),
          width: 32
        )
        ex_super_sie_effective = local(:ex_super_sie_effective, csr_read_data5 | ex_super_sie_machine_alias, width: 32)
        ex_machine_enabled_interrupts = local(:ex_machine_enabled_interrupts, ex_machine_irq_masked & csr_read_data3, width: 32)
        ex_super_enabled_interrupts = local(:ex_super_enabled_interrupts, ex_super_irq_masked & ex_super_sie_effective, width: 32)
        ex_global_mie_enabled = local(:ex_global_mie_enabled,
                                      (csr_read_data2 & lit(0x8, width: 32)) != lit(0, width: 32),
                                      width: 1)
        ex_global_sie_enabled = local(:ex_global_sie_enabled,
                                      (csr_read_data4 & lit(0x2, width: 32)) != lit(0, width: 32),
                                      width: 1)
        # RISC-V spec: M-mode interrupts globally enabled when priv < M or (priv == M and MIE)
        ex_machine_globally_enabled = local(:ex_machine_globally_enabled,
                                            ~ex_priv_is_m | ex_global_mie_enabled,
                                            width: 1)
        # RISC-V spec: S-mode interrupts globally enabled when priv < S or (priv == S and SIE)
        ex_super_globally_enabled = local(:ex_super_globally_enabled,
                                          ex_priv_is_u | (ex_priv_is_s & ex_global_sie_enabled),
                                          width: 1)
        ex_machine_interrupt_pending = local(:ex_machine_interrupt_pending,
                                             ex_machine_globally_enabled & (ex_machine_enabled_interrupts != lit(0, width: 32)),
                                             width: 1)
        ex_super_interrupt_pending = local(:ex_super_interrupt_pending,
                                           ex_delegate_allowed & ex_super_globally_enabled &
                                           (ex_super_enabled_interrupts != lit(0, width: 32)),
                                           width: 1)
        # Detect pipeline bubble in EX (flushed ID/EX sets opcode to 0, which is not a valid RISC-V opcode).
        # Async interrupts must only be taken when EX holds a valid instruction so that ex_pc
        # correctly represents the interrupted instruction for mepc/sepc.
        ex_is_bubble = local(:ex_is_bubble, ex_opcode == lit(0, width: 7), width: 1)
        ex_interrupt_pending = local(:ex_interrupt_pending,
                                     (ex_machine_interrupt_pending | ex_super_interrupt_pending) & ~ex_is_bubble,
                                     width: 1)
        ex_interrupt_from_supervisor = local(:ex_interrupt_from_supervisor,
                                             ex_delegate_allowed & ex_super_interrupt_pending &
                                             ~ex_machine_interrupt_pending,
                                             width: 1)
        ex_selected_interrupts = local(:ex_selected_interrupts,
                                       mux(ex_machine_interrupt_pending, ex_machine_enabled_interrupts, ex_super_enabled_interrupts),
                                       width: 32)

        ex_sync_trap_taken = local(:ex_sync_trap_taken,
                                   ex_is_ecall | ex_is_ebreak | ex_is_illegal_system |
                                   ex_inst_page_fault | ex_data_page_fault,
                                   width: 1)
        ex_ecall_cause = local(:ex_ecall_cause,
                               mux(ex_priv_is_u, lit(8, width: 32),
                                   mux(ex_priv_is_s, lit(9, width: 32), lit(11, width: 32))),
                               width: 32)
        ex_ecall_deleg_mask = local(:ex_ecall_deleg_mask,
                                    mux(ex_priv_is_u, lit(0x100, width: 32),
                                        mux(ex_priv_is_s, lit(0x200, width: 32), lit(0x800, width: 32))),
                                    width: 32)
        ex_ecall_delegated = local(:ex_ecall_delegated,
                                   (csr_read_data6 & ex_ecall_deleg_mask) != lit(0, width: 32),
                                   width: 1)
        ex_ebreak_delegated = local(:ex_ebreak_delegated,
                                    (csr_read_data6 & lit(0x8, width: 32)) != lit(0, width: 32),
                                    width: 1)
        ex_illegal_delegated = local(:ex_illegal_delegated,
                                     (csr_read_data6 & lit(0x4, width: 32)) != lit(0, width: 32),
                                     width: 1)
        ex_inst_page_fault_delegated = local(:ex_inst_page_fault_delegated,
                                             (csr_read_data6 & lit(0x1000, width: 32)) != lit(0, width: 32),
                                             width: 1)
        ex_load_page_fault_delegated = local(:ex_load_page_fault_delegated,
                                             (csr_read_data6 & lit(0x2000, width: 32)) != lit(0, width: 32),
                                             width: 1)
        ex_store_page_fault_delegated = local(:ex_store_page_fault_delegated,
                                              (csr_read_data6 & lit(0x8000, width: 32)) != lit(0, width: 32),
                                              width: 1)
        ex_data_page_fault_delegated = local(:ex_data_page_fault_delegated,
                                             mux(ex_data_store_access, ex_store_page_fault_delegated, ex_load_page_fault_delegated),
                                             width: 1)
        ex_sync_trap_delegated = local(:ex_sync_trap_delegated,
                                       ex_delegate_allowed &
                                       mux(ex_inst_page_fault, ex_inst_page_fault_delegated,
                                           mux(ex_data_page_fault, ex_data_page_fault_delegated,
                                               mux(ex_is_ecall, ex_ecall_delegated,
                                                   mux(ex_is_ebreak, ex_ebreak_delegated, ex_illegal_delegated)))),
                                       width: 1)
        ex_trap_to_supervisor = local(:ex_trap_to_supervisor,
                                      (ex_sync_trap_taken & ex_sync_trap_delegated) | ex_interrupt_from_supervisor,
                                      width: 1)
        ex_trap_taken = local(:ex_trap_taken, ex_sync_trap_taken | ex_interrupt_pending, width: 1)
        # Unified interrupt cause: the cause code encodes the interrupt type (bit position),
        # not which privilege mode handles it. Priority: highest bit first.
        ex_interrupt_cause = local(:ex_interrupt_cause,
                                   mux((ex_selected_interrupts & lit(0x800, width: 32)) != lit(0, width: 32),
                                       lit(0x8000000B, width: 32), # cause 11: machine external (MEIP, bit 11)
                                       mux((ex_selected_interrupts & lit(0x200, width: 32)) != lit(0, width: 32),
                                           lit(0x80000009, width: 32), # cause 9: supervisor external (SEIP, bit 9)
                                           mux((ex_selected_interrupts & lit(0x080, width: 32)) != lit(0, width: 32),
                                               lit(0x80000007, width: 32), # cause 7: machine timer (MTIP, bit 7)
                                               mux((ex_selected_interrupts & lit(0x020, width: 32)) != lit(0, width: 32),
                                                   lit(0x80000005, width: 32), # cause 5: supervisor timer (STIP, bit 5)
                                                   mux((ex_selected_interrupts & lit(0x008, width: 32)) != lit(0, width: 32),
                                                       lit(0x80000003, width: 32), # cause 3: machine software (MSIP, bit 3)
                                                       lit(0x80000001, width: 32)))))), # cause 1: supervisor software (SSIP, bit 1)
                                   width: 32)
        ex_trap_cause = local(:ex_trap_cause,
                              mux(ex_interrupt_pending,
                                  ex_interrupt_cause,
                                  mux(ex_inst_page_fault,
                                      lit(12, width: 32),
                                      mux(ex_data_page_fault,
                                          ex_data_page_fault_cause,
                                          mux(ex_is_illegal_system,
                                              lit(2, width: 32),
                                              mux(ex_is_ebreak, lit(3, width: 32), ex_ecall_cause))))),
                              width: 32)
        ex_trap_epc = local(:ex_trap_epc, ex_pc, width: 32)
        ex_inst_word = local(:ex_inst_word,
                             cat(ex_funct7, ex_rs2_addr, ex_rs1_addr, ex_funct3, ex_rd_addr, ex_opcode),
                             width: 32)
        ex_trap_tval = local(:ex_trap_tval,
                             mux(ex_inst_page_fault, ex_pc,
                                 mux(ex_data_page_fault, ex_data_vaddr,
                                     mux(ex_is_illegal_system, ex_inst_word, lit(0, width: 32)))),
                             width: 32)
        ex_old_mie_to_mpie = local(:ex_old_mie_to_mpie,
                                   mux((csr_read_data2 & lit(0x8, width: 32)) == lit(0, width: 32),
                                       lit(0, width: 32),
                                       lit(0x80, width: 32)),
                                   width: 32)
        ex_old_mpie_to_mie = local(:ex_old_mpie_to_mie,
                                   mux((csr_read_data2 & lit(0x80, width: 32)) == lit(0, width: 32),
                                       lit(0, width: 32),
                                       lit(0x8, width: 32)),
                                   width: 32)
        ex_trap_mpp = local(:ex_trap_mpp,
                            mux(priv_mode == lit(PrivMode::MACHINE, width: 2),
                                lit(0x1800, width: 32),
                                mux(priv_mode == lit(PrivMode::SUPERVISOR, width: 2),
                                    lit(0x800, width: 32),
                                    lit(0, width: 32))),
                            width: 32)
        ex_trap_mstatus = local(:ex_trap_mstatus,
                                (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                                ex_old_mie_to_mpie |
                                ex_trap_mpp,
                                width: 32)
        ex_mret_mstatus = local(:ex_mret_mstatus,
                                (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                                ex_old_mpie_to_mie |
                                lit(0x80, width: 32),
                                width: 32)

        ex_old_sie_to_spie = local(:ex_old_sie_to_spie,
                                   mux((csr_read_data4 & lit(0x2, width: 32)) == lit(0, width: 32),
                                       lit(0, width: 32),
                                       lit(0x20, width: 32)),
                                   width: 32)
        ex_old_spie_to_sie = local(:ex_old_spie_to_sie,
                                   mux((csr_read_data4 & lit(0x20, width: 32)) == lit(0, width: 32),
                                       lit(0, width: 32),
                                       lit(0x2, width: 32)),
                                   width: 32)
        ex_trap_spp = local(:ex_trap_spp,
                            mux(priv_mode == lit(PrivMode::USER, width: 2),
                                lit(0, width: 32),
                                lit(0x100, width: 32)),
                            width: 32)
        ex_trap_sstatus = local(:ex_trap_sstatus,
                                (csr_read_data4 & lit(0xFFFFFEDD, width: 32)) |
                                ex_old_sie_to_spie |
                                ex_trap_spp,
                                width: 32)
        ex_sret_sstatus = local(:ex_sret_sstatus,
                                (csr_read_data4 & lit(0xFFFFFEDD, width: 32)) |
                                ex_old_spie_to_sie |
                                lit(0x20, width: 32),
                                width: 32)
        ex_mret_target_mode = local(:ex_mret_target_mode, csr_read_data2[12..11], width: 2)
        ex_sret_target_mode = local(:ex_sret_target_mode,
                                    mux((csr_read_data4 & lit(0x100, width: 32)) == lit(0, width: 32),
                                        lit(PrivMode::USER, width: 2),
                                        lit(PrivMode::SUPERVISOR, width: 2)),
                                    width: 2)
        ex_trap_target_mode = local(:ex_trap_target_mode,
                                    mux(ex_trap_to_supervisor, lit(PrivMode::SUPERVISOR, width: 2),
                                        lit(PrivMode::MACHINE, width: 2)),
                                    width: 2)
        ex_ret_target_mode = local(:ex_ret_target_mode,
                                   mux(ex_is_mret, ex_mret_target_mode, ex_sret_target_mode),
                                   width: 2)
        ex_trap_or_ret = local(:ex_trap_or_ret, ex_trap_taken | ex_is_mret | ex_is_sret, width: 1)
        ex_reg_write_effective = local(:ex_reg_write_effective,
                                       (ex_reg_write | ex_is_amo | ex_is_vsetvli | ex_is_vmv_x_s | ex_is_fp_int_write) & ~ex_trap_taken,
                                       width: 1)
        ex_mem_read_effective = local(:ex_mem_read_effective, (ex_mem_read | ex_is_lr | ex_is_amo_rmw) & ~ex_trap_taken, width: 1)
        ex_mem_write_effective = local(:ex_mem_write_effective, ex_mem_write & ~ex_trap_taken, width: 1)

        csr_read_addr <= mux(ex_trap_taken, mux(ex_trap_to_supervisor, lit(0x105, width: 12), lit(0x305, width: 12)),
                             mux(ex_is_mret, lit(0x341, width: 12),
                                 mux(ex_is_sret, lit(0x141, width: 12), ex_imm[11..0])))
        csr_read_addr2 <= lit(0x300, width: 12) # mstatus
        csr_read_addr3 <= lit(0x304, width: 12) # mie
        csr_read_addr4 <= lit(0x100, width: 12) # sstatus
        csr_read_addr5 <= lit(0x104, width: 12) # sie
        csr_read_addr6 <= lit(0x302, width: 12) # medeleg
        csr_read_addr7 <= lit(0x303, width: 12) # mideleg
        csr_read_addr8 <= lit(0x180, width: 12) # satp
        csr_read_addr9 <= lit(0x305, width: 12) # mtvec
        csr_read_addr10 <= lit(0x105, width: 12) # stvec
        csr_read_addr11 <= lit(0x341, width: 12) # mepc
        csr_read_addr12 <= lit(0x141, width: 12) # sepc
        csr_read_addr13 <= lit(0x144, width: 12) # sip (for software SSIP readback)
        ex_csr_read_selected = local(:ex_csr_read_selected,
                                     mux(csr_read_addr == lit(0xC20, width: 12), vec_vl,
                                         mux(csr_read_addr == lit(0xC21, width: 12), vec_vtype,
                                             mux(csr_read_addr == lit(0x344, width: 12), ex_irq_pending_bits,
                                                 mux(csr_read_addr == lit(0x144, width: 12), ex_irq_pending_bits & ex_effective_mideleg, csr_read_data)))),
                                     width: 32)
        ex_csr_write_data = local(:ex_csr_write_data, case_select(ex_funct3, {
          0b001 => ex_csr_src,                  # CSRRW
          0b010 => ex_csr_read_selected | ex_csr_src,  # CSRRS
          0b011 => ex_csr_read_selected & ~ex_csr_src, # CSRRC
          0b101 => ex_csr_src,                  # CSRRWI
          0b110 => ex_csr_read_selected | ex_csr_src,  # CSRRSI
          0b111 => ex_csr_read_selected & ~ex_csr_src  # CSRRCI
        }, default: ex_csr_read_selected), width: 32)
        ex_csr_write_we = local(:ex_csr_write_we, ex_is_csr_instr & case_select(ex_funct3, {
          0b001 => lit(1, width: 1),   # CSRRW
          0b010 => ex_csr_rs1_nonzero, # CSRRS
          0b011 => ex_csr_rs1_nonzero, # CSRRC
          0b101 => lit(1, width: 1),   # CSRRWI
          0b110 => ex_csr_rs1_nonzero, # CSRRSI (zimm != 0)
          0b111 => ex_csr_rs1_nonzero  # CSRRCI (zimm != 0)
        }, default: lit(0, width: 1)), width: 1)
        ex_is_vl_csr_instr = local(:ex_is_vl_csr_instr,
                                   ex_is_csr_instr & (ex_imm[11..0] == lit(0xC20, width: 12)),
                                   width: 1)
        ex_is_vtype_csr_instr = local(:ex_is_vtype_csr_instr,
                                      ex_is_csr_instr & (ex_imm[11..0] == lit(0xC21, width: 12)),
                                      width: 1)
        ex_is_vector_csr_instr = local(:ex_is_vector_csr_instr,
                                       ex_is_vl_csr_instr | ex_is_vtype_csr_instr,
                                       width: 1)
        ex_satp_write = local(:ex_satp_write,
                              ex_is_csr_instr & ex_csr_write_we & (ex_imm[11..0] == lit(0x180, width: 12)),
                              width: 1)
        tlb_flush_all <= ex_is_sfence_vma | ex_satp_write
        csr_write_addr <= mux(ex_trap_taken, mux(ex_trap_to_supervisor, lit(0x141, width: 12), lit(0x341, width: 12)),
                              mux(ex_is_mret, lit(0x300, width: 12),
                                  mux(ex_is_sret, lit(0x100, width: 12), ex_imm[11..0])))
        csr_write_data <= mux(ex_trap_taken, ex_trap_epc,
                              mux(ex_is_mret, ex_mret_mstatus,
                                  mux(ex_is_sret, ex_sret_sstatus, ex_csr_write_data)))
        csr_write_we <= mux(ex_trap_or_ret, lit(1, width: 1), ex_csr_write_we & ~ex_is_vector_csr_instr)
        csr_write_addr2 <= mux(ex_trap_to_supervisor, lit(0x142, width: 12), lit(0x342, width: 12))
        csr_write_data2 <= ex_trap_cause
        csr_write_we2 <= ex_trap_taken
        csr_write_addr3 <= mux(ex_trap_to_supervisor, lit(0x100, width: 12), lit(0x300, width: 12))
        csr_write_data3 <= mux(ex_trap_to_supervisor, ex_trap_sstatus, ex_trap_mstatus)
        csr_write_we3 <= ex_trap_taken
        csr_write_addr4 <= mux(ex_trap_to_supervisor, lit(0x143, width: 12), lit(0x343, width: 12))
        csr_write_data4 <= ex_trap_tval
        csr_write_we4 <= ex_trap_taken
        vec_vl_write_data <= mux(ex_is_vsetvli, ex_vsetvli_new_vl, ex_csr_write_data)
        vec_vtype_write_data <= mux(ex_is_vsetvli, ex_vsetvli_new_vtype, ex_csr_write_data)
        vec_vl_write_we <= (ex_is_vsetvli | (ex_is_vl_csr_instr & ex_csr_write_we)) & ~ex_trap_taken
        vec_vtype_write_we <= (ex_is_vsetvli | (ex_is_vtype_csr_instr & ex_csr_write_we)) & ~ex_trap_taken
        priv_mode_we <= ex_trap_taken | ex_is_mret | ex_is_sret
        priv_mode_next <= mux(ex_trap_taken, ex_trap_target_mode, ex_ret_target_mode)
        data_ptw_addr1 <= ex_data_ptw_addr1_calc
        data_ptw_addr0 <= ex_data_ptw_addr0_calc
        ex_v_rd_lane0_in <= mux(ex_is_vmv_s_x, forwarded_rs1,
                                mux(ex_v_all_lane_write & ex_v_lane0_active, ex_v_lane0_all_next, ex_v_rd_lane0))
        ex_v_rd_lane1_in <= mux(ex_v_all_lane_write & ex_v_lane1_active, ex_v_lane1_all_next, ex_v_rd_lane1)
        ex_v_rd_lane2_in <= mux(ex_v_all_lane_write & ex_v_lane2_active, ex_v_lane2_all_next, ex_v_rd_lane2)
        ex_v_rd_lane3_in <= mux(ex_v_all_lane_write & ex_v_lane3_active, ex_v_lane3_all_next, ex_v_rd_lane3)
        ex_v_rd_we <= (ex_v_all_lane_write | ex_is_vmv_s_x) & ~ex_trap_taken
        ex_mem_addr = local(:ex_mem_addr,
                            mux(ex_satp_translate & ex_data_access_req, ex_data_paddr, alu_result),
                            width: 32)
        ex_amo_addr = local(:ex_amo_addr,
                            mux(ex_satp_translate & ex_data_access_req, ex_data_paddr, forwarded_rs1),
                            width: 32)
        ex_result <= mux(ex_is_amo, ex_amo_addr,
                         mux(ex_is_vsetvli | ex_is_vmv_x_s, ex_v_scalar_result,
                         mux(ex_is_csr_instr, ex_csr_read_selected,
                            mux(ex_is_fp_int_write, ex_fp_int_result,
                                mux(ex_is_fp_reg_write_op, ex_fp_result, ex_mem_addr)))))

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
        ex_trap_vector = local(:ex_trap_vector,
                               mux(ex_trap_to_supervisor, csr_read_data10, csr_read_data9),
                               width: 32)
        ex_ret_vector = local(:ex_ret_vector,
                              mux(ex_is_mret, csr_read_data11, csr_read_data12),
                              width: 32)
        trap_target <= ex_trap_vector & lit(0xFFFFFFFC, width: 32)
        mret_target <= ex_ret_vector
        control_target <= mux(ex_trap_taken, trap_target,
                              mux(ex_is_mret | ex_is_sret, mret_target, jump_target))

        # Branch taken = branch instruction AND condition met
        take_branch <= (branch_cond_taken & ex_branch) | ex_jump | ex_trap_taken | ex_is_mret | ex_is_sret

        # -----------------------------------------
        # EX/MEM Register inputs (latch wires)
        # -----------------------------------------
        ex_mem_alu_result_in <= ex_result
        ex_mem_rs2_data_in <= forwarded_rs2
        ex_mem_rd_src_data_in <= mux(ex_is_fsgnj_d | ex_is_fminmax_d | ex_is_d_arith, ex_fp_result_hi, forwarded_rd_src)
        ex_mem_rd_addr_in <= ex_rd_addr
        ex_mem_pc_plus4_in <= ex_pc_plus4
        ex_mem_funct3_in <= ex_funct3
        ex_mem_funct7_in <= ex_funct7
        ex_mem_opcode_in <= ex_opcode
        ex_mem_rs2_addr_in <= ex_rs2_addr
        ex_mem_reg_write_in <= ex_reg_write_effective
        ex_mem_mem_read_in <= ex_mem_read_effective
        ex_mem_mem_write_in <= ex_mem_write_effective
        ex_mem_mem_to_reg_in <= ex_mem_to_reg
        ex_mem_jump_in <= ex_jump

        # -----------------------------------------
        # MEM Stage: Memory interface outputs
        # -----------------------------------------
        mem_is_amo_word = local(:mem_is_amo_word,
                                (mem_opcode == lit(Opcode::AMO, width: 7)) & (mem_funct3 == lit(Funct3::WORD, width: 3)),
                                width: 1)
        mem_amo_funct5 = mem_funct7[6..2]
        mem_is_lr = local(:mem_is_lr,
                          mem_is_amo_word & (mem_amo_funct5 == lit(0b00010, width: 5)) & (mem_rs2_addr == lit(0, width: 5)),
                          width: 1)
        mem_is_sc = local(:mem_is_sc, mem_is_amo_word & (mem_amo_funct5 == lit(0b00011, width: 5)), width: 1)
        mem_is_amocas = local(:mem_is_amocas, mem_is_amo_word & (mem_amo_funct5 == lit(0b00101, width: 5)), width: 1)
        mem_is_amo_rmw = local(:mem_is_amo_rmw,
                               mem_is_amo_word & (
                                 (mem_amo_funct5 == lit(0b00000, width: 5)) |
                                 (mem_amo_funct5 == lit(0b00001, width: 5)) |
                                 (mem_amo_funct5 == lit(0b00101, width: 5)) |
                                 (mem_amo_funct5 == lit(0b00100, width: 5)) |
                                 (mem_amo_funct5 == lit(0b01000, width: 5)) |
                                 (mem_amo_funct5 == lit(0b01100, width: 5)) |
                                 (mem_amo_funct5 == lit(0b10000, width: 5)) |
                                 (mem_amo_funct5 == lit(0b10100, width: 5)) |
                                 (mem_amo_funct5 == lit(0b11000, width: 5)) |
                                 (mem_amo_funct5 == lit(0b11100, width: 5))
                               ),
                               width: 1)
        mem_is_amo = local(:mem_is_amo, mem_is_lr | mem_is_sc | mem_is_amo_rmw, width: 1)
        mem_is_fp_load = local(:mem_is_fp_load,
                               (mem_opcode == lit(Opcode::LOAD_FP, width: 7)) &
                               ((mem_funct3 == lit(Funct3::WORD, width: 3)) | (mem_funct3 == lit(Funct3::DOUBLE, width: 3))),
                               width: 1)
        mem_is_fmv_w_x = local(:mem_is_fmv_w_x,
                               (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (mem_funct7 == lit(0b1111000, width: 7)) &
                               (mem_funct3 == lit(0, width: 3)) &
                               (mem_rs2_addr == lit(0, width: 5)),
                               width: 1)
        mem_is_fsgnj_s = local(:mem_is_fsgnj_s,
                               (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (mem_funct7 == lit(0b0010000, width: 7)),
                               width: 1)
        mem_is_fsgnj_d = local(:mem_is_fsgnj_d,
                               (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (mem_funct7 == lit(0b0010001, width: 7)),
                               width: 1)
        mem_is_fminmax_s = local(:mem_is_fminmax_s,
                                 (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                 (mem_funct7 == lit(0b0010100, width: 7)),
                                 width: 1)
        mem_is_fminmax_d = local(:mem_is_fminmax_d,
                                 (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                 (mem_funct7 == lit(0b0010101, width: 7)),
                                 width: 1)
        mem_is_fadd_d = local(:mem_is_fadd_d,
                              (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (mem_funct7 == lit(0b0000001, width: 7)),
                              width: 1)
        mem_is_fsub_d = local(:mem_is_fsub_d,
                              (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (mem_funct7 == lit(0b0000101, width: 7)),
                              width: 1)
        mem_is_fmul_d = local(:mem_is_fmul_d,
                              (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (mem_funct7 == lit(0b0001001, width: 7)),
                              width: 1)
        mem_is_fdiv_d = local(:mem_is_fdiv_d,
                              (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                              (mem_funct7 == lit(0b0001101, width: 7)),
                              width: 1)
        mem_is_fsqrt_d = local(:mem_is_fsqrt_d,
                               (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                               (mem_funct7 == lit(0b0101101, width: 7)) &
                               (mem_rs2_addr == lit(0, width: 5)),
                               width: 1)
        mem_is_fmadd_d = local(:mem_is_fmadd_d,
                               (mem_opcode == lit(Opcode::MADD, width: 7)) &
                               (mem_funct7[1..0] == lit(0b01, width: 2)),
                               width: 1)
        mem_is_fmsub_d = local(:mem_is_fmsub_d,
                               (mem_opcode == lit(Opcode::MSUB, width: 7)) &
                               (mem_funct7[1..0] == lit(0b01, width: 2)),
                               width: 1)
        mem_is_fnmsub_d = local(:mem_is_fnmsub_d,
                                (mem_opcode == lit(Opcode::NMSUB, width: 7)) &
                                (mem_funct7[1..0] == lit(0b01, width: 2)),
                                width: 1)
        mem_is_fnmadd_d = local(:mem_is_fnmadd_d,
                                (mem_opcode == lit(Opcode::NMADD, width: 7)) &
                                (mem_funct7[1..0] == lit(0b01, width: 2)),
                                width: 1)
        mem_is_d_arith = local(:mem_is_d_arith,
                               mem_is_fadd_d | mem_is_fsub_d | mem_is_fmul_d | mem_is_fdiv_d | mem_is_fsqrt_d |
                               mem_is_fmadd_d | mem_is_fmsub_d | mem_is_fnmsub_d | mem_is_fnmadd_d,
                               width: 1)
        mem_is_fcvt_s_d = local(:mem_is_fcvt_s_d,
                                (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (mem_funct7 == lit(0b0100000, width: 7)) &
                                (mem_rs2_addr == lit(0b00001, width: 5)),
                                width: 1)
        mem_is_fcvt_s_w = local(:mem_is_fcvt_s_w,
                                (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (mem_funct7 == lit(0b1101000, width: 7)) &
                                (mem_rs2_addr == lit(0b00000, width: 5)),
                                width: 1)
        mem_is_fcvt_s_wu = local(:mem_is_fcvt_s_wu,
                                 (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                 (mem_funct7 == lit(0b1101000, width: 7)) &
                                 (mem_rs2_addr == lit(0b00001, width: 5)),
                                 width: 1)
        mem_is_fcvt_d_s = local(:mem_is_fcvt_d_s,
                                (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (mem_funct7 == lit(0b0100001, width: 7)) &
                                (mem_rs2_addr == lit(0b00000, width: 5)),
                                width: 1)
        mem_is_fcvt_d_w = local(:mem_is_fcvt_d_w,
                                (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                (mem_funct7 == lit(0b1101001, width: 7)) &
                                (mem_rs2_addr == lit(0b00000, width: 5)),
                                width: 1)
        mem_is_fcvt_d_wu = local(:mem_is_fcvt_d_wu,
                                 (mem_opcode == lit(Opcode::OP_FP, width: 7)) &
                                 (mem_funct7 == lit(0b1101001, width: 7)) &
                                 (mem_rs2_addr == lit(0b00001, width: 5)),
                                 width: 1)
        mem_is_fp_reg_write_op = local(:mem_is_fp_reg_write_op,
                                       mem_is_fmv_w_x | mem_is_fsgnj_s | mem_is_fminmax_s |
                                       mem_is_fsgnj_d | mem_is_fminmax_d |
                                       mem_is_fcvt_s_d | mem_is_fcvt_s_w | mem_is_fcvt_s_wu | mem_is_d_arith,
                                       width: 1)
        mem_amo_active = local(:mem_amo_active, mem_is_amo & (mem_reg_write | mem_mem_read | mem_mem_write), width: 1)
        mem_amo_old = local(:mem_amo_old, data_rdata, width: 32)
        mem_amo_old_sign = mem_amo_old[31]
        mem_rs2_sign = mem_rs2_data[31]
        mem_amo_old_lt_signed = local(:mem_amo_old_lt_signed,
                                      mux(mem_amo_old_sign != mem_rs2_sign, mem_amo_old_sign, mem_amo_old < mem_rs2_data),
                                      width: 1)
        mem_amo_min_signed = local(:mem_amo_min_signed, mux(mem_amo_old_lt_signed, mem_amo_old, mem_rs2_data), width: 32)
        mem_amo_max_signed = local(:mem_amo_max_signed, mux(mem_amo_old_lt_signed, mem_rs2_data, mem_amo_old), width: 32)
        mem_amo_min_unsigned = local(:mem_amo_min_unsigned, mux(mem_amo_old < mem_rs2_data, mem_amo_old, mem_rs2_data), width: 32)
        mem_amo_max_unsigned = local(:mem_amo_max_unsigned, mux(mem_amo_old < mem_rs2_data, mem_rs2_data, mem_amo_old), width: 32)
        mem_amo_expected = local(:mem_amo_expected, mem_rd_src_data, width: 32)
        mem_amo_cas_success = local(:mem_amo_cas_success, mem_amo_old == mem_amo_expected, width: 1)
        mem_amo_new_data = local(:mem_amo_new_data, case_select(mem_amo_funct5, {
          0b00000 => mem_amo_old + mem_rs2_data,
          0b00001 => mem_rs2_data,
          0b00101 => mem_rs2_data,
          0b00100 => mem_amo_old ^ mem_rs2_data,
          0b01000 => mem_amo_old | mem_rs2_data,
          0b01100 => mem_amo_old & mem_rs2_data,
          0b10000 => mem_amo_min_signed,
          0b10100 => mem_amo_max_signed,
          0b11000 => mem_amo_min_unsigned,
          0b11100 => mem_amo_max_unsigned
        }, default: mem_rs2_data), width: 32)
        mem_sc_success = local(:mem_sc_success, reservation_valid & (reservation_addr == mem_alu_result), width: 1)
        mem_amo_read = local(:mem_amo_read, mem_is_lr | mem_is_amo_rmw, width: 1)
        mem_amo_write = local(:mem_amo_write,
                              (mem_is_sc & mem_sc_success) |
                              (mem_is_amo_rmw & (~mem_is_amocas | mem_amo_cas_success)),
                              width: 1)
        mem_sc_result = local(:mem_sc_result,
                              mux(mem_sc_success, lit(0, width: 32), lit(1, width: 32)),
                              width: 32)
        mem_forward_data <= mux(mem_jump, mem_pc_plus4,
                                mux(mem_amo_active & mem_is_sc, mem_sc_result,
                                    mux(mem_mem_to_reg, data_rdata, mem_alu_result)))

        data_addr <= mem_alu_result
        data_wdata <= mux(mem_amo_active & mem_is_amo_rmw, mem_amo_new_data, mem_rs2_data)
        data_we <= mux(mem_amo_active, mem_amo_write, mem_mem_write)
        data_re <= mux(mem_amo_active, mem_amo_read, mem_mem_read)
        data_funct3 <= mux(mem_amo_active, lit(Funct3::WORD, width: 3), mem_funct3)
        reservation_set <= mem_amo_active & mem_is_lr
        reservation_clear <= (mem_amo_active & (mem_is_sc | mem_is_amo_rmw)) | mem_mem_write
        reservation_set_addr <= mem_alu_result
        mem_fp_src_sign = mem_alu_result[31]
        mem_fp_src_exp = mem_alu_result[30..23]
        mem_fp_src_frac = mem_alu_result[22..0]
        mem_fp_src_is_zero = local(:mem_fp_src_is_zero,
                                   (mem_fp_src_exp == lit(0, width: 8)) & (mem_fp_src_frac == lit(0, width: 23)),
                                   width: 1)
        mem_fp_src_is_subnormal = local(:mem_fp_src_is_subnormal,
                                        (mem_fp_src_exp == lit(0, width: 8)) & (mem_fp_src_frac != lit(0, width: 23)),
                                        width: 1)
        mem_fp_src_is_inf = local(:mem_fp_src_is_inf,
                                  (mem_fp_src_exp == lit(0xFF, width: 8)) & (mem_fp_src_frac == lit(0, width: 23)),
                                  width: 1)
        mem_fp_src_is_nan = local(:mem_fp_src_is_nan,
                                  (mem_fp_src_exp == lit(0xFF, width: 8)) & (mem_fp_src_frac != lit(0, width: 23)),
                                  width: 1)
        mem_fcvt_ds_exp11 = local(:mem_fcvt_ds_exp11, cat(lit(0, width: 3), mem_fp_src_exp) + lit(896, width: 11), width: 11)
        mem_fcvt_ds_frac52 = local(:mem_fcvt_ds_frac52, cat(mem_fp_src_frac, lit(0, width: 29)), width: 52)
        mem_fcvt_d_s_zero = local(:mem_fcvt_d_s_zero, cat(mem_fp_src_sign, lit(0, width: 11), lit(0, width: 52)), width: 64)
        mem_fcvt_d_s_inf = local(:mem_fcvt_d_s_inf, cat(mem_fp_src_sign, lit(0x7FF, width: 11), lit(0, width: 52)), width: 64)
        mem_fcvt_d_s_nan = local(:mem_fcvt_d_s_nan, cat(mem_fp_src_sign, lit(0x7FF, width: 11), cat(mem_fp_src_frac, lit(0, width: 29))), width: 64)
        mem_fcvt_d_s_norm = local(:mem_fcvt_d_s_norm, cat(mem_fp_src_sign, mem_fcvt_ds_exp11, mem_fcvt_ds_frac52), width: 64)
        mem_fcvt_d_s_result64 = local(:mem_fcvt_d_s_result64,
                                      mux(mem_fp_src_is_zero | mem_fp_src_is_subnormal,
                                          mem_fcvt_d_s_zero,
                                          mux(mem_fp_src_is_nan,
                                              mem_fcvt_d_s_nan,
                                              mux(mem_fp_src_is_inf,
                                                  mem_fcvt_d_s_inf,
                                                  mem_fcvt_d_s_norm))),
                                      width: 64)
        mem_fcvt_dw_sign = local(:mem_fcvt_dw_sign,
                                 mux(mem_is_fcvt_d_w, mem_alu_result[31], lit(0, width: 1)),
                                 width: 1)
        mem_fcvt_dw_abs = local(:mem_fcvt_dw_abs,
                                mux(mem_is_fcvt_d_w & mem_alu_result[31], ~mem_alu_result + lit(1, width: 32), mem_alu_result),
                                width: 32)
        mem_fcvt_dw_msb_expr = local(:mem_fcvt_dw_msb_seed, lit(0, width: 6), width: 6)
        32.times do |i|
          mem_fcvt_dw_msb_expr = local(:"mem_fcvt_dw_msb_stage_#{i}",
                                       mux(mem_fcvt_dw_abs[i], lit(i, width: 6), mem_fcvt_dw_msb_expr),
                                       width: 6)
        end
        mem_fcvt_dw_msb = local(:mem_fcvt_dw_msb, mem_fcvt_dw_msb_expr, width: 6)
        mem_fcvt_dw_nonzero = local(:mem_fcvt_dw_nonzero, mem_fcvt_dw_abs != lit(0, width: 32), width: 1)
        mem_fcvt_dw_shift_left_amt = local(:mem_fcvt_dw_shift_left_amt, lit(52, width: 6) - mem_fcvt_dw_msb, width: 6)
        mem_fcvt_dw_norm = local(:mem_fcvt_dw_norm, cat(lit(0, width: 32), mem_fcvt_dw_abs) << mem_fcvt_dw_shift_left_amt, width: 64)
        mem_fcvt_dw_frac52 = mem_fcvt_dw_norm[51..0]
        mem_fcvt_dw_exp11 = local(:mem_fcvt_dw_exp11, cat(lit(0, width: 5), mem_fcvt_dw_msb) + lit(1023, width: 11), width: 11)
        mem_fcvt_d_w_result64 = local(:mem_fcvt_d_w_result64,
                                      mux(mem_fcvt_dw_nonzero,
                                          cat(mem_fcvt_dw_sign, mem_fcvt_dw_exp11, mem_fcvt_dw_frac52),
                                          lit(0, width: 64)),
                                      width: 64)
        fp_rd_data <= mux(mem_is_fp_load, data_rdata, mem_alu_result)
        mem_is_ex_d_result64 = local(:mem_is_ex_d_result64, mem_is_fsgnj_d | mem_is_fminmax_d | mem_is_d_arith, width: 1)
        fp_rd_data64 <= mux(mem_is_fcvt_d_s, mem_fcvt_d_s_result64,
                            mux(mem_is_fcvt_d_w | mem_is_fcvt_d_wu, mem_fcvt_d_w_result64,
                                mux(mem_is_ex_d_result64, cat(mem_rd_src_data, mem_alu_result), cat(lit(0xFFFF_FFFF, width: 32), fp_rd_data))))
        fp_reg_write <= (mem_is_fp_load & mem_mem_read) | mem_is_fp_reg_write_op
        fp_reg_write64 <= mem_is_fcvt_d_s | mem_is_fcvt_d_w | mem_is_fcvt_d_wu | mem_is_ex_d_result64

        # -----------------------------------------
        # MEM/WB Register inputs (latch wires)
        # -----------------------------------------
        mem_wb_alu_result_in <= mux(mem_amo_active & mem_is_sc, mem_sc_result, mem_alu_result)
        mem_wb_mem_data_in <= data_rdata
        mem_wb_rd_addr_in <= mem_rd_addr
        mem_wb_pc_plus4_in <= mem_pc_plus4
        mem_wb_reg_write_in <= mem_reg_write
        mem_wb_mem_to_reg_in <= mux(mem_amo_active & mem_is_sc, lit(0, width: 1), mem_mem_to_reg)
        mem_wb_jump_in <= mem_jump

        # -----------------------------------------
        # Output connections
        # -----------------------------------------
        inst_addr <= mux(if_satp_translate, if_paddr, current_pc)
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

      def read_csr(index)
        @csrfile.read_csr(index)
      end

      def self.verilog_module_name
        'riscv_pipelined_cpu'
      end

      def self.to_verilog(top_name: nil)
        name = top_name || verilog_module_name
        to_verilog_via_circt(top_name: name)
      end
        end
      end
    end
  end
end
