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
require_relative 'fp_register_file'
require_relative 'vector_register_file'
require_relative 'vector_csr_file'
require_relative 'csr_file'
require_relative 'imm_gen'
require_relative 'compressed_decoder'
require_relative 'decoder'
require_relative 'branch_cond'
require_relative 'program_counter'
require_relative 'atomic_reservation'
require_relative 'priv_mode_reg'
require_relative 'sv32_tlb'

module RHDL
  module Examples
    module RISCV
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
    output :inst_addr, width: 32    # Instruction address (PC)
    input :inst_data, width: 32     # Instruction data from memory
    output :inst_ptw_addr1, width: 32  # Sv32 level-1 PTE address for instruction translation
    output :inst_ptw_addr0, width: 32  # Sv32 level-0 PTE address for instruction translation
    input :inst_ptw_pte1, width: 32    # Sv32 level-1 PTE value for instruction translation
    input :inst_ptw_pte0, width: 32    # Sv32 level-0 PTE value for instruction translation

    # Data memory interface
    output :data_addr, width: 32    # Data address
    output :data_wdata, width: 32   # Write data
    input :data_rdata, width: 32    # Read data from memory
    output :data_we                 # Write enable
    output :data_re                 # Read enable
    output :data_funct3, width: 3   # Memory access size
    output :data_ptw_addr1, width: 32  # Sv32 level-1 PTE address (for harness memory read)
    output :data_ptw_addr0, width: 32  # Sv32 level-0 PTE address (for harness memory read)
    input :data_ptw_pte1, width: 32    # Sv32 level-1 PTE value
    input :data_ptw_pte0, width: 32    # Sv32 level-0 PTE value

    # Debug outputs
    output :debug_pc, width: 32
    output :debug_inst, width: 32
    output :debug_x1, width: 32
    output :debug_x2, width: 32
    output :debug_x10, width: 32
    output :debug_x11, width: 32
    input :debug_reg_addr, width: 5
    output :debug_reg_data, width: 32

    # Internal signals - from sub-components
    wire :pc, width: 32
    wire :pc_next, width: 32
    wire :inst_exec, width: 32
    wire :inst_pc_step, width: 32
    wire :imm, width: 32
    wire :rs1_data, width: 32
    wire :rs2_data, width: 32
    wire :rd_lookup_data, width: 32
    wire :fp_rs1_data, width: 32
    wire :fp_rs2_data, width: 32
    wire :fp_rs3_data, width: 32
    wire :fp_rs1_data64, width: 64
    wire :fp_rs2_data64, width: 64
    wire :fp_rs3_data64, width: 64
    wire :fp_rs3_addr, width: 5
    wire :v_rs1_lane0, width: 32
    wire :v_rs1_lane1, width: 32
    wire :v_rs1_lane2, width: 32
    wire :v_rs1_lane3, width: 32
    wire :v_rs2_lane0, width: 32
    wire :v_rs2_lane1, width: 32
    wire :v_rs2_lane2, width: 32
    wire :v_rs2_lane3, width: 32
    wire :v_rd_lane0, width: 32
    wire :v_rd_lane1, width: 32
    wire :v_rd_lane2, width: 32
    wire :v_rd_lane3, width: 32
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
    wire :reg_write_final
    wire :mem_read_final
    wire :mem_write_final
    wire :alu_op, width: 6

    # Internal signals - computed by behavior block
    wire :alu_a, width: 32
    wire :alu_b, width: 32
    wire :rd_data, width: 32
    wire :fp_rd_data, width: 32
    wire :fp_rd_data64, width: 64
    wire :regfile_forwarding_en
    wire :fp_reg_write
    wire :fp_reg_write64
    wire :v_rd_lane0_in, width: 32
    wire :v_rd_lane1_in, width: 32
    wire :v_rd_lane2_in, width: 32
    wire :v_rd_lane3_in, width: 32
    wire :v_rd_we
    wire :vec_vl, width: 32
    wire :vec_vtype, width: 32
    wire :vec_vl_write_data, width: 32
    wire :vec_vtype_write_data, width: 32
    wire :vec_vl_write_we
    wire :vec_vtype_write_we
    wire :pc_plus4, width: 32
    wire :branch_target, width: 32
    wire :jalr_target, width: 32
    wire :pc_we  # PC write enable (always 1 for single-cycle)
    wire :csr_addr, width: 12
    wire :csr_addr2, width: 12
    wire :csr_addr3, width: 12
    wire :csr_addr4, width: 12
    wire :csr_addr5, width: 12
    wire :csr_addr6, width: 12
    wire :csr_addr7, width: 12
    wire :csr_addr8, width: 12
    wire :csr_addr9, width: 12
    wire :csr_addr10, width: 12
    wire :csr_addr11, width: 12
    wire :csr_addr12, width: 12
    wire :csr_addr13, width: 12
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

    # Component instances
    instance :pc_reg, ProgramCounter
    instance :regfile, RegisterFile
    instance :fp_regfile, FPRegisterFile
    instance :vregfile, VectorRegisterFile
    instance :vec_csrfile, VectorCSRFile
    instance :csrfile, CSRFile
    instance :reservation, AtomicReservation
    instance :priv_mode_reg, PrivModeReg
    instance :itlb, Sv32Tlb
    instance :dtlb, Sv32Tlb
    instance :c_decoder, CompressedDecoder
    instance :decoder, Decoder
    instance :imm_gen, ImmGen
    instance :alu, ALU
    instance :branch_cond, BranchCond

    # Clock and reset to sequential components
    port :clk => [[:pc_reg, :clk], [:regfile, :clk], [:fp_regfile, :clk], [:vregfile, :clk], [:vec_csrfile, :clk],
                  [:csrfile, :clk], [:reservation, :clk], [:priv_mode_reg, :clk],
                  [:itlb, :clk], [:dtlb, :clk]]
    port :rst => [[:pc_reg, :rst], [:regfile, :rst], [:fp_regfile, :rst], [:vregfile, :rst], [:vec_csrfile, :rst],
                  [:csrfile, :rst], [:reservation, :rst], [:priv_mode_reg, :rst],
                  [:itlb, :rst], [:dtlb, :rst]]

    # PC connections
    port :pc_next => [:pc_reg, :pc_next]
    port [:pc_reg, :pc] => :pc

    # Instruction to decoder and immediate generator
    port :inst_data => [:c_decoder, :inst_word]
    port [:c_decoder, :inst_out] => :inst_exec
    port [:c_decoder, :pc_step] => :inst_pc_step
    port :inst_exec => [:decoder, :inst]
    port :inst_exec => [:imm_gen, :inst]

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
    port :rd => [:regfile, :rs3_addr]
    port :rd => [:regfile, :rd_addr]
    port :rd_data => [:regfile, :rd_data]
    port :reg_write_final => [:regfile, :rd_we]
    port :regfile_forwarding_en => [:regfile, :forwarding_en]
    port :debug_reg_addr => [:regfile, :debug_raddr]
    port [:regfile, :rs1_data] => :rs1_data
    port [:regfile, :rs2_data] => :rs2_data
    port [:regfile, :rs3_data] => :rd_lookup_data
    port [:regfile, :debug_rdata] => :debug_reg_data

    # FP register file connections
    port :rs1 => [:fp_regfile, :rs1_addr]
    port :rs2 => [:fp_regfile, :rs2_addr]
    port :fp_rs3_addr => [:fp_regfile, :rs3_addr]
    port :rd => [:fp_regfile, :rd_addr]
    port :fp_rd_data => [:fp_regfile, :rd_data]
    port :fp_reg_write => [:fp_regfile, :rd_we]
    port :fp_rd_data64 => [:fp_regfile, :rd_data64]
    port :fp_reg_write64 => [:fp_regfile, :rd_we64]
    port [:fp_regfile, :rs1_data] => :fp_rs1_data
    port [:fp_regfile, :rs2_data] => :fp_rs2_data
    port [:fp_regfile, :rs3_data] => :fp_rs3_data
    port [:fp_regfile, :rs1_data64] => :fp_rs1_data64
    port [:fp_regfile, :rs2_data64] => :fp_rs2_data64
    port [:fp_regfile, :rs3_data64] => :fp_rs3_data64

    # Vector register file connections
    port :rs1 => [:vregfile, :rs1_addr]
    port :rs2 => [:vregfile, :rs2_addr]
    port :rd => [:vregfile, :rd_addr_read]
    port :rd => [:vregfile, :rd_addr]
    port :v_rd_lane0_in => [:vregfile, :rd_lane0_in]
    port :v_rd_lane1_in => [:vregfile, :rd_lane1_in]
    port :v_rd_lane2_in => [:vregfile, :rd_lane2_in]
    port :v_rd_lane3_in => [:vregfile, :rd_lane3_in]
    port :v_rd_we => [:vregfile, :rd_we]
    port [:vregfile, :rs1_lane0] => :v_rs1_lane0
    port [:vregfile, :rs1_lane1] => :v_rs1_lane1
    port [:vregfile, :rs1_lane2] => :v_rs1_lane2
    port [:vregfile, :rs1_lane3] => :v_rs1_lane3
    port [:vregfile, :rs2_lane0] => :v_rs2_lane0
    port [:vregfile, :rs2_lane1] => :v_rs2_lane1
    port [:vregfile, :rs2_lane2] => :v_rs2_lane2
    port [:vregfile, :rs2_lane3] => :v_rs2_lane3
    port [:vregfile, :rd_lane0] => :v_rd_lane0
    port [:vregfile, :rd_lane1] => :v_rd_lane1
    port [:vregfile, :rd_lane2] => :v_rd_lane2
    port [:vregfile, :rd_lane3] => :v_rd_lane3

    # Vector control CSR state
    port :vec_vl_write_data => [:vec_csrfile, :vl_write_data]
    port :vec_vl_write_we => [:vec_csrfile, :vl_write_we]
    port :vec_vtype_write_data => [:vec_csrfile, :vtype_write_data]
    port :vec_vtype_write_we => [:vec_csrfile, :vtype_write_we]
    port [:vec_csrfile, :vl] => :vec_vl
    port [:vec_csrfile, :vtype] => :vec_vtype

    # CSR file connections
    port :csr_addr => [:csrfile, :read_addr]
    port :csr_addr2 => [:csrfile, :read_addr2]
    port :csr_addr3 => [:csrfile, :read_addr3]
    port :csr_addr4 => [:csrfile, :read_addr4]
    port :csr_addr5 => [:csrfile, :read_addr5]
    port :csr_addr6 => [:csrfile, :read_addr6]
    port :csr_addr7 => [:csrfile, :read_addr7]
    port :csr_addr8 => [:csrfile, :read_addr8]
    port :csr_addr9 => [:csrfile, :read_addr9]
    port :csr_addr10 => [:csrfile, :read_addr10]
    port :csr_addr11 => [:csrfile, :read_addr11]
    port :csr_addr12 => [:csrfile, :read_addr12]
    port :csr_addr13 => [:csrfile, :read_addr13]
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
      regfile_forwarding_en <= lit(0, width: 1)

      # PC + 4 for sequential execution and return address
      pc_plus4 <= pc + inst_pc_step

      # Branch target = PC + immediate
      branch_target <= pc + imm

      # JALR target = rs1 + immediate with LSB cleared
      jalr_target <= (rs1_data + imm) & lit(0xFFFFFFFE, width: 32)

      # ALU A input mux: AUIPC uses PC, others use rs1_data
      alu_a <= mux(opcode == lit(Opcode::AUIPC, width: 7), pc, rs1_data)

      # ALU B input mux: alu_src=1 uses immediate, alu_src=0 uses rs2_data
      alu_b <= mux(alu_src, imm, rs2_data)

      # RV32F subset decode
      fp_rs3_addr <= inst_exec[31..27]
      fp_fmt = inst_exec[26..25]

      is_fp_load = local(:is_fp_load,
                         (opcode == lit(Opcode::LOAD_FP, width: 7)) &
                         ((funct3 == lit(Funct3::WORD, width: 3)) | (funct3 == lit(Funct3::DOUBLE, width: 3))),
                         width: 1)
      is_fp_store = local(:is_fp_store,
                          (opcode == lit(Opcode::STORE_FP, width: 7)) &
                          ((funct3 == lit(Funct3::WORD, width: 3)) | (funct3 == lit(Funct3::DOUBLE, width: 3))),
                          width: 1)
      is_fmv_x_w = local(:is_fmv_x_w,
                         (opcode == lit(Opcode::OP_FP, width: 7)) &
                         (funct7 == lit(0b1110000, width: 7)) &
                         (funct3 == lit(0, width: 3)) &
                         (rs2 == lit(0, width: 5)),
                         width: 1)
      is_fmv_w_x = local(:is_fmv_w_x,
                         (opcode == lit(Opcode::OP_FP, width: 7)) &
                         (funct7 == lit(0b1111000, width: 7)) &
                         (funct3 == lit(0, width: 3)) &
                         (rs2 == lit(0, width: 5)),
                         width: 1)
      is_fsgnj_s = local(:is_fsgnj_s,
                         (opcode == lit(Opcode::OP_FP, width: 7)) &
                         (funct7 == lit(0b0010000, width: 7)),
                         width: 1)
      is_fsgnj_d = local(:is_fsgnj_d,
                         (opcode == lit(Opcode::OP_FP, width: 7)) &
                         (funct7 == lit(0b0010001, width: 7)),
                         width: 1)
      is_fminmax_s = local(:is_fminmax_s,
                           (opcode == lit(Opcode::OP_FP, width: 7)) &
                           (funct7 == lit(0b0010100, width: 7)),
                           width: 1)
      is_fminmax_d = local(:is_fminmax_d,
                           (opcode == lit(Opcode::OP_FP, width: 7)) &
                           (funct7 == lit(0b0010101, width: 7)),
                           width: 1)
      is_fcmp_s = local(:is_fcmp_s,
                        (opcode == lit(Opcode::OP_FP, width: 7)) &
                        (funct7 == lit(0b1010000, width: 7)),
                        width: 1)
      is_fcmp_d = local(:is_fcmp_d,
                        (opcode == lit(Opcode::OP_FP, width: 7)) &
                        (funct7 == lit(0b1010001, width: 7)),
                        width: 1)
      is_fadd_d = local(:is_fadd_d,
                        (opcode == lit(Opcode::OP_FP, width: 7)) &
                        (funct7 == lit(0b0000001, width: 7)),
                        width: 1)
      is_fsub_d = local(:is_fsub_d,
                        (opcode == lit(Opcode::OP_FP, width: 7)) &
                        (funct7 == lit(0b0000101, width: 7)),
                        width: 1)
      is_fmul_d = local(:is_fmul_d,
                        (opcode == lit(Opcode::OP_FP, width: 7)) &
                        (funct7 == lit(0b0001001, width: 7)),
                        width: 1)
      is_fdiv_d = local(:is_fdiv_d,
                        (opcode == lit(Opcode::OP_FP, width: 7)) &
                        (funct7 == lit(0b0001101, width: 7)),
                        width: 1)
      is_fsqrt_d = local(:is_fsqrt_d,
                         (opcode == lit(Opcode::OP_FP, width: 7)) &
                         (funct7 == lit(0b0101101, width: 7)) &
                         (rs2 == lit(0, width: 5)),
                         width: 1)
      is_fmadd_d = local(:is_fmadd_d,
                         (opcode == lit(Opcode::MADD, width: 7)) &
                         (fp_fmt == lit(0b01, width: 2)),
                         width: 1)
      is_fmsub_d = local(:is_fmsub_d,
                         (opcode == lit(Opcode::MSUB, width: 7)) &
                         (fp_fmt == lit(0b01, width: 2)),
                         width: 1)
      is_fnmsub_d = local(:is_fnmsub_d,
                          (opcode == lit(Opcode::NMSUB, width: 7)) &
                          (fp_fmt == lit(0b01, width: 2)),
                          width: 1)
      is_fnmadd_d = local(:is_fnmadd_d,
                          (opcode == lit(Opcode::NMADD, width: 7)) &
                          (fp_fmt == lit(0b01, width: 2)),
                          width: 1)
      is_d_arith = local(:is_d_arith,
                         is_fadd_d | is_fsub_d | is_fmul_d | is_fdiv_d | is_fsqrt_d |
                         is_fmadd_d | is_fmsub_d | is_fnmsub_d | is_fnmadd_d,
                         width: 1)
      is_fclass_s = local(:is_fclass_s,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b1110000, width: 7)) &
                          (funct3 == lit(0b001, width: 3)) &
                          (rs2 == lit(0, width: 5)),
                          width: 1)
      is_fclass_d = local(:is_fclass_d,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b1110001, width: 7)) &
                          (funct3 == lit(0b001, width: 3)) &
                          (rs2 == lit(0, width: 5)),
                          width: 1)
      is_fcvt_w_s = local(:is_fcvt_w_s,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b1100000, width: 7)) &
                          (rs2 == lit(0b00000, width: 5)),
                          width: 1)
      is_fcvt_wu_s = local(:is_fcvt_wu_s,
                           (opcode == lit(Opcode::OP_FP, width: 7)) &
                           (funct7 == lit(0b1100000, width: 7)) &
                           (rs2 == lit(0b00001, width: 5)),
                           width: 1)
      is_fcvt_w_d = local(:is_fcvt_w_d,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b1100001, width: 7)) &
                          (rs2 == lit(0b00000, width: 5)),
                          width: 1)
      is_fcvt_wu_d = local(:is_fcvt_wu_d,
                           (opcode == lit(Opcode::OP_FP, width: 7)) &
                           (funct7 == lit(0b1100001, width: 7)) &
                           (rs2 == lit(0b00001, width: 5)),
                           width: 1)
      is_fcvt_s_w = local(:is_fcvt_s_w,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b1101000, width: 7)) &
                          (rs2 == lit(0b00000, width: 5)),
                          width: 1)
      is_fcvt_s_wu = local(:is_fcvt_s_wu,
                           (opcode == lit(Opcode::OP_FP, width: 7)) &
                           (funct7 == lit(0b1101000, width: 7)) &
                           (rs2 == lit(0b00001, width: 5)),
                           width: 1)
      is_fcvt_s_d = local(:is_fcvt_s_d,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b0100000, width: 7)) &
                          (rs2 == lit(0b00001, width: 5)),
                          width: 1)
      is_fcvt_d_s = local(:is_fcvt_d_s,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b0100001, width: 7)) &
                          (rs2 == lit(0b00000, width: 5)),
                          width: 1)
      is_fcvt_d_w = local(:is_fcvt_d_w,
                          (opcode == lit(Opcode::OP_FP, width: 7)) &
                          (funct7 == lit(0b1101001, width: 7)) &
                          (rs2 == lit(0b00000, width: 5)),
                          width: 1)
      is_fcvt_d_wu = local(:is_fcvt_d_wu,
                           (opcode == lit(Opcode::OP_FP, width: 7)) &
                           (funct7 == lit(0b1101001, width: 7)) &
                           (rs2 == lit(0b00001, width: 5)),
                           width: 1)
      is_fp_int_write = local(:is_fp_int_write,
                              is_fmv_x_w | is_fcmp_s | is_fcmp_d | is_fclass_s | is_fclass_d |
                              is_fcvt_w_s | is_fcvt_wu_s | is_fcvt_w_d | is_fcvt_wu_d,
                              width: 1)
      is_fp_reg_write_op = local(:is_fp_reg_write_op,
                                 is_fp_load | is_fmv_w_x | is_fsgnj_s | is_fsgnj_d | is_fminmax_s | is_fminmax_d |
                                 is_fcvt_s_w | is_fcvt_s_wu | is_fcvt_s_d | is_d_arith,
                                 width: 1)
      is_fp_reg_write64_op = local(:is_fp_reg_write64_op,
                                   is_fcvt_d_s | is_fcvt_d_w | is_fcvt_d_wu | is_fsgnj_d | is_fminmax_d | is_d_arith,
                                   width: 1)

      fp_rs1_sign = fp_rs1_data[31]
      fp_rs2_sign = fp_rs2_data[31]
      fp_rs1_exp = fp_rs1_data[30..23]
      fp_rs2_exp = fp_rs2_data[30..23]
      fp_rs1_frac = fp_rs1_data[22..0]
      fp_rs2_frac = fp_rs2_data[22..0]

      fp_rs1_is_zero = local(:fp_rs1_is_zero,
                             (fp_rs1_exp == lit(0, width: 8)) & (fp_rs1_frac == lit(0, width: 23)),
                             width: 1)
      fp_rs2_is_zero = local(:fp_rs2_is_zero,
                             (fp_rs2_exp == lit(0, width: 8)) & (fp_rs2_frac == lit(0, width: 23)),
                             width: 1)
      fp_both_zero = local(:fp_both_zero, fp_rs1_is_zero & fp_rs2_is_zero, width: 1)
      fp_rs1_is_nan = local(:fp_rs1_is_nan,
                            (fp_rs1_exp == lit(0xFF, width: 8)) & (fp_rs1_frac != lit(0, width: 23)),
                            width: 1)
      fp_rs2_is_nan = local(:fp_rs2_is_nan,
                            (fp_rs2_exp == lit(0xFF, width: 8)) & (fp_rs2_frac != lit(0, width: 23)),
                            width: 1)
      fp_any_nan = local(:fp_any_nan, fp_rs1_is_nan | fp_rs2_is_nan, width: 1)
      fp_both_nan = local(:fp_both_nan, fp_rs1_is_nan & fp_rs2_is_nan, width: 1)
      fp_ordered_lt = local(:fp_ordered_lt,
                            mux(fp_both_zero,
                                lit(0, width: 1),
                                mux(fp_rs1_sign != fp_rs2_sign,
                                    fp_rs1_sign,
                                    mux(fp_rs1_sign == lit(0, width: 1),
                                        fp_rs1_data < fp_rs2_data,
                                        fp_rs1_data > fp_rs2_data))),
                            width: 1)
      fp_ordered_eq = local(:fp_ordered_eq,
                            (fp_rs1_data == fp_rs2_data) | fp_both_zero,
                            width: 1)
      fp_lt = local(:fp_lt, mux(fp_any_nan, lit(0, width: 1), fp_ordered_lt), width: 1)
      fp_eq = local(:fp_eq, mux(fp_any_nan, lit(0, width: 1), fp_ordered_eq), width: 1)
      fp_le = local(:fp_le, fp_lt | fp_eq, width: 1)

      fsgnj_sign = local(:fsgnj_sign,
                         case_select(funct3, {
                           0b000 => fp_rs2_sign,             # fsgnj.s
                           0b001 => ~fp_rs2_sign,            # fsgnjn.s
                           0b010 => fp_rs1_sign ^ fp_rs2_sign # fsgnjx.s
                         }, default: fp_rs2_sign),
                         width: 1)
      fsgnj_result = local(:fsgnj_result,
                           cat(fsgnj_sign, fp_rs1_data[30..0]),
                           width: 32)

      fp_canonical_nan = local(:fp_canonical_nan, lit(0x7FC00000, width: 32), width: 32)
      fp_min_zero = local(:fp_min_zero,
                          mux(fp_rs1_sign | fp_rs2_sign, lit(0x80000000, width: 32), lit(0, width: 32)),
                          width: 32)
      fp_max_zero = local(:fp_max_zero,
                          mux(fp_rs1_sign & fp_rs2_sign, lit(0x80000000, width: 32), lit(0, width: 32)),
                          width: 32)
      fp_min_result = local(:fp_min_result,
                            mux(fp_both_nan,
                                fp_canonical_nan,
                                mux(fp_rs1_is_nan,
                                    fp_rs2_data,
                                    mux(fp_rs2_is_nan,
                                        fp_rs1_data,
                                        mux(fp_both_zero,
                                            fp_min_zero,
                                            mux(fp_lt, fp_rs1_data, fp_rs2_data))))),
                            width: 32)
      fp_max_result = local(:fp_max_result,
                            mux(fp_both_nan,
                                fp_canonical_nan,
                                mux(fp_rs1_is_nan,
                                    fp_rs2_data,
                                    mux(fp_rs2_is_nan,
                                        fp_rs1_data,
                                        mux(fp_both_zero,
                                            fp_max_zero,
                                            mux(fp_lt, fp_rs2_data, fp_rs1_data))))),
                            width: 32)
      fp_minmax_result = local(:fp_minmax_result,
                               mux(funct3 == lit(0b000, width: 3), fp_min_result, fp_max_result),
                               width: 32)

      fp_is_inf = local(:fp_is_inf,
                        (fp_rs1_exp == lit(0xFF, width: 8)) & (fp_rs1_frac == lit(0, width: 23)),
                        width: 1)
      fp_is_subnormal = local(:fp_is_subnormal,
                              (fp_rs1_exp == lit(0, width: 8)) & (fp_rs1_frac != lit(0, width: 23)),
                              width: 1)
      fp_is_normal = local(:fp_is_normal,
                           (fp_rs1_exp != lit(0, width: 8)) & (fp_rs1_exp != lit(0xFF, width: 8)),
                           width: 1)
      fp_is_snan = local(:fp_is_snan, fp_rs1_is_nan & (fp_rs1_frac[22] == lit(0, width: 1)), width: 1)
      fp_is_qnan = local(:fp_is_qnan, fp_rs1_is_nan & (fp_rs1_frac[22] == lit(1, width: 1)), width: 1)
      fp_class_result = local(:fp_class_result,
                              mux(fp_is_inf & fp_rs1_sign, lit(1 << 0, width: 32),
                                  mux(fp_is_normal & fp_rs1_sign, lit(1 << 1, width: 32),
                                      mux(fp_is_subnormal & fp_rs1_sign, lit(1 << 2, width: 32),
                                          mux(fp_rs1_is_zero & fp_rs1_sign, lit(1 << 3, width: 32),
                                              mux(fp_rs1_is_zero & ~fp_rs1_sign, lit(1 << 4, width: 32),
                                                  mux(fp_is_subnormal & ~fp_rs1_sign, lit(1 << 5, width: 32),
                                                      mux(fp_is_normal & ~fp_rs1_sign, lit(1 << 6, width: 32),
                                                          mux(fp_is_inf & ~fp_rs1_sign, lit(1 << 7, width: 32),
                                                              mux(fp_is_snan, lit(1 << 8, width: 32),
                                                                  mux(fp_is_qnan, lit(1 << 9, width: 32),
                                                                      lit(0, width: 32))))))))))),
                              width: 32)
      fp_cmp_result = local(:fp_cmp_result,
                            case_select(funct3, {
                              0b010 => cat(lit(0, width: 31), fp_eq), # feq.s
                              0b001 => cat(lit(0, width: 31), fp_lt), # flt.s
                              0b000 => cat(lit(0, width: 31), fp_le)  # fle.s
                            }, default: lit(0, width: 32)),
                            width: 32)

      fp64_rs1_sign = fp_rs1_data64[63]
      fp64_rs1_exp = fp_rs1_data64[62..52]
      fp64_rs1_frac = fp_rs1_data64[51..0]
      fp64_rs1_is_zero = local(:fp64_rs1_is_zero,
                               (fp64_rs1_exp == lit(0, width: 11)) & (fp64_rs1_frac == lit(0, width: 52)),
                               width: 1)
      fp64_rs1_is_inf = local(:fp64_rs1_is_inf,
                              (fp64_rs1_exp == lit(0x7FF, width: 11)) & (fp64_rs1_frac == lit(0, width: 52)),
                              width: 1)
      fp64_rs1_is_nan = local(:fp64_rs1_is_nan,
                              (fp64_rs1_exp == lit(0x7FF, width: 11)) & (fp64_rs1_frac != lit(0, width: 52)),
                              width: 1)
      fp64_rs1_is_subnormal = local(:fp64_rs1_is_subnormal,
                                    (fp64_rs1_exp == lit(0, width: 11)) & (fp64_rs1_frac != lit(0, width: 52)),
                                    width: 1)
      fp64_rs1_is_normal = local(:fp64_rs1_is_normal,
                                 (fp64_rs1_exp != lit(0, width: 11)) & (fp64_rs1_exp != lit(0x7FF, width: 11)),
                                 width: 1)
      fp64_rs1_is_snan = local(:fp64_rs1_is_snan, fp64_rs1_is_nan & (fp64_rs1_frac[51] == lit(0, width: 1)), width: 1)
      fp64_rs1_is_qnan = local(:fp64_rs1_is_qnan, fp64_rs1_is_nan & (fp64_rs1_frac[51] == lit(1, width: 1)), width: 1)

      fp64_rs2_sign = fp_rs2_data64[63]
      fp64_rs2_exp = fp_rs2_data64[62..52]
      fp64_rs2_frac = fp_rs2_data64[51..0]
      fp64_rs3_sign = fp_rs3_data64[63]
      fp64_rs3_exp = fp_rs3_data64[62..52]
      fp64_rs3_frac = fp_rs3_data64[51..0]
      fp64_rs2_is_zero = local(:fp64_rs2_is_zero,
                               (fp64_rs2_exp == lit(0, width: 11)) & (fp64_rs2_frac == lit(0, width: 52)),
                               width: 1)
      fp64_rs2_is_nan = local(:fp64_rs2_is_nan,
                              (fp64_rs2_exp == lit(0x7FF, width: 11)) & (fp64_rs2_frac != lit(0, width: 52)),
                              width: 1)
      fp64_rs3_is_nan = local(:fp64_rs3_is_nan,
                              (fp64_rs3_exp == lit(0x7FF, width: 11)) & (fp64_rs3_frac != lit(0, width: 52)),
                              width: 1)
      fp64_both_zero = local(:fp64_both_zero, fp64_rs1_is_zero & fp64_rs2_is_zero, width: 1)
      fp64_any_nan = local(:fp64_any_nan, fp64_rs1_is_nan | fp64_rs2_is_nan, width: 1)
      fp64_both_nan = local(:fp64_both_nan, fp64_rs1_is_nan & fp64_rs2_is_nan, width: 1)
      fp64_ordered_lt = local(:fp64_ordered_lt,
                              mux(fp64_both_zero,
                                  lit(0, width: 1),
                                  mux(fp64_rs1_sign != fp64_rs2_sign,
                                      fp64_rs1_sign,
                                      mux(fp64_rs1_sign == lit(0, width: 1),
                                          fp_rs1_data64 < fp_rs2_data64,
                                          fp_rs1_data64 > fp_rs2_data64))),
                              width: 1)
      fp64_ordered_eq = local(:fp64_ordered_eq,
                              (fp_rs1_data64 == fp_rs2_data64) | fp64_both_zero,
                              width: 1)
      fp64_lt = local(:fp64_lt, mux(fp64_any_nan, lit(0, width: 1), fp64_ordered_lt), width: 1)
      fp64_eq = local(:fp64_eq, mux(fp64_any_nan, lit(0, width: 1), fp64_ordered_eq), width: 1)
      fp64_le = local(:fp64_le, fp64_lt | fp64_eq, width: 1)
      fsgnj_d_sign = local(:fsgnj_d_sign,
                           case_select(funct3, {
                             0b000 => fp64_rs2_sign,
                             0b001 => ~fp64_rs2_sign,
                             0b010 => fp64_rs1_sign ^ fp64_rs2_sign
                           }, default: fp64_rs2_sign),
                           width: 1)
      fsgnj_d_result64 = local(:fsgnj_d_result64, cat(fsgnj_d_sign, fp_rs1_data64[62..0]), width: 64)
      fp64_canonical_nan = local(:fp64_canonical_nan, lit(0x7FF8_0000_0000_0000, width: 64), width: 64)
      fp64_min_zero = local(:fp64_min_zero,
                            mux(fp64_rs1_sign | fp64_rs2_sign, cat(lit(1, width: 1), lit(0, width: 63)), lit(0, width: 64)),
                            width: 64)
      fp64_max_zero = local(:fp64_max_zero,
                            mux(fp64_rs1_sign & fp64_rs2_sign, cat(lit(1, width: 1), lit(0, width: 63)), lit(0, width: 64)),
                            width: 64)
      fp64_min_result = local(:fp64_min_result,
                              mux(fp64_both_nan,
                                  fp64_canonical_nan,
                                  mux(fp64_rs1_is_nan,
                                      fp_rs2_data64,
                                      mux(fp64_rs2_is_nan,
                                          fp_rs1_data64,
                                          mux(fp64_both_zero,
                                              fp64_min_zero,
                                              mux(fp64_lt, fp_rs1_data64, fp_rs2_data64))))),
                              width: 64)
      fp64_max_result = local(:fp64_max_result,
                              mux(fp64_both_nan,
                                  fp64_canonical_nan,
                                  mux(fp64_rs1_is_nan,
                                      fp_rs2_data64,
                                      mux(fp64_rs2_is_nan,
                                          fp_rs1_data64,
                                          mux(fp64_both_zero,
                                              fp64_max_zero,
                                              mux(fp64_lt, fp_rs2_data64, fp_rs1_data64))))),
                              width: 64)
      fp64_minmax_result = local(:fp64_minmax_result,
                                 mux(funct3 == lit(0b000, width: 3), fp64_min_result, fp64_max_result),
                                 width: 64)
      fp_cmp_d_result = local(:fp_cmp_d_result,
                              case_select(funct3, {
                                0b010 => cat(lit(0, width: 31), fp64_eq), # feq.d
                                0b001 => cat(lit(0, width: 31), fp64_lt), # flt.d
                                0b000 => cat(lit(0, width: 31), fp64_le)  # fle.d
                              }, default: lit(0, width: 32)),
                              width: 32)

      fp_exp_ge_127 = local(:fp_exp_ge_127, fp_rs1_exp >= lit(127, width: 8), width: 1)
      fp_exp_gt_157 = local(:fp_exp_gt_157, fp_rs1_exp > lit(157, width: 8), width: 1)
      fp_exp_ge_150 = local(:fp_exp_ge_150, fp_rs1_exp >= lit(150, width: 8), width: 1)
      fp_shift_left_amt = local(:fp_shift_left_amt, fp_rs1_exp - lit(150, width: 8), width: 8)
      fp_shift_right_amt = local(:fp_shift_right_amt, lit(150, width: 8) - fp_rs1_exp, width: 8)
      fp_mantissa = local(:fp_mantissa, cat(lit(1, width: 1), fp_rs1_frac), width: 24)
      fp_abs_int_from_float = local(:fp_abs_int_from_float,
                                    mux(fp_exp_ge_150,
                                        cat(lit(0, width: 8), fp_mantissa) << fp_shift_left_amt,
                                        cat(lit(0, width: 8), fp_mantissa) >> fp_shift_right_amt),
                                    width: 32)
      fp_signed_int_from_float = local(:fp_signed_int_from_float,
                                       mux(fp_rs1_sign, ~fp_abs_int_from_float + lit(1, width: 32), fp_abs_int_from_float),
                                       width: 32)
      fcvt_w_s_result = local(:fcvt_w_s_result,
                              mux(fp_rs1_is_nan | fp_exp_gt_157,
                                  lit(0x80000000, width: 32),
                                  mux(~fp_exp_ge_127,
                                      lit(0, width: 32),
                                      fp_signed_int_from_float)),
                              width: 32)
      fcvt_wu_s_result = local(:fcvt_wu_s_result,
                               mux(fp_rs1_is_nan | fp_exp_gt_157 | fp_rs1_sign,
                                   lit(0xFFFFFFFF, width: 32),
                                   mux(~fp_exp_ge_127,
                                       lit(0, width: 32),
                                       fp_abs_int_from_float)),
                               width: 32)

      fcvt_sw_sign = local(:fcvt_sw_sign,
                           mux(is_fcvt_s_w, rs1_data[31], lit(0, width: 1)),
                           width: 1)
      fcvt_sw_abs = local(:fcvt_sw_abs,
                          mux(is_fcvt_s_w & rs1_data[31], ~rs1_data + lit(1, width: 32), rs1_data),
                          width: 32)
      fcvt_sw_msb_expr = local(:fcvt_sw_msb_seed, lit(0, width: 6), width: 6)
      32.times do |i|
        fcvt_sw_msb_expr = local(:"fcvt_sw_msb_stage_#{i}",
                                 mux(fcvt_sw_abs[i], lit(i, width: 6), fcvt_sw_msb_expr),
                                 width: 6)
      end
      fcvt_sw_msb = local(:fcvt_sw_msb, fcvt_sw_msb_expr, width: 6)
      fcvt_sw_nonzero = local(:fcvt_sw_nonzero, fcvt_sw_abs != lit(0, width: 32), width: 1)
      fcvt_sw_shift_left_amt = local(:fcvt_sw_shift_left_amt, lit(23, width: 6) - fcvt_sw_msb, width: 6)
      fcvt_sw_shift_right_amt = local(:fcvt_sw_shift_right_amt, fcvt_sw_msb - lit(23, width: 6), width: 6)
      fcvt_sw_norm = local(:fcvt_sw_norm,
                           mux(fcvt_sw_msb > lit(23, width: 6),
                               fcvt_sw_abs >> fcvt_sw_shift_right_amt,
                               fcvt_sw_abs << fcvt_sw_shift_left_amt),
                           width: 32)
      fcvt_sw_frac = fcvt_sw_norm[22..0]
      fcvt_sw_exp = local(:fcvt_sw_exp, cat(lit(0, width: 2), fcvt_sw_msb) + lit(127, width: 8), width: 8)
      fcvt_s_w_result = local(:fcvt_s_w_result,
                              mux(fcvt_sw_nonzero,
                                  cat(fcvt_sw_sign, fcvt_sw_exp, fcvt_sw_frac),
                                  lit(0, width: 32)),
                              width: 32)

      fp64_class_result = local(:fp64_class_result,
                                mux(fp64_rs1_is_inf & fp64_rs1_sign, lit(1 << 0, width: 32),
                                    mux(fp64_rs1_is_normal & fp64_rs1_sign, lit(1 << 1, width: 32),
                                        mux(fp64_rs1_is_subnormal & fp64_rs1_sign, lit(1 << 2, width: 32),
                                            mux(fp64_rs1_is_zero & fp64_rs1_sign, lit(1 << 3, width: 32),
                                                mux(fp64_rs1_is_zero & ~fp64_rs1_sign, lit(1 << 4, width: 32),
                                                    mux(fp64_rs1_is_subnormal & ~fp64_rs1_sign, lit(1 << 5, width: 32),
                                                        mux(fp64_rs1_is_normal & ~fp64_rs1_sign, lit(1 << 6, width: 32),
                                                            mux(fp64_rs1_is_inf & ~fp64_rs1_sign, lit(1 << 7, width: 32),
                                                                mux(fp64_rs1_is_snan, lit(1 << 8, width: 32),
                                                                    mux(fp64_rs1_is_qnan, lit(1 << 9, width: 32),
                                                                        lit(0, width: 32))))))))))),
                                width: 32)
      fp64_rs1_exp_le_896 = local(:fp64_rs1_exp_le_896, fp64_rs1_exp <= lit(896, width: 11), width: 1)
      fp64_rs1_exp_gt_1150 = local(:fp64_rs1_exp_gt_1150, fp64_rs1_exp > lit(1150, width: 11), width: 1)
      fcvt_sd_exp11 = local(:fcvt_sd_exp11, fp64_rs1_exp - lit(896, width: 11), width: 11)
      fcvt_sd_frac = fp64_rs1_frac[51..29]
      fcvt_s_d_zero = local(:fcvt_s_d_zero, cat(fp64_rs1_sign, lit(0, width: 31)), width: 32)
      fcvt_s_d_inf = local(:fcvt_s_d_inf, cat(fp64_rs1_sign, lit(0xFF, width: 8), lit(0, width: 23)), width: 32)
      fcvt_s_d_norm = local(:fcvt_s_d_norm, cat(fp64_rs1_sign, fcvt_sd_exp11[7..0], fcvt_sd_frac), width: 32)
      fcvt_s_d_result = local(:fcvt_s_d_result,
                              mux(fp64_rs1_is_zero,
                                  fcvt_s_d_zero,
                                  mux(fp64_rs1_is_nan,
                                      lit(0x7FC0_0000, width: 32),
                                      mux(fp64_rs1_is_inf,
                                          fcvt_s_d_inf,
                                          mux(fp64_rs1_exp_le_896,
                                              fcvt_s_d_zero,
                                              mux(fp64_rs1_exp_gt_1150,
                                                  fcvt_s_d_inf,
                                                  fcvt_s_d_norm))))),
                              width: 32)

      fp64_exp_ge_1023 = local(:fp64_exp_ge_1023, fp64_rs1_exp >= lit(1023, width: 11), width: 1)
      fp64_exp_gt_1053 = local(:fp64_exp_gt_1053, fp64_rs1_exp > lit(1053, width: 11), width: 1)
      fp64_exp_ge_1075 = local(:fp64_exp_ge_1075, fp64_rs1_exp >= lit(1075, width: 11), width: 1)
      fp64_shift_left_amt = local(:fp64_shift_left_amt, fp64_rs1_exp - lit(1075, width: 11), width: 11)
      fp64_shift_right_amt = local(:fp64_shift_right_amt, lit(1075, width: 11) - fp64_rs1_exp, width: 11)
      fp64_mantissa = local(:fp64_mantissa, cat(lit(1, width: 1), fp64_rs1_frac), width: 53)
      fp64_abs_int_from_double = local(:fp64_abs_int_from_double,
                                       mux(fp64_exp_ge_1075,
                                           cat(lit(0, width: 11), fp64_mantissa) << fp64_shift_left_amt,
                                           cat(lit(0, width: 11), fp64_mantissa) >> fp64_shift_right_amt),
                                       width: 64)
      fp64_signed_int_from_double = local(:fp64_signed_int_from_double,
                                          mux(fp64_rs1_sign,
                                              ~fp64_abs_int_from_double + lit(1, width: 64),
                                              fp64_abs_int_from_double),
                                          width: 64)
      fcvt_w_d_result = local(:fcvt_w_d_result,
                              mux(fp64_rs1_is_nan | fp64_exp_gt_1053,
                                  lit(0x80000000, width: 32),
                                  mux(~fp64_exp_ge_1023,
                                      lit(0, width: 32),
                                      fp64_signed_int_from_double[31..0])),
                              width: 32)
      fcvt_wu_d_result = local(:fcvt_wu_d_result,
                               mux(fp64_rs1_is_nan | fp64_exp_gt_1053 | fp64_rs1_sign,
                                   lit(0xFFFFFFFF, width: 32),
                                   mux(~fp64_exp_ge_1023,
                                       lit(0, width: 32),
                                       fp64_abs_int_from_double[31..0])),
                               width: 32)

      fp64_rs2_exp_ge_1023 = local(:fp64_rs2_exp_ge_1023, fp64_rs2_exp >= lit(1023, width: 11), width: 1)
      fp64_rs2_exp_gt_1053 = local(:fp64_rs2_exp_gt_1053, fp64_rs2_exp > lit(1053, width: 11), width: 1)
      fp64_rs2_exp_ge_1075 = local(:fp64_rs2_exp_ge_1075, fp64_rs2_exp >= lit(1075, width: 11), width: 1)
      fp64_rs2_shift_left_amt = local(:fp64_rs2_shift_left_amt, fp64_rs2_exp - lit(1075, width: 11), width: 11)
      fp64_rs2_shift_right_amt = local(:fp64_rs2_shift_right_amt, lit(1075, width: 11) - fp64_rs2_exp, width: 11)
      fp64_rs2_mantissa = local(:fp64_rs2_mantissa, cat(lit(1, width: 1), fp64_rs2_frac), width: 53)
      fp64_rs2_abs_int_from_double = local(:fp64_rs2_abs_int_from_double,
                                           mux(fp64_rs2_exp_ge_1075,
                                               cat(lit(0, width: 11), fp64_rs2_mantissa) << fp64_rs2_shift_left_amt,
                                               cat(lit(0, width: 11), fp64_rs2_mantissa) >> fp64_rs2_shift_right_amt),
                                           width: 64)
      fp64_rs2_signed_int_from_double = local(:fp64_rs2_signed_int_from_double,
                                              mux(fp64_rs2_sign,
                                                  ~fp64_rs2_abs_int_from_double + lit(1, width: 64),
                                                  fp64_rs2_abs_int_from_double),
                                              width: 64)
      fcvt_w_d_rs2_result = local(:fcvt_w_d_rs2_result,
                                  mux(fp64_rs2_is_nan | fp64_rs2_exp_gt_1053,
                                      lit(0x80000000, width: 32),
                                      mux(~fp64_rs2_exp_ge_1023,
                                          lit(0, width: 32),
                                          fp64_rs2_signed_int_from_double[31..0])),
                                  width: 32)
      fp64_rs3_exp_ge_1023 = local(:fp64_rs3_exp_ge_1023, fp64_rs3_exp >= lit(1023, width: 11), width: 1)
      fp64_rs3_exp_gt_1053 = local(:fp64_rs3_exp_gt_1053, fp64_rs3_exp > lit(1053, width: 11), width: 1)
      fp64_rs3_exp_ge_1075 = local(:fp64_rs3_exp_ge_1075, fp64_rs3_exp >= lit(1075, width: 11), width: 1)
      fp64_rs3_shift_left_amt = local(:fp64_rs3_shift_left_amt, fp64_rs3_exp - lit(1075, width: 11), width: 11)
      fp64_rs3_shift_right_amt = local(:fp64_rs3_shift_right_amt, lit(1075, width: 11) - fp64_rs3_exp, width: 11)
      fp64_rs3_mantissa = local(:fp64_rs3_mantissa, cat(lit(1, width: 1), fp64_rs3_frac), width: 53)
      fp64_rs3_abs_int_from_double = local(:fp64_rs3_abs_int_from_double,
                                           mux(fp64_rs3_exp_ge_1075,
                                               cat(lit(0, width: 11), fp64_rs3_mantissa) << fp64_rs3_shift_left_amt,
                                               cat(lit(0, width: 11), fp64_rs3_mantissa) >> fp64_rs3_shift_right_amt),
                                           width: 64)
      fp64_rs3_signed_int_from_double = local(:fp64_rs3_signed_int_from_double,
                                              mux(fp64_rs3_sign,
                                                  ~fp64_rs3_abs_int_from_double + lit(1, width: 64),
                                                  fp64_rs3_abs_int_from_double),
                                              width: 64)
      fcvt_w_d_rs3_result = local(:fcvt_w_d_rs3_result,
                                  mux(fp64_rs3_is_nan | fp64_rs3_exp_gt_1053,
                                      lit(0x80000000, width: 32),
                                      mux(~fp64_rs3_exp_ge_1023,
                                          lit(0, width: 32),
                                          fp64_rs3_signed_int_from_double[31..0])),
                                  width: 32)

      d_add_i32 = local(:d_add_i32, fcvt_w_d_result + fcvt_w_d_rs2_result, width: 32)
      d_sub_i32 = local(:d_sub_i32, fcvt_w_d_result - fcvt_w_d_rs2_result, width: 32)
      d_mul_a_sign = fcvt_w_d_result[31]
      d_mul_b_sign = fcvt_w_d_rs2_result[31]
      d_mul_a_abs = local(:d_mul_a_abs,
                          mux(d_mul_a_sign, ~fcvt_w_d_result + lit(1, width: 32), fcvt_w_d_result),
                          width: 32)
      d_mul_b_abs = local(:d_mul_b_abs,
                          mux(d_mul_b_sign, ~fcvt_w_d_rs2_result + lit(1, width: 32), fcvt_w_d_rs2_result),
                          width: 32)
      d_mul_abs64 = local(:d_mul_abs64, cat(lit(0, width: 32), d_mul_a_abs) * cat(lit(0, width: 32), d_mul_b_abs), width: 64)
      d_mul_neg = local(:d_mul_neg, d_mul_a_sign ^ d_mul_b_sign, width: 1)
      d_mul_i64 = local(:d_mul_i64,
                        mux(d_mul_neg, ~d_mul_abs64 + lit(1, width: 64), d_mul_abs64),
                        width: 64)
      d_mul_i32 = d_mul_i64[31..0]
      d_fmadd_i32 = local(:d_fmadd_i32, d_mul_i32 + fcvt_w_d_rs3_result, width: 32)
      d_fmsub_i32 = local(:d_fmsub_i32, d_mul_i32 - fcvt_w_d_rs3_result, width: 32)
      d_fnmsub_i32 = local(:d_fnmsub_i32, (~d_mul_i32 + lit(1, width: 32)) + fcvt_w_d_rs3_result, width: 32)
      d_fnmadd_i32 = local(:d_fnmadd_i32, (~d_mul_i32 + lit(1, width: 32)) - fcvt_w_d_rs3_result, width: 32)
      d_div_a_sign = fcvt_w_d_result[31]
      d_div_b_sign = fcvt_w_d_rs2_result[31]
      d_div_a_abs = local(:d_div_a_abs,
                          mux(d_div_a_sign, ~fcvt_w_d_result + lit(1, width: 32), fcvt_w_d_result),
                          width: 32)
      d_div_b_abs = local(:d_div_b_abs,
                          mux(d_div_b_sign, ~fcvt_w_d_rs2_result + lit(1, width: 32), fcvt_w_d_rs2_result),
                          width: 32)
      d_div_abs = local(:d_div_abs,
                        mux(d_div_b_abs == lit(0, width: 32), lit(0, width: 32), d_div_a_abs / d_div_b_abs),
                        width: 32)
      d_div_neg = local(:d_div_neg, d_div_a_sign ^ d_div_b_sign, width: 1)
      d_div_i32 = local(:d_div_i32,
                        mux(d_div_neg, ~d_div_abs + lit(1, width: 32), d_div_abs),
                        width: 32)
      d_sqrt_input_abs = local(:d_sqrt_input_abs,
                               mux(fcvt_w_d_result[31], ~fcvt_w_d_result + lit(1, width: 32), fcvt_w_d_result),
                               width: 32)
      d_sqrt_result_expr = local(:d_sqrt_result_seed, lit(0, width: 32), width: 32)
      16.times do |k|
        bit = 15 - k
        trial = local(:"d_sqrt_trial_#{bit}", d_sqrt_result_expr | lit(1 << bit, width: 32), width: 32)
        trial_sq = local(:"d_sqrt_trial_sq_#{bit}", cat(lit(0, width: 32), trial) * cat(lit(0, width: 32), trial), width: 64)
        d_sqrt_result_expr = local(:"d_sqrt_result_stage_#{bit}",
                                   mux(trial_sq <= cat(lit(0, width: 32), d_sqrt_input_abs), trial, d_sqrt_result_expr),
                                   width: 32)
      end
      d_sqrt_i32 = local(:d_sqrt_i32,
                         mux(fcvt_w_d_result[31], lit(0, width: 32), d_sqrt_result_expr),
                         width: 32)
      d_alu_i32 = local(:d_alu_i32,
                        mux(is_fadd_d, d_add_i32,
                            mux(is_fsub_d, d_sub_i32,
                                mux(is_fmul_d, d_mul_i32,
                                    mux(is_fmadd_d, d_fmadd_i32,
                                        mux(is_fmsub_d, d_fmsub_i32,
                                            mux(is_fnmsub_d, d_fnmsub_i32,
                                                mux(is_fnmadd_d, d_fnmadd_i32,
                                                    mux(is_fdiv_d, d_div_i32,
                                                        mux(is_fsqrt_d, d_sqrt_i32, lit(0, width: 32)))))))))),
                        width: 32)
      d_alu_sign = d_alu_i32[31]
      d_alu_abs = local(:d_alu_abs,
                        mux(d_alu_i32[31], ~d_alu_i32 + lit(1, width: 32), d_alu_i32),
                        width: 32)
      d_alu_msb_expr = local(:d_alu_msb_seed, lit(0, width: 6), width: 6)
      32.times do |i|
        d_alu_msb_expr = local(:"d_alu_msb_stage_#{i}",
                               mux(d_alu_abs[i], lit(i, width: 6), d_alu_msb_expr),
                               width: 6)
      end
      d_alu_msb = local(:d_alu_msb, d_alu_msb_expr, width: 6)
      d_alu_nonzero = local(:d_alu_nonzero, d_alu_abs != lit(0, width: 32), width: 1)
      d_alu_shift_left_amt = local(:d_alu_shift_left_amt, lit(52, width: 6) - d_alu_msb, width: 6)
      d_alu_norm = local(:d_alu_norm, cat(lit(0, width: 32), d_alu_abs) << d_alu_shift_left_amt, width: 64)
      d_alu_frac52 = d_alu_norm[51..0]
      d_alu_exp11 = local(:d_alu_exp11, cat(lit(0, width: 5), d_alu_msb) + lit(1023, width: 11), width: 11)
      d_alu_result64 = local(:d_alu_result64,
                             mux(d_alu_nonzero,
                                 cat(d_alu_sign, d_alu_exp11, d_alu_frac52),
                                 lit(0, width: 64)),
                             width: 64)

      fcvt_ds_exp11 = local(:fcvt_ds_exp11, cat(lit(0, width: 3), fp_rs1_exp) + lit(896, width: 11), width: 11)
      fcvt_ds_frac52 = local(:fcvt_ds_frac52, cat(fp_rs1_frac, lit(0, width: 29)), width: 52)
      fcvt_d_s_zero = local(:fcvt_d_s_zero, cat(fp_rs1_sign, lit(0, width: 11), lit(0, width: 52)), width: 64)
      fcvt_d_s_inf = local(:fcvt_d_s_inf, cat(fp_rs1_sign, lit(0x7FF, width: 11), lit(0, width: 52)), width: 64)
      fcvt_d_s_nan = local(:fcvt_d_s_nan, cat(fp_rs1_sign, lit(0x7FF, width: 11), cat(fp_rs1_frac, lit(0, width: 29))), width: 64)
      fcvt_d_s_norm = local(:fcvt_d_s_norm, cat(fp_rs1_sign, fcvt_ds_exp11, fcvt_ds_frac52), width: 64)
      fcvt_d_s_result64 = local(:fcvt_d_s_result64,
                                mux(fp_rs1_is_zero | fp_is_subnormal,
                                    fcvt_d_s_zero,
                                    mux(fp_rs1_is_nan,
                                        fcvt_d_s_nan,
                                        mux(fp_is_inf,
                                            fcvt_d_s_inf,
                                            fcvt_d_s_norm))),
                                width: 64)
      fcvt_dw_sign = local(:fcvt_dw_sign,
                           mux(is_fcvt_d_w, rs1_data[31], lit(0, width: 1)),
                           width: 1)
      fcvt_dw_abs = local(:fcvt_dw_abs,
                          mux(is_fcvt_d_w & rs1_data[31], ~rs1_data + lit(1, width: 32), rs1_data),
                          width: 32)
      fcvt_dw_msb_expr = local(:fcvt_dw_msb_seed, lit(0, width: 6), width: 6)
      32.times do |i|
        fcvt_dw_msb_expr = local(:"fcvt_dw_msb_stage_#{i}",
                                 mux(fcvt_dw_abs[i], lit(i, width: 6), fcvt_dw_msb_expr),
                                 width: 6)
      end
      fcvt_dw_msb = local(:fcvt_dw_msb, fcvt_dw_msb_expr, width: 6)
      fcvt_dw_nonzero = local(:fcvt_dw_nonzero, fcvt_dw_abs != lit(0, width: 32), width: 1)
      fcvt_dw_shift_left_amt = local(:fcvt_dw_shift_left_amt, lit(52, width: 6) - fcvt_dw_msb, width: 6)
      fcvt_dw_norm = local(:fcvt_dw_norm, cat(lit(0, width: 32), fcvt_dw_abs) << fcvt_dw_shift_left_amt, width: 64)
      fcvt_dw_frac52 = fcvt_dw_norm[51..0]
      fcvt_dw_exp11 = local(:fcvt_dw_exp11, cat(lit(0, width: 5), fcvt_dw_msb) + lit(1023, width: 11), width: 11)
      fcvt_d_w_result64 = local(:fcvt_d_w_result64,
                                mux(fcvt_dw_nonzero,
                                    cat(fcvt_dw_sign, fcvt_dw_exp11, fcvt_dw_frac52),
                                    lit(0, width: 64)),
                                width: 64)

      # RVV scoped baseline decode/data path
      # Supported:
      # - vsetvli (rd, rs1, zimm)
      # - vmv.v.x, vmv.s.x, vmv.x.s
      # - vadd.vv, vadd.vx
      # Baseline profile:
      # - VLEN=128, SEW=32, LMUL=1, VLMAX=4
      # - unmasked execution only (vm=1)
      is_op_v = local(:is_op_v, opcode == lit(Opcode::OP_V, width: 7), width: 1)
      v_funct6 = inst_exec[31..26]
      v_vm = inst_exec[25]
      is_vsetvli = local(:is_vsetvli,
                         is_op_v &
                         (funct3 == lit(0b111, width: 3)) &
                         (inst_exec[31] == lit(0, width: 1)),
                         width: 1)
      is_vadd_vv = local(:is_vadd_vv,
                         is_op_v &
                         (funct3 == lit(0b000, width: 3)) &
                         (v_funct6 == lit(0b000000, width: 6)) &
                         v_vm,
                         width: 1)
      is_vadd_vx = local(:is_vadd_vx,
                         is_op_v &
                         (funct3 == lit(0b100, width: 3)) &
                         (v_funct6 == lit(0b000000, width: 6)) &
                         v_vm,
                         width: 1)
      is_vmv_v_x = local(:is_vmv_v_x,
                         is_op_v &
                         (funct3 == lit(0b100, width: 3)) &
                         (v_funct6 == lit(0b010111, width: 6)) &
                         v_vm &
                         (rs2 == lit(0, width: 5)),
                         width: 1)
      is_vmv_x_s = local(:is_vmv_x_s,
                         is_op_v &
                         (funct3 == lit(0b010, width: 3)) &
                         (v_funct6 == lit(0b010000, width: 6)) &
                         v_vm &
                         (rs1 == lit(0, width: 5)),
                         width: 1)
      is_vmv_s_x = local(:is_vmv_s_x,
                         is_op_v &
                         (funct3 == lit(0b110, width: 3)) &
                         (v_funct6 == lit(0b010000, width: 6)) &
                         v_vm &
                         (rs2 == lit(0, width: 5)),
                         width: 1)
      vsetvli_avl = local(:vsetvli_avl,
                          mux(rs1 == lit(0, width: 5), lit(4, width: 32), rs1_data),
                          width: 32)
      vsetvli_new_vl = local(:vsetvli_new_vl,
                             mux(vsetvli_avl > lit(4, width: 32), lit(4, width: 32), vsetvli_avl),
                             width: 32)
      vsetvli_new_vtype = local(:vsetvli_new_vtype,
                                cat(lit(0, width: 21), inst_exec[30..20]),
                                width: 32)
      v_lane0_active = local(:v_lane0_active, vec_vl > lit(0, width: 32), width: 1)
      v_lane1_active = local(:v_lane1_active, vec_vl > lit(1, width: 32), width: 1)
      v_lane2_active = local(:v_lane2_active, vec_vl > lit(2, width: 32), width: 1)
      v_lane3_active = local(:v_lane3_active, vec_vl > lit(3, width: 32), width: 1)
      v_lane0_vadd_vv = local(:v_lane0_vadd_vv, v_rs2_lane0 + v_rs1_lane0, width: 32)
      v_lane1_vadd_vv = local(:v_lane1_vadd_vv, v_rs2_lane1 + v_rs1_lane1, width: 32)
      v_lane2_vadd_vv = local(:v_lane2_vadd_vv, v_rs2_lane2 + v_rs1_lane2, width: 32)
      v_lane3_vadd_vv = local(:v_lane3_vadd_vv, v_rs2_lane3 + v_rs1_lane3, width: 32)
      v_lane0_vadd_vx = local(:v_lane0_vadd_vx, v_rs2_lane0 + rs1_data, width: 32)
      v_lane1_vadd_vx = local(:v_lane1_vadd_vx, v_rs2_lane1 + rs1_data, width: 32)
      v_lane2_vadd_vx = local(:v_lane2_vadd_vx, v_rs2_lane2 + rs1_data, width: 32)
      v_lane3_vadd_vx = local(:v_lane3_vadd_vx, v_rs2_lane3 + rs1_data, width: 32)
      v_all_lane_write = local(:v_all_lane_write, is_vmv_v_x | is_vadd_vv | is_vadd_vx, width: 1)
      v_lane0_all_next = local(:v_lane0_all_next,
                               mux(is_vmv_v_x, rs1_data,
                                   mux(is_vadd_vv, v_lane0_vadd_vv,
                                       mux(is_vadd_vx, v_lane0_vadd_vx, v_rd_lane0))),
                               width: 32)
      v_lane1_all_next = local(:v_lane1_all_next,
                               mux(is_vmv_v_x, rs1_data,
                                   mux(is_vadd_vv, v_lane1_vadd_vv,
                                       mux(is_vadd_vx, v_lane1_vadd_vx, v_rd_lane1))),
                               width: 32)
      v_lane2_all_next = local(:v_lane2_all_next,
                               mux(is_vmv_v_x, rs1_data,
                                   mux(is_vadd_vv, v_lane2_vadd_vv,
                                       mux(is_vadd_vx, v_lane2_vadd_vx, v_rd_lane2))),
                               width: 32)
      v_lane3_all_next = local(:v_lane3_all_next,
                               mux(is_vmv_v_x, rs1_data,
                                   mux(is_vadd_vv, v_lane3_vadd_vv,
                                       mux(is_vadd_vx, v_lane3_vadd_vx, v_rd_lane3))),
                               width: 32)
      v_scalar_result = local(:v_scalar_result, mux(is_vsetvli, vsetvli_new_vl, v_rs2_lane0), width: 32)

      # Atomic (RV32A) decode/data path
      is_amo_word = local(:is_amo_word,
                          (opcode == lit(Opcode::AMO, width: 7)) & (funct3 == lit(Funct3::WORD, width: 3)),
                          width: 1)
      amo_funct5 = inst_exec[31..27]
      is_lr = local(:is_lr,
                    is_amo_word & (amo_funct5 == lit(0b00010, width: 5)) & (rs2 == lit(0, width: 5)),
                    width: 1)
      is_sc = local(:is_sc, is_amo_word & (amo_funct5 == lit(0b00011, width: 5)), width: 1)
      is_amocas = local(:is_amocas, is_amo_word & (amo_funct5 == lit(0b00101, width: 5)), width: 1)
      is_amo_rmw = local(:is_amo_rmw,
                         is_amo_word & (
                           (amo_funct5 == lit(0b00000, width: 5)) | # AMOADD.W
                           (amo_funct5 == lit(0b00001, width: 5)) | # AMOSWAP.W
                           (amo_funct5 == lit(0b00101, width: 5)) | # AMOCAS.W
                           (amo_funct5 == lit(0b00100, width: 5)) | # AMOXOR.W
                           (amo_funct5 == lit(0b01000, width: 5)) | # AMOOR.W
                           (amo_funct5 == lit(0b01100, width: 5)) | # AMOAND.W
                           (amo_funct5 == lit(0b10000, width: 5)) | # AMOMIN.W
                           (amo_funct5 == lit(0b10100, width: 5)) | # AMOMAX.W
                           (amo_funct5 == lit(0b11000, width: 5)) | # AMOMINU.W
                           (amo_funct5 == lit(0b11100, width: 5))   # AMOMAXU.W
                         ),
                         width: 1)
      is_amo = local(:is_amo, is_lr | is_sc | is_amo_rmw, width: 1)
      amo_old = local(:amo_old, data_rdata, width: 32)
      amo_old_sign = amo_old[31]
      rs2_sign = rs2_data[31]
      amo_old_lt_signed = local(:amo_old_lt_signed,
                                mux(amo_old_sign != rs2_sign, amo_old_sign, amo_old < rs2_data),
                                width: 1)
      amo_min_signed = local(:amo_min_signed, mux(amo_old_lt_signed, amo_old, rs2_data), width: 32)
      amo_max_signed = local(:amo_max_signed, mux(amo_old_lt_signed, rs2_data, amo_old), width: 32)
      amo_min_unsigned = local(:amo_min_unsigned, mux(amo_old < rs2_data, amo_old, rs2_data), width: 32)
      amo_max_unsigned = local(:amo_max_unsigned, mux(amo_old < rs2_data, rs2_data, amo_old), width: 32)
      amo_new_data = local(:amo_new_data, case_select(amo_funct5, {
        0b00000 => amo_old + rs2_data,  # AMOADD.W
        0b00001 => rs2_data,            # AMOSWAP.W
        0b00101 => rs2_data,            # AMOCAS.W (store candidate)
        0b00100 => amo_old ^ rs2_data,  # AMOXOR.W
        0b01000 => amo_old | rs2_data,  # AMOOR.W
        0b01100 => amo_old & rs2_data,  # AMOAND.W
        0b10000 => amo_min_signed,      # AMOMIN.W
        0b10100 => amo_max_signed,      # AMOMAX.W
        0b11000 => amo_min_unsigned,    # AMOMINU.W
        0b11100 => amo_max_unsigned     # AMOMAXU.W
      }, default: rs2_data), width: 32)
      amo_expected = local(:amo_expected, rd_lookup_data, width: 32)
      amo_cas_success = local(:amo_cas_success, amo_old == amo_expected, width: 1)
      amo_sc_success = local(:amo_sc_success, reservation_valid & (reservation_addr == rs1_data), width: 1)
      amo_mem_read = local(:amo_mem_read, is_lr | is_amo_rmw, width: 1)
      amo_mem_write = local(:amo_mem_write,
                            (is_sc & amo_sc_success) |
                            (is_amo_rmw & (~is_amocas | amo_cas_success)),
                            width: 1)
      amo_rd_data = local(:amo_rd_data,
                          mux(is_sc, mux(amo_sc_success, lit(0, width: 32), lit(1, width: 32)), amo_old),
                          width: 32)
      data_vaddr = local(:data_vaddr, mux(is_amo, rs1_data, alu_result), width: 32)
      data_access_req = local(:data_access_req, mem_read | mem_write | is_amo, width: 1)
      data_store_access = local(:data_store_access, mem_write | is_sc | is_amo_rmw, width: 1)

      # Sv32 translation context.
      satp_mode_sv32 = local(:satp_mode_sv32, csr_read_data8[31], width: 1)
      satp_root_ppn = csr_read_data8[19..0]
      satp_root_base = local(:satp_root_base, cat(satp_root_ppn, lit(0, width: 12)), width: 32)
      priv_is_u = local(:priv_is_u, priv_mode == lit(PrivMode::USER, width: 2), width: 1)
      priv_is_s = local(:priv_is_s, priv_mode == lit(PrivMode::SUPERVISOR, width: 2), width: 1)
      priv_is_m = local(:priv_is_m, priv_mode == lit(PrivMode::MACHINE, width: 2), width: 1)
      satp_translate = local(:satp_translate, satp_mode_sv32 & ~priv_is_m, width: 1)
      sum_enabled = local(:sum_enabled,
                          (((csr_read_data2 | csr_read_data4) & lit(0x40000, width: 32)) != lit(0, width: 32)),
                          width: 1)
      mxr_enabled = local(:mxr_enabled,
                          (((csr_read_data2 | csr_read_data4) & lit(0x80000, width: 32)) != lit(0, width: 32)),
                          width: 1)

      # Sv32 instruction translation (for instruction fetch at PC).
      inst_vaddr = local(:inst_vaddr, pc, width: 32)
      inst_vpn = inst_vaddr[31..12]
      inst_vpn1 = inst_vaddr[31..22]
      inst_vpn0 = inst_vaddr[21..12]
      inst_page_off = inst_vaddr[11..0]
      inst_tlb_lookup_en <= satp_translate
      inst_tlb_lookup_vpn <= inst_vpn
      inst_tlb_lookup_root <= satp_root_ppn
      inst_ptw_addr1_calc = local(:inst_ptw_addr1_calc,
                                  satp_root_base + cat(lit(0, width: 20), inst_vpn1, lit(0, width: 2)),
                                  width: 32)
      inst_l0_base = local(:inst_l0_base, cat(inst_ptw_pte1[29..10], lit(0, width: 12)), width: 32)
      inst_ptw_addr0_calc = local(:inst_ptw_addr0_calc,
                                  inst_l0_base + cat(lit(0, width: 20), inst_vpn0, lit(0, width: 2)),
                                  width: 32)
      inst_pte1_leaf = local(:inst_pte1_leaf,
                             inst_ptw_pte1[0] & (inst_ptw_pte1[1] | inst_ptw_pte1[3]),
                             width: 1)
      inst_pte1_next = local(:inst_pte1_next,
                             inst_ptw_pte1[0] & ~(inst_ptw_pte1[1] | inst_ptw_pte1[3]),
                             width: 1)
      inst_pte0_leaf = local(:inst_pte0_leaf,
                             inst_pte1_next & inst_ptw_pte0[0] & (inst_ptw_pte0[1] | inst_ptw_pte0[3]),
                             width: 1)
      inst_walk_ok = local(:inst_walk_ok, inst_pte1_leaf | inst_pte0_leaf, width: 1)
      inst_walk_pte = local(:inst_walk_pte, mux(inst_pte1_leaf, inst_ptw_pte1, inst_ptw_pte0), width: 32)
      inst_walk_ppn = local(:inst_walk_ppn,
                            mux(inst_pte1_leaf, cat(inst_ptw_pte1[29..20], inst_vpn0), inst_ptw_pte0[29..10]),
                            width: 20)
      inst_walk_perm_r = inst_walk_pte[1]
      inst_walk_perm_w = inst_walk_pte[2]
      inst_walk_perm_x = inst_walk_pte[3]
      inst_walk_perm_u = inst_walk_pte[4]
      inst_tlb_fill_en <= satp_translate & ~inst_tlb_hit & inst_walk_ok
      inst_tlb_fill_vpn <= inst_vpn
      inst_tlb_fill_root <= satp_root_ppn
      inst_tlb_fill_ppn <= inst_walk_ppn
      inst_tlb_fill_perm_r <= inst_walk_perm_r
      inst_tlb_fill_perm_w <= inst_walk_perm_w
      inst_tlb_fill_perm_x <= inst_walk_perm_x
      inst_tlb_fill_perm_u <= inst_walk_perm_u
      inst_translated = local(:inst_translated, inst_tlb_hit | inst_walk_ok, width: 1)
      inst_eff_ppn = local(:inst_eff_ppn, mux(inst_tlb_hit, inst_tlb_ppn, inst_walk_ppn), width: 20)
      inst_eff_perm_x = local(:inst_eff_perm_x, mux(inst_tlb_hit, inst_tlb_perm_x, inst_walk_perm_x), width: 1)
      inst_eff_perm_u = local(:inst_eff_perm_u, mux(inst_tlb_hit, inst_tlb_perm_u, inst_walk_perm_u), width: 1)
      inst_u_ok = local(:inst_u_ok,
                        mux(priv_is_u, inst_eff_perm_u,
                            mux(priv_is_s, ~inst_eff_perm_u, lit(1, width: 1))),
                        width: 1)
      inst_perm_ok = local(:inst_perm_ok, inst_translated & inst_eff_perm_x & inst_u_ok, width: 1)
      inst_paddr = local(:inst_paddr, cat(inst_eff_ppn, inst_page_off), width: 32)
      inst_page_fault = local(:inst_page_fault, satp_translate & ~inst_perm_ok, width: 1)

      # Sv32 data translation (address walk inputs are provided via external ports).
      data_vpn = data_vaddr[31..12]
      data_vpn1 = data_vaddr[31..22]
      data_vpn0 = data_vaddr[21..12]
      data_page_off = data_vaddr[11..0]
      data_tlb_lookup_en <= satp_translate & data_access_req
      data_tlb_lookup_vpn <= data_vpn
      data_tlb_lookup_root <= satp_root_ppn
      data_ptw_addr1_calc = local(:data_ptw_addr1_calc,
                                  satp_root_base + cat(lit(0, width: 20), data_vpn1, lit(0, width: 2)),
                                  width: 32)
      data_l0_base = local(:data_l0_base, cat(data_ptw_pte1[29..10], lit(0, width: 12)), width: 32)
      data_ptw_addr0_calc = local(:data_ptw_addr0_calc,
                                  data_l0_base + cat(lit(0, width: 20), data_vpn0, lit(0, width: 2)),
                                  width: 32)
      data_pte1_leaf = local(:data_pte1_leaf,
                             data_ptw_pte1[0] & (data_ptw_pte1[1] | data_ptw_pte1[3]),
                             width: 1)
      data_pte1_next = local(:data_pte1_next,
                             data_ptw_pte1[0] & ~(data_ptw_pte1[1] | data_ptw_pte1[3]),
                             width: 1)
      data_pte0_leaf = local(:data_pte0_leaf,
                             data_pte1_next & data_ptw_pte0[0] & (data_ptw_pte0[1] | data_ptw_pte0[3]),
                             width: 1)
      data_walk_ok = local(:data_walk_ok, data_pte1_leaf | data_pte0_leaf, width: 1)
      data_walk_pte = local(:data_walk_pte, mux(data_pte1_leaf, data_ptw_pte1, data_ptw_pte0), width: 32)
      data_walk_ppn = local(:data_walk_ppn,
                            mux(data_pte1_leaf, cat(data_ptw_pte1[29..20], data_vpn0), data_ptw_pte0[29..10]),
                            width: 20)
      data_walk_perm_r = data_walk_pte[1]
      data_walk_perm_w = data_walk_pte[2]
      data_walk_perm_x = data_walk_pte[3]
      data_walk_perm_u = data_walk_pte[4]
      data_tlb_fill_en <= satp_translate & data_access_req & ~data_tlb_hit & data_walk_ok
      data_tlb_fill_vpn <= data_vpn
      data_tlb_fill_root <= satp_root_ppn
      data_tlb_fill_ppn <= data_walk_ppn
      data_tlb_fill_perm_r <= data_walk_perm_r
      data_tlb_fill_perm_w <= data_walk_perm_w
      data_tlb_fill_perm_x <= data_walk_perm_x
      data_tlb_fill_perm_u <= data_walk_perm_u
      data_translated = local(:data_translated, data_tlb_hit | data_walk_ok, width: 1)
      data_eff_ppn = local(:data_eff_ppn, mux(data_tlb_hit, data_tlb_ppn, data_walk_ppn), width: 20)
      data_eff_perm_r = local(:data_eff_perm_r, mux(data_tlb_hit, data_tlb_perm_r, data_walk_perm_r), width: 1)
      data_eff_perm_w = local(:data_eff_perm_w, mux(data_tlb_hit, data_tlb_perm_w, data_walk_perm_w), width: 1)
      data_eff_perm_x = local(:data_eff_perm_x, mux(data_tlb_hit, data_tlb_perm_x, data_walk_perm_x), width: 1)
      data_eff_perm_u = local(:data_eff_perm_u, mux(data_tlb_hit, data_tlb_perm_u, data_walk_perm_u), width: 1)
      data_need_read = local(:data_need_read, mem_read | is_lr | is_amo_rmw, width: 1)
      data_need_write = local(:data_need_write, mem_write | is_sc | is_amo_rmw, width: 1)
      data_read_ok = local(:data_read_ok, data_eff_perm_r | (mxr_enabled & data_eff_perm_x), width: 1)
      data_write_ok = local(:data_write_ok, data_eff_perm_w, width: 1)
      data_rw_ok = local(:data_rw_ok,
                         (~data_need_read | data_read_ok) & (~data_need_write | data_write_ok),
                         width: 1)
      data_u_ok = local(:data_u_ok,
                        mux(priv_is_u, data_eff_perm_u,
                            mux(priv_is_s, mux(data_eff_perm_u, sum_enabled, lit(1, width: 1)), lit(1, width: 1))),
                        width: 1)
      data_perm_ok = local(:data_perm_ok, data_translated & data_rw_ok & data_u_ok, width: 1)
      data_paddr = local(:data_paddr, cat(data_eff_ppn, data_page_off), width: 32)
      data_page_fault = local(:data_page_fault,
                              satp_translate & data_access_req & ~data_perm_ok,
                              width: 1)
      data_page_fault_cause = local(:data_page_fault_cause,
                                    mux(data_store_access, lit(15, width: 32), lit(13, width: 32)),
                                    width: 32)

      # CSR and SYSTEM decode
      is_csr_instr = local(:is_csr_instr,
                           (opcode == lit(Opcode::SYSTEM, width: 7)) & (funct3 != lit(0, width: 3)),
                           width: 1)
      is_system_plain = local(:is_system_plain,
                              (opcode == lit(Opcode::SYSTEM, width: 7)) & (funct3 == lit(0, width: 3)),
                              width: 1)
      sys_imm = inst_exec[31..20]
      is_ecall = local(:is_ecall, is_system_plain & (sys_imm == lit(0x000, width: 12)), width: 1)
      is_ebreak = local(:is_ebreak, is_system_plain & (sys_imm == lit(0x001, width: 12)), width: 1)
      is_sret = local(:is_sret, is_system_plain & (sys_imm == lit(0x102, width: 12)), width: 1)
      is_mret = local(:is_mret, is_system_plain & (sys_imm == lit(0x302, width: 12)), width: 1)
      is_wfi = local(:is_wfi, is_system_plain & (sys_imm == lit(0x105, width: 12)), width: 1)
      is_wrs_nto = local(:is_wrs_nto, is_system_plain & (sys_imm == lit(0x00D, width: 12)), width: 1)
      is_wrs_sto = local(:is_wrs_sto, is_system_plain & (sys_imm == lit(0x01D, width: 12)), width: 1)
      is_sfence_vma = local(:is_sfence_vma,
                            is_system_plain & (inst_exec[31..25] == lit(0b0001001, width: 7)) & (rd == lit(0, width: 5)),
                            width: 1)
      is_illegal_system = local(:is_illegal_system,
                                is_system_plain & ~(is_ecall | is_ebreak | is_mret | is_sret | is_wfi |
                                                     is_wrs_nto | is_wrs_sto | is_sfence_vma),
                                width: 1)
      # Hardware interrupt pending bits at RISC-V standard positions.
      # External timer input is mirrored to both MTIP (bit 7) and STIP (bit 5):
      # - MTIP keeps M-mode timer semantics for xv6/machine-mode paths.
      # - STIP allows S-mode Linux timer delivery through mideleg/sie.
      # Software-writable SSIP (bit 1) is merged from CSR store (SIP register).
      irq_pending_bits = local(:irq_pending_bits,
                               (csr_read_data13 & lit(0x2, width: 32)) |
                               mux(irq_software, lit(0x8, width: 32), lit(0, width: 32)) |
                               mux(irq_timer, lit(0xA0, width: 32), lit(0, width: 32)) |
                               mux(irq_external, lit(0x200, width: 32), lit(0, width: 32)),
                               width: 32)
      csr_use_imm = funct3[2]
      csr_src = local(:csr_src, mux(csr_use_imm, cat(lit(0, width: 27), rs1), rs1_data), width: 32)
      csr_rs1_nonzero = local(:csr_rs1_nonzero, rs1 != lit(0, width: 5), width: 1)

      # Interrupt enable filtering for M-mode (mstatus/mie) and S-mode (sstatus/sie).
      # Per RISC-V spec, machine-level interrupt bits (MSIP=3, MTIP=7, MEIP=11) are
      # not delegable to S-mode. Mask them out of mideleg (csr_read_data7).
      effective_mideleg = local(:effective_mideleg, csr_read_data7 & lit(0xFFFFF777, width: 32), width: 32)
      machine_irq_masked = local(:machine_irq_masked, irq_pending_bits & ~effective_mideleg, width: 32)
      super_irq_masked = local(:super_irq_masked, irq_pending_bits & effective_mideleg, width: 32)
      super_sie_machine_alias = local(
        :super_sie_machine_alias,
        mux((csr_read_data5 & lit(0x002, width: 32)) != lit(0, width: 32), lit(0x008, width: 32), lit(0, width: 32)) |
        mux((csr_read_data5 & lit(0x020, width: 32)) != lit(0, width: 32), lit(0x080, width: 32), lit(0, width: 32)) |
        mux((csr_read_data5 & lit(0x200, width: 32)) != lit(0, width: 32), lit(0x800, width: 32), lit(0, width: 32)),
        width: 32
      )
      super_sie_effective = local(:super_sie_effective, csr_read_data5 | super_sie_machine_alias, width: 32)
      machine_enabled_interrupts = local(:machine_enabled_interrupts, machine_irq_masked & csr_read_data3, width: 32)
      super_enabled_interrupts = local(:super_enabled_interrupts, super_irq_masked & super_sie_effective, width: 32)
      global_mie_enabled = local(:global_mie_enabled,
                                 (csr_read_data2 & lit(0x8, width: 32)) != lit(0, width: 32),
                                 width: 1)
      global_sie_enabled = local(:global_sie_enabled,
                                 (csr_read_data4 & lit(0x2, width: 32)) != lit(0, width: 32),
                                 width: 1)
      # RISC-V spec: M-mode interrupts globally enabled when priv < M or (priv == M and MIE)
      machine_globally_enabled = local(:machine_globally_enabled,
                                       ~priv_is_m | global_mie_enabled,
                                       width: 1)
      # RISC-V spec: S-mode interrupts globally enabled when priv < S or (priv == S and SIE)
      super_globally_enabled = local(:super_globally_enabled,
                                     priv_is_u | (priv_is_s & global_sie_enabled),
                                     width: 1)
      machine_interrupt_pending = local(:machine_interrupt_pending,
                                        machine_globally_enabled & (machine_enabled_interrupts != lit(0, width: 32)),
                                        width: 1)
      super_interrupt_pending = local(:super_interrupt_pending,
                                      super_globally_enabled & (super_enabled_interrupts != lit(0, width: 32)),
                                      width: 1)
      interrupt_pending = local(:interrupt_pending, machine_interrupt_pending | super_interrupt_pending, width: 1)
      interrupt_from_supervisor = local(:interrupt_from_supervisor,
                                        super_interrupt_pending & ~machine_interrupt_pending,
                                        width: 1)
      selected_interrupts = local(:selected_interrupts,
                                  mux(machine_interrupt_pending, machine_enabled_interrupts, super_enabled_interrupts),
                                  width: 32)

      sync_trap_taken = local(:sync_trap_taken,
                              is_ecall | is_ebreak | is_illegal_system | inst_page_fault | data_page_fault,
                              width: 1)
      ecall_cause = local(:ecall_cause,
                          mux(priv_is_u, lit(8, width: 32),
                              mux(priv_is_s, lit(9, width: 32), lit(11, width: 32))),
                          width: 32)
      ecall_deleg_mask = local(:ecall_deleg_mask,
                               mux(priv_is_u, lit(0x100, width: 32),
                                   mux(priv_is_s, lit(0x200, width: 32), lit(0x800, width: 32))),
                               width: 32)
      ecall_delegated = local(:ecall_delegated,
                              (csr_read_data6 & ecall_deleg_mask) != lit(0, width: 32),
                              width: 1)
      ebreak_delegated = local(:ebreak_delegated,
                               (csr_read_data6 & lit(0x8, width: 32)) != lit(0, width: 32),
                               width: 1)
      illegal_delegated = local(:illegal_delegated,
                                (csr_read_data6 & lit(0x4, width: 32)) != lit(0, width: 32),
                                width: 1)
      inst_page_fault_delegated = local(:inst_page_fault_delegated,
                                        (csr_read_data6 & lit(0x1000, width: 32)) != lit(0, width: 32),
                                        width: 1)
      load_page_fault_delegated = local(:load_page_fault_delegated,
                                        (csr_read_data6 & lit(0x2000, width: 32)) != lit(0, width: 32),
                                        width: 1)
      store_page_fault_delegated = local(:store_page_fault_delegated,
                                         (csr_read_data6 & lit(0x8000, width: 32)) != lit(0, width: 32),
                                         width: 1)
      data_page_fault_delegated = local(:data_page_fault_delegated,
                                        mux(data_store_access, store_page_fault_delegated, load_page_fault_delegated),
                                        width: 1)
      sync_trap_delegated = local(:sync_trap_delegated,
                                  mux(inst_page_fault, inst_page_fault_delegated,
                                      mux(data_page_fault, data_page_fault_delegated,
                                      mux(is_ecall, ecall_delegated,
                                          mux(is_ebreak, ebreak_delegated, illegal_delegated)))),
                                  width: 1)
      trap_to_supervisor = local(:trap_to_supervisor,
                                 (sync_trap_taken & sync_trap_delegated) | interrupt_from_supervisor,
                                 width: 1)
      trap_taken = local(:trap_taken, sync_trap_taken | interrupt_pending, width: 1)
      # Unified interrupt cause: the cause code encodes the interrupt type (bit position),
      # not which privilege mode handles it. Priority: highest bit first.
      interrupt_cause = local(:interrupt_cause,
                              mux((selected_interrupts & lit(0x800, width: 32)) != lit(0, width: 32),
                                  lit(0x8000000B, width: 32), # cause 11: machine external (MEIP, bit 11)
                                  mux((selected_interrupts & lit(0x200, width: 32)) != lit(0, width: 32),
                                      lit(0x80000009, width: 32), # cause 9: supervisor external (SEIP, bit 9)
                                      mux((selected_interrupts & lit(0x080, width: 32)) != lit(0, width: 32),
                                          lit(0x80000007, width: 32), # cause 7: machine timer (MTIP, bit 7)
                                          mux((selected_interrupts & lit(0x020, width: 32)) != lit(0, width: 32),
                                              lit(0x80000005, width: 32), # cause 5: supervisor timer (STIP, bit 5)
                                              mux((selected_interrupts & lit(0x008, width: 32)) != lit(0, width: 32),
                                                  lit(0x80000003, width: 32), # cause 3: machine software (MSIP, bit 3)
                                                  lit(0x80000001, width: 32)))))), # cause 1: supervisor software (SSIP, bit 1)
                              width: 32)
      trap_cause = local(:trap_cause,
                         mux(interrupt_pending,
                             interrupt_cause,
                             mux(inst_page_fault,
                                 lit(12, width: 32),
                                 mux(data_page_fault,
                                     data_page_fault_cause,
                                     mux(is_illegal_system,
                                         lit(2, width: 32),
                                         mux(is_ebreak, lit(3, width: 32), ecall_cause))))),
                         width: 32)
      trap_tval = local(:trap_tval,
                        mux(inst_page_fault, inst_vaddr,
                            mux(data_page_fault, data_vaddr,
                                mux(is_illegal_system, inst_exec, lit(0, width: 32)))),
                        width: 32)

      # CSR read address:
      # - trap entry reads mtvec/stvec
      # - mret reads mepc
      # - sret reads sepc
      # - CSR instructions read csr from instruction imm field
      csr_addr <= mux(trap_taken, mux(trap_to_supervisor, lit(0x105, width: 12), lit(0x305, width: 12)),
                      mux(is_mret, lit(0x341, width: 12),
                          mux(is_sret, lit(0x141, width: 12), inst_exec[31..20])))
      csr_addr2 <= lit(0x300, width: 12) # mstatus
      csr_addr3 <= lit(0x304, width: 12) # mie
      csr_addr4 <= lit(0x100, width: 12) # sstatus
      csr_addr5 <= lit(0x104, width: 12) # sie
      csr_addr6 <= lit(0x302, width: 12) # medeleg
      csr_addr7 <= lit(0x303, width: 12) # mideleg
      csr_addr8 <= lit(0x180, width: 12) # satp
      csr_addr9 <= lit(0x305, width: 12) # mtvec
      csr_addr10 <= lit(0x105, width: 12) # stvec
      csr_addr11 <= lit(0x341, width: 12) # mepc
      csr_addr12 <= lit(0x141, width: 12) # sepc
      csr_addr13 <= lit(0x144, width: 12) # sip (for software SSIP readback)
      csr_read_selected = local(:csr_read_selected,
                                mux(csr_addr == lit(0xC20, width: 12), vec_vl,
                                    mux(csr_addr == lit(0xC21, width: 12), vec_vtype,
                                        mux(csr_addr == lit(0x344, width: 12), irq_pending_bits,
                                            mux(csr_addr == lit(0x144, width: 12), irq_pending_bits & effective_mideleg, csr_read_data)))),
                                width: 32)

      csr_instr_write_data = local(:csr_instr_write_data, case_select(funct3, {
        0b001 => csr_src,                  # CSRRW
        0b010 => csr_read_selected | csr_src,  # CSRRS
        0b011 => csr_read_selected & ~csr_src, # CSRRC
        0b101 => csr_src,                  # CSRRWI
        0b110 => csr_read_selected | csr_src,  # CSRRSI
        0b111 => csr_read_selected & ~csr_src  # CSRRCI
      }, default: csr_read_selected), width: 32)
      csr_instr_write_we = local(:csr_instr_write_we, is_csr_instr & case_select(funct3, {
        0b001 => lit(1, width: 1), # CSRRW
        0b010 => csr_rs1_nonzero,  # CSRRS
        0b011 => csr_rs1_nonzero,  # CSRRC
        0b101 => lit(1, width: 1), # CSRRWI
        0b110 => csr_rs1_nonzero,  # CSRRSI (zimm != 0)
        0b111 => csr_rs1_nonzero   # CSRRCI (zimm != 0)
      }, default: lit(0, width: 1)), width: 1)
      is_vl_csr_instr = local(:is_vl_csr_instr,
                              is_csr_instr & (inst_exec[31..20] == lit(0xC20, width: 12)),
                              width: 1)
      is_vtype_csr_instr = local(:is_vtype_csr_instr,
                                 is_csr_instr & (inst_exec[31..20] == lit(0xC21, width: 12)),
                                 width: 1)
      is_vector_csr_instr = local(:is_vector_csr_instr, is_vl_csr_instr | is_vtype_csr_instr, width: 1)
      satp_write = local(:satp_write,
                         is_csr_instr & csr_instr_write_we & (inst_exec[31..20] == lit(0x180, width: 12)),
                         width: 1)
      tlb_flush_all <= is_sfence_vma | satp_write

      old_mie_to_mpie = local(:old_mie_to_mpie,
                              mux((csr_read_data2 & lit(0x8, width: 32)) == lit(0, width: 32),
                                  lit(0, width: 32),
                                  lit(0x80, width: 32)),
                              width: 32)
      old_mpie_to_mie = local(:old_mpie_to_mie,
                              mux((csr_read_data2 & lit(0x80, width: 32)) == lit(0, width: 32),
                                  lit(0, width: 32),
                                  lit(0x8, width: 32)),
                              width: 32)
      trap_mpp = local(:trap_mpp,
                       mux(priv_mode == lit(PrivMode::MACHINE, width: 2),
                           lit(0x1800, width: 32),
                           mux(priv_mode == lit(PrivMode::SUPERVISOR, width: 2),
                               lit(0x800, width: 32),
                               lit(0, width: 32))),
                       width: 32)
      trap_mstatus = local(:trap_mstatus,
                           (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                           old_mie_to_mpie |
                           trap_mpp,
                           width: 32)
      mret_mstatus = local(:mret_mstatus,
                           (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                           old_mpie_to_mie |
                           lit(0x80, width: 32),
                           width: 32)
      old_sie_to_spie = local(:old_sie_to_spie,
                              mux((csr_read_data4 & lit(0x2, width: 32)) == lit(0, width: 32),
                                  lit(0, width: 32),
                                  lit(0x20, width: 32)),
                              width: 32)
      old_spie_to_sie = local(:old_spie_to_sie,
                              mux((csr_read_data4 & lit(0x20, width: 32)) == lit(0, width: 32),
                                  lit(0, width: 32),
                                  lit(0x2, width: 32)),
                              width: 32)
      trap_spp = local(:trap_spp,
                       mux(priv_mode == lit(PrivMode::USER, width: 2),
                           lit(0, width: 32),
                           lit(0x100, width: 32)),
                       width: 32)
      trap_sstatus = local(:trap_sstatus,
                           (csr_read_data4 & lit(0xFFFFFEDD, width: 32)) |
                           old_sie_to_spie |
                           trap_spp,
                           width: 32)
      sret_sstatus = local(:sret_sstatus,
                           (csr_read_data4 & lit(0xFFFFFEDD, width: 32)) |
                           old_spie_to_sie |
                           lit(0x20, width: 32),
                           width: 32)
      mret_target_mode = local(:mret_target_mode, csr_read_data2[12..11], width: 2)
      sret_target_mode = local(:sret_target_mode,
                               mux((csr_read_data4 & lit(0x100, width: 32)) == lit(0, width: 32),
                                   lit(PrivMode::USER, width: 2),
                                   lit(PrivMode::SUPERVISOR, width: 2)),
                               width: 2)
      trap_target_mode = local(:trap_target_mode,
                               mux(trap_to_supervisor, lit(PrivMode::SUPERVISOR, width: 2),
                                   lit(PrivMode::MACHINE, width: 2)),
                               width: 2)
      ret_target_mode = local(:ret_target_mode, mux(is_mret, mret_target_mode, sret_target_mode), width: 2)
      trap_or_ret = local(:trap_or_ret, trap_taken | is_mret | is_sret, width: 1)

      # SYSTEM side effects:
      # - Trap: write epc, cause, and status (M or S based on delegation)
      # - MRET/SRET: restore mstatus/sstatus trap-stack bits
      # - CSR instructions: normal CSR RMW
      csr_write_addr <= mux(trap_taken, mux(trap_to_supervisor, lit(0x141, width: 12), lit(0x341, width: 12)),
                            mux(is_mret, lit(0x300, width: 12),
                                mux(is_sret, lit(0x100, width: 12), inst_exec[31..20])))
      csr_write_data <= mux(trap_taken, pc,
                            mux(is_mret, mret_mstatus,
                                mux(is_sret, sret_sstatus, csr_instr_write_data)))
      csr_write_we <= mux(trap_or_ret, lit(1, width: 1), csr_instr_write_we & ~is_vector_csr_instr)
      csr_write_addr2 <= mux(trap_to_supervisor, lit(0x142, width: 12), lit(0x342, width: 12))
      csr_write_data2 <= trap_cause
      csr_write_we2 <= trap_taken
      csr_write_addr3 <= mux(trap_to_supervisor, lit(0x100, width: 12), lit(0x300, width: 12))
      csr_write_data3 <= mux(trap_to_supervisor, trap_sstatus, trap_mstatus)
      csr_write_we3 <= trap_taken
      csr_write_addr4 <= mux(trap_to_supervisor, lit(0x143, width: 12), lit(0x343, width: 12))
      csr_write_data4 <= trap_tval
      csr_write_we4 <= trap_taken
      vec_vl_write_data <= mux(is_vsetvli, vsetvli_new_vl, csr_instr_write_data)
      vec_vtype_write_data <= mux(is_vsetvli, vsetvli_new_vtype, csr_instr_write_data)
      vec_vl_write_we <= (is_vsetvli | (is_vl_csr_instr & csr_instr_write_we)) & ~trap_taken
      vec_vtype_write_we <= (is_vsetvli | (is_vtype_csr_instr & csr_instr_write_we)) & ~trap_taken
      priv_mode_we <= trap_taken | is_mret | is_sret
      priv_mode_next <= mux(trap_taken, trap_target_mode, ret_target_mode)

      # PC next selection:
      # - jump && jalr: jalr_target
      # - jump && !jalr: pc + imm (JAL target)
      # - branch && branch_taken: branch_target
      # - mret/sret: mepc/sepc
      # - trap: mtvec/stvec
      # - else: pc_plus4
      jal_target = local(:jal_target, pc + imm, width: 32)
      trap_target = local(:trap_target, csr_read_selected & lit(0xFFFFFFFC, width: 32), width: 32)

      pc_next <= mux(trap_taken, trap_target,
                     mux(is_mret | is_sret, csr_read_selected,
                         mux(jump,
                             mux(jalr, jalr_target, jal_target),
                             mux(branch & branch_taken, branch_target, pc_plus4))))

      # Register write data selection:
      # - mem_to_reg: data from memory
      # - jump: return address (pc + 4)
      # - csr: old CSR value
      # - fmv.x.w: raw bits from fp register
      # - else: ALU result
      rd_data <= mux(is_amo, amo_rd_data,
                     mux(is_vsetvli | is_vmv_x_s, v_scalar_result,
                     mux(is_csr_instr, csr_read_selected,
                     mux(is_fmv_x_w, fp_rs1_data,
                     mux(is_fcmp_s, fp_cmp_result,
                     mux(is_fcmp_d, fp_cmp_d_result,
                     mux(is_fclass_s, fp_class_result,
                     mux(is_fclass_d, fp64_class_result,
                     mux(is_fcvt_w_s, fcvt_w_s_result,
                     mux(is_fcvt_wu_s, fcvt_wu_s_result,
                     mux(is_fcvt_w_d, fcvt_w_d_result,
                     mux(is_fcvt_wu_d, fcvt_wu_d_result,
                     mux(mem_to_reg, data_rdata,
                     mux(jump, pc_plus4, alu_result))
                     ))))))))))))
      fp_rd_data <= mux(is_fp_load, data_rdata,
                        mux(is_fsgnj_s, fsgnj_result,
                            mux(is_fminmax_s, fp_minmax_result,
                                mux(is_fsgnj_d, fsgnj_d_result64[31..0],
                                    mux(is_fminmax_d, fp64_minmax_result[31..0],
                                mux(is_d_arith, d_alu_result64[31..0],
                                mux(is_fcvt_s_d, fcvt_s_d_result,
                                    mux(is_fcvt_s_w | is_fcvt_s_wu, fcvt_s_w_result, rs1_data))))))))
      fp_rd_data64 <= mux(is_fcvt_d_s, fcvt_d_s_result64,
                          mux(is_fcvt_d_w | is_fcvt_d_wu, fcvt_d_w_result64,
                              mux(is_fsgnj_d, fsgnj_d_result64,
                                  mux(is_fminmax_d, fp64_minmax_result,
                                      mux(is_d_arith, d_alu_result64, cat(lit(0xFFFF_FFFF, width: 32), fp_rd_data))))))
      v_rd_lane0_in <= mux(is_vmv_s_x, rs1_data,
                           mux(v_all_lane_write & v_lane0_active, v_lane0_all_next, v_rd_lane0))
      v_rd_lane1_in <= mux(v_all_lane_write & v_lane1_active, v_lane1_all_next, v_rd_lane1)
      v_rd_lane2_in <= mux(v_all_lane_write & v_lane2_active, v_lane2_all_next, v_rd_lane2)
      v_rd_lane3_in <= mux(v_all_lane_write & v_lane3_active, v_lane3_all_next, v_rd_lane3)
      v_rd_we <= (v_all_lane_write | is_vmv_s_x) & ~trap_taken
      fp_reg_write <= is_fp_reg_write_op & ~trap_taken
      fp_reg_write64 <= is_fp_reg_write64_op & ~trap_taken
      reg_write_final <= (reg_write | is_amo | is_vsetvli | is_vmv_x_s | is_fp_int_write) & ~trap_taken
      mem_read_final <= mem_read & ~trap_taken
      mem_write_final <= mem_write & ~trap_taken
      reservation_set <= is_lr & ~trap_taken
      reservation_clear <= (is_sc | is_amo_rmw | mem_write_final) & ~trap_taken
      reservation_set_addr <= rs1_data

      # Output connections
      inst_addr <= mux(satp_translate, inst_paddr, pc)
      inst_ptw_addr1 <= inst_ptw_addr1_calc
      inst_ptw_addr0 <= inst_ptw_addr0_calc
      data_addr <= mux(satp_translate & data_access_req, data_paddr, data_vaddr)
      data_ptw_addr1 <= data_ptw_addr1_calc
      data_ptw_addr0 <= data_ptw_addr0_calc
      data_wdata <= mux(is_amo_rmw, amo_new_data, mux(is_fp_store, fp_rs2_data, rs2_data))
      data_we <= mux(is_amo, amo_mem_write & ~trap_taken & ~data_page_fault,
                     mem_write_final & ~data_page_fault)
      data_re <= mux(is_amo, amo_mem_read & ~trap_taken & ~data_page_fault,
                     mem_read_final & ~data_page_fault)
      data_funct3 <= mux(is_amo, lit(Funct3::WORD, width: 3), funct3)
      debug_pc <= pc
      debug_inst <= inst_exec
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

    def read_freg(index)
      @fp_regfile.read_reg(index)
    end

    def write_freg(index, value)
      @fp_regfile.write_reg(index, value)
    end

    def read_vreg(index)
      @vregfile.read_vreg(index)
    end

    def read_vl
      @vec_csrfile.read_vl
    end

    def read_vtype
      @vec_csrfile.read_vtype
    end

    def read_csr(index)
      @csrfile.read_csr(index)
    end

    # Generate complete Verilog hierarchy
    def self.to_verilog_hierarchy(top_name: nil)
      to_verilog(top_name: top_name)
    end
      end
    end
  end
end
