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
      wire :id_rd_addr, width: 5
      wire :id_opcode, width: 7
      wire :id_funct3, width: 3
      wire :id_funct7, width: 7
      wire :id_alu_op, width: 5
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
      wire :id_ex_imm_in, width: 32
      wire :id_ex_rs1_addr_in, width: 5
      wire :id_ex_rs2_addr_in, width: 5
      wire :id_ex_rd_addr_in, width: 5
      wire :id_ex_opcode_in, width: 7
      wire :id_ex_funct3_in, width: 3
      wire :id_ex_funct7_in, width: 7
      wire :id_ex_alu_op_in, width: 5
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
      wire :ex_imm, width: 32
      wire :ex_rs1_addr, width: 5
      wire :ex_rs2_addr, width: 5
      wire :ex_rd_addr, width: 5
      wire :ex_opcode, width: 7
      wire :ex_funct3, width: 3
      wire :ex_funct7, width: 7
      wire :ex_alu_op, width: 5
      wire :ex_alu_src
      wire :ex_reg_write
      wire :ex_mem_read
      wire :ex_mem_write
      wire :ex_mem_to_reg
      wire :ex_branch
      wire :ex_jump
      wire :ex_jalr
      wire :ex_inst_page_fault

      # ========================================
      # Internal signals - EX Stage (Execute)
      # ========================================
      wire :forward_a, width: 2
      wire :forward_b, width: 2
      wire :forwarded_rs1, width: 32
      wire :alu_a, width: 32
      wire :alu_b, width: 32
      wire :forwarded_rs2, width: 32
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
      wire :csr_write_addr, width: 12
      wire :csr_read_data, width: 32
      wire :csr_read_data2, width: 32
      wire :csr_read_data3, width: 32
      wire :csr_read_data4, width: 32
      wire :csr_read_data5, width: 32
      wire :csr_read_data6, width: 32
      wire :csr_read_data7, width: 32
      wire :csr_read_data8, width: 32
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
      port :clk => [[:pc_reg, :clk], [:regfile, :clk], [:csrfile, :clk], [:if_id, :clk],
                    [:id_ex, :clk], [:ex_mem, :clk], [:mem_wb, :clk], [:reservation, :clk], [:priv_mode_reg, :clk],
                    [:itlb, :clk], [:dtlb, :clk]]
      port :rst => [[:pc_reg, :rst], [:regfile, :rst], [:csrfile, :rst], [:if_id, :rst],
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
      port :inst_data => [:if_id, :inst_in]
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
      port :wb_rd_addr => [:regfile, :rd_addr]
      port :wb_data => [:regfile, :rd_data]
      port :wb_reg_write => [:regfile, :rd_we]
      port :regfile_forwarding_en => [:regfile, :forwarding_en]
      port :debug_reg_addr => [:regfile, :debug_raddr]
      port [:regfile, :rs1_data] => :id_rs1_data
      port [:regfile, :rs2_data] => :id_rs2_data
      port [:regfile, :debug_x1] => :debug_x1
      port [:regfile, :debug_x2] => :debug_x2
      port [:regfile, :debug_x10] => :debug_x10
      port [:regfile, :debug_x11] => :debug_x11
      port [:regfile, :debug_rdata] => :debug_reg_data

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
      port [:csrfile, :read_data] => :csr_read_data
      port [:csrfile, :read_data2] => :csr_read_data2
      port [:csrfile, :read_data3] => :csr_read_data3
      port [:csrfile, :read_data4] => :csr_read_data4
      port [:csrfile, :read_data5] => :csr_read_data5
      port [:csrfile, :read_data6] => :csr_read_data6
      port [:csrfile, :read_data7] => :csr_read_data7
      port [:csrfile, :read_data8] => :csr_read_data8
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
        pc_plus4_if = local(:pc_plus4_if, current_pc + lit(4, width: 32), width: 32)
        if_id_pc_plus4_in <= pc_plus4_if

        # Sv32 instruction translation for IF fetch address.
        if_satp_mode_sv32 = local(:if_satp_mode_sv32, csr_read_data8[31], width: 1)
        if_priv_is_u = local(:if_priv_is_u, priv_mode == lit(PrivMode::USER, width: 2), width: 1)
        if_priv_is_s = local(:if_priv_is_s, priv_mode == lit(PrivMode::SUPERVISOR, width: 2), width: 1)
        if_satp_root_ppn = csr_read_data8[19..0]
        if_satp_root_base = local(:if_satp_root_base, cat(if_satp_root_ppn, lit(0, width: 12)), width: 32)
        if_vpn = current_pc[31..12]
        if_vpn1 = current_pc[31..22]
        if_vpn0 = current_pc[21..12]
        if_page_off = current_pc[11..0]
        inst_tlb_lookup_en <= if_satp_mode_sv32
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
        inst_tlb_fill_en <= if_satp_mode_sv32 & ~inst_tlb_hit & if_walk_ok
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
        if_inst_page_fault = local(:if_inst_page_fault, if_satp_mode_sv32 & ~if_perm_ok, width: 1)
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
        id_ex_pc_in <= id_pc
        id_ex_pc_plus4_in <= id_pc_plus4
        id_ex_rs1_data_in <= id_rs1_data
        id_ex_rs2_data_in <= id_rs2_data
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
        # Forward A (rs1) - priority: EX/MEM > MEM/WB > register file
        forwarded_rs1 <= mux(forward_a == lit(ForwardSel::EX_MEM, width: 2), mem_alu_result,
                          mux(forward_a == lit(ForwardSel::MEM_WB, width: 2), wb_data,
                            ex_rs1_data))

        # AUIPC uses PC as ALU A operand (not rs1)
        alu_a <= mux(ex_opcode == lit(Opcode::AUIPC, width: 7), ex_pc, forwarded_rs1)

        # Forward B (rs2) for store and branch comparison
        forwarded_rs2 <= mux(forward_b == lit(ForwardSel::EX_MEM, width: 2), mem_alu_result,
                          mux(forward_b == lit(ForwardSel::MEM_WB, width: 2), wb_data,
                            ex_rs2_data))

        # ALU B input: immediate or forwarded rs2
        alu_b <= mux(ex_alu_src, ex_imm, forwarded_rs2)

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
        ex_is_amo_rmw = local(:ex_is_amo_rmw,
                              ex_is_amo_word & (
                                (ex_amo_funct5 == lit(0b00000, width: 5)) |
                                (ex_amo_funct5 == lit(0b00001, width: 5)) |
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
        ex_is_sfence_vma = local(:ex_is_sfence_vma,
                                 ex_is_system_plain & (ex_funct7 == lit(0b0001001, width: 7)) & (ex_rd_addr == lit(0, width: 5)),
                                 width: 1)
        ex_is_illegal_system = local(:ex_is_illegal_system,
                                     ex_is_system_plain & ~(ex_is_ecall | ex_is_ebreak | ex_is_mret | ex_is_sret |
                                                            ex_is_wfi | ex_is_sfence_vma),
                                     width: 1)
        ex_irq_pending_bits = local(:ex_irq_pending_bits,
                                    mux(irq_software, lit(0x8, width: 32), lit(0, width: 32)) |
                                    mux(irq_timer, lit(0x80, width: 32), lit(0, width: 32)) |
                                    mux(irq_external, lit(0x800, width: 32), lit(0, width: 32)),
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
        data_tlb_lookup_en <= ex_satp_mode_sv32 & ex_data_access_req
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
        data_tlb_fill_en <= ex_satp_mode_sv32 & ex_data_access_req & ~data_tlb_hit & ex_data_walk_ok
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
                                   ex_satp_mode_sv32 & ex_data_access_req & ~ex_data_perm_ok,
                                   width: 1)
        ex_data_page_fault_cause = local(:ex_data_page_fault_cause,
                                         mux(ex_data_store_access, lit(15, width: 32), lit(13, width: 32)),
                                         width: 32)

        ex_machine_irq_masked = local(:ex_machine_irq_masked, ex_irq_pending_bits & ~csr_read_data7, width: 32)
        ex_super_irq_masked = local(:ex_super_irq_masked, ex_irq_pending_bits & csr_read_data7, width: 32)
        ex_machine_enabled_interrupts = local(:ex_machine_enabled_interrupts, ex_machine_irq_masked & csr_read_data3, width: 32)
        ex_super_enabled_interrupts = local(:ex_super_enabled_interrupts, ex_super_irq_masked & csr_read_data5, width: 32)
        ex_global_mie_enabled = local(:ex_global_mie_enabled,
                                      (csr_read_data2 & lit(0x8, width: 32)) != lit(0, width: 32),
                                      width: 1)
        ex_global_sie_enabled = local(:ex_global_sie_enabled,
                                      (csr_read_data4 & lit(0x2, width: 32)) != lit(0, width: 32),
                                      width: 1)
        ex_machine_interrupt_pending = local(:ex_machine_interrupt_pending,
                                             ex_global_mie_enabled & (ex_machine_enabled_interrupts != lit(0, width: 32)),
                                             width: 1)
        ex_super_interrupt_pending = local(:ex_super_interrupt_pending,
                                           ex_global_sie_enabled & (ex_super_enabled_interrupts != lit(0, width: 32)),
                                           width: 1)
        ex_interrupt_pending = local(:ex_interrupt_pending, ex_machine_interrupt_pending | ex_super_interrupt_pending, width: 1)
        ex_interrupt_from_supervisor = local(:ex_interrupt_from_supervisor,
                                             ex_super_interrupt_pending & ~ex_machine_interrupt_pending,
                                             width: 1)
        ex_selected_interrupts = local(:ex_selected_interrupts,
                                       mux(ex_machine_interrupt_pending, ex_machine_enabled_interrupts, ex_super_enabled_interrupts),
                                       width: 32)

        ex_sync_trap_taken = local(:ex_sync_trap_taken,
                                   ex_is_ecall | ex_is_ebreak | ex_is_illegal_system |
                                   ex_inst_page_fault | ex_data_page_fault,
                                   width: 1)
        ex_ecall_delegated = local(:ex_ecall_delegated,
                                   (csr_read_data6 & lit(0x800, width: 32)) != lit(0, width: 32),
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
                                       mux(ex_inst_page_fault, ex_inst_page_fault_delegated,
                                           mux(ex_data_page_fault, ex_data_page_fault_delegated,
                                               mux(ex_is_ecall, ex_ecall_delegated,
                                                   mux(ex_is_ebreak, ex_ebreak_delegated, ex_illegal_delegated)))),
                                       width: 1)
        ex_trap_to_supervisor = local(:ex_trap_to_supervisor,
                                      (ex_sync_trap_taken & ex_sync_trap_delegated) | ex_interrupt_from_supervisor,
                                      width: 1)
        ex_trap_taken = local(:ex_trap_taken, ex_sync_trap_taken | ex_interrupt_pending, width: 1)
        ex_interrupt_cause = local(:ex_interrupt_cause,
                                   mux((ex_selected_interrupts & lit(0x800, width: 32)) != lit(0, width: 32),
                                       lit(0x8000000B, width: 32), # MEI
                                       mux((ex_selected_interrupts & lit(0x80, width: 32)) != lit(0, width: 32),
                                           lit(0x80000007, width: 32), # MTI
                                           lit(0x80000003, width: 32)  # MSI
                                       )),
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
                                              mux(ex_is_ebreak, lit(3, width: 32), lit(11, width: 32)))))),
                              width: 32)
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
        ex_trap_mstatus = local(:ex_trap_mstatus,
                                (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                                ex_old_mie_to_mpie |
                                lit(0x1800, width: 32),
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
        ex_trap_sstatus = local(:ex_trap_sstatus,
                                (csr_read_data4 & lit(0xFFFFFEDD, width: 32)) |
                                ex_old_sie_to_spie |
                                lit(0x100, width: 32),
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
        ex_reg_write_effective = local(:ex_reg_write_effective, (ex_reg_write | ex_is_amo) & ~ex_trap_taken, width: 1)
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
        ex_csr_read_selected = local(:ex_csr_read_selected,
                                     mux(csr_read_addr == lit(0x344, width: 12), ex_irq_pending_bits,
                                         mux(csr_read_addr == lit(0x144, width: 12), ex_irq_pending_bits & csr_read_data7, csr_read_data)),
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
        ex_satp_write = local(:ex_satp_write,
                              ex_is_csr_instr & ex_csr_write_we & (ex_imm[11..0] == lit(0x180, width: 12)),
                              width: 1)
        tlb_flush_all <= ex_is_sfence_vma | ex_satp_write
        csr_write_addr <= mux(ex_trap_taken, mux(ex_trap_to_supervisor, lit(0x141, width: 12), lit(0x341, width: 12)),
                              mux(ex_is_mret, lit(0x300, width: 12),
                                  mux(ex_is_sret, lit(0x100, width: 12), ex_imm[11..0])))
        csr_write_data <= mux(ex_trap_taken, ex_pc,
                              mux(ex_is_mret, ex_mret_mstatus,
                                  mux(ex_is_sret, ex_sret_sstatus, ex_csr_write_data)))
        csr_write_we <= mux(ex_trap_or_ret, lit(1, width: 1), ex_csr_write_we)
        csr_write_addr2 <= mux(ex_trap_to_supervisor, lit(0x142, width: 12), lit(0x342, width: 12))
        csr_write_data2 <= ex_trap_cause
        csr_write_we2 <= ex_trap_taken
        csr_write_addr3 <= mux(ex_trap_to_supervisor, lit(0x100, width: 12), lit(0x300, width: 12))
        csr_write_data3 <= mux(ex_trap_to_supervisor, ex_trap_sstatus, ex_trap_mstatus)
        csr_write_we3 <= ex_trap_taken
        csr_write_addr4 <= mux(ex_trap_to_supervisor, lit(0x143, width: 12), lit(0x343, width: 12))
        csr_write_data4 <= ex_trap_tval
        csr_write_we4 <= ex_trap_taken
        priv_mode_we <= ex_trap_taken | ex_is_mret | ex_is_sret
        priv_mode_next <= mux(ex_trap_taken, ex_trap_target_mode, ex_ret_target_mode)
        data_ptw_addr1 <= ex_data_ptw_addr1_calc
        data_ptw_addr0 <= ex_data_ptw_addr0_calc
        ex_result <= mux(ex_is_amo, forwarded_rs1,
                         mux(ex_is_csr_instr, ex_csr_read_selected,
                             mux(ex_satp_mode_sv32 & ex_data_access_req, ex_data_paddr, alu_result)))

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
        trap_target <= ex_csr_read_selected & lit(0xFFFFFFFC, width: 32)
        mret_target <= ex_csr_read_selected
        control_target <= mux(ex_trap_taken, trap_target,
                              mux(ex_is_mret | ex_is_sret, mret_target, jump_target))

        # Branch taken = branch instruction AND condition met
        take_branch <= (branch_cond_taken & ex_branch) | ex_jump | ex_trap_taken | ex_is_mret | ex_is_sret

        # -----------------------------------------
        # EX/MEM Register inputs (latch wires)
        # -----------------------------------------
        ex_mem_alu_result_in <= ex_result
        ex_mem_rs2_data_in <= forwarded_rs2
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
        mem_is_amo_rmw = local(:mem_is_amo_rmw,
                               mem_is_amo_word & (
                                 (mem_amo_funct5 == lit(0b00000, width: 5)) |
                                 (mem_amo_funct5 == lit(0b00001, width: 5)) |
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
        mem_amo_new_data = local(:mem_amo_new_data, case_select(mem_amo_funct5, {
          0b00000 => mem_amo_old + mem_rs2_data,
          0b00001 => mem_rs2_data,
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
        mem_amo_write = local(:mem_amo_write, (mem_is_sc & mem_sc_success) | mem_is_amo_rmw, width: 1)
        mem_sc_result = local(:mem_sc_result,
                              mux(mem_sc_success, lit(0, width: 32), lit(1, width: 32)),
                              width: 32)

        data_addr <= mem_alu_result
        data_wdata <= mux(mem_amo_active & mem_is_amo_rmw, mem_amo_new_data, mem_rs2_data)
        data_we <= mux(mem_amo_active, mem_amo_write, mem_mem_write)
        data_re <= mux(mem_amo_active, mem_amo_read, mem_mem_read)
        data_funct3 <= mux(mem_amo_active, lit(Funct3::WORD, width: 3), mem_funct3)
        reservation_set <= mem_amo_active & mem_is_lr
        reservation_clear <= (mem_amo_active & (mem_is_sc | mem_is_amo_rmw)) | mem_mem_write
        reservation_set_addr <= mem_alu_result

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
        inst_addr <= mux(if_satp_mode_sv32, if_paddr, current_pc)
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
        RHDL::Export::Verilog.generate(to_ir(top_name: name))
      end
        end
      end
    end
  end
end

# Load the harness after CPU is defined
require_relative 'harness'
