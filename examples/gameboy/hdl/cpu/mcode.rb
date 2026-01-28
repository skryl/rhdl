# SM83 Microcode - Game Boy CPU Instruction Decoder
# Corresponds to: reference/rtl/T80/T80_MCode.vhd
#
# This module decodes instructions and generates control signals
# for each machine cycle and T-state of instruction execution.
#
# The SM83 uses a microcode-like approach where each instruction
# is broken into machine cycles (m_cycles), and each machine cycle
# has multiple T-states for timing.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module GameBoy
  class SM83_MCode < RHDL::HDL::Component
    include RHDL::DSL::Behavior

    # Address mode constants
    ADDR_NONE   = 0
    ADDR_HL     = 1
    ADDR_BC     = 2
    ADDR_DE     = 3
    ADDR_SP     = 4
    ADDR_IMM16  = 5
    ADDR_FF00_C = 6
    ADDR_FF00_N = 7

    # Instruction inputs
    input :clk
    input :ir, width: 8         # Instruction register
    input :i_set, width: 2       # Instruction set (00=normal, 01=CB prefix)
    input :m_cycle, width: 3     # Current machine cycle
    input :flags, width: 8          # Flags
    input :nmi_cycle             # NMI active
    input :int_cycle             # Interrupt active
    input :xy_state, width: 2   # IX/IY state (unused in GB)

    # Control outputs
    output :m_cycles, width: 3       # Machine cycles for this instruction
    output :t_states, width: 3       # T-states for current machine cycle
    output :prefix, width: 2        # prefix for next instruction
    output :inc_pc                  # Increment pc
    output :inc_wz                  # Increment WZ temp register
    output :inc_dec_16, width: 4     # 16-bit inc/dec control
    output :read_to_acc             # Read to accumulator
    output :read_to_reg             # Read to register
    output :set_bus_b_to, width: 4   # Bus B source select
    output :set_bus_a_to, width: 4   # Bus addr_bus source select
    output :alu_op, width: 4        # ALU operation
    output :save_alu                # Save ALU result
    output :rot_akku                # Rotate accumulator
    output :preserve_c               # Preserve carry flag
    output :arith16                 # 16-bit arithmetic
    output :set_addr_to, width: 3   # Address bus source
    output :iorq                    # I/O request
    output :jump                    # jump instruction
    output :jump_e                   # Relative jump
    output :jump_xy                  # jump to hl/IX/IY
    output :call_out                    # call_out instruction
    output :rst_p                    # RST instruction
    output :ldz                     # Load Z register
    output :ldw                     # Load W register
    output :ldsphl                  # LD sp,hl
    output :ldhlsp                  # LD hl,sp+n
    output :addsp_dd                 # ADD sp,dd
    output :special_ld, width: 3    # Special load operations
    output :exchange_dh              # Exchange D and H (unused in GB)
    output :exchange_rp              # Exchange register pairs (unused in GB)
    output :exchange_af              # Exchange AF (unused in GB)
    output :exchange_rs              # Exchange register sets (unused in GB)
    output :i_djnz                  # DJNZ instruction (stop_out on GB)
    output :i_cpl                   # CPL instruction
    output :i_ccf                   # CCF instruction
    output :i_scf                   # SCF instruction
    output :i_retn                  # RETI instruction
    output :i_bt                    # Block transfer (unused in GB)
    output :i_bc                    # Block compare (unused in GB)
    output :i_btr                   # Block transfer repeat (unused in GB)
    output :i_rld                   # RLD instruction (unused in GB)
    output :i_rrd                   # RRD instruction (unused in GB)
    output :i_inrc                  # IN r,(C) (unused in GB)
    output :set_di                   # Disable interrupts
    output :set_ei                   # Enable interrupts
    output :i_mode, width: 2         # Interrupt mode (unused in GB)
    output :halt_sig                    # HALT instruction
    output :no_read                  # Suppress memory read
    output :write_sig                   # Memory write

    behavior do
      # Default values
      m_cycles <= lit(1, width: 3)
      t_states <= lit(4, width: 3)
      prefix <= lit(0, width: 2)
      inc_pc <= lit(0, width: 1)
      inc_wz <= lit(0, width: 1)
      inc_dec_16 <= lit(0, width: 4)
      read_to_acc <= lit(0, width: 1)
      read_to_reg <= lit(0, width: 1)
      set_bus_b_to <= lit(0, width: 4)
      set_bus_a_to <= lit(0, width: 4)
      alu_op <= lit(0, width: 4)
      save_alu <= lit(0, width: 1)
      rot_akku <= lit(0, width: 1)
      preserve_c <= lit(0, width: 1)
      arith16 <= lit(0, width: 1)
      set_addr_to <= lit(0, width: 3)
      iorq <= lit(0, width: 1)
      jump <= lit(0, width: 1)
      jump_e <= lit(0, width: 1)
      jump_xy <= lit(0, width: 1)
      call_out <= lit(0, width: 1)
      rst_p <= lit(0, width: 1)
      ldz <= lit(0, width: 1)
      ldw <= lit(0, width: 1)
      ldsphl <= lit(0, width: 1)
      ldhlsp <= lit(0, width: 1)
      addsp_dd <= lit(0, width: 1)
      special_ld <= lit(0, width: 3)
      exchange_dh <= lit(0, width: 1)
      exchange_rp <= lit(0, width: 1)
      exchange_af <= lit(0, width: 1)
      exchange_rs <= lit(0, width: 1)
      i_djnz <= lit(0, width: 1)
      i_cpl <= lit(0, width: 1)
      i_ccf <= lit(0, width: 1)
      i_scf <= lit(0, width: 1)
      i_retn <= lit(0, width: 1)
      i_bt <= lit(0, width: 1)
      i_bc <= lit(0, width: 1)
      i_btr <= lit(0, width: 1)
      i_rld <= lit(0, width: 1)
      i_rrd <= lit(0, width: 1)
      i_inrc <= lit(0, width: 1)
      set_di <= lit(0, width: 1)
      set_ei <= lit(0, width: 1)
      i_mode <= lit(0, width: 2)
      halt_sig <= lit(0, width: 1)
      no_read <= lit(0, width: 1)
      write_sig <= lit(0, width: 1)

      # Instruction decoding based on opcode
      # This is a simplified version - full implementation would decode all GB opcodes
      # The actual T80_MCode.vhd is ~1500 lines of VHDL

      # NOP (0x00)
      # LD r,r' (0x40-0x7F except 0x76)
      # LD r,n (0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E)
      # ALU addr_bus,r (0x80-0xBF)
      # etc.

      # CB prefix detection
      prefix <= mux(ir == lit(0xCB, width: 8),
                    lit(1, width: 2),
                    lit(0, width: 2))

      # Basic instruction timing (simplified)
      # Most instructions are 1-4 machine cycles
      # Each machine cycle is 4 T-states on GB (not the 3-6 of Z80)
      t_states <= lit(4, width: 3)

      # HALT instruction (0x76)
      halt_sig <= (ir == lit(0x76, width: 8)) & (i_set == lit(0, width: 2))

      # stop_out instruction (0x10) - shows as i_djnz in T80
      i_djnz <= (ir == lit(0x10, width: 8)) & (i_set == lit(0, width: 2))

      # data_in instruction (0xF3)
      set_di <= (ir == lit(0xF3, width: 8)) & (i_set == lit(0, width: 2))

      # EI instruction (0xFB)
      set_ei <= (ir == lit(0xFB, width: 8)) & (i_set == lit(0, width: 2))

      # CPL instruction (0x2F)
      i_cpl <= (ir == lit(0x2F, width: 8)) & (i_set == lit(0, width: 2))

      # CCF instruction (0x3F)
      i_ccf <= (ir == lit(0x3F, width: 8)) & (i_set == lit(0, width: 2))

      # SCF instruction (0x37)
      i_scf <= (ir == lit(0x37, width: 8)) & (i_set == lit(0, width: 2))

      # RETI instruction (0xD9) - note: different from Z80's EXX
      i_retn <= (ir == lit(0xD9, width: 8)) & (i_set == lit(0, width: 2))

      # LD sp,hl (0xF9)
      ldsphl <= (ir == lit(0xF9, width: 8)) & (i_set == lit(0, width: 2))

      # LD hl,sp+n (0xF8)
      ldhlsp <= (ir == lit(0xF8, width: 8)) & (i_set == lit(0, width: 2))

      # ADD sp,dd (0xE8)
      addsp_dd <= (ir == lit(0xE8, width: 8)) & (i_set == lit(0, width: 2))

      # Increment pc for most instructions during fetch
      inc_pc <= (m_cycle == lit(1, width: 3))

      # Read/write_sig control based on instruction type
      no_read <= lit(0, width: 1)  # Default to allow reads
      write_sig <= lit(0, width: 1)   # Default to no writes
    end
  end
end
