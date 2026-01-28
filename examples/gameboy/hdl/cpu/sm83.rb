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

    # Cycle count condition wires (for m_cycles calculation)
    wire :is_6_cycles           # 6-cycle instructions
    wire :is_4_cycles           # 4-cycle instructions
    wire :is_3_cycles           # 3-cycle instructions
    wire :is_2_cycles           # 2-cycle instructions

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
      # Instruction Decoder (Microcode) - Default values
      # -----------------------------------------------------------------------
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

      # m_cycles calculation - simplified: most instructions are 1 cycle
      is_6_cycles <= lit(0, width: 1)
      is_4_cycles <= lit(0, width: 1)
      is_3_cycles <= lit(0, width: 1)
      is_2_cycles <= lit(0, width: 1)

      # Default: all instructions take 1 cycle (will add proper cycle counts later)
      m_cycles <= lit(1, width: 3)

      # -----------------------------------------------------------------------
      # Instruction Decoder - Specific instructions
      # -----------------------------------------------------------------------

      # LD rr,nn - load WZ register for 16-bit immediate
      ldz <= mux((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), lit(0, width: 1))
      ldw <= mux((ir[3..0] == lit(1, width: 4)) & (ir[7..6] == lit(0, width: 2)) & (m_cycle == lit(3, width: 3)),
                 lit(1, width: 1), lit(0, width: 1))

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
                          lit(1, width: 1), lit(0, width: 1))

      # Address source for BC/DE indirect
      set_addr_to <= mux((ir == lit(0x02, width: 8)) | (ir == lit(0x0A, width: 8)),
                         lit(ADDR_BC, width: 3),
                         mux((ir == lit(0x12, width: 8)) | (ir == lit(0x1A, width: 8)),
                             lit(ADDR_DE, width: 3),
                             lit(ADDR_PC, width: 3)))

      # JR e - relative jump
      jump_e <= mux(ir == lit(0x18, width: 8), lit(1, width: 1), lit(0, width: 1))
      ldz <= mux((ir == lit(0x18, width: 8)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)

      # HALT
      halt <= (ir == lit(0x76, width: 8))

      # ALU A,r operations
      alu_op <= mux(ir[7..6] == lit(2, width: 2), ir[5..3], lit(0, width: 4))
      save_alu <= mux(ir[7..6] == lit(2, width: 2), lit(1, width: 1), lit(0, width: 1))
      set_bus_a_to <= mux(ir[7..6] == lit(2, width: 2), lit(7, width: 4), lit(7, width: 4)) # ACC
      set_bus_b_to <= mux(ir[7..6] == lit(2, width: 2), cat(lit(0, width: 1), ir[2..0]), lit(7, width: 4))

      # RET
      ret <= mux(ir == lit(0xC9, width: 8), lit(1, width: 1), lit(0, width: 1))

      # JP nn
      jump <= mux(ir == lit(0xC3, width: 8), lit(1, width: 1), lit(0, width: 1))
      ldz <= mux((ir == lit(0xC3, width: 8)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)
      ldw <= mux((ir == lit(0xC3, width: 8)) & (m_cycle == lit(3, width: 3)),
                 lit(1, width: 1), ldw)

      # CB prefix
      prefix <= mux(ir == lit(0xCB, width: 8), lit(1, width: 2), lit(0, width: 2))

      # CALL nn - set call signal and load address
      call <= mux(ir == lit(0xCD, width: 8), lit(1, width: 1), lit(0, width: 1))
      ldz <= mux((ir == lit(0xCD, width: 8)) & (m_cycle == lit(2, width: 3)),
                 lit(1, width: 1), ldz)
      ldw <= mux((ir == lit(0xCD, width: 8)) & (m_cycle == lit(3, width: 3)),
                 lit(1, width: 1), ldw)

      # JP (HL) - 1 cycle jump using HL address
      jump <= mux(ir == lit(0xE9, width: 8), lit(1, width: 1), jump)
      set_addr_to <= mux(ir == lit(0xE9, width: 8), lit(ADDR_HL, width: 3), set_addr_to)

      # DI - disable interrupts
      set_di <= (ir == lit(0xF3, width: 8))

      # EI - enable interrupts
      set_ei <= (ir == lit(0xFB, width: 8))

      # STOP
      is_stop <= (ir == lit(0x10, width: 8))

      # PC increment during M1 (when not halted and not in interrupt cycle)
      inc_pc <= (m_cycle == lit(1, width: 3)) & ~halt & ~int_cycle

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
      bus_b <= mux(set_bus_b_to == lit(0, width: 4), b_reg,
               mux(set_bus_b_to == lit(1, width: 4), c_reg,
               mux(set_bus_b_to == lit(2, width: 4), d_reg,
               mux(set_bus_b_to == lit(3, width: 4), e_reg,
               mux(set_bus_b_to == lit(4, width: 4), h_reg,
               mux(set_bus_b_to == lit(5, width: 4), l_reg,
               mux(set_bus_b_to == lit(6, width: 4), di_reg,
               mux(set_bus_b_to == lit(7, width: 4), acc,
                   acc))))))))

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

      # State - t_state starts at 1 (valid range is 1-4)
      ir: 0x00, wz: 0x0000,
      m_cycle: 1, t_state: 1,
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
