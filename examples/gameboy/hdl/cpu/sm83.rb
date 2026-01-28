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

    # ALU signals
    wire :bus_a, width: 8       # ALU operand A
    wire :bus_b, width: 8       # ALU operand B
    wire :alu_result, width: 8  # ALU result
    wire :alu_flags, width: 8   # ALU flag output

    # =========================================================================
    # Register Pair Composition
    # =========================================================================

    behavior do
      bc <= cat(b_reg, c_reg)
      de <= cat(d_reg, e_reg)
      hl <= cat(h_reg, l_reg)
    end

    # =========================================================================
    # Instruction Decoder (Microcode)
    # =========================================================================

    behavior do
      # Default values
      m_cycles <= lit(1, width: 3)
      inc_pc <= lit(0, width: 1)
      read_to_acc <= lit(0, width: 1)
      set_bus_a_to <= lit(7, width: 4)  # ACC
      set_bus_b_to <= lit(7, width: 4)  # ACC
      alu_op <= lit(0, width: 4)
      save_alu <= lit(0, width: 1)
      set_addr_to <= lit(0, width: 3)   # PC
      no_read <= lit(0, width: 1)
      write_sig <= lit(0, width: 1)
      ldz <= lit(0, width: 1)
      ldw <= lit(0, width: 1)
      jump <= lit(0, width: 1)
      jump_e <= lit(0, width: 1)
      call <= lit(0, width: 1)
      ret <= lit(0, width: 1)
      halt <= lit(0, width: 1)
      set_di <= lit(0, width: 1)
      set_ei <= lit(0, width: 1)
      is_stop <= lit(0, width: 1)
      prefix <= lit(0, width: 2)

      # Opcode decoding for normal instruction set (prefix = 00)
      # Pattern match on opcode bits

      # -----------------------------------------------------------------------
      # 0x00: NOP - 1 cycle
      # -----------------------------------------------------------------------
      # Default is 1 cycle, no operation

      # -----------------------------------------------------------------------
      # 0x01, 0x11, 0x21, 0x31: LD rr,nn - 3 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)),
                      lit(3, width: 3),
                      m_cycles)
      ldz <= mux((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)
      ldw <= mux((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle == lit(3, width: 3)),
                 lit(1, width: 1), ldw)

      # -----------------------------------------------------------------------
      # 0x02, 0x12: LD (BC/DE),A - 2 cycles
      # 0x0A, 0x1A: LD A,(BC/DE) - 2 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(((ir == lit(0x02, width: 8)) | (ir == lit(0x12, width: 8)) |
                       (ir == lit(0x0A, width: 8)) | (ir == lit(0x1A, width: 8))),
                      lit(2, width: 3), m_cycles)

      # Write to memory for LD (BC/DE),A
      write_sig <= mux(((ir == lit(0x02, width: 8)) | (ir == lit(0x12, width: 8))) &
                       (m_cycle == lit(2, width: 3)),
                       lit(1, width: 1), write_sig)
      no_read <= mux(((ir == lit(0x02, width: 8)) | (ir == lit(0x12, width: 8))) &
                      (m_cycle == lit(2, width: 3)),
                      lit(1, width: 1), no_read)

      # Read from memory for LD A,(BC/DE)
      read_to_acc <= mux(((ir == lit(0x0A, width: 8)) | (ir == lit(0x1A, width: 8))) &
                          (m_cycle == lit(2, width: 3)),
                          lit(1, width: 1), read_to_acc)

      # Address source for BC/DE indirect
      set_addr_to <= mux((ir == lit(0x02, width: 8)) | (ir == lit(0x0A, width: 8)),
                         lit(ADDR_BC, width: 3),
                         mux((ir == lit(0x12, width: 8)) | (ir == lit(0x1A, width: 8)),
                             lit(ADDR_DE, width: 3),
                             set_addr_to))

      # -----------------------------------------------------------------------
      # 0x03, 0x13, 0x23, 0x33: INC rr - 2 cycles
      # 0x0B, 0x1B, 0x2B, 0x3B: DEC rr - 2 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(((ir[3..0] == lit(3, width: 4)) | (ir[3..0] == lit(0xB, width: 4))) &
                      (ir[7..6] == lit(0, width: 2)),
                      lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x3C: INC r - 1 cycle
      # 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x3D: DEC r - 1 cycle
      # (0x34, 0x35: INC/DEC (HL) - 3 cycles - handled separately)
      # -----------------------------------------------------------------------
      # Single cycle for register inc/dec (not (HL))

      # -----------------------------------------------------------------------
      # 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E: LD r,n - 2 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir[2..0] == lit(6, width: 3)) & (ir[7..6] == lit(0, width: 2)),
                      lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0x18: JR e - 3 cycles
      # 0x20, 0x28, 0x30, 0x38: JR cc,e - 2/3 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(ir == lit(0x18, width: 8),
                      lit(3, width: 3), m_cycles)
      m_cycles <= mux((ir[7..5] == lit(1, width: 3)) & (ir[2..0] == lit(0, width: 3)),
                      lit(3, width: 3), m_cycles)  # May reduce to 2 if not taken
      jump_e <= mux(ir == lit(0x18, width: 8), lit(1, width: 1), jump_e)
      ldz <= mux((ir == lit(0x18, width: 8)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)

      # -----------------------------------------------------------------------
      # 0x22: LD (HL+),A - 2 cycles
      # 0x2A: LD A,(HL+) - 2 cycles
      # 0x32: LD (HL-),A - 2 cycles
      # 0x3A: LD A,(HL-) - 2 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir == lit(0x22, width: 8)) | (ir == lit(0x2A, width: 8)) |
                      (ir == lit(0x32, width: 8)) | (ir == lit(0x3A, width: 8)),
                      lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0x40-0x7F: LD r,r' (except 0x76 = HALT) - 1 cycle (2 for (HL))
      # -----------------------------------------------------------------------
      # Most are 1 cycle, (HL) source/dest adds 1 cycle
      m_cycles <= mux((ir[7..6] == lit(1, width: 2)) & (ir != lit(0x76, width: 8)) &
                      ((ir[2..0] == lit(6, width: 3)) | (ir[5..3] == lit(6, width: 3))),
                      lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0x76: HALT - 1 cycle
      # -----------------------------------------------------------------------
      halt <= (ir == lit(0x76, width: 8))

      # -----------------------------------------------------------------------
      # 0x80-0xBF: ALU A,r - 1 cycle (2 for (HL))
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir[7..6] == lit(2, width: 2)) & (ir[2..0] == lit(6, width: 3)),
                      lit(2, width: 3), m_cycles)
      alu_op <= mux(ir[7..6] == lit(2, width: 2), ir[5..3], alu_op)
      save_alu <= mux(ir[7..6] == lit(2, width: 2), lit(1, width: 1), save_alu)
      set_bus_a_to <= mux(ir[7..6] == lit(2, width: 2), lit(7, width: 4), set_bus_a_to) # ACC
      set_bus_b_to <= mux(ir[7..6] == lit(2, width: 2), cat(lit(0, width: 1), ir[2..0]), set_bus_b_to)

      # -----------------------------------------------------------------------
      # 0xC0-0xC8, 0xD0-0xD8: RET cc / RET - 2-5 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir == lit(0xC9, width: 8)), lit(4, width: 3), m_cycles) # RET
      ret <= mux(ir == lit(0xC9, width: 8), lit(1, width: 1), ret)

      # -----------------------------------------------------------------------
      # 0xC3: JP nn - 4 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(ir == lit(0xC3, width: 8), lit(4, width: 3), m_cycles)
      jump <= mux(ir == lit(0xC3, width: 8), lit(1, width: 1), jump)
      ldz <= mux((ir == lit(0xC3, width: 8)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)
      ldw <= mux((ir == lit(0xC3, width: 8)) & (m_cycle == lit(3, width: 3)),
                 lit(1, width: 1), ldw)

      # -----------------------------------------------------------------------
      # 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE: ALU A,n - 2 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir[7..6] == lit(3, width: 2)) & (ir[2..0] == lit(6, width: 3)),
                      lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xCB: CB prefix - 2+ cycles
      # -----------------------------------------------------------------------
      prefix <= mux(ir == lit(0xCB, width: 8), lit(1, width: 2), prefix)
      m_cycles <= mux(ir == lit(0xCB, width: 8), lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xCD: CALL nn - 6 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(ir == lit(0xCD, width: 8), lit(6, width: 3), m_cycles)
      call <= mux(ir == lit(0xCD, width: 8), lit(1, width: 1), call)
      ldz <= mux((ir == lit(0xCD, width: 8)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)
      ldw <= mux((ir == lit(0xCD, width: 8)) & (m_cycle == lit(3, width: 3)),
                 lit(1, width: 1), ldw)

      # -----------------------------------------------------------------------
      # 0xE0: LDH (n),A - 3 cycles (write to 0xFF00+n)
      # 0xF0: LDH A,(n) - 3 cycles (read from 0xFF00+n)
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir == lit(0xE0, width: 8)) | (ir == lit(0xF0, width: 8)),
                      lit(3, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xE2: LD (C),A - 2 cycles (write to 0xFF00+C)
      # 0xF2: LD A,(C) - 2 cycles (read from 0xFF00+C)
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir == lit(0xE2, width: 8)) | (ir == lit(0xF2, width: 8)),
                      lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xE8: ADD SP,n - 4 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(ir == lit(0xE8, width: 8), lit(4, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xE9: JP (HL) - 1 cycle
      # -----------------------------------------------------------------------
      jump <= mux(ir == lit(0xE9, width: 8), lit(1, width: 1), jump)
      set_addr_to <= mux(ir == lit(0xE9, width: 8), lit(ADDR_HL, width: 3), set_addr_to)

      # -----------------------------------------------------------------------
      # 0xEA: LD (nn),A - 4 cycles
      # 0xFA: LD A,(nn) - 4 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux((ir == lit(0xEA, width: 8)) | (ir == lit(0xFA, width: 8)),
                      lit(4, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xF3: DI - 1 cycle
      # -----------------------------------------------------------------------
      set_di <= (ir == lit(0xF3, width: 8))

      # -----------------------------------------------------------------------
      # 0xF8: LD HL,SP+n - 3 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(ir == lit(0xF8, width: 8), lit(3, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xF9: LD SP,HL - 2 cycles
      # -----------------------------------------------------------------------
      m_cycles <= mux(ir == lit(0xF9, width: 8), lit(2, width: 3), m_cycles)

      # -----------------------------------------------------------------------
      # 0xFB: EI - 1 cycle
      # -----------------------------------------------------------------------
      set_ei <= (ir == lit(0xFB, width: 8))

      # -----------------------------------------------------------------------
      # 0x10: STOP - 1 cycle
      # -----------------------------------------------------------------------
      is_stop <= (ir == lit(0x10, width: 8))

      # -----------------------------------------------------------------------
      # PC increment during M1
      # -----------------------------------------------------------------------
      inc_pc <= (m_cycle == lit(1, width: 3)) & ~halt & ~int_cycle

    end

    # =========================================================================
    # ALU (Simplified)
    # =========================================================================

    behavior do
      # ALU operation decode
      # 0 = ADD, 1 = ADC, 2 = SUB, 3 = SBC, 4 = AND, 5 = XOR, 6 = OR, 7 = CP

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

      # Zero flag - set if result is 0
      alu_flags <= cat(
        (alu_result == lit(0, width: 8)),  # Z flag (bit 7)
        mux((alu_op == lit(2, width: 4)) | (alu_op == lit(3, width: 4)) | (alu_op == lit(7, width: 4)),
            lit(1, width: 1), lit(0, width: 1)),  # N flag (bit 6) - set for sub ops
        lit(0, width: 1),  # H flag (bit 5) - TODO: proper half-carry
        mux((alu_op == lit(0, width: 4)) | (alu_op == lit(1, width: 4)),
            (bus_a + bus_b)[8],  # C flag for ADD
            mux((alu_op == lit(2, width: 4)) | (alu_op == lit(3, width: 4)) | (alu_op == lit(7, width: 4)),
                (bus_b > bus_a),  # C flag for SUB (borrow)
                lit(0, width: 1))),  # C flag (bit 4)
        lit(0, width: 4)  # bits 3-0 always 0
      )
    end

    # =========================================================================
    # Bus Muxing
    # =========================================================================

    behavior do
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
      bus_b <= mux(set_bus_b_to == lit(0, width: 4), b_reg,
               mux(set_bus_b_to == lit(1, width: 4), c_reg,
               mux(set_bus_b_to == lit(2, width: 4), d_reg,
               mux(set_bus_b_to == lit(3, width: 4), e_reg,
               mux(set_bus_b_to == lit(4, width: 4), h_reg,
               mux(set_bus_b_to == lit(5, width: 4), l_reg,
               mux(set_bus_b_to == lit(6, width: 4), di_reg,
               mux(set_bus_b_to == lit(7, width: 4), acc,
                   acc))))))))
    end

    # =========================================================================
    # Combinational Outputs
    # =========================================================================

    behavior do
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
      addr_bus <= mux(m_cycle == lit(1, width: 3), pc,
                  mux(set_addr_to == lit(ADDR_PC, width: 3), pc,
                  mux(set_addr_to == lit(ADDR_SP, width: 3), sp,
                  mux(set_addr_to == lit(ADDR_HL, width: 3), hl,
                  mux(set_addr_to == lit(ADDR_DE, width: 3), de,
                  mux(set_addr_to == lit(ADDR_BC, width: 3), bc,
                  mux(set_addr_to == lit(ADDR_WZ, width: 3), wz,
                      pc)))))))

      # Data output (for writes)
      data_out <= acc
    end

    # =========================================================================
    # Main State Machine
    # =========================================================================

    sequential clock: :clk, reset: :reset_n, reset_values: {
      # Registers - post-boot ROM values for DMG
      acc: 0x01, f_reg: 0xB0,
      b_reg: 0x00, c_reg: 0x13,
      d_reg: 0x00, e_reg: 0xD8,
      h_reg: 0x01, l_reg: 0x4D,
      sp: 0xFFFE, pc: 0x0100,

      # State
      ir: 0x00, wz: 0x0000,
      m_cycle: 1, t_state: 0,
      int_e_ff1: 0, int_e_ff2: 0,
      halt_ff: 0, int_cycle: 0,

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

      # Memory request (active during T1-T3 of each cycle)
      # Note: Use < 4 instead of <= 3 because <= is the assignment operator in behavior DSL
      mreq_n <= mux(clken,
                    mux((t_state >= lit(1, width: 3)) & (t_state < lit(4, width: 3)) & ~no_read,
                        lit(0, width: 1),
                        lit(1, width: 1)),
                    mreq_n)

      # Read strobe (active during T1-T3 when reading)
      rd_n <= mux(clken,
                  mux((t_state >= lit(1, width: 3)) & (t_state < lit(4, width: 3)) & ~no_read & ~write_sig,
                      lit(0, width: 1),
                      lit(1, width: 1)),
                  rd_n)

      # Write strobe (active during T1-T3 when writing)
      wr_n <= mux(clken,
                  mux((t_state >= lit(1, width: 3)) & (t_state < lit(4, width: 3)) & write_sig,
                      lit(0, width: 1),
                      lit(1, width: 1)),
                  wr_n)

      # Latch data input at T3
      di_reg <= mux(clken & (t_state == lit(3, width: 3)) & (wait_n == lit(1, width: 1)),
                    data_in,
                    di_reg)

      # -----------------------------------------------------------------------
      # Instruction Register and PC Update
      # -----------------------------------------------------------------------

      # Latch instruction during M1, T3 (when data is stable)
      ir <= mux(clken & (m_cycle == lit(1, width: 3)) & (t_state == lit(3, width: 3)),
                mux(halt_ff, lit(0x00, width: 8), data_in),  # NOP if halted
                ir)

      # Increment PC at end of M1 (T4) for fetch, or at end of M2+ when reading operands
      pc <= mux(clken & (t_state == lit(4, width: 3)) & inc_pc,
                pc + lit(1, width: 16),
                mux(clken & jump & (m_cycle == m_cycles) & (t_state == lit(4, width: 3)),
                    wz,  # Jump to address in WZ
                    pc))

      # -----------------------------------------------------------------------
      # Temporary Address Register (WZ)
      # -----------------------------------------------------------------------

      # Load low byte
      wz <= mux(clken & ldz & (t_state == lit(4, width: 3)),
                cat(wz[15..8], di_reg),
                mux(clken & ldw & (t_state == lit(4, width: 3)),
                    cat(di_reg, wz[7..0]),
                    wz))

      # -----------------------------------------------------------------------
      # Register Updates
      # -----------------------------------------------------------------------

      # Accumulator
      acc <= mux(clken & save_alu & (t_state == lit(4, width: 3)) & (alu_op != lit(7, width: 4)),
                 alu_result,  # Save ALU result (except for CP)
                 mux(clken & read_to_acc & (t_state == lit(4, width: 3)),
                     di_reg,  # Load from memory
                     acc))

      # Flags
      f_reg <= mux(clken & save_alu & (t_state == lit(4, width: 3)),
                   alu_flags,
                   f_reg)

      # -----------------------------------------------------------------------
      # Interrupt Enable
      # -----------------------------------------------------------------------

      int_e_ff1 <= mux(clken & set_ei & (t_state == lit(4, width: 3)),
                       lit(1, width: 1),
                       mux(clken & set_di & (t_state == lit(4, width: 3)),
                           lit(0, width: 1),
                           int_e_ff1))

      int_e_ff2 <= mux(clken & set_ei & (t_state == lit(4, width: 3)),
                       lit(1, width: 1),
                       mux(clken & set_di & (t_state == lit(4, width: 3)),
                           lit(0, width: 1),
                           int_e_ff2))

      # -----------------------------------------------------------------------
      # Halt
      # -----------------------------------------------------------------------

      halt_ff <= mux(clken & halt & (t_state == lit(4, width: 3)),
                     lit(1, width: 1),
                     mux(int_cycle | (int_n == lit(0, width: 1)),
                         lit(0, width: 1),  # Exit halt on interrupt
                         halt_ff))

    end

  end
end
