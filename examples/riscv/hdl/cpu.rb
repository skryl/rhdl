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
require_relative 'csr_file'
require_relative 'imm_gen'
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
    wire :reg_write_final
    wire :mem_read_final
    wire :mem_write_final
    wire :alu_op, width: 5

    # Internal signals - computed by behavior block
    wire :alu_a, width: 32
    wire :alu_b, width: 32
    wire :rd_data, width: 32
    wire :regfile_forwarding_en
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
    instance :csrfile, CSRFile
    instance :reservation, AtomicReservation
    instance :priv_mode_reg, PrivModeReg
    instance :itlb, Sv32Tlb
    instance :dtlb, Sv32Tlb
    instance :decoder, Decoder
    instance :imm_gen, ImmGen
    instance :alu, ALU
    instance :branch_cond, BranchCond

    # Clock and reset to sequential components
    port :clk => [[:pc_reg, :clk], [:regfile, :clk], [:csrfile, :clk], [:reservation, :clk], [:priv_mode_reg, :clk],
                  [:itlb, :clk], [:dtlb, :clk]]
    port :rst => [[:pc_reg, :rst], [:regfile, :rst], [:csrfile, :rst], [:reservation, :rst], [:priv_mode_reg, :rst],
                  [:itlb, :rst], [:dtlb, :rst]]

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
    port :reg_write_final => [:regfile, :rd_we]
    port :regfile_forwarding_en => [:regfile, :forwarding_en]
    port :debug_reg_addr => [:regfile, :debug_raddr]
    port [:regfile, :rs1_data] => :rs1_data
    port [:regfile, :rs2_data] => :rs2_data
    port [:regfile, :debug_rdata] => :debug_reg_data

    # CSR file connections
    port :csr_addr => [:csrfile, :read_addr]
    port :csr_addr2 => [:csrfile, :read_addr2]
    port :csr_addr3 => [:csrfile, :read_addr3]
    port :csr_addr4 => [:csrfile, :read_addr4]
    port :csr_addr5 => [:csrfile, :read_addr5]
    port :csr_addr6 => [:csrfile, :read_addr6]
    port :csr_addr7 => [:csrfile, :read_addr7]
    port :csr_addr8 => [:csrfile, :read_addr8]
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
      pc_plus4 <= pc + lit(4, width: 32)

      # Branch target = PC + immediate
      branch_target <= pc + imm

      # JALR target = rs1 + immediate with LSB cleared
      jalr_target <= (rs1_data + imm) & lit(0xFFFFFFFE, width: 32)

      # ALU A input mux: AUIPC uses PC, others use rs1_data
      alu_a <= mux(opcode == lit(Opcode::AUIPC, width: 7), pc, rs1_data)

      # ALU B input mux: alu_src=1 uses immediate, alu_src=0 uses rs2_data
      alu_b <= mux(alu_src, imm, rs2_data)

      # Atomic (RV32A) decode/data path
      is_amo_word = local(:is_amo_word,
                          (opcode == lit(Opcode::AMO, width: 7)) & (funct3 == lit(Funct3::WORD, width: 3)),
                          width: 1)
      amo_funct5 = inst_data[31..27]
      is_lr = local(:is_lr,
                    is_amo_word & (amo_funct5 == lit(0b00010, width: 5)) & (rs2 == lit(0, width: 5)),
                    width: 1)
      is_sc = local(:is_sc, is_amo_word & (amo_funct5 == lit(0b00011, width: 5)), width: 1)
      is_amo_rmw = local(:is_amo_rmw,
                         is_amo_word & (
                           (amo_funct5 == lit(0b00000, width: 5)) | # AMOADD.W
                           (amo_funct5 == lit(0b00001, width: 5)) | # AMOSWAP.W
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
        0b00100 => amo_old ^ rs2_data,  # AMOXOR.W
        0b01000 => amo_old | rs2_data,  # AMOOR.W
        0b01100 => amo_old & rs2_data,  # AMOAND.W
        0b10000 => amo_min_signed,      # AMOMIN.W
        0b10100 => amo_max_signed,      # AMOMAX.W
        0b11000 => amo_min_unsigned,    # AMOMINU.W
        0b11100 => amo_max_unsigned     # AMOMAXU.W
      }, default: rs2_data), width: 32)
      amo_sc_success = local(:amo_sc_success, reservation_valid & (reservation_addr == rs1_data), width: 1)
      amo_mem_read = local(:amo_mem_read, is_lr | is_amo_rmw, width: 1)
      amo_mem_write = local(:amo_mem_write, (is_sc & amo_sc_success) | is_amo_rmw, width: 1)
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
      inst_tlb_lookup_en <= satp_mode_sv32
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
      inst_tlb_fill_en <= satp_mode_sv32 & ~inst_tlb_hit & inst_walk_ok
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
      inst_page_fault = local(:inst_page_fault, satp_mode_sv32 & ~inst_perm_ok, width: 1)

      # Sv32 data translation (address walk inputs are provided via external ports).
      data_vpn = data_vaddr[31..12]
      data_vpn1 = data_vaddr[31..22]
      data_vpn0 = data_vaddr[21..12]
      data_page_off = data_vaddr[11..0]
      data_tlb_lookup_en <= satp_mode_sv32 & data_access_req
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
      data_tlb_fill_en <= satp_mode_sv32 & data_access_req & ~data_tlb_hit & data_walk_ok
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
                              satp_mode_sv32 & data_access_req & ~data_perm_ok,
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
      sys_imm = inst_data[31..20]
      is_ecall = local(:is_ecall, is_system_plain & (sys_imm == lit(0x000, width: 12)), width: 1)
      is_ebreak = local(:is_ebreak, is_system_plain & (sys_imm == lit(0x001, width: 12)), width: 1)
      is_sret = local(:is_sret, is_system_plain & (sys_imm == lit(0x102, width: 12)), width: 1)
      is_mret = local(:is_mret, is_system_plain & (sys_imm == lit(0x302, width: 12)), width: 1)
      is_wfi = local(:is_wfi, is_system_plain & (sys_imm == lit(0x105, width: 12)), width: 1)
      is_sfence_vma = local(:is_sfence_vma,
                            is_system_plain & (inst_data[31..25] == lit(0b0001001, width: 7)) & (rd == lit(0, width: 5)),
                            width: 1)
      is_illegal_system = local(:is_illegal_system,
                                is_system_plain & ~(is_ecall | is_ebreak | is_mret | is_sret | is_wfi | is_sfence_vma),
                                width: 1)
      irq_pending_bits = local(:irq_pending_bits,
                               mux(irq_software, lit(0x8, width: 32), lit(0, width: 32)) |
                               mux(irq_timer, lit(0x80, width: 32), lit(0, width: 32)) |
                               mux(irq_external, lit(0x800, width: 32), lit(0, width: 32)),
                               width: 32)
      csr_use_imm = funct3[2]
      csr_src = local(:csr_src, mux(csr_use_imm, cat(lit(0, width: 27), rs1), rs1_data), width: 32)
      csr_rs1_nonzero = local(:csr_rs1_nonzero, rs1 != lit(0, width: 5), width: 1)

      # Interrupt enable filtering for M-mode (mstatus/mie) and S-mode (sstatus/sie).
      machine_irq_masked = local(:machine_irq_masked, irq_pending_bits & ~csr_read_data7, width: 32)
      super_irq_masked = local(:super_irq_masked, irq_pending_bits & csr_read_data7, width: 32)
      super_sie_machine_alias = local(:super_sie_machine_alias,
                                      mux((csr_read_data5 & lit(0x200, width: 32)) != lit(0, width: 32),
                                          lit(0x800, width: 32),
                                          lit(0, width: 32)),
                                      width: 32)
      super_sie_effective = local(:super_sie_effective, csr_read_data5 | super_sie_machine_alias, width: 32)
      machine_enabled_interrupts = local(:machine_enabled_interrupts, machine_irq_masked & csr_read_data3, width: 32)
      super_enabled_interrupts = local(:super_enabled_interrupts, super_irq_masked & super_sie_effective, width: 32)
      global_mie_enabled = local(:global_mie_enabled,
                                 (csr_read_data2 & lit(0x8, width: 32)) != lit(0, width: 32),
                                 width: 1)
      global_sie_enabled = local(:global_sie_enabled,
                                 (csr_read_data4 & lit(0x2, width: 32)) != lit(0, width: 32),
                                 width: 1)
      machine_interrupt_pending = local(:machine_interrupt_pending,
                                        global_mie_enabled & (machine_enabled_interrupts != lit(0, width: 32)),
                                        width: 1)
      super_interrupt_pending = local(:super_interrupt_pending,
                                      global_sie_enabled & (super_enabled_interrupts != lit(0, width: 32)),
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
      machine_interrupt_cause = local(:machine_interrupt_cause,
                                      mux((selected_interrupts & lit(0x800, width: 32)) != lit(0, width: 32),
                                          lit(0x8000000B, width: 32), # machine external
                                          mux((selected_interrupts & lit(0x80, width: 32)) != lit(0, width: 32),
                                              lit(0x80000007, width: 32), # machine timer
                                              lit(0x80000003, width: 32))), # machine software
                                      width: 32)
      supervisor_interrupt_cause = local(:supervisor_interrupt_cause,
                                         mux((selected_interrupts & lit(0x800, width: 32)) != lit(0, width: 32),
                                             lit(0x80000009, width: 32), # supervisor external
                                             mux((selected_interrupts & lit(0x80, width: 32)) != lit(0, width: 32),
                                                 lit(0x80000005, width: 32), # supervisor timer
                                                 lit(0x80000001, width: 32))), # supervisor software
                                         width: 32)
      interrupt_cause = local(:interrupt_cause,
                              mux(interrupt_from_supervisor, supervisor_interrupt_cause, machine_interrupt_cause),
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
                                mux(is_illegal_system, inst_data, lit(0, width: 32)))),
                        width: 32)

      # CSR read address:
      # - trap entry reads mtvec/stvec
      # - mret reads mepc
      # - sret reads sepc
      # - CSR instructions read csr from instruction imm field
      csr_addr <= mux(trap_taken, mux(trap_to_supervisor, lit(0x105, width: 12), lit(0x305, width: 12)),
                      mux(is_mret, lit(0x341, width: 12),
                          mux(is_sret, lit(0x141, width: 12), inst_data[31..20])))
      csr_addr2 <= lit(0x300, width: 12) # mstatus
      csr_addr3 <= lit(0x304, width: 12) # mie
      csr_addr4 <= lit(0x100, width: 12) # sstatus
      csr_addr5 <= lit(0x104, width: 12) # sie
      csr_addr6 <= lit(0x302, width: 12) # medeleg
      csr_addr7 <= lit(0x303, width: 12) # mideleg
      csr_addr8 <= lit(0x180, width: 12) # satp
      csr_read_selected = local(:csr_read_selected,
                                mux(csr_addr == lit(0x344, width: 12), irq_pending_bits,
                                    mux(csr_addr == lit(0x144, width: 12), irq_pending_bits & csr_read_data7, csr_read_data)),
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
      satp_write = local(:satp_write,
                         is_csr_instr & csr_instr_write_we & (inst_data[31..20] == lit(0x180, width: 12)),
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
                                mux(is_sret, lit(0x100, width: 12), inst_data[31..20])))
      csr_write_data <= mux(trap_taken, pc,
                            mux(is_mret, mret_mstatus,
                                mux(is_sret, sret_sstatus, csr_instr_write_data)))
      csr_write_we <= mux(trap_or_ret, lit(1, width: 1), csr_instr_write_we)
      csr_write_addr2 <= mux(trap_to_supervisor, lit(0x142, width: 12), lit(0x342, width: 12))
      csr_write_data2 <= trap_cause
      csr_write_we2 <= trap_taken
      csr_write_addr3 <= mux(trap_to_supervisor, lit(0x100, width: 12), lit(0x300, width: 12))
      csr_write_data3 <= mux(trap_to_supervisor, trap_sstatus, trap_mstatus)
      csr_write_we3 <= trap_taken
      csr_write_addr4 <= mux(trap_to_supervisor, lit(0x143, width: 12), lit(0x343, width: 12))
      csr_write_data4 <= trap_tval
      csr_write_we4 <= trap_taken
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
      # - else: ALU result
      rd_data <= mux(is_amo, amo_rd_data,
                     mux(is_csr_instr, csr_read_selected,
                     mux(mem_to_reg, data_rdata,
                     mux(jump, pc_plus4, alu_result))
                     ))
      reg_write_final <= (reg_write | is_amo) & ~trap_taken
      mem_read_final <= mem_read & ~trap_taken
      mem_write_final <= mem_write & ~trap_taken
      reservation_set <= is_lr & ~trap_taken
      reservation_clear <= (is_sc | is_amo_rmw | mem_write_final) & ~trap_taken
      reservation_set_addr <= rs1_data

      # Output connections
      inst_addr <= mux(satp_mode_sv32, inst_paddr, pc)
      inst_ptw_addr1 <= inst_ptw_addr1_calc
      inst_ptw_addr0 <= inst_ptw_addr0_calc
      data_addr <= mux(satp_mode_sv32 & data_access_req, data_paddr, data_vaddr)
      data_ptw_addr1 <= data_ptw_addr1_calc
      data_ptw_addr0 <= data_ptw_addr0_calc
      data_wdata <= mux(is_amo_rmw, amo_new_data, rs2_data)
      data_we <= mux(is_amo, amo_mem_write & ~trap_taken & ~data_page_fault,
                     mem_write_final & ~data_page_fault)
      data_re <= mux(is_amo, amo_mem_read & ~trap_taken & ~data_page_fault,
                     mem_read_final & ~data_page_fault)
      data_funct3 <= mux(is_amo, lit(Funct3::WORD, width: 3), funct3)
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

    def read_csr(index)
      @csrfile.read_csr(index)
    end

    # Generate complete Verilog hierarchy
    def self.to_verilog_hierarchy(top_name: nil)
      parts = []

      # Generate sub-modules first
      parts << ALU.to_verilog
      parts << RegisterFile.to_verilog
      parts << CSRFile.to_verilog
      parts << ImmGen.to_verilog
      parts << Decoder.to_verilog
      parts << BranchCond.to_verilog
      parts << ProgramCounter.to_verilog
      parts << AtomicReservation.to_verilog
      parts << PrivModeReg.to_verilog
      parts << Sv32Tlb.to_verilog

      # Generate top-level last
      parts << to_verilog(top_name: top_name)

      parts.join("\n\n")
    end
      end
    end
  end
end
