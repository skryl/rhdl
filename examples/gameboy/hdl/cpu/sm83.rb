# SM83 CPU - Game Boy CPU Core
# Corresponds to: reference/rtl/T80/GBse.vhd and T80.vhd
#
# The SM83 is a custom Sharp CPU used in the Game Boy.
# It's similar to the Z80 but with some differences:
# - No IX, IY index registers
# - No shadow registers
# - Different flag bit positions: Z=7, N=6, H=5, C=4
# - Different instruction set (subset of Z80 + GB-specific)
#
# This implementation follows the T80 core with Mode=3 (Game Boy mode)
#
# Instruction Set Summary (all Game Boy instructions):
# 8-bit load: LD r,r' | LD r,n | LD r,(HL) | LD (HL),r | LD (HL),n | LD A,(BC/DE) | LD (BC/DE),A
#            LDI/LDD A,(HL) | LDI/LDD (HL),A | LDH (a8),A | LDH A,(a8) | LDH (C),A | LDH A,(C)
#            LD A,(a16) | LD (a16),A
# 16-bit load: LD rr,nn | LD SP,HL | PUSH rr | POP rr | LD (a16),SP | LD HL,SP+n
# 8-bit ALU: ADD/ADC/SUB/SBC/AND/XOR/OR/CP A,r | ADD/ADC/SUB/SBC/AND/XOR/OR/CP A,(HL)
#           ADD/ADC/SUB/SBC/AND/XOR/OR/CP A,n | INC/DEC r | INC/DEC (HL) | DAA | CPL | CCF | SCF
# 16-bit ALU: ADD HL,rr | INC/DEC rr | ADD SP,n
# Rotate/Shift: RLCA | RLA | RRCA | RRA | CB prefix (RLC/RL/RRC/RR/SLA/SRA/SRL/SWAP/BIT/SET/RES)
# Control: JP nn | JP cc,nn | JP (HL) | JR n | JR cc,n | CALL nn | CALL cc,nn | RET | RET cc | RETI | RST
# Misc: NOP | HALT | STOP | DI | EI

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SM83 < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Flag bit positions (Game Boy mode)
    FLAG_Z = 7  # Zero
    FLAG_N = 6  # Subtract
    FLAG_H = 5  # Half-carry
    FLAG_C = 4  # Carry

    # Address mode constants for Set_Addr_To
    ADDR_PC = 0   # Program counter
    ADDR_SP = 1   # Stack pointer
    ADDR_HL = 2   # HL register pair
    ADDR_DE = 3   # DE register pair
    ADDR_BC = 4   # BC register pair
    ADDR_WZ = 5   # WZ temp register (TmpAddr)
    ADDR_IO = 6   # I/O address (0xFF00 + n)
    ADDR_IOC = 7  # I/O address (0xFF00 + C)

    # Control signals
    input :reset_n         # Active-low reset
    input :clk             # Clock (active edge)
    input :clken           # Clock enable
    input :wait_n          # Wait signal
    input :int_n           # Interrupt request (active low)
    input :nmi_n, default: 1  # Non-maskable interrupt (unused in GB)
    input :busrq_n, default: 1  # Bus request

    # Bus signals
    output :m1_n           # Machine cycle 1 (opcode fetch)
    output :mreq_n         # Memory request
    output :iorq_n         # I/O request
    output :rd_n           # Read
    output :wr_n           # Write
    output :rfsh_n         # Refresh (unused in GB)
    output :halt_n         # Halt status
    output :busak_n        # Bus acknowledge

    # Address and data
    output :addr_bus, width: 16   # Address bus
    input :data_in, width: 8      # Data in
    output :data_out, width: 8    # Data out

    # Game Boy specific
    output :stop_out           # STOP instruction executed
    input :is_gbc              # Game Boy Color mode

    # Debug outputs (for Verilator simulation visibility)
    output :debug_pc, width: 16    # Program counter for debugging
    output :debug_acc, width: 8    # Accumulator for debugging
    output :debug_f, width: 8      # Flags register for debugging
    output :debug_b, width: 8      # B register for debugging
    output :debug_c, width: 8      # C register for debugging
    output :debug_d, width: 8      # D register for debugging
    output :debug_e, width: 8      # E register for debugging
    output :debug_h, width: 8      # H register for debugging
    output :debug_l, width: 8      # L register for debugging
    output :debug_sp, width: 16    # Stack pointer for debugging
    output :debug_ir, width: 8     # Current instruction register
    output :debug_save_alu         # ALU save signal
    output :debug_t_state, width: 3 # T-state counter
    output :debug_m_cycle, width: 3 # M-cycle counter
    output :debug_alu_flags, width: 8 # ALU flags output
    output :debug_clken            # Clock enable signal
    output :debug_alu_op, width: 4 # ALU operation
    output :debug_bus_a, width: 8  # ALU input A
    output :debug_bus_b, width: 8  # ALU input B
    output :debug_alu_result, width: 8 # ALU result
    output :debug_z_flag               # Direct zero flag computation for debugging
    output :debug_bus_a_zero           # Test if bus_a is zero
    output :debug_const_one            # Constant 1 for testing

    # =========================================================================
    # Internal Registers
    # =========================================================================

    # Main registers
    wire :acc, width: 8         # Accumulator
    wire :f_reg, width: 8       # Flags: ZNHC----
    wire :b_reg, width: 8       # B register
    wire :c_reg, width: 8       # C register
    wire :d_reg, width: 8       # D register
    wire :e_reg, width: 8       # E register
    wire :h_reg, width: 8       # H register
    wire :l_reg, width: 8       # L register
    wire :sp, width: 16         # Stack pointer
    wire :pc, width: 16         # Program counter

    # Composed register pairs
    wire :bc, width: 16
    wire :de, width: 16
    wire :hl, width: 16

    # Help registers
    wire :ir, width: 8          # Instruction register
    wire :wz, width: 16         # Temporary address register (WZ/TmpAddr)
    wire :di_reg, width: 8      # Data input latch

    # State machine
    wire :m_cycle, width: 3     # Current machine cycle (1-7)
    wire :t_state, width: 3     # Current T-state (1-4)
    wire :m_cycles, width: 3    # Total machine cycles for current instruction

    # Control flags
    wire :int_e_ff1             # Interrupt enable flag 1 (IME)
    wire :int_e_ff2             # Interrupt enable flag 2
    wire :halt_ff               # Halt flag
    wire :int_cycle             # Interrupt cycle active
    wire :prefix, width: 2      # Instruction prefix (CB)
    wire :cb_prefix             # CB prefix active (latched)
    wire :cb_ir, width: 8       # CB instruction register

    # =========================================================================
    # Microcode Control Signals
    # =========================================================================

    wire :inc_pc                # Increment PC
    wire :read_to_acc           # Read to accumulator
    wire :set_bus_a_to, width: 4  # ALU operand A source
    wire :set_bus_b_to, width: 4  # ALU operand B source
    wire :alu_op, width: 4      # ALU operation
    wire :save_alu              # Save ALU result
    wire :set_addr_to, width: 3 # Address bus source
    wire :no_read               # Suppress memory read
    wire :write_sig             # Memory write
    wire :ldz                   # Load WZ low byte
    wire :ldw                   # Load WZ high byte
    wire :jump                  # Jump instruction
    wire :jump_e                # Relative jump
    wire :call                  # Call instruction
    wire :ret                   # Return instruction
    wire :halt                  # Halt instruction
    wire :set_di                # Disable interrupts
    wire :set_ei                # Enable interrupts
    wire :is_stop               # STOP instruction
    wire :load_sp_wz            # Load SP from WZ
    wire :load_bc_wz            # Load BC from WZ
    wire :load_de_wz            # Load DE from WZ
    wire :load_hl_wz            # Load HL from WZ
    wire :inc_hl                # Increment HL (for LDI)
    wire :dec_hl                # Decrement HL (for LDD)
    wire :write_hl              # Write to (HL)
    wire :cond_true             # Condition true for conditional jump
    wire :is_cond_jr            # Conditional JR instruction
    wire :cb_bit                # CB BIT instruction
    wire :cb_bit_flags, width: 8  # Flags result from CB BIT instruction
    wire :cb_src, width: 8        # Source register for CB operation
    wire :bit_mask, width: 8      # Bit mask for CB BIT

    # Additional control signals for full instruction set
    wire :read_to_reg           # Read to specified register (not acc)
    wire :write_reg, width: 3   # Which register to write to (0-7: B,C,D,E,H,L,(HL),A)
    wire :incdec_16, width: 4   # 16-bit increment/decrement: [3:2]=dir, [1:0]=pair
    wire :rot_akku              # Rotate accumulator (RLCA/RLA/RRCA/RRA)
    wire :ld_sp_hl              # LD SP,HL instruction
    wire :rst_p                 # RST instruction
    wire :rst_addr, width: 8    # RST target address
    wire :push_op               # PUSH operation
    wire :pop_op                # POP operation
    wire :reti_op               # RETI instruction
    wire :cpl_op                # CPL instruction
    wire :ccf_op                # CCF instruction
    wire :scf_op                # SCF instruction
    wire :daa_op                # DAA instruction
    wire :cb_rot_op             # CB rotate/shift operation
    wire :cb_set_op             # CB SET operation
    wire :cb_res_op             # CB RES operation
    wire :cb_result, width: 8   # Result of CB operation

    # Cycle count condition wires (for m_cycles calculation)
    wire :is_6_cycles           # 6-cycle instructions (CALL)
    wire :is_5_cycles           # 5-cycle instructions (PUSH, LD (nn),SP)
    wire :is_4_cycles           # 4-cycle instructions (PUSH, RET, RST, RETI)
    wire :is_3_cycles           # 3-cycle instructions
    wire :is_2_cycles           # 2-cycle instructions

    # Instruction pattern detection wires (shared between behavior and sequential)
    wire :is_ld_rr              # LD r,r' (register to register)
    wire :is_ld_r_n             # LD r,n (immediate to register)
    wire :is_ld_r_hl            # LD r,(HL)
    wire :is_ld_hl_r            # LD (HL),r
    wire :is_inc_r              # INC r
    wire :is_dec_r              # DEC r
    wire :is_alu_imm            # ALU A,n immediate
    wire :is_rst                # RST instruction
    wire :is_push               # PUSH instruction

    # ALU signals
    wire :bus_a, width: 8       # ALU operand A
    wire :bus_b, width: 8       # ALU operand B
    wire :alu_result, width: 8  # ALU result
    wire :alu_flags, width: 8   # ALU flag output

    # =========================================================================
    # ALL Combinational Logic (MUST be in single behavior block!)
    # The behavior DSL only keeps the LAST behavior block, so all combinational
    # logic must be merged into one block.
    # =========================================================================

    behavior do
      # -----------------------------------------------------------------------
      # Register Pair Composition
      # -----------------------------------------------------------------------
      bc <= cat(b_reg, c_reg)
      de <= cat(d_reg, e_reg)
      hl <= cat(h_reg, l_reg)

      # -----------------------------------------------------------------------
      # Debug Outputs
      # -----------------------------------------------------------------------
      debug_pc <= pc
      debug_acc <= acc
      debug_f <= f_reg
      debug_b <= b_reg
      debug_c <= c_reg
      debug_d <= d_reg
      debug_e <= e_reg
      debug_h <= h_reg
      debug_l <= l_reg
      debug_sp <= sp
      debug_ir <= ir
      debug_save_alu <= save_alu
      debug_t_state <= t_state
      debug_m_cycle <= m_cycle
      debug_alu_flags <= alu_flags
      debug_clken <= clken
      debug_alu_op <= alu_op
      debug_bus_a <= bus_a
      debug_bus_b <= bus_b
      debug_alu_result <= alu_result
      debug_z_flag <= (alu_result == lit(0, width: 8))  # Direct zero flag check
      debug_bus_a_zero <= (bus_a == lit(0, width: 8))  # Test bus_a is zero
      debug_const_one <= lit(1, width: 1)  # Always 1 for testing

      # -----------------------------------------------------------------------
      # Instruction Decoder (Microcode) - Default values
      # -----------------------------------------------------------------------
      # Note: inc_pc is set comprehensively below (around line 769)
      read_to_acc <= lit(0, width: 1)
      set_bus_a_to <= lit(7, width: 4)  # ACC
      set_bus_b_to <= lit(7, width: 4)  # ACC
      alu_op <= lit(0, width: 4)
      save_alu <= lit(0, width: 1)
      set_addr_to <= lit(0, width: 3)   # PC
      no_read <= lit(0, width: 1)
      write_sig <= lit(0, width: 1)
      # ldz - Load WZ low byte (consolidated from all instruction handlers)
      ldz <= # LD rr,nn M2
             ((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle == lit(2, width: 3))) |
             # JR e M2
             ((ir == lit(0x18, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # RET M2
             ((ir == lit(0xC9, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # JP nn M2
             ((ir == lit(0xC3, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # CALL nn M2
             ((ir == lit(0xCD, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # LDH (a8),A M2
             ((ir == lit(0xE0, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # LDH A,(a8) M2
             ((ir == lit(0xF0, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # Conditional JR M2
             (is_cond_jr & (m_cycle == lit(2, width: 3))) |
             # LD (HL),n M2
             ((ir == lit(0x36, width: 8)) & (m_cycle == lit(2, width: 3))) |
             # LD (a16),A / LD A,(a16) M2
             (((ir == lit(0xEA, width: 8)) | (ir == lit(0xFA, width: 8))) & (m_cycle == lit(2, width: 3)))

      # ldw - Load WZ high byte (consolidated from all instruction handlers)
      ldw <= # LD rr,nn M3
             ((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle == lit(3, width: 3))) |
             # RET M3
             ((ir == lit(0xC9, width: 8)) & (m_cycle == lit(3, width: 3))) |
             # JP nn M3
             ((ir == lit(0xC3, width: 8)) & (m_cycle == lit(3, width: 3))) |
             # CALL nn M3
             ((ir == lit(0xCD, width: 8)) & (m_cycle == lit(3, width: 3))) |
             # LD (a16),A / LD A,(a16) M3
             (((ir == lit(0xEA, width: 8)) | (ir == lit(0xFA, width: 8))) & (m_cycle == lit(3, width: 3)))

      # jump - Absolute jump (consolidated from JP nn and JP (HL))
      jump <= (ir == lit(0xC3, width: 8)) | (ir == lit(0xE9, width: 8))

      # jump_e - Relative jump (consolidated from JR e and conditional JR)
      jump_e <= (ir == lit(0x18, width: 8)) | (is_cond_jr & cond_true)
      call <= lit(0, width: 1)
      ret <= lit(0, width: 1)
      halt <= lit(0, width: 1)
      set_di <= lit(0, width: 1)
      set_ei <= lit(0, width: 1)
      is_stop <= lit(0, width: 1)
      prefix <= lit(0, width: 2)
      load_sp_wz <= lit(0, width: 1)
      load_bc_wz <= lit(0, width: 1)
      load_de_wz <= lit(0, width: 1)
      load_hl_wz <= lit(0, width: 1)
      inc_hl <= lit(0, width: 1)
      dec_hl <= lit(0, width: 1)
      write_hl <= lit(0, width: 1)
      cond_true <= lit(0, width: 1)
      is_cond_jr <= lit(0, width: 1)
      cb_bit <= lit(0, width: 1)
      read_to_reg <= lit(0, width: 1)
      write_reg <= lit(0, width: 3)
      incdec_16 <= lit(0, width: 4)
      rot_akku <= lit(0, width: 1)
      ld_sp_hl <= lit(0, width: 1)
      rst_p <= lit(0, width: 1)
      rst_addr <= lit(0, width: 8)
      push_op <= lit(0, width: 1)
      pop_op <= lit(0, width: 1)
      reti_op <= lit(0, width: 1)
      cpl_op <= lit(0, width: 1)
      ccf_op <= lit(0, width: 1)
      scf_op <= lit(0, width: 1)
      daa_op <= lit(0, width: 1)
      cb_rot_op <= lit(0, width: 1)
      cb_set_op <= lit(0, width: 1)
      cb_res_op <= lit(0, width: 1)
      cb_result <= lit(0, width: 8)

      # m_cycles calculation - categorize all GB instructions by cycle count
      # Reference: T80_MCode.vhd Mode=3 timings

      # 6-cycle instructions: CALL nn (CD)
      is_6_cycles <= (ir == lit(0xCD, width: 8))

      # 5-cycle instructions: LD (a16),SP (08)
      is_5_cycles <= (ir == lit(0x08, width: 8))

      # 4-cycle instructions: PUSH (C5/D5/E5/F5), RET (C9), RST (C7/CF/D7/DF/E7/EF/F7/FF),
      # RETI (D9), JP nn (C3), LD A,(a16) (FA), LD (a16),A (EA)
      # Also: CB rotate/set/res with (HL) operand (cb_ir[2:0] = 6, cb_ir[7:6] != 01)
      is_push <= (ir[3..0] == lit(5, width: 4)) & (ir[7..6] == lit(3, width: 2))
      is_rst <= (ir[3..0] == lit(7, width: 4)) & (ir[7..6] == lit(3, width: 2))

      # CB (HL) instruction detection - cb_ir is available from M2/T2
      # cb_ir[2:0] = 6 means (HL) operand
      # cb_ir[7:6] = 01 means BIT (test only, no write back) - 3 cycles
      # cb_ir[7:6] = 00/10/11 means rotate/set/res (read-modify-write) - 4 cycles
      is_cb = (ir == lit(0xCB, width: 8))
      is_cb_hl = is_cb & (cb_ir[2..0] == lit(6, width: 3))
      is_cb_bit_hl = is_cb_hl & (cb_ir[7..6] == lit(1, width: 2))
      is_cb_rw_hl = is_cb_hl & (cb_ir[7..6] != lit(1, width: 2))

      is_4_cycles <= is_push | is_rst |
                     (ir == lit(0xC9, width: 8)) | (ir == lit(0xD9, width: 8)) |
                     (ir == lit(0xC3, width: 8)) |
                     (ir == lit(0xFA, width: 8)) | (ir == lit(0xEA, width: 8)) |
                     is_cb_rw_hl  # CB rotate/set/res (HL) = 4 cycles

      # Conditional JR detection (needed for cycle count) - must be before is_3_cycles
      # JR NZ/Z/NC/C - 0x20/0x28/0x30/0x38
      # 2 cycles if condition false, 3 cycles if condition true
      is_cond_jr <= (ir == lit(0x20, width: 8)) | (ir == lit(0x28, width: 8)) |
                    (ir == lit(0x30, width: 8)) | (ir == lit(0x38, width: 8))
      # Condition evaluation: 20=NZ (Z=0), 28=Z (Z=1), 30=NC (C=0), 38=C (C=1)
      # ir[4:3] = condition code: 00=NZ, 01=Z, 10=NC, 11=C
      cond_true <= mux(ir[4..3] == lit(0, width: 2), ~f_reg[FLAG_Z],     # NZ
                   mux(ir[4..3] == lit(1, width: 2), f_reg[FLAG_Z],      # Z
                   mux(ir[4..3] == lit(2, width: 2), ~f_reg[FLAG_C],     # NC
                   mux(ir[4..3] == lit(3, width: 2), f_reg[FLAG_C],      # C
                       lit(0, width: 1)))))

      # 3-cycle instructions: LDH (E0, F0), LD rr,nn (01, 11, 21, 31), POP (C1/D1/E1/F1)
      # LD r,(HL) (46/4E/56/5E/66/6E/7E), LD (HL),r (70-77 except 76=HALT)
      # INC/DEC (HL) (34/35), LD (HL),n (36), JR e (18), LD HL,SP+n (F8)
      # Also: conditional JR when condition is TRUE (extra cycle for displacement add)
      is_pop = (ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(3, width: 2))
      is_ld_r_hl <= (ir[7..6] == lit(1, width: 2)) & (ir[2..0] == lit(6, width: 3)) & (ir != lit(0x76, width: 8))
      is_ld_hl_r <= (ir[7..6] == lit(1, width: 2)) & (ir[5..3] == lit(6, width: 3)) & (ir != lit(0x76, width: 8))
      is_3_cycles <= (ir == lit(0xE0, width: 8)) | (ir == lit(0xF0, width: 8)) |
                     ((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2))) |
                     is_pop | is_ld_r_hl | is_ld_hl_r |
                     (ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8)) |
                     (ir == lit(0x36, width: 8)) | (ir == lit(0x18, width: 8)) |
                     (ir == lit(0xF8, width: 8)) |
                     (is_cond_jr & cond_true) |  # Conditional JR taken = 3 cycles
                     is_cb_bit_hl  # CB BIT (HL) = 3 cycles (read from memory, no write)

      # 2-cycle instructions: LD (BC),A, LD (DE),A, LD A,(BC), LD A,(DE), LD r,n
      # LDD/LDI (HL),A (32/22), LDD/LDI A,(HL) (3A/2A), CB prefix (without (HL))
      # conditional JR when NOT taken (20, 28, 30, 38), ALU A,n ops, INC/DEC rr (03/13/23/33, 0B/1B/2B/3B)
      # ADD HL,rr (09/19/29/39), LD SP,HL (F9), LD (C),A (E2), LD A,(C) (F2)
      is_ld_r_n <= (ir[2..0] == lit(6, width: 3)) & (ir[7..6] == lit(0, width: 2)) & (ir[5..3] != lit(6, width: 3))
      is_inc_rr = (ir[3..0] == lit(3, width: 4)) & (ir[7..6] == lit(0, width: 2))
      is_dec_rr = (ir[3..0] == lit(0xB, width: 4)) & (ir[7..6] == lit(0, width: 2))
      is_add_hl_rr = (ir[3..0] == lit(9, width: 4)) & (ir[7..6] == lit(0, width: 2))
      is_alu_imm <= (ir[7..6] == lit(3, width: 2)) & (ir[2..0] == lit(6, width: 3))

      # CB with register operand (not (HL)) - 2 cycles
      # is_cb_hl is defined above - it's true when cb_ir[2:0] == 6
      is_cb_reg = is_cb & ~is_cb_hl

      # 2-cycle instructions including CB prefix with register operands
      is_2_cycles <= (ir == lit(0x02, width: 8)) | (ir == lit(0x12, width: 8)) |
                     (ir == lit(0x0A, width: 8)) | (ir == lit(0x1A, width: 8)) |
                     (ir == lit(0x32, width: 8)) | (ir == lit(0x22, width: 8)) |
                     (ir == lit(0x3A, width: 8)) | (ir == lit(0x2A, width: 8)) |
                     is_cb_reg |  # CB with register operand = 2 cycles
                     (is_cond_jr & ~cond_true) |
                     is_alu_imm | is_ld_r_n | is_inc_rr | is_dec_rr | is_add_hl_rr |
                     (ir == lit(0xF9, width: 8)) |
                     (ir == lit(0xE2, width: 8)) | (ir == lit(0xF2, width: 8))

      # Default: 1 cycle for NOP, LD r,r', ALU A,r, INC/DEC r, rotates, etc.
      m_cycles <= mux(is_6_cycles, lit(6, width: 3),
                  mux(is_5_cycles, lit(5, width: 3),
                  mux(is_4_cycles, lit(4, width: 3),
                  mux(is_3_cycles, lit(3, width: 3),
                  mux(is_2_cycles, lit(2, width: 3),
                      lit(1, width: 3))))))

      # -----------------------------------------------------------------------
      # Instruction Decoder - Specific instructions
      # -----------------------------------------------------------------------

      # LD rr,nn - load WZ register for 16-bit immediate (01=BC, 11=DE, 21=HL, 31=SP)
      # ldz/ldw consolidated above
      # At end of M3, copy WZ to the target register pair based on bits 5:4
      # 01 (00): BC, 11 (01): DE, 21 (10): HL, 31 (11): SP
      load_bc_wz <= (ir == lit(0x01, width: 8)) & (m_cycle == lit(3, width: 3))
      load_de_wz <= (ir == lit(0x11, width: 8)) & (m_cycle == lit(3, width: 3))
      load_hl_wz <= (ir == lit(0x21, width: 8)) & (m_cycle == lit(3, width: 3))
      load_sp_wz <= (ir == lit(0x31, width: 8)) & (m_cycle == lit(3, width: 3))

      # LD A,n (3E) - load 8-bit immediate into A
      # M2: Read immediate byte from (PC) to A
      read_to_acc <= mux((ir == lit(0x3E, width: 8)) & (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_acc)

      # Write to memory for LD (BC/DE),A
      write_sig <= mux(((ir == lit(0x02, width: 8)) | (ir == lit(0x12, width: 8))) &
                       (m_cycle == lit(2, width: 3)),
                       lit(1, width: 1), lit(0, width: 1))
      no_read <= mux(((ir == lit(0x02, width: 8)) | (ir == lit(0x12, width: 8))) &
                      (m_cycle == lit(2, width: 3)),
                      lit(1, width: 1), lit(0, width: 1))

      # Read from memory for LD A,(BC/DE)
      read_to_acc <= mux(((ir == lit(0x0A, width: 8)) | (ir == lit(0x1A, width: 8))) &
                          (m_cycle == lit(2, width: 3)),
                          lit(1, width: 1), read_to_acc)

      # Address source for BC/DE indirect
      set_addr_to <= mux((ir == lit(0x02, width: 8)) | (ir == lit(0x0A, width: 8)),
                         lit(ADDR_BC, width: 3),
                         mux((ir == lit(0x12, width: 8)) | (ir == lit(0x1A, width: 8)),
                             lit(ADDR_DE, width: 3),
                             lit(ADDR_PC, width: 3)))

      # JR e - relative jump
      # jump_e and ldz consolidated above

      # HALT
      halt <= (ir == lit(0x76, width: 8))

      # ALU A,r operations (10xxxrrr - ADD/ADC/SUB/SBC/AND/XOR/OR/CP A,r)
      alu_op <= mux(ir[7..6] == lit(2, width: 2), ir[5..3], lit(0, width: 4))
      save_alu <= mux(ir[7..6] == lit(2, width: 2), lit(1, width: 1), lit(0, width: 1))
      set_bus_a_to <= mux(ir[7..6] == lit(2, width: 2), lit(7, width: 4), lit(7, width: 4)) # ACC
      set_bus_b_to <= mux(ir[7..6] == lit(2, width: 2), cat(lit(0, width: 1), ir[2..0]), lit(7, width: 4))

      # ALU A,n operations (11xxx110 - ADD/ADC/SUB/SBC/AND/XOR/OR/CP A,n)
      # These are 2-cycle instructions: M1=fetch opcode, M2=read immediate and execute
      # di_reg holds the immediate value read during M2
      is_alu_imm = (ir[7..6] == lit(3, width: 2)) & (ir[2..0] == lit(6, width: 3))
      # Only execute ALU operation during M2 (when immediate has been read into di_reg)
      alu_op <= mux(is_alu_imm & (m_cycle == lit(2, width: 3)), ir[5..3], alu_op)
      save_alu <= mux(is_alu_imm & (m_cycle == lit(2, width: 3)), lit(1, width: 1), save_alu)
      set_bus_a_to <= mux(is_alu_imm & (m_cycle == lit(2, width: 3)), lit(7, width: 4), set_bus_a_to)  # ACC
      # For ALU immediate, bus_b comes from di_reg (value 6) during M2
      set_bus_b_to <= mux(is_alu_imm & (m_cycle == lit(2, width: 3)),
                          lit(6, width: 4),  # 6 = di_reg (data input register)
                          set_bus_b_to)

      # RET - Return from call (4 cycles: M1=fetch, M2=read low from SP, M3=read high from SP+1, M4=jump)
      ret <= mux(ir == lit(0xC9, width: 8), lit(1, width: 1), lit(0, width: 1))
      # ldz/ldw consolidated above
      # RET reads from SP during M2 and M3 (handled via set_addr_to below)

      # JP nn - jump/ldz/ldw consolidated above

      # CB prefix
      prefix <= mux(ir == lit(0xCB, width: 8), lit(1, width: 2), lit(0, width: 2))

      # CALL nn - set call signal and load address
      # M1: fetch, M2: read low addr, M3: read high addr, M4: push PC high, M5: push PC low, M6: jump
      call <= mux(ir == lit(0xCD, width: 8), lit(1, width: 1), lit(0, width: 1))
      # ldz/ldw consolidated above
      # CALL M4 and M5: write return address to stack
      write_sig <= mux((ir == lit(0xCD, width: 8)) & ((m_cycle == lit(4, width: 3)) | (m_cycle == lit(5, width: 3))),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0xCD, width: 8)) & ((m_cycle == lit(4, width: 3)) | (m_cycle == lit(5, width: 3))),
                     lit(1, width: 1), no_read)

      # JP (HL) - 1 cycle jump using HL address (jump consolidated above)
      set_addr_to <= mux(ir == lit(0xE9, width: 8), lit(ADDR_HL, width: 3), set_addr_to)

      # DI - disable interrupts
      set_di <= (ir == lit(0xF3, width: 8))

      # EI - enable interrupts
      set_ei <= (ir == lit(0xFB, width: 8))

      # STOP
      is_stop <= (ir == lit(0x10, width: 8))

      # LDH (a8), A (E0) - Write A to (0xFF00 + n)
      # M2: Read immediate n from (PC), store in wz[7:0] (ldz consolidated above)
      # M3: Write A to (0xFF00 + n)
      set_addr_to <= mux((ir == lit(0xE0, width: 8)) & (m_cycle == lit(3, width: 3)),
                         lit(ADDR_IO, width: 3), set_addr_to)
      write_sig <= mux((ir == lit(0xE0, width: 8)) & (m_cycle == lit(3, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0xE0, width: 8)) & (m_cycle == lit(3, width: 3)),
                     lit(1, width: 1), no_read)

      # LDH A, (a8) (F0) - Read from (0xFF00 + n) to A
      # M2: Read immediate n from (PC), store in wz[7:0] (ldz consolidated above)
      # M3: Read from (0xFF00 + n) to A
      set_addr_to <= mux((ir == lit(0xF0, width: 8)) & (m_cycle == lit(3, width: 3)),
                         lit(ADDR_IO, width: 3), set_addr_to)
      read_to_acc <= mux((ir == lit(0xF0, width: 8)) & (m_cycle == lit(3, width: 3)),
                         lit(1, width: 1), read_to_acc)

      # LDD (HL), A (0x32) - Write A to (HL) then decrement HL
      # M2: Write A to (HL), then decrement HL
      set_addr_to <= mux((ir == lit(0x32, width: 8)) & (m_cycle == lit(2, width: 3)),
                         lit(ADDR_HL, width: 3), set_addr_to)
      write_sig <= mux((ir == lit(0x32, width: 8)) & (m_cycle == lit(2, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0x32, width: 8)) & (m_cycle == lit(2, width: 3)),
                     lit(1, width: 1), no_read)
      dec_hl <= (ir == lit(0x32, width: 8)) & (m_cycle == lit(2, width: 3))

      # LDI (HL), A (0x22) - Write A to (HL) then increment HL
      # M2: Write A to (HL), then increment HL
      set_addr_to <= mux((ir == lit(0x22, width: 8)) & (m_cycle == lit(2, width: 3)),
                         lit(ADDR_HL, width: 3), set_addr_to)
      write_sig <= mux((ir == lit(0x22, width: 8)) & (m_cycle == lit(2, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0x22, width: 8)) & (m_cycle == lit(2, width: 3)),
                     lit(1, width: 1), no_read)
      inc_hl <= (ir == lit(0x22, width: 8)) & (m_cycle == lit(2, width: 3))

      # Conditional JR (JR NZ/Z/NC/C) - 0x20/0x28/0x30/0x38
      # M2: Read displacement to WZ low, check condition (ldz consolidated above)
      # M3: If condition true, add displacement to PC (extra cycle for is_cond_jr & cond_true)
      # Note: is_cond_jr, cond_true, and jump_e are defined/consolidated above

      # -----------------------------------------------------------------------
      # LD r,r' - Register to register loads (01xxxyyy except 76=HALT)
      # This is a 1-cycle instruction that copies from source (bits 2:0) to dest (bits 5:3)
      # Register encoding: 0=B, 1=C, 2=D, 3=E, 4=H, 5=L, 6=(HL), 7=A
      # -----------------------------------------------------------------------
      is_ld_rr <= (ir[7..6] == lit(1, width: 2)) & (ir != lit(0x76, width: 8)) &
                  (ir[2..0] != lit(6, width: 3)) & (ir[5..3] != lit(6, width: 3))
      # For LD r,r', source is ir[2:0], dest is ir[5:3]
      # We'll handle this in sequential block by using read_to_reg and write_reg
      read_to_reg <= mux(is_ld_rr, lit(1, width: 1), read_to_reg)
      write_reg <= mux(is_ld_rr, ir[5..3], write_reg)
      set_bus_b_to <= mux(is_ld_rr, cat(lit(0, width: 1), ir[2..0]), set_bus_b_to)

      # -----------------------------------------------------------------------
      # LD r,n - Load 8-bit immediate into register (00xxx110)
      # M1: fetch opcode, M2: read immediate to register
      # This is 2-cycle for r=B,C,D,E,H,L,A; 3-cycle for (HL)
      # -----------------------------------------------------------------------
      # LD r,n for all registers including A (06/0E/16/1E/26/2E/3E)
      is_ld_r_imm = (ir[2..0] == lit(6, width: 3)) & (ir[7..6] == lit(0, width: 2))
      read_to_reg <= mux(is_ld_r_imm & (ir[5..3] != lit(6, width: 3)) & (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_reg)
      read_to_acc <= mux(is_ld_r_imm & (ir[5..3] == lit(7, width: 3)) & (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_acc)
      write_reg <= mux(is_ld_r_imm & (m_cycle == lit(2, width: 3)), ir[5..3], write_reg)
      # PC increment for LD r,n M2 - covered by comprehensive inc_pc below

      # -----------------------------------------------------------------------
      # LD r,(HL) - Load from (HL) into register (01xxx110 except 76=HALT)
      # M1: fetch, M2: read (HL) to register
      # -----------------------------------------------------------------------
      read_to_reg <= mux(is_ld_r_hl & (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_reg)
      read_to_acc <= mux((ir == lit(0x7E, width: 8)) & (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_acc)
      write_reg <= mux(is_ld_r_hl & (m_cycle == lit(2, width: 3)), ir[5..3], write_reg)
      set_addr_to <= mux(is_ld_r_hl, lit(ADDR_HL, width: 3), set_addr_to)

      # -----------------------------------------------------------------------
      # LD (HL),r - Store register to (HL) (01110xxx except 76=HALT)
      # M1: fetch, M2: write register to (HL)
      # -----------------------------------------------------------------------
      set_addr_to <= mux(is_ld_hl_r, lit(ADDR_HL, width: 3), set_addr_to)
      set_bus_b_to <= mux(is_ld_hl_r, cat(lit(0, width: 1), ir[2..0]), set_bus_b_to)
      write_sig <= mux(is_ld_hl_r & (m_cycle == lit(2, width: 3)), lit(1, width: 1), write_sig)
      no_read <= mux(is_ld_hl_r & (m_cycle == lit(2, width: 3)), lit(1, width: 1), no_read)

      # -----------------------------------------------------------------------
      # LD (HL),n - Store immediate to (HL) (36)
      # M1: fetch, M2: read immediate (ldz consolidated above), M3: write to (HL)
      # -----------------------------------------------------------------------
      set_addr_to <= mux((ir == lit(0x36, width: 8)) & (m_cycle == lit(3, width: 3)),
                         lit(ADDR_HL, width: 3), set_addr_to)
      write_sig <= mux((ir == lit(0x36, width: 8)) & (m_cycle == lit(3, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0x36, width: 8)) & (m_cycle == lit(3, width: 3)),
                     lit(1, width: 1), no_read)
      # PC increment for LD (HL),n M2 - covered by comprehensive inc_pc below

      # -----------------------------------------------------------------------
      # LDD A,(HL) (3A) - Load from (HL) to A, decrement HL
      # LDI A,(HL) (2A) - Load from (HL) to A, increment HL
      # -----------------------------------------------------------------------
      set_addr_to <= mux((ir == lit(0x3A, width: 8)) | (ir == lit(0x2A, width: 8)),
                         lit(ADDR_HL, width: 3), set_addr_to)
      read_to_acc <= mux(((ir == lit(0x3A, width: 8)) | (ir == lit(0x2A, width: 8))) &
                         (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_acc)
      dec_hl <= mux((ir == lit(0x3A, width: 8)) & (m_cycle == lit(2, width: 3)),
                    lit(1, width: 1), dec_hl)
      inc_hl <= mux((ir == lit(0x2A, width: 8)) & (m_cycle == lit(2, width: 3)),
                    lit(1, width: 1), inc_hl)

      # -----------------------------------------------------------------------
      # INC r / DEC r - Increment/Decrement register (00xxx100/00xxx101)
      # These are 1-cycle instructions except for (HL) which is 3-cycle
      # -----------------------------------------------------------------------
      is_inc_r <= (ir[2..0] == lit(4, width: 3)) & (ir[7..6] == lit(0, width: 2))
      is_dec_r <= (ir[2..0] == lit(5, width: 3)) & (ir[7..6] == lit(0, width: 2))
      # INC/DEC r uses ALU with operand B = 1, and preserves carry
      alu_op <= mux(is_inc_r & (ir[5..3] != lit(6, width: 3)), lit(0, width: 4), alu_op)   # ADD for INC
      alu_op <= mux(is_dec_r & (ir[5..3] != lit(6, width: 3)), lit(2, width: 4), alu_op)   # SUB for DEC
      save_alu <= mux((is_inc_r | is_dec_r) & (ir[5..3] != lit(6, width: 3)), lit(1, width: 1), save_alu)
      set_bus_a_to <= mux((is_inc_r | is_dec_r) & (ir[5..3] != lit(6, width: 3)),
                          cat(lit(0, width: 1), ir[5..3]), set_bus_a_to)
      set_bus_b_to <= mux((is_inc_r | is_dec_r) & (ir[5..3] != lit(6, width: 3)),
                          lit(10, width: 4), set_bus_b_to)  # 10 = constant 1
      read_to_reg <= mux((is_inc_r | is_dec_r) & (ir[5..3] != lit(6, width: 3)),
                         lit(1, width: 1), read_to_reg)
      write_reg <= mux((is_inc_r | is_dec_r), ir[5..3], write_reg)

      # -----------------------------------------------------------------------
      # INC (HL) / DEC (HL) - Increment/Decrement memory at (HL) (34/35)
      # M1: fetch, M2: read (HL), M3: write back
      # -----------------------------------------------------------------------
      set_addr_to <= mux((ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8)),
                         lit(ADDR_HL, width: 3), set_addr_to)
      alu_op <= mux((ir == lit(0x34, width: 8)) & (m_cycle == lit(2, width: 3)),
                    lit(0, width: 4), alu_op)  # ADD for INC
      alu_op <= mux((ir == lit(0x35, width: 8)) & (m_cycle == lit(2, width: 3)),
                    lit(2, width: 4), alu_op)  # SUB for DEC
      save_alu <= mux(((ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8))) & (m_cycle == lit(2, width: 3)),
                      lit(1, width: 1), save_alu)
      set_bus_a_to <= mux(((ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8))) & (m_cycle == lit(2, width: 3)),
                          lit(6, width: 4), set_bus_a_to)  # di_reg
      set_bus_b_to <= mux(((ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8))) & (m_cycle == lit(2, width: 3)),
                          lit(10, width: 4), set_bus_b_to)  # constant 1
      write_sig <= mux(((ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8))) & (m_cycle == lit(3, width: 3)),
                       lit(1, width: 1), write_sig)

      # -----------------------------------------------------------------------
      # RLCA, RLA, RRCA, RRA - Rotate accumulator (07, 17, 0F, 1F)
      # These are 1-cycle instructions that rotate A through or not through carry
      # -----------------------------------------------------------------------
      rot_akku <= (ir == lit(0x07, width: 8)) | (ir == lit(0x17, width: 8)) |
                  (ir == lit(0x0F, width: 8)) | (ir == lit(0x1F, width: 8))

      # -----------------------------------------------------------------------
      # INC rr / DEC rr - Increment/Decrement 16-bit register pair (00xx0011/00xx1011)
      # These are 2-cycle instructions in Game Boy mode
      # -----------------------------------------------------------------------
      incdec_16 <= mux(is_inc_rr & (m_cycle == lit(2, width: 3)),
                       cat(lit(0, width: 2), ir[5..4]),  # increment, pair from bits 5:4
                       mux(is_dec_rr & (m_cycle == lit(2, width: 3)),
                           cat(lit(2, width: 2), ir[5..4]),  # decrement, pair from bits 5:4
                           lit(0, width: 4)))

      # -----------------------------------------------------------------------
      # ADD HL,rr - Add 16-bit register pair to HL (00xx1001)
      # These are 2-cycle instructions in Game Boy mode
      # -----------------------------------------------------------------------
      # We'll handle this with a special flag in sequential block

      # -----------------------------------------------------------------------
      # CPL - Complement A (2F)
      # -----------------------------------------------------------------------
      cpl_op <= (ir == lit(0x2F, width: 8))

      # -----------------------------------------------------------------------
      # CCF - Complement carry flag (3F)
      # -----------------------------------------------------------------------
      ccf_op <= (ir == lit(0x3F, width: 8))

      # -----------------------------------------------------------------------
      # SCF - Set carry flag (37)
      # -----------------------------------------------------------------------
      scf_op <= (ir == lit(0x37, width: 8))

      # -----------------------------------------------------------------------
      # PUSH qq - Push 16-bit register to stack (C5/D5/E5/F5)
      # M1: fetch, M2: delay, M3: write high, M4: write low
      # -----------------------------------------------------------------------
      push_op <= is_push
      # PUSH M3 and M4: write to stack
      write_sig <= mux(is_push & ((m_cycle == lit(3, width: 3)) | (m_cycle == lit(4, width: 3))),
                       lit(1, width: 1), write_sig)
      no_read <= mux(is_push & ((m_cycle == lit(3, width: 3)) | (m_cycle == lit(4, width: 3))),
                     lit(1, width: 1), no_read)

      # -----------------------------------------------------------------------
      # POP qq - Pop 16-bit register from stack (C1/D1/E1/F1)
      # M1: fetch, M2: read low, M3: read high
      # -----------------------------------------------------------------------
      pop_op <= is_pop

      # -----------------------------------------------------------------------
      # RST p - Restart (call to fixed address) (C7/CF/D7/DF/E7/EF/F7/FF)
      # M1: fetch, M2: delay, M3: push PC high, M4: push PC low, jump
      # -----------------------------------------------------------------------
      rst_p <= is_rst
      rst_addr <= cat(lit(0, width: 2), ir[5..3], lit(0, width: 3))  # p * 8
      # RST M3 and M4: write to stack
      write_sig <= mux(is_rst & ((m_cycle == lit(3, width: 3)) | (m_cycle == lit(4, width: 3))),
                       lit(1, width: 1), write_sig)
      no_read <= mux(is_rst & ((m_cycle == lit(3, width: 3)) | (m_cycle == lit(4, width: 3))),
                     lit(1, width: 1), no_read)

      # -----------------------------------------------------------------------
      # RETI - Return from interrupt (D9)
      # Same as RET but also enables interrupts
      # -----------------------------------------------------------------------
      reti_op <= (ir == lit(0xD9, width: 8))
      set_ei <= mux((ir == lit(0xD9, width: 8)) & (m_cycle == lit(3, width: 3)),
                    lit(1, width: 1), set_ei)

      # -----------------------------------------------------------------------
      # LD SP,HL - Load SP from HL (F9)
      # -----------------------------------------------------------------------
      ld_sp_hl <= (ir == lit(0xF9, width: 8))

      # -----------------------------------------------------------------------
      # LDH (C),A (E2) - Write A to (0xFF00+C)
      # LDH A,(C) (F2) - Read (0xFF00+C) to A
      # -----------------------------------------------------------------------
      set_addr_to <= mux((ir == lit(0xE2, width: 8)) | (ir == lit(0xF2, width: 8)),
                         lit(ADDR_IOC, width: 3), set_addr_to)
      write_sig <= mux((ir == lit(0xE2, width: 8)) & (m_cycle == lit(2, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0xE2, width: 8)) & (m_cycle == lit(2, width: 3)),
                     lit(1, width: 1), no_read)
      read_to_acc <= mux((ir == lit(0xF2, width: 8)) & (m_cycle == lit(2, width: 3)),
                         lit(1, width: 1), read_to_acc)

      # -----------------------------------------------------------------------
      # LD (a16),A (EA) - Write A to 16-bit address
      # LD A,(a16) (FA) - Read from 16-bit address to A
      # M2: read low address, M3: read high address (ldz/ldw consolidated above), M4: read/write
      # -----------------------------------------------------------------------
      # PC increment for 0xEA/0xFA M2-M3 - covered by comprehensive inc_pc below
      set_addr_to <= mux(((ir == lit(0xEA, width: 8)) | (ir == lit(0xFA, width: 8))) & (m_cycle == lit(4, width: 3)),
                         lit(ADDR_WZ, width: 3), set_addr_to)
      write_sig <= mux((ir == lit(0xEA, width: 8)) & (m_cycle == lit(4, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux((ir == lit(0xEA, width: 8)) & (m_cycle == lit(4, width: 3)),
                     lit(1, width: 1), no_read)
      read_to_acc <= mux((ir == lit(0xFA, width: 8)) & (m_cycle == lit(4, width: 3)),
                         lit(1, width: 1), read_to_acc)

      # CB prefix - triggers CB instruction execution
      # The CB opcode is in cb_ir after M2
      # CB BIT b, r - test bit b of register r, affect Z flag only
      # For CB (HL) operations, M3 reads from (HL) address
      cb_bit <= cb_prefix & (cb_ir[7..6] == lit(1, width: 2))

      # CB (HL) - set address bus to HL during M3 for memory read
      # is_cb_hl is defined in the cycle count section above
      set_addr_to <= mux(is_cb_hl & (m_cycle == lit(3, width: 3)),
                         lit(ADDR_HL, width: 3), set_addr_to)

      # PC increment during M1 (when not halted and not in interrupt cycle)
      # Also increment during operand reads when reading from instruction stream
      # Explicit conditions for each instruction type that reads operands from PC
      inc_pc <= ((m_cycle == lit(1, width: 3)) & ~halt & ~int_cycle) |
                # LD r, n (0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E) - M2 reads immediate
                (is_ld_r_n & (m_cycle == lit(2, width: 3))) |
                # LD (HL), n (0x36) - M2 reads immediate
                ((ir == lit(0x36, width: 8)) & (m_cycle == lit(2, width: 3))) |
                # LDH (n), A (0xE0) - M2 reads offset
                ((ir == lit(0xE0, width: 8)) & (m_cycle == lit(2, width: 3))) |
                # LDH A, (n) (0xF0) - M2 reads offset
                ((ir == lit(0xF0, width: 8)) & (m_cycle == lit(2, width: 3))) |
                # LD rr, nn - M2 and M3 read 16-bit immediate
                ((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle >= lit(2, width: 3))) |
                # JP nn (0xC3) - M2 and M3 read address (not M4 which jumps)
                ((ir == lit(0xC3, width: 8)) & ((m_cycle == lit(2, width: 3)) | (m_cycle == lit(3, width: 3)))) |
                # CALL nn (0xCD) - M2 and M3 read address (not M4-M6 which push/jump)
                ((ir == lit(0xCD, width: 8)) & ((m_cycle == lit(2, width: 3)) | (m_cycle == lit(3, width: 3)))) |
                # LD (nn), A (0xEA) / LD A, (nn) (0xFA) - M2 and M3 read 16-bit address
                (((ir == lit(0xEA, width: 8)) | (ir == lit(0xFA, width: 8))) & ((m_cycle == lit(2, width: 3)) | (m_cycle == lit(3, width: 3)))) |
                # JR e (0x18) - M2 reads displacement
                ((ir == lit(0x18, width: 8)) & (m_cycle == lit(2, width: 3))) |
                # Conditional JR (0x20, 0x28, 0x30, 0x38) - M2 reads displacement
                (is_cond_jr & (m_cycle == lit(2, width: 3))) |
                # CB prefix (0xCB) - M2 reads CB opcode
                ((ir == lit(0xCB, width: 8)) & (m_cycle == lit(2, width: 3))) |
                # ALU A,n immediate ops (C6, CE, D6, DE, E6, EE, F6, FE) - M2 reads immediate
                (is_alu_imm & (m_cycle == lit(2, width: 3)))

      # -----------------------------------------------------------------------
      # ALU (Simplified)
      # 0 = ADD, 1 = ADC, 2 = SUB, 3 = SBC, 4 = AND, 5 = XOR, 6 = OR, 7 = CP
      # -----------------------------------------------------------------------

      # Result computation
      alu_result <= mux(alu_op == lit(0, width: 4), (bus_a + bus_b)[7..0],          # ADD
                   mux(alu_op == lit(1, width: 4), (bus_a + bus_b + f_reg[FLAG_C])[7..0],  # ADC
                   mux(alu_op == lit(2, width: 4), (bus_a - bus_b)[7..0],          # SUB
                   mux(alu_op == lit(3, width: 4), (bus_a - bus_b - f_reg[FLAG_C])[7..0],  # SBC
                   mux(alu_op == lit(4, width: 4), bus_a & bus_b,                  # AND
                   mux(alu_op == lit(5, width: 4), bus_a ^ bus_b,                  # XOR
                   mux(alu_op == lit(6, width: 4), bus_a | bus_b,                  # OR
                   mux(alu_op == lit(7, width: 4), (bus_a - bus_b)[7..0],          # CP (same as SUB but don't save)
                       bus_a))))))))

      # ALU flags computation using explicit bit operations to avoid Verilator cat() bug
      # Z flag (bit 7) - set if result is 0
      z_bit = mux(alu_result == lit(0, width: 8), lit(0x80, width: 8), lit(0, width: 8))
      # N flag (bit 6) - set for sub ops
      n_bit = mux((alu_op == lit(2, width: 4)) | (alu_op == lit(3, width: 4)) | (alu_op == lit(7, width: 4)),
                  lit(0x40, width: 8), lit(0, width: 8))
      # H flag (bit 5) - TODO: proper half-carry
      h_bit = lit(0, width: 8)
      # C flag (bit 4)
      c_bit = mux((alu_op == lit(0, width: 4)) | (alu_op == lit(1, width: 4)),
                  mux((bus_a + bus_b)[8], lit(0x10, width: 8), lit(0, width: 8)),
                  mux((alu_op == lit(2, width: 4)) | (alu_op == lit(3, width: 4)) | (alu_op == lit(7, width: 4)),
                      mux(bus_b > bus_a, lit(0x10, width: 8), lit(0, width: 8)),
                      lit(0, width: 8)))
      alu_flags <= (z_bit | n_bit | h_bit | c_bit)

      # -----------------------------------------------------------------------
      # Bus Muxing
      # -----------------------------------------------------------------------

      # Bus A mux (ALU operand A)
      bus_a <= mux(set_bus_a_to == lit(0, width: 4), b_reg,
               mux(set_bus_a_to == lit(1, width: 4), c_reg,
               mux(set_bus_a_to == lit(2, width: 4), d_reg,
               mux(set_bus_a_to == lit(3, width: 4), e_reg,
               mux(set_bus_a_to == lit(4, width: 4), h_reg,
               mux(set_bus_a_to == lit(5, width: 4), l_reg,
               mux(set_bus_a_to == lit(6, width: 4), di_reg,
               mux(set_bus_a_to == lit(7, width: 4), acc,
                   acc))))))))

      # Bus B mux (ALU operand B)
      # 0-7: B,C,D,E,H,L,di_reg,A  8: SP(L), 9: SP(H), 10: constant 1, 11: F
      bus_b <= mux(set_bus_b_to == lit(0, width: 4), b_reg,
               mux(set_bus_b_to == lit(1, width: 4), c_reg,
               mux(set_bus_b_to == lit(2, width: 4), d_reg,
               mux(set_bus_b_to == lit(3, width: 4), e_reg,
               mux(set_bus_b_to == lit(4, width: 4), h_reg,
               mux(set_bus_b_to == lit(5, width: 4), l_reg,
               mux(set_bus_b_to == lit(6, width: 4), di_reg,
               mux(set_bus_b_to == lit(7, width: 4), acc,
               mux(set_bus_b_to == lit(8, width: 4), sp[7..0],    # SP low byte
               mux(set_bus_b_to == lit(9, width: 4), sp[15..8],   # SP high byte
               mux(set_bus_b_to == lit(10, width: 4), lit(1, width: 8),  # Constant 1 for INC/DEC
               mux(set_bus_b_to == lit(11, width: 4), f_reg,     # Flags register
                   acc))))))))))))

      # -----------------------------------------------------------------------
      # Combinational Outputs
      # -----------------------------------------------------------------------

      # STOP instruction detection
      stop_out <= is_stop

      # Bus acknowledge (always ready in this implementation)
      busak_n <= lit(1, width: 1)

      # Refresh (not used in GB, always high)
      rfsh_n <= lit(1, width: 1)

      # Halt output
      halt_n <= ~halt_ff

      # I/O request (always inactive for now)
      iorq_n <= lit(1, width: 1)

      # Address bus mux - select based on set_addr_to and state
      # During M1, always use PC for opcode fetch
      # During LDH M3, use IO address (0xFF00 + wz[7:0])
      io_addr = cat(lit(0xFF, width: 8), wz[7..0])
      io_addr_c = cat(lit(0xFF, width: 8), c_reg)  # 0xFF00 + C register
      is_ldh_m3 = (ir == lit(0xE0, width: 8)) & (m_cycle == lit(3, width: 3)) |
                  (ir == lit(0xF0, width: 8)) & (m_cycle == lit(3, width: 3))

      # RST/CALL/PUSH stack push addresses - pre-compute for stack operations
      # RST: M3 write high byte to SP-1, M4 write low byte to SP-2
      # CALL: M4 write high byte to SP-1, M5 write low byte to SP-2
      sp_minus_1 = sp - lit(1, width: 16)
      sp_minus_2 = sp - lit(2, width: 16)
      sp_plus_1 = sp + lit(1, width: 16)
      is_rst_m3 = is_rst & (m_cycle == lit(3, width: 3))
      is_rst_m4 = is_rst & (m_cycle == lit(4, width: 3))
      is_call_m4 = call & (m_cycle == lit(4, width: 3))
      is_call_m5 = call & (m_cycle == lit(5, width: 3))
      is_ret_m2 = ret & (m_cycle == lit(2, width: 3))
      is_ret_m3 = ret & (m_cycle == lit(3, width: 3))

      addr_bus <= mux(m_cycle == lit(1, width: 3), pc,
                  mux(is_ldh_m3, io_addr,  # Direct override for LDH instructions
                  mux(is_rst_m3, sp_minus_1,  # RST M3: Write PC high to SP-1
                  mux(is_rst_m4, sp_minus_2,  # RST M4: Write PC low to SP-2
                  mux(is_call_m4, sp_minus_1, # CALL M4: Write PC high to SP-1
                  mux(is_call_m5, sp_minus_2, # CALL M5: Write PC low to SP-2
                  mux(is_ret_m2, sp,          # RET M2: Read low byte from SP
                  mux(is_ret_m3, sp_plus_1,   # RET M3: Read high byte from SP+1
                  # Address select based on set_addr_to
                  mux(set_addr_to == lit(ADDR_PC, width: 3), pc,
                  mux(set_addr_to == lit(ADDR_SP, width: 3), sp,
                  mux(set_addr_to == lit(ADDR_HL, width: 3), hl,
                  mux(set_addr_to == lit(ADDR_DE, width: 3), de,
                  mux(set_addr_to == lit(ADDR_BC, width: 3), bc,
                  mux(set_addr_to == lit(ADDR_WZ, width: 3), wz,
                  mux(set_addr_to == lit(ADDR_IO, width: 3), io_addr,
                  mux(set_addr_to == lit(ADDR_IOC, width: 3), io_addr_c,
                      pc))))))))))))))))

      # Data output (for writes) - select based on instruction
      # For LD (HL),r, use the source register from bus_b
      # For LD (HL),n, use wz[7:0] (the immediate value)
      # For RST: M3 outputs PC[15:8], M4 outputs PC[7:0]
      # For CALL: M4 outputs PC[15:8], M5 outputs PC[7:0]
      data_out <= mux(is_rst_m3, pc[15..8],  # RST M3: Push PC high byte
                  mux(is_rst_m4, pc[7..0],   # RST M4: Push PC low byte
                  mux(is_call_m4, pc[15..8], # CALL M4: Push PC high byte
                  mux(is_call_m5, pc[7..0],  # CALL M5: Push PC low byte
                  mux(is_ld_hl_r, bus_b,
                  mux((ir == lit(0x36, width: 8)) & (m_cycle == lit(3, width: 3)), wz[7..0],
                  mux(((ir == lit(0x34, width: 8)) | (ir == lit(0x35, width: 8))) & (m_cycle == lit(3, width: 3)),
                      alu_result,  # INC/DEC (HL) - write ALU result back
                      acc)))))))

      # -----------------------------------------------------------------------
      # CB BIT instruction - compute flags
      # CB BIT b, r - test bit b of register r, set Z flag if bit is 0
      # cb_ir[7:6] = 01 (BIT), cb_ir[5:3] = bit number, cb_ir[2:0] = register
      # -----------------------------------------------------------------------

      # Get the source register value for CB operations
      cb_src <= mux(cb_ir[2..0] == lit(0, width: 3), b_reg,
                mux(cb_ir[2..0] == lit(1, width: 3), c_reg,
                mux(cb_ir[2..0] == lit(2, width: 3), d_reg,
                mux(cb_ir[2..0] == lit(3, width: 3), e_reg,
                mux(cb_ir[2..0] == lit(4, width: 3), h_reg,
                mux(cb_ir[2..0] == lit(5, width: 3), l_reg,
                mux(cb_ir[2..0] == lit(6, width: 3), di_reg,  # (HL) - need memory read
                mux(cb_ir[2..0] == lit(7, width: 3), acc,
                    acc))))))))

      # Compute the bit mask based on bit number
      bit_mask <= mux(cb_ir[5..3] == lit(0, width: 3), lit(0x01, width: 8),
                  mux(cb_ir[5..3] == lit(1, width: 3), lit(0x02, width: 8),
                  mux(cb_ir[5..3] == lit(2, width: 3), lit(0x04, width: 8),
                  mux(cb_ir[5..3] == lit(3, width: 3), lit(0x08, width: 8),
                  mux(cb_ir[5..3] == lit(4, width: 3), lit(0x10, width: 8),
                  mux(cb_ir[5..3] == lit(5, width: 3), lit(0x20, width: 8),
                  mux(cb_ir[5..3] == lit(6, width: 3), lit(0x40, width: 8),
                  mux(cb_ir[5..3] == lit(7, width: 3), lit(0x80, width: 8),
                      lit(0x01, width: 8)))))))))

      # Test the specified bit - Z flag is set if bit is 0
      bit_is_zero = (cb_src & bit_mask) == lit(0, width: 8)

      # Compute flags for CB BIT: Z=result, N=0, H=1, C=unchanged
      cb_bit_flags <= cat(bit_is_zero, lit(0, width: 1), lit(1, width: 1), f_reg[FLAG_C], lit(0, width: 4))
    end

    # =========================================================================
    # Main State Machine
    # =========================================================================

    sequential clock: :clk, reset: :reset_n, reset_values: {
      # Registers - initial values for boot ROM execution
      # Boot ROM will set these to their final state (A=0x01, F=0xB0, etc.)
      # before jumping to cartridge at 0x0100
      acc: 0x00, f_reg: 0x00,
      b_reg: 0x00, c_reg: 0x00,
      d_reg: 0x00, e_reg: 0x00,
      h_reg: 0x00, l_reg: 0x00,
      sp: 0x0000, pc: 0x0000,

      # State - t_state starts at 1 (valid range is 1-4)
      ir: 0x00, wz: 0x0000,
      m_cycle: 1, t_state: 1,
      int_e_ff1: 0, int_e_ff2: 0,
      halt_ff: 0, int_cycle: 0,
      cb_prefix: 0, cb_ir: 0x00,

      # Bus control
      m1_n: 1, mreq_n: 1, rd_n: 1, wr_n: 1,
      di_reg: 0x00
    } do

      # T-state counter (1-4 on Game Boy)
      t_state <= mux(clken,
                     mux(t_state == lit(4, width: 3),
                         lit(1, width: 3),
                         t_state + lit(1, width: 3)),
                     t_state)

      # Machine cycle state machine
      m_cycle <= mux(clken & (t_state == lit(4, width: 3)),
                     mux(m_cycle == m_cycles,
                         lit(1, width: 3),  # Start new instruction
                         m_cycle + lit(1, width: 3)),  # Next machine cycle
                     m_cycle)

      # M1 indicator (low during opcode fetch)
      m1_n <= mux(clken,
                  mux(m_cycle == lit(1, width: 3), lit(0, width: 1), lit(1, width: 1)),
                  m1_n)

      # Memory request (active during T1-T3 of each cycle for both reads AND writes)
      # Note: Use < 4 instead of <= 3 because <= is the assignment operator in behavior DSL
      # Must assert for reads (~no_read) OR writes (write_sig)
      mreq_n <= mux(clken,
                    mux((t_state >= lit(1, width: 3)) & (t_state < lit(4, width: 3)) & (~no_read | write_sig),
                        lit(0, width: 1),
                        lit(1, width: 1)),
                    mreq_n)

      # Read strobe (active during T1-T3 when reading)
      rd_n <= mux(clken,
                  mux((t_state >= lit(1, width: 3)) & (t_state < lit(4, width: 3)) & ~no_read & ~write_sig,
                      lit(0, width: 1),
                      lit(1, width: 1)),
                  rd_n)

      # Write strobe (active during T2-T3 when writing)
      # Note: Using t_state < 3 (not < 4) because:
      # - Sequential blocks use pre-tick t_state to compute wr_n_new
      # - At T2: t_state_old=1, wr_n=0 (write active)
      # - At T3: t_state_old=2, wr_n=0 (write active)
      # - At T4: t_state_old=3, wr_n=1 (write INACTIVE - prevents wrong data after PC jump)
      # This is critical for CALL/RST which update PC at T3 but need correct pre-jump PC for stack push
      wr_n <= mux(clken,
                  mux((t_state >= lit(1, width: 3)) & (t_state < lit(3, width: 3)) & write_sig,
                      lit(0, width: 1),
                      lit(1, width: 1)),
                  wr_n)

      # Latch data input at T2 (data will be available for use at T3/T4)
      # Note: In synchronous simulation, we latch when t_state=2 because at the clock edge
      # t_state will advance to 3 but we use pre-edge values for the condition
      di_reg <= mux(clken & (t_state == lit(2, width: 3)),
                    data_in,
                    di_reg)

      # -----------------------------------------------------------------------
      # Instruction Register and PC Update
      # -----------------------------------------------------------------------

      # Latch instruction during M1, T2 (data will be stable, latch before T3)
      ir <= mux(clken & (m_cycle == lit(1, width: 3)) & (t_state == lit(2, width: 3)),
                mux(halt_ff, lit(0x00, width: 8), data_in),  # NOP if halted
                ir)

      # Increment PC at end of T3 (pre-edge timing), or jump to target address
      # For relative jumps (JR), sign-extend the 8-bit displacement and add to PC
      disp_sign_ext = mux(wz[7], lit(0xFF, width: 8), lit(0, width: 8))  # Sign extension
      pc_rel = pc + cat(disp_sign_ext, wz[7..0])  # PC + signed displacement

      pc <= mux(clken & (t_state == lit(3, width: 3)) & inc_pc,
                pc + lit(1, width: 16),
                mux(clken & jump & (m_cycle == m_cycles) & (t_state == lit(3, width: 3)),
                    wz,  # Jump address stored in WZ (loaded during M2/M3)
                mux(clken & jump_e & (m_cycle == m_cycles) & (t_state == lit(3, width: 3)),
                    pc_rel,  # Relative jump: PC + signed displacement
                mux(clken & call & (m_cycle == m_cycles) & (t_state == lit(3, width: 3)),
                    wz,  # CALL: jump to address stored in WZ
                mux(clken & ret & (m_cycle == lit(4, width: 3)) & (t_state == lit(3, width: 3)),
                    wz,  # RET: jump to address popped from stack (stored in WZ)
                mux(clken & is_rst & (m_cycle == lit(4, width: 3)) & (t_state == lit(3, width: 3)),
                    cat(lit(0, width: 8), rst_addr),  # RST jump address: 0x00nn
                    pc))))))

      # -----------------------------------------------------------------------
      # Temporary Address Register (WZ)
      # -----------------------------------------------------------------------

      # Load low byte at T3 (when clken=1, t_state is still 3 pre-edge)
      wz <= mux(clken & ldz & (t_state == lit(3, width: 3)),
                cat(wz[15..8], di_reg),
                mux(clken & ldw & (t_state == lit(3, width: 3)),
                    cat(di_reg, wz[7..0]),
                    wz))

      # -----------------------------------------------------------------------
      # Register Updates
      # -----------------------------------------------------------------------

      # NOTE: Accumulator combined update is at the end of the sequential block,
      # after all its dependencies (rot_result, reg_write_data) are defined.

      # Flags - update at T3 (pre-edge timing)
      # Combined update for all flag-modifying instructions to avoid multiple assignment override
      # CB BIT (HL) updates flags at M3/T3 (after memory read)
      # CB BIT with register updates flags at M2/T3
      is_cb_bit = cb_prefix & (cb_ir[7..6] == lit(1, width: 2))
      is_cb_bit_hl_local = is_cb_bit & (cb_ir[2..0] == lit(6, width: 3))
      is_cb_bit_reg = is_cb_bit & (cb_ir[2..0] != lit(6, width: 3))
      # Combined flag update condition: M2/T3 for register, M3/T3 for (HL)
      is_cb_bit_update = (is_cb_bit_reg & (m_cycle == lit(2, width: 3))) |
                         (is_cb_bit_hl_local & (m_cycle == lit(3, width: 3)))

      # Pre-compute rotate flags: Z=0, N=0, H=0, C=rot_carry (computed later in behavior block)
      # Note: rot_carry needs to be computed before this, so we inline it here
      rot_carry_local = mux(ir == lit(0x07, width: 8), acc[7],
                        mux(ir == lit(0x17, width: 8), acc[7],
                        mux(ir == lit(0x0F, width: 8), acc[0],
                        mux(ir == lit(0x1F, width: 8), acc[0],
                            f_reg[FLAG_C]))))
      rot_flags_local = cat(lit(0, width: 3), rot_carry_local, lit(0, width: 4))

      # CPL flags: N=1, H=1, Z and C preserved
      cpl_flags_local = cat(f_reg[FLAG_Z], lit(1, width: 1), lit(1, width: 1), f_reg[FLAG_C], lit(0, width: 4))

      # CCF flags: N=0, H=prev_C, C=~C, Z unchanged
      ccf_flags_local = cat(f_reg[FLAG_Z], lit(0, width: 1), f_reg[FLAG_C], ~f_reg[FLAG_C], lit(0, width: 4))

      # SCF flags: N=0, H=0, C=1, Z unchanged
      scf_flags_local = cat(f_reg[FLAG_Z], lit(0, width: 1), lit(0, width: 1), lit(1, width: 1), lit(0, width: 4))

      # Combined f_reg update - all conditions in priority order
      f_reg <= mux(clken & save_alu & (t_state == lit(3, width: 3)),
                   alu_flags,
               mux(clken & is_cb_bit_update & (t_state == lit(3, width: 3)),
                   cb_bit_flags,  # CB BIT updates flags at M2/T3 (reg) or M3/T3 (HL)
               mux(clken & rot_akku & (t_state == lit(3, width: 3)),
                   rot_flags_local,  # RLCA/RLA/RRCA/RRA
               mux(clken & cpl_op & (t_state == lit(3, width: 3)),
                   cpl_flags_local,  # CPL
               mux(clken & ccf_op & (t_state == lit(3, width: 3)),
                   ccf_flags_local,  # CCF
               mux(clken & scf_op & (t_state == lit(3, width: 3)),
                   scf_flags_local,  # SCF
                   f_reg))))))

      # -----------------------------------------------------------------------
      # Register Pair Updates from WZ (for LD rr,nn instructions)
      # -----------------------------------------------------------------------

      # Stack pointer update is handled later (line ~1170) with all SP-modifying instructions combined
      # This includes: LD SP,nn (load_sp_wz), INC/DEC SP, and LD SP,HL

      # BC and DE register pair updates are handled later with all conditions combined
      # (includes load_bc_wz, load_de_wz, read_to_reg, INC/DEC BC/DE)

      # HL register pair updates are handled later (line ~1161) with all conditions combined
      # This includes: LD HL,nn (load_hl_wz), INC/DEC HL, LDI/LDD (inc_hl/dec_hl), LD H/L,r
      hl_new = cat(h_reg, l_reg)
      hl_inc = hl_new + lit(1, width: 16)
      hl_dec = hl_new - lit(1, width: 16)

      # -----------------------------------------------------------------------
      # Register Updates for LD r,r' and LD r,n (read_to_reg signal)
      # -----------------------------------------------------------------------
      # Note: Accumulator handled separately above
      # For LD r,r', data comes from bus_b; for LD r,n, data comes from di_reg
      reg_write_data = mux(is_ld_r_n | is_ld_r_hl, di_reg, bus_b)

      # B, C, D, E, H, L register updates are handled later with all conditions combined
      # (includes read_to_reg for LD r,r' / LD r,n / INC r / DEC r)
      # NOTE: Accumulator update for LD A,r is now in the combined acc <= statement above

      # -----------------------------------------------------------------------
      # Rotate Accumulator Instructions (RLCA, RLA, RRCA, RRA)
      # -----------------------------------------------------------------------
      # RLCA (07): A = (A << 1) | (A >> 7), C = A[7]
      # RLA  (17): A = (A << 1) | C, C = A[7]
      # RRCA (0F): A = (A >> 1) | (A[0] << 7), C = A[0]
      # RRA  (1F): A = (A >> 1) | (C << 7), C = A[0]
      rlca_result = cat(acc[6..0], acc[7])
      rla_result = cat(acc[6..0], f_reg[FLAG_C])
      rrca_result = cat(acc[0], acc[7..1])
      rra_result = cat(f_reg[FLAG_C], acc[7..1])

      rot_result = mux(ir == lit(0x07, width: 8), rlca_result,
                   mux(ir == lit(0x17, width: 8), rla_result,
                   mux(ir == lit(0x0F, width: 8), rrca_result,
                   mux(ir == lit(0x1F, width: 8), rra_result,
                       acc))))

      rot_carry = mux(ir == lit(0x07, width: 8), acc[7],
                  mux(ir == lit(0x17, width: 8), acc[7],
                  mux(ir == lit(0x0F, width: 8), acc[0],
                  mux(ir == lit(0x1F, width: 8), acc[0],
                      f_reg[FLAG_C]))))

      # NOTE: acc update for rotate is now in the combined acc <= statement above
      # Rotate flags are now handled in the combined f_reg update above

      # -----------------------------------------------------------------------
      # CPL - Complement A (2F)
      # -----------------------------------------------------------------------
      # NOTE: acc update for CPL is now in the combined acc <= statement above
      # CPL flags are now handled in the combined f_reg update above

      # CCF and SCF flags are now handled in the combined f_reg update above

      # -----------------------------------------------------------------------
      # INC/DEC 16-bit Register Pairs
      # incdec_16[3:2] = direction (00=inc, 10=dec)
      # incdec_16[1:0] = pair (00=BC, 01=DE, 10=HL, 11=SP)
      # -----------------------------------------------------------------------
      is_incdec_bc = (incdec_16[1..0] == lit(0, width: 2)) & (incdec_16 != lit(0, width: 4))
      is_incdec_de = (incdec_16[1..0] == lit(1, width: 2)) & (incdec_16 != lit(0, width: 4))
      is_incdec_hl = (incdec_16[1..0] == lit(2, width: 2)) & (incdec_16 != lit(0, width: 4))
      is_incdec_sp = (incdec_16[1..0] == lit(3, width: 2)) & (incdec_16 != lit(0, width: 4))
      is_dec_16 = incdec_16[3]

      bc_16 = cat(b_reg, c_reg)
      de_16 = cat(d_reg, e_reg)
      hl_16 = cat(h_reg, l_reg)

      bc_16_new = mux(is_dec_16, bc_16 - lit(1, width: 16), bc_16 + lit(1, width: 16))
      de_16_new = mux(is_dec_16, de_16 - lit(1, width: 16), de_16 + lit(1, width: 16))
      hl_16_new = mux(is_dec_16, hl_16 - lit(1, width: 16), hl_16 + lit(1, width: 16))
      sp_16_new = mux(is_dec_16, sp - lit(1, width: 16), sp + lit(1, width: 16))

      # B register combined update
      b_reg <= mux(clken & load_bc_wz & (t_state == lit(3, width: 3)),
                   di_reg,  # LD BC,nn - high byte from di_reg
               mux(clken & is_incdec_bc & (t_state == lit(3, width: 3)),
                   bc_16_new[15..8],  # INC/DEC BC
               mux(clken & read_to_reg & (write_reg == lit(0, width: 3)) & (t_state == lit(3, width: 3)),
                   mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD B,r / INC B / DEC B
                   b_reg)))
      # C register combined update
      c_reg <= mux(clken & load_bc_wz & (t_state == lit(3, width: 3)),
                   wz[7..0],  # LD BC,nn - low byte from WZ
               mux(clken & is_incdec_bc & (t_state == lit(3, width: 3)),
                   bc_16_new[7..0],  # INC/DEC BC
               mux(clken & read_to_reg & (write_reg == lit(1, width: 3)) & (t_state == lit(3, width: 3)),
                   mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD C,r / INC C / DEC C
                   c_reg)))
      # D register combined update
      d_reg <= mux(clken & load_de_wz & (t_state == lit(3, width: 3)),
                   di_reg,  # LD DE,nn - high byte from di_reg
               mux(clken & is_incdec_de & (t_state == lit(3, width: 3)),
                   de_16_new[15..8],  # INC/DEC DE
               mux(clken & read_to_reg & (write_reg == lit(2, width: 3)) & (t_state == lit(3, width: 3)),
                   mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD D,r / INC D / DEC D
                   d_reg)))
      # E register combined update
      e_reg <= mux(clken & load_de_wz & (t_state == lit(3, width: 3)),
                   wz[7..0],  # LD DE,nn - low byte from WZ
               mux(clken & is_incdec_de & (t_state == lit(3, width: 3)),
                   de_16_new[7..0],  # INC/DEC DE
               mux(clken & read_to_reg & (write_reg == lit(3, width: 3)) & (t_state == lit(3, width: 3)),
                   mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD E,r / INC E / DEC E
                   e_reg)))
      # H register combined update - all H-modifying instructions:
      # Priority: 1. LD HL,nn, 2. LDI/LDD, 3. INC/DEC HL, 4. LD H,r/INC H/DEC H
      h_reg <= mux(clken & load_hl_wz & (t_state == lit(3, width: 3)),
                   di_reg,  # LD HL,nn - high byte from di_reg
               mux(clken & inc_hl & (t_state == lit(3, width: 3)),
                   hl_inc[15..8],  # LDI - increment HL
               mux(clken & dec_hl & (t_state == lit(3, width: 3)),
                   hl_dec[15..8],  # LDD - decrement HL
               mux(clken & is_incdec_hl & (t_state == lit(3, width: 3)),
                   hl_16_new[15..8],  # INC/DEC HL
               mux(clken & read_to_reg & (write_reg == lit(4, width: 3)) & (t_state == lit(3, width: 3)),
                   mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD H,r / INC H / DEC H
                   h_reg)))))
      # L register combined update
      l_reg <= mux(clken & load_hl_wz & (t_state == lit(3, width: 3)),
                   wz[7..0],  # LD HL,nn - low byte from WZ
               mux(clken & inc_hl & (t_state == lit(3, width: 3)),
                   hl_inc[7..0],  # LDI - increment HL
               mux(clken & dec_hl & (t_state == lit(3, width: 3)),
                   hl_dec[7..0],  # LDD - decrement HL
               mux(clken & is_incdec_hl & (t_state == lit(3, width: 3)),
                   hl_16_new[7..0],  # INC/DEC HL
               mux(clken & read_to_reg & (write_reg == lit(5, width: 3)) & (t_state == lit(3, width: 3)),
                   mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD L,r / INC L / DEC L
                   l_reg)))))
      # SP combined update - all SP-modifying instructions:
      # 1. LD SP,nn (load_sp_wz) - highest priority
      # 2. LD SP,HL (ld_sp_hl)
      # 3. INC/DEC SP (is_incdec_sp)
      # 4. RST (decrement by 2 at end of M4)
      # 5. CALL (decrement by 2 at end of M5)
      # 6. RET (increment by 2 at end of M4)
      # 7. PUSH (decrement by 2 at end of M4)
      # 8. POP (increment by 2 at end of M3)
      sp <= mux(clken & load_sp_wz & (t_state == lit(3, width: 3)),
                cat(di_reg, wz[7..0]),  # LD SP,nn
            mux(clken & ld_sp_hl & (m_cycle == lit(2, width: 3)) & (t_state == lit(3, width: 3)),
                cat(h_reg, l_reg),      # LD SP,HL
            mux(clken & is_incdec_sp & (t_state == lit(3, width: 3)),
                sp_16_new,              # INC/DEC SP
            mux(clken & is_rst & (m_cycle == lit(4, width: 3)) & (t_state == lit(3, width: 3)),
                sp - lit(2, width: 16), # RST: decrement SP by 2
            mux(clken & call & (m_cycle == lit(5, width: 3)) & (t_state == lit(3, width: 3)),
                sp - lit(2, width: 16), # CALL: decrement SP by 2
            mux(clken & ret & (m_cycle == lit(4, width: 3)) & (t_state == lit(3, width: 3)),
                sp + lit(2, width: 16), # RET: increment SP by 2
            mux(clken & push_op & (m_cycle == lit(4, width: 3)) & (t_state == lit(3, width: 3)),
                sp - lit(2, width: 16), # PUSH: decrement SP by 2
            mux(clken & pop_op & (m_cycle == lit(3, width: 3)) & (t_state == lit(3, width: 3)),
                sp + lit(2, width: 16), # POP: increment SP by 2
                sp))))))))

      # -----------------------------------------------------------------------
      # CB Prefix Handling
      # -----------------------------------------------------------------------

      # Latch CB prefix flag when ir == 0xCB and instruction starts
      # Clear timing depends on operand:
      # - Register operand (cb_ir[2:0] != 6): clear at M2/T3
      # - (HL) operand BIT: clear at M3/T3 (after memory read)
      # - (HL) operand rot/set/res: clear at M4/T3 (after memory write)
      cb_is_hl = (cb_ir[2..0] == lit(6, width: 3))
      cb_is_bit = (cb_ir[7..6] == lit(1, width: 2))
      cb_clear_m2 = cb_prefix & (m_cycle == lit(2, width: 3)) & ~cb_is_hl
      cb_clear_m3 = cb_prefix & (m_cycle == lit(3, width: 3)) & cb_is_hl & cb_is_bit
      cb_clear_m4 = cb_prefix & (m_cycle == lit(4, width: 3)) & cb_is_hl & ~cb_is_bit

      cb_prefix <= mux(clken & (ir == lit(0xCB, width: 8)) & (m_cycle == lit(1, width: 3)) & (t_state == lit(3, width: 3)),
                       lit(1, width: 1),
                       mux(clken & (cb_clear_m2 | cb_clear_m3 | cb_clear_m4) & (t_state == lit(3, width: 3)),
                           lit(0, width: 1),
                           cb_prefix))

      # Latch CB opcode from data_in during M2/T2
      cb_ir <= mux(clken & (ir == lit(0xCB, width: 8)) & (m_cycle == lit(2, width: 3)) & (t_state == lit(2, width: 3)),
                   data_in,  # Latch CB opcode
                   cb_ir)

      # -----------------------------------------------------------------------
      # Interrupt Enable
      # -----------------------------------------------------------------------

      int_e_ff1 <= mux(clken & set_ei & (t_state == lit(3, width: 3)),
                       lit(1, width: 1),
                       mux(clken & set_di & (t_state == lit(3, width: 3)),
                           lit(0, width: 1),
                           int_e_ff1))

      int_e_ff2 <= mux(clken & set_ei & (t_state == lit(3, width: 3)),
                       lit(1, width: 1),
                       mux(clken & set_di & (t_state == lit(3, width: 3)),
                           lit(0, width: 1),
                           int_e_ff2))

      # -----------------------------------------------------------------------
      # Halt
      # -----------------------------------------------------------------------

      halt_ff <= mux(clken & halt & (t_state == lit(3, width: 3)),
                     lit(1, width: 1),
                     mux(int_cycle | (int_n == lit(0, width: 1)),
                         lit(0, width: 1),  # Exit halt on interrupt
                         halt_ff))

      # -----------------------------------------------------------------------
      # Accumulator - Combined update at T3
      # -----------------------------------------------------------------------
      # All accumulator-modifying conditions in priority order:
      # 1. save_alu - ALU operations (ADD, SUB, AND, OR, XOR, INC, DEC) except CP
      # 2. read_to_acc - Load from memory (LD A,(nn), LD A,(BC), etc.)
      # 3. read_to_reg with write_reg==7 - LD A,r / INC A / DEC A
      # 4. rot_akku - Rotate accumulator (RLCA/RLA/RRCA/RRA)
      # 5. cpl_op - Complement A
      # Note: CP (alu_op==7) tests but doesn't store result
      acc <= mux(clken & save_alu & (t_state == lit(3, width: 3)) & (alu_op != lit(7, width: 4)),
                 alu_result,  # Save ALU result (ADD/SUB/AND/OR/XOR/INC/DEC, but not CP)
             mux(clken & read_to_acc & (t_state == lit(3, width: 3)),
                 di_reg,  # Load from memory
             mux(clken & read_to_reg & (write_reg == lit(7, width: 3)) & (t_state == lit(3, width: 3)),
                 mux(is_inc_r | is_dec_r, alu_result, reg_write_data),  # LD A,r / INC A / DEC A
             mux(clken & rot_akku & (t_state == lit(3, width: 3)),
                 rot_result,  # RLCA/RLA/RRCA/RRA
             mux(clken & cpl_op & (t_state == lit(3, width: 3)),
                 ~acc,  # CPL
                 acc)))))

    end

  end
end
