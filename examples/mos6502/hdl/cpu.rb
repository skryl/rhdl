# MOS 6502 CPU - Synthesizable DSL Version
# Integrates all CPU components into a complete CPU
# Uses class-level instance/port declarations for component instantiation and wiring
# Sequential - requires always @(posedge clk) for synthesis
# FULLY DECLARATIVE - no behavioral Ruby code, only DSL constructs

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'registers'
require_relative 'status_register'
require_relative 'alu'
require_relative 'address_gen'
require_relative 'instruction_decoder'
require_relative 'control_unit'

module MOS6502
  class CPU < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # External interface
    input :clk
    input :rst
    input :rdy
    input :irq
    input :nmi

    # Memory interface
    input :data_in, width: 8
    output :data_out, width: 8
    output :addr, width: 16
    output :rw
    output :sync

    # External register load inputs (for test/debug)
    input :ext_pc_load_data, width: 16
    input :ext_pc_load_en
    input :ext_a_load_data, width: 8
    input :ext_a_load_en
    input :ext_x_load_data, width: 8
    input :ext_x_load_en
    input :ext_y_load_data, width: 8
    input :ext_y_load_en
    input :ext_sp_load_data, width: 8
    input :ext_sp_load_en

    # Debug outputs
    output :reg_a, width: 8
    output :reg_x, width: 8
    output :reg_y, width: 8
    output :reg_sp, width: 8
    output :reg_pc, width: 16
    output :reg_p, width: 8
    output :opcode, width: 8
    output :state, width: 8
    output :halted
    output :cycle_count, width: 32

    # Internal signals from subcomponents
    wire :ir_opcode, width: 8
    wire :ir_operand_lo, width: 8
    wire :ir_operand_hi, width: 8
    wire :dec_addr_mode, width: 4
    wire :dec_alu_op, width: 4
    wire :dec_instr_type, width: 4
    wire :dec_src_reg, width: 2
    wire :dec_dst_reg, width: 2
    wire :dec_branch_cond, width: 3
    wire :dec_is_read
    wire :dec_is_write
    wire :dec_is_rmw
    wire :dec_sets_nz
    wire :dec_sets_c
    wire :dec_sets_v
    wire :dec_writes_reg
    wire :dec_is_status_op
    wire :ctrl_state, width: 8
    wire :ctrl_pc_inc
    wire :ctrl_pc_load
    wire :ctrl_load_opcode
    wire :ctrl_load_operand_lo
    wire :ctrl_load_operand_hi
    wire :ctrl_load_addr_lo
    wire :ctrl_load_addr_hi
    wire :ctrl_load_data
    wire :ctrl_addr_sel, width: 3
    wire :ctrl_data_sel, width: 3
    wire :ctrl_reg_write
    wire :ctrl_sp_inc
    wire :ctrl_sp_dec
    wire :ctrl_update_flags
    wire :ctrl_mem_write
    wire :ctrl_halted
    wire :ctrl_cycle_count, width: 32
    wire :alu_result, width: 8
    wire :alu_n
    wire :alu_z
    wire :alu_c
    wire :alu_v
    wire :regs_a, width: 8
    wire :regs_x, width: 8
    wire :regs_y, width: 8
    wire :sr_p, width: 8
    wire :sr_n
    wire :sr_v
    wire :sr_z
    wire :sr_c
    wire :sr_d
    wire :pc_val, width: 16
    wire :sp_val, width: 8
    wire :agen_eff_addr, width: 16
    wire :agen_page_cross
    wire :acalc_ptr_addr_lo, width: 16
    wire :acalc_ptr_addr_hi, width: 16
    wire :alatch_addr_lo, width: 8
    wire :alatch_addr_hi, width: 8
    wire :alatch_addr, width: 16
    wire :dlatch_data, width: 8
    wire :alu_result_latched, width: 8
    wire :latch_alu_result

    # Computed control signals for subcomponents
    wire :actual_load_a
    wire :actual_load_x
    wire :actual_load_y
    wire :actual_reg_data, width: 8
    wire :actual_pc_load
    wire :actual_pc_inc
    wire :actual_pc_addr, width: 16
    wire :actual_sp_load
    wire :actual_sp_data, width: 8
    wire :actual_load_n
    wire :actual_load_z
    wire :actual_load_c
    wire :actual_load_v
    wire :actual_load_i
    wire :actual_load_d
    wire :flag_n_in
    wire :flag_z_in
    wire :flag_c_in
    wire :flag_v_in
    wire :flag_i_in
    wire :flag_d_in
    wire :sr_load_flags     # Status register: load N,V,Z,C from ALU (unused)
    wire :sr_load_b         # Status register: load B flag (unused)
    wire :sr_b_in           # Status register: B flag input (unused)

    # Additional computed signals
    wire :stack_addr, width: 16
    wire :stack_addr_plus1, width: 16
    wire :alu_a_sel, width: 8
    wire :alu_b_sel, width: 8
    wire :pc_hi_byte, width: 8
    wire :pc_lo_byte, width: 8
    wire :is_execute_state
    wire :load_from_imm
    wire :load_from_mem
    wire :is_load_instr
    wire :is_flag_instr
    wire :is_transfer_instr
    wire :is_tsx_instr
    wire :is_txs_instr
    wire :flag_set_value
    wire :flag_type, width: 2
    wire :is_flag_c_instr
    wire :is_flag_i_instr
    wire :is_flag_v_instr
    wire :is_flag_d_instr
    wire :is_rmw_instr
    wire :is_write_mem_state
    wire :is_fetch_op1_state
    wire :is_read_mem_state
    wire :is_stack_instr
    wire :is_stack_pull_reg
    wire :is_pull_state
    wire :actual_load_all
    wire :uses_reg_for_nz       # Flag: N/Z flags come from register data, not ALU
    wire :reg_data_n            # N flag computed from actual_reg_data
    wire :reg_data_z            # Z flag computed from actual_reg_data
    wire :is_decode_state       # We're in DECODE state
    wire :decode_to_execute     # Implied mode in DECODE transitioning to EXECUTE
    wire :sr_data_in, width: 8  # Status register data input (data_in during PULL)
    wire :pc_minus_one, width: 16  # PC-1 for JSR return address push
    wire :pc_m1_hi, width: 8       # High byte of PC-1
    wire :pc_m1_lo, width: 8       # Low byte of PC-1
    wire :is_rts_pull_hi           # In RTS_PULL_HI state
    wire :is_rti_pull_hi           # In RTI_PULL_HI state
    wire :is_brk_vec_hi            # In BRK_VEC_HI state
    wire :return_addr, width: 16   # Computed return address for RTS/RTI (cat(data_in, alatch_addr_lo))

    # Component instances
    instance :registers, Registers
    instance :status_reg, StatusRegister
    instance :pc, ProgramCounter
    instance :sp, StackPointer
    instance :ir, InstructionRegister
    instance :addr_latch, AddressLatch
    instance :data_latch, DataLatch
    instance :alu_latch, DataLatch
    instance :control, ControlUnit
    instance :alu, ALU
    instance :decoder, InstructionDecoder
    instance :addr_gen, AddressGenerator
    instance :addr_calc, IndirectAddressCalc

    # Clock and reset to all sequential components
    port :clk => [[:registers, :clk], [:status_reg, :clk], [:pc, :clk],
                  [:sp, :clk], [:ir, :clk], [:addr_latch, :clk],
                  [:data_latch, :clk], [:alu_latch, :clk], [:control, :clk]]
    port :rst => [[:registers, :rst], [:status_reg, :rst], [:pc, :rst],
                  [:sp, :rst], [:ir, :rst], [:addr_latch, :rst],
                  [:data_latch, :rst], [:alu_latch, :rst], [:control, :rst]]

    # Control unit inputs
    port :rdy => [:control, :rdy]

    # IR connections
    port :data_in => [:ir, :data_in]
    port [:ir, :opcode] => :ir_opcode
    port [:ir, :operand_lo] => :ir_operand_lo
    port [:ir, :operand_hi] => :ir_operand_hi
    port :ctrl_load_opcode => [:ir, :load_opcode]
    port :ctrl_load_operand_lo => [:ir, :load_operand_lo]
    port :ctrl_load_operand_hi => [:ir, :load_operand_hi]

    # Decoder connections
    port :ir_opcode => [:decoder, :opcode]
    port [:decoder, :addr_mode] => :dec_addr_mode
    port [:decoder, :alu_op] => :dec_alu_op
    port [:decoder, :instr_type] => :dec_instr_type
    port [:decoder, :src_reg] => :dec_src_reg
    port [:decoder, :dst_reg] => :dec_dst_reg
    port [:decoder, :branch_cond] => :dec_branch_cond
    port [:decoder, :is_read] => :dec_is_read
    port [:decoder, :is_write] => :dec_is_write
    port [:decoder, :is_rmw] => :dec_is_rmw
    port [:decoder, :sets_nz] => :dec_sets_nz
    port [:decoder, :sets_c] => :dec_sets_c
    port [:decoder, :sets_v] => :dec_sets_v
    port [:decoder, :writes_reg] => :dec_writes_reg
    port [:decoder, :is_status_op] => :dec_is_status_op

    # Control unit connections
    port :dec_addr_mode => [:control, :addr_mode]
    port :dec_instr_type => [:control, :instr_type]
    port :dec_branch_cond => [:control, :branch_cond]
    port :dec_is_read => [:control, :is_read]
    port :dec_is_write => [:control, :is_write]
    port :dec_is_rmw => [:control, :is_rmw]
    port :dec_writes_reg => [:control, :writes_reg]
    port :dec_is_status_op => [:control, :is_status_op]

    port [:control, :state] => :ctrl_state
    port [:control, :pc_inc] => :ctrl_pc_inc
    port [:control, :pc_load] => :ctrl_pc_load
    port [:control, :load_opcode] => :ctrl_load_opcode
    port [:control, :load_operand_lo] => :ctrl_load_operand_lo
    port [:control, :load_operand_hi] => :ctrl_load_operand_hi
    port [:control, :load_addr_lo] => :ctrl_load_addr_lo
    port [:control, :load_addr_hi] => :ctrl_load_addr_hi
    port [:control, :load_data] => :ctrl_load_data
    port [:control, :addr_sel] => :ctrl_addr_sel
    port [:control, :data_sel] => :ctrl_data_sel
    port [:control, :reg_write] => :ctrl_reg_write
    port [:control, :sp_inc] => :ctrl_sp_inc
    port [:control, :sp_dec] => :ctrl_sp_dec
    port [:control, :update_flags] => :ctrl_update_flags
    port [:control, :mem_write] => :ctrl_mem_write
    port [:control, :halted] => :ctrl_halted
    port [:control, :cycle_count] => :ctrl_cycle_count

    # Status register connections
    port [:status_reg, :n] => :sr_n
    port [:status_reg, :v] => :sr_v
    port [:status_reg, :z] => :sr_z
    port [:status_reg, :c] => :sr_c
    port [:status_reg, :d] => :sr_d
    port [:status_reg, :p] => :sr_p
    port :sr_n => [:control, :flag_n]
    port :sr_v => [:control, :flag_v]
    port :sr_z => [:control, :flag_z]
    port :sr_c => [:control, :flag_c]
    port :actual_load_n => [:status_reg, :load_n]
    port :actual_load_z => [:status_reg, :load_z]
    port :actual_load_c => [:status_reg, :load_c]
    port :actual_load_v => [:status_reg, :load_v]
    port :actual_load_i => [:status_reg, :load_i]
    port :actual_load_d => [:status_reg, :load_d]
    port :flag_n_in => [:status_reg, :n_in]
    port :flag_z_in => [:status_reg, :z_in]
    port :flag_c_in => [:status_reg, :c_in]
    port :flag_v_in => [:status_reg, :v_in]
    port :flag_i_in => [:status_reg, :i_in]
    port :flag_d_in => [:status_reg, :d_in]
    port :actual_load_all => [:status_reg, :load_all]
    port :sr_data_in => [:status_reg, :data_in]
    port :sr_load_flags => [:status_reg, :load_flags]
    port :sr_load_b => [:status_reg, :load_b]
    port :sr_b_in => [:status_reg, :b_in]

    # ALU connections
    port [:alu, :result] => :alu_result
    port [:alu, :n] => :alu_n
    port [:alu, :z] => :alu_z
    port [:alu, :c] => :alu_c
    port [:alu, :v] => :alu_v
    port :dec_alu_op => [:alu, :op]
    port :sr_c => [:alu, :c_in]
    port :sr_d => [:alu, :d_flag]
    port :alu_a_sel => [:alu, :a]
    port :alu_b_sel => [:alu, :b]

    # Register connections (use computed signals)
    port [:registers, :a] => :regs_a
    port [:registers, :x] => :regs_x
    port [:registers, :y] => :regs_y
    port :actual_load_a => [:registers, :load_a]
    port :actual_load_x => [:registers, :load_x]
    port :actual_load_y => [:registers, :load_y]
    port :actual_reg_data => [:registers, :data_in]

    # PC connections (use computed signals)
    port [:pc, :pc] => :pc_val
    port :actual_pc_load => [:pc, :load]
    port :actual_pc_addr => [:pc, :addr_in]
    port :actual_pc_inc => [:pc, :inc]

    # SP connections (use computed signals)
    port [:sp, :sp] => :sp_val
    port :actual_sp_load => [:sp, :load]
    port :actual_sp_data => [:sp, :data_in]
    port :ctrl_sp_inc => [:sp, :inc]
    port :ctrl_sp_dec => [:sp, :dec]

    # Address generator connections
    port :dec_addr_mode => [:addr_gen, :mode]
    port :ir_operand_lo => [:addr_gen, :operand_lo]
    port :ir_operand_hi => [:addr_gen, :operand_hi]
    port :regs_x => [:addr_gen, :x_reg]
    port :regs_y => [:addr_gen, :y_reg]
    port :pc_val => [:addr_gen, :pc]
    port :sp_val => [:addr_gen, :sp]
    port [:addr_gen, :eff_addr] => :agen_eff_addr
    port [:addr_gen, :page_cross] => :agen_page_cross
    port :agen_page_cross => [:control, :page_cross]

    # Indirect address calculator connections
    port :dec_addr_mode => [:addr_calc, :mode]
    port :ir_operand_lo => [:addr_calc, :operand_lo]
    port :ir_operand_hi => [:addr_calc, :operand_hi]
    port :regs_x => [:addr_calc, :x_reg]
    port [:addr_calc, :ptr_addr_lo] => :acalc_ptr_addr_lo
    port [:addr_calc, :ptr_addr_hi] => :acalc_ptr_addr_hi

    # Address latch connections
    port [:addr_latch, :addr_lo] => :alatch_addr_lo
    port [:addr_latch, :addr_hi] => :alatch_addr_hi
    port [:addr_latch, :addr] => :alatch_addr
    port :data_in => [:addr_latch, :data_in]
    port :agen_eff_addr => [:addr_latch, :addr_in]
    port :ctrl_load_addr_lo => [:addr_latch, :load_lo]
    port :ctrl_load_addr_hi => [:addr_latch, :load_hi]
    port :alatch_addr_lo => [:addr_gen, :indirect_lo]
    port :alatch_addr_hi => [:addr_gen, :indirect_hi]

    # Data latch connections
    port [:data_latch, :data] => :dlatch_data
    port :data_in => [:data_latch, :data_in]
    port :ctrl_load_data => [:data_latch, :load]

    # ALU result latch connections (for RMW write-back)
    port :alu_result => [:alu_latch, :data_in]
    port :latch_alu_result => [:alu_latch, :load]
    port [:alu_latch, :data] => :alu_result_latched

    # Combinational logic
    behavior do
      # Stack address computation (0x0100 + SP forms stack address in page 1)
      stack_addr <= cat(lit(0x01, width: 8), sp_val)
      # For PULL: compute address at SP+1 (where data to be pulled is located)
      # Use full 16-bit addition to avoid width issues with 8-bit SP increment
      stack_addr_plus1 <= stack_addr + lit(1, width: 16)

      # PC byte extraction
      pc_hi_byte <= pc_val[15..8]
      pc_lo_byte <= pc_val[7..0]

      # PC-1 for JSR (6502 pushes return address - 1)
      pc_minus_one <= pc_val - lit(1, width: 16)
      pc_m1_hi <= pc_minus_one[15..8]
      pc_m1_lo <= pc_minus_one[7..0]

      # State detection
      is_execute_state <= (ctrl_state == lit(ControlUnit::STATE_EXECUTE, width: 8))
      is_write_mem_state <= (ctrl_state == lit(ControlUnit::STATE_WRITE_MEM, width: 8))
      is_fetch_op1_state <= (ctrl_state == lit(ControlUnit::STATE_FETCH_OP1, width: 8))
      is_read_mem_state <= (ctrl_state == lit(ControlUnit::STATE_READ_MEM, width: 8))
      is_pull_state <= (ctrl_state == lit(ControlUnit::STATE_PULL, width: 8))
      is_decode_state <= (ctrl_state == lit(ControlUnit::STATE_DECODE, width: 8))

      # RTS/RTI/BRK vector states - for loading PC from return address
      is_rts_pull_hi <= (ctrl_state == lit(ControlUnit::STATE_RTS_PULL_HI, width: 8))
      is_rti_pull_hi <= (ctrl_state == lit(ControlUnit::STATE_RTI_PULL_HI, width: 8))
      is_brk_vec_hi <= (ctrl_state == lit(ControlUnit::STATE_BRK_VEC_HI, width: 8))

      # Compute return address for RTS/RTI
      # When in RTS_PULL_HI or RTI_PULL_HI state, data_in has the high byte
      # and alatch_addr_lo has the low byte (captured in previous cycle)
      # For RTS, we need to add 1 to get the actual return address
      # But agen_eff_addr already handles the +1 for RTS
      # So we build the address from data_in (hi) and alatch_addr_lo (lo)
      return_addr <= cat(data_in, alatch_addr_lo)

      # Implied mode instructions transition directly from DECODE to EXECUTE
      # This is used for TXS timing since it doesn't set writes_reg
      decode_to_execute <= is_decode_state &
                           (dec_addr_mode == lit(AddressGenerator::MODE_IMPLIED, width: 4))

      # Addressing mode detection
      load_from_imm <= (dec_addr_mode == lit(AddressGenerator::MODE_IMMEDIATE, width: 4))
      load_from_mem <= ~load_from_imm

      # Instruction type detection (TYPE_LOAD = 1, TYPE_TRANSFER = 3, TYPE_STACK = 8, TYPE_FLAG = 9)
      is_load_instr <= (dec_instr_type == lit(InstructionDecoder::TYPE_LOAD, width: 4))
      is_transfer_instr <= (dec_instr_type == lit(InstructionDecoder::TYPE_TRANSFER, width: 4))
      is_flag_instr <= (dec_instr_type == lit(InstructionDecoder::TYPE_FLAG, width: 4))
      is_stack_instr <= (dec_instr_type == lit(InstructionDecoder::TYPE_STACK, width: 4))

      # PLA: stack pull to register (TYPE_STACK with writes_reg and not is_status)
      is_stack_pull_reg <= is_stack_instr & dec_writes_reg & ~dec_is_status_op

      # Special instructions involving SP: TSX (0xBA) and TXS (0x9A)
      is_tsx_instr <= (ir_opcode == lit(0xBA, width: 8))
      is_txs_instr <= (ir_opcode == lit(0x9A, width: 8))

      # For flag instructions (SEC/CLC/SED/CLD/SEI/CLI/CLV), bit 5 of opcode = set(1)/clear(0)
      flag_set_value <= ir_opcode[5]

      # Flag type from opcode bits 7:6: 00=C, 01=I, 10=V, 11=D
      flag_type <= ir_opcode[7..6]
      is_flag_c_instr <= is_flag_instr & (flag_type == lit(0, width: 2))
      is_flag_i_instr <= is_flag_instr & (flag_type == lit(1, width: 2))
      is_flag_v_instr <= is_flag_instr & (flag_type == lit(2, width: 2))
      is_flag_d_instr <= is_flag_instr & (flag_type == lit(3, width: 2))

      # Status register unused inputs (tie to 0)
      # load_flags is not used - we use individual load_n/z/c/v instead
      # load_b and b_in are not used - B flag is rarely modified
      sr_load_flags <= lit(0, width: 1)
      sr_load_b <= lit(0, width: 1)
      sr_b_in <= lit(0, width: 1)

      # RMW instruction detection (INC/DEC memory, shifts on memory)
      is_rmw_instr <= dec_is_rmw

      # Latch ALU result during EXECUTE state for RMW operations
      # This captures the result before the carry flag gets updated
      latch_alu_result <= is_execute_state & is_rmw_instr

      # ALU input A selection
      # For RMW (INC/DEC memory): use data latch (memory value)
      # Otherwise: src_reg selects A(0), X(1), Y(2), or memory(3)
      alu_a_sel <= mux(is_rmw_instr,
                       dlatch_data,
                       mux(dec_src_reg[1],
                           mux(dec_src_reg[0], dlatch_data, regs_y),
                           mux(dec_src_reg[0], regs_x, regs_a)))

      # ALU input B selection
      # For immediate mode during FETCH_OP1, use data_in directly (operand not yet in IR)
      # For memory mode during READ_MEM, use data_in directly (data not yet in latch)
      alu_b_sel <= mux(load_from_imm,
                       mux(is_fetch_op1_state, data_in, ir_operand_lo),
                       mux(is_read_mem_state, data_in, dlatch_data))

      # Register data input selection
      # Priority: external load > TSX (sp to x) > PLA (stack pull) > load instruction > transfer > ALU result
      # - TSX: use SP value
      # - PLA: use data_in directly during PULL state (data not yet in latch)
      # - Load instructions (LDA, LDX, LDY): use immediate operand or memory data
      #   For immediate mode during FETCH_OP1, use data_in directly (operand not yet in IR)
      #   For memory mode during READ_MEM, use data_in directly (data not yet in latch)
      # - Transfer instructions (TAX, TAY, TXA, TYA): use source register (alu_a_sel)
      # - ALU/other instructions: use ALU result
      actual_reg_data <= mux(ext_a_load_en | ext_x_load_en | ext_y_load_en,
                             mux(ext_a_load_en, ext_a_load_data,
                                 mux(ext_x_load_en, ext_x_load_data, ext_y_load_data)),
                             mux(is_tsx_instr, sp_val,
                                 mux(is_stack_pull_reg,
                                     mux(is_pull_state, data_in, dlatch_data),
                                     mux(is_load_instr,
                                         mux(load_from_imm,
                                             mux(is_fetch_op1_state, data_in, ir_operand_lo),
                                             mux(is_read_mem_state, data_in, dlatch_data)),
                                         mux(is_transfer_instr, alu_a_sel, alu_result)))))

      # Register load enables
      # External loads have priority, then internal writes based on dst_reg
      # Control unit sets reg_write=1 during state that transitions to EXECUTE
      # So we use ctrl_reg_write directly (it's already "early" timed)
      # The register will capture on the clock edge entering EXECUTE
      actual_load_a <= ext_a_load_en |
                       (ctrl_reg_write &
                        (dec_dst_reg == lit(MOS6502::REG_A, width: 2)))
      actual_load_x <= ext_x_load_en |
                       (ctrl_reg_write &
                        (dec_dst_reg == lit(MOS6502::REG_X, width: 2))) |
                       (is_tsx_instr & ctrl_reg_write)
      actual_load_y <= ext_y_load_en |
                       (ctrl_reg_write &
                        (dec_dst_reg == lit(MOS6502::REG_Y, width: 2)))

      # PC control
      # For RTS/RTI: PC loads from return_addr (cat(data_in, alatch_addr_lo))
      # This avoids race condition where PC would see old alatch_addr value
      # For BRK vector: same issue - need to use data_in directly
      actual_pc_load <= ext_pc_load_en | ctrl_pc_load
      # PC increment: follows control unit
      # During ext_pc_load in FETCH state:
      #   actual_pc_load = 1, actual_pc_inc = 1 (from ctrl_pc_inc)
      #   ProgramCounter: PC = addr_in + 1 = target_addr + 1
      # This is correct - after FETCH, PC should point past the opcode to the operand
      actual_pc_inc <= ctrl_pc_inc
      actual_pc_addr <= mux(ext_pc_load_en, ext_pc_load_data,
                            mux(is_rts_pull_hi | is_rti_pull_hi | is_brk_vec_hi,
                                return_addr, agen_eff_addr))

      # SP control
      # TXS (0x9A) transfers X to SP
      # Use decode_to_execute for early timing (TXS doesn't set writes_reg, so ctrl_reg_write=0)
      actual_sp_load <= ext_sp_load_en | (is_txs_instr & decode_to_execute)
      actual_sp_data <= mux(is_txs_instr, regs_x, ext_sp_load_data)

      # Flag update enables
      # For RMW instructions, delay flag updates until WRITE_MEM state to avoid
      # affecting the ALU result that gets written to memory
      # ALU flags from arithmetic/logic ops (non-RMW, use ctrl_update_flags which is early-timed)
      # For RMW during WRITE_MEM
      actual_load_n <= (ctrl_update_flags & dec_sets_nz & ~is_rmw_instr) |
                       (is_write_mem_state & is_rmw_instr & dec_sets_nz)
      actual_load_z <= (ctrl_update_flags & dec_sets_nz & ~is_rmw_instr) |
                       (is_write_mem_state & is_rmw_instr & dec_sets_nz)
      # Carry: ALU ops that set C (delayed for RMW), or SEC/CLC flag instruction
      actual_load_c <= (ctrl_update_flags & dec_sets_c & ~is_rmw_instr) |
                       (is_write_mem_state & is_rmw_instr & dec_sets_c) |
                       (is_flag_c_instr & ctrl_update_flags)
      # Overflow: ALU ops that set V, or CLV flag instruction
      actual_load_v <= (ctrl_update_flags & dec_sets_v) |
                       (is_flag_v_instr & ctrl_update_flags)
      # Interrupt: SEI/CLI flag instruction only
      actual_load_i <= is_flag_i_instr & ctrl_update_flags
      # Decimal: SED/CLD flag instruction only
      actual_load_d <= is_flag_d_instr & ctrl_update_flags

      # Flag input values
      # For load/transfer/PLA instructions, use register data for N/Z flags
      # For flag instructions (SEC/CLC/SED/CLD/SEI/CLI/CLV), use opcode bit 5
      # Otherwise use ALU outputs (ADC, SBC, AND, ORA, EOR, etc.)
      flag_n_in <= mux(uses_reg_for_nz, reg_data_n, alu_n)
      flag_z_in <= mux(uses_reg_for_nz, reg_data_z, alu_z)
      flag_c_in <= mux(is_flag_c_instr, flag_set_value, alu_c)
      # Note: CLV always clears V (there's no SEV instruction), so use 0, not flag_set_value
      flag_v_in <= mux(is_flag_v_instr, lit(0, width: 1), alu_v)
      flag_i_in <= flag_set_value
      flag_d_in <= flag_set_value

      # PLP: load entire status register from stack
      # Use ctrl_update_flags for early timing (set during PULL state before EXECUTE)
      # Only for PLP (read from stack), not PHP (write to stack)
      actual_load_all <= is_stack_instr & dec_is_status_op & dec_is_read & ctrl_update_flags

      # Status register data input
      # During PULL state for PLP, use data_in directly (dlatch_data not captured yet)
      # Otherwise use dlatch_data
      sr_data_in <= mux(is_pull_state, data_in, dlatch_data)

      # For load/transfer/PLA instructions, N/Z flags come from register data, not ALU
      # This is because these instructions bypass the ALU (data goes directly to register)
      uses_reg_for_nz <= is_load_instr | is_transfer_instr | is_stack_pull_reg

      # Compute N/Z from actual_reg_data for load/transfer/PLA
      reg_data_n <= actual_reg_data[7]
      reg_data_z <= (actual_reg_data == lit(0, width: 8))

      # Address bus mux (8-way based on ctrl_addr_sel)
      addr <= mux(ctrl_addr_sel[2],
                  mux(ctrl_addr_sel[1],
                      mux(ctrl_addr_sel[0], lit(0xFFFE, width: 16), stack_addr_plus1),
                      mux(ctrl_addr_sel[0], stack_addr, agen_eff_addr)),
                  mux(ctrl_addr_sel[1],
                      mux(ctrl_addr_sel[0], acalc_ptr_addr_hi, acalc_ptr_addr_lo),
                      mux(ctrl_addr_sel[0], lit(0xFFFC, width: 16), pc_val)))

      # Data output mux (7-way based on ctrl_data_sel)
      # For JSR (data_sel 2,3), use PC-1 since 6502 pushes return address minus 1
      data_out <= mux(ctrl_data_sel[2],
                      mux(ctrl_data_sel[1],
                          mux(ctrl_data_sel[0], regs_a, regs_y),
                          mux(ctrl_data_sel[0], regs_x, (sr_p | lit(0x30, width: 8)))),
                      mux(ctrl_data_sel[1],
                          mux(ctrl_data_sel[0], pc_m1_lo, pc_m1_hi),
                          mux(ctrl_data_sel[0], alu_result, regs_a)))

      # RW signal
      rw <= ~ctrl_mem_write

      # Sync signal
      sync <= (ctrl_state == lit(ControlUnit::STATE_FETCH, width: 8))

      # Debug outputs
      reg_a <= regs_a
      reg_x <= regs_x
      reg_y <= regs_y
      reg_sp <= sp_val
      reg_pc <= pc_val
      reg_p <= sr_p
      opcode <= ir_opcode
      state <= ctrl_state
      halted <= ctrl_halted
      cycle_count <= ctrl_cycle_count
    end

  end
end
