# SM83 Microcode - Game Boy CPU Instruction Decoder
# Corresponds to: reference/rtl/T80/T80_MCode.vhd
#
# This module decodes instructions and generates control signals
# for each machine cycle and T-state of instruction execution.
#
# The SM83 uses a microcode-like approach where each instruction
# is broken into machine cycles (MCycles), and each machine cycle
# has multiple T-states for timing.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

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
    input :IR, width: 8         # Instruction register
    input :ISet, width: 2       # Instruction set (00=normal, 01=CB prefix)
    input :MCycle, width: 3     # Current machine cycle
    input :F, width: 8          # Flags
    input :NMICycle             # NMI active
    input :IntCycle             # Interrupt active
    input :XY_State, width: 2   # IX/IY state (unused in GB)

    # Control outputs
    output :MCycles, width: 3       # Machine cycles for this instruction
    output :TStates, width: 3       # T-states for current machine cycle
    output :Prefix, width: 2        # Prefix for next instruction
    output :Inc_PC                  # Increment PC
    output :Inc_WZ                  # Increment WZ temp register
    output :IncDec_16, width: 4     # 16-bit inc/dec control
    output :Read_To_Acc             # Read to accumulator
    output :Read_To_Reg             # Read to register
    output :Set_BusB_To, width: 4   # Bus B source select
    output :Set_BusA_To, width: 4   # Bus A source select
    output :ALU_Op, width: 4        # ALU operation
    output :Save_ALU                # Save ALU result
    output :Rot_Akku                # Rotate accumulator
    output :PreserveC               # Preserve carry flag
    output :Arith16                 # 16-bit arithmetic
    output :Set_Addr_To, width: 3   # Address bus source
    output :IORQ                    # I/O request
    output :Jump                    # Jump instruction
    output :JumpE                   # Relative jump
    output :JumpXY                  # Jump to HL/IX/IY
    output :Call                    # Call instruction
    output :RstP                    # RST instruction
    output :LDZ                     # Load Z register
    output :LDW                     # Load W register
    output :LDSPHL                  # LD SP,HL
    output :LDHLSP                  # LD HL,SP+n
    output :ADDSPdd                 # ADD SP,dd
    output :Special_LD, width: 3    # Special load operations
    output :ExchangeDH              # Exchange D and H (unused in GB)
    output :ExchangeRp              # Exchange register pairs (unused in GB)
    output :ExchangeAF              # Exchange AF (unused in GB)
    output :ExchangeRS              # Exchange register sets (unused in GB)
    output :I_DJNZ                  # DJNZ instruction (STOP on GB)
    output :I_CPL                   # CPL instruction
    output :I_CCF                   # CCF instruction
    output :I_SCF                   # SCF instruction
    output :I_RETN                  # RETI instruction
    output :I_BT                    # Block transfer (unused in GB)
    output :I_BC                    # Block compare (unused in GB)
    output :I_BTR                   # Block transfer repeat (unused in GB)
    output :I_RLD                   # RLD instruction (unused in GB)
    output :I_RRD                   # RRD instruction (unused in GB)
    output :I_INRC                  # IN r,(C) (unused in GB)
    output :SetDI                   # Disable interrupts
    output :SetEI                   # Enable interrupts
    output :IMode, width: 2         # Interrupt mode (unused in GB)
    output :Halt                    # HALT instruction
    output :NoRead                  # Suppress memory read
    output :Write                   # Memory write

    behavior do
      # Default values
      MCycles <= lit(1, width: 3)
      TStates <= lit(4, width: 3)
      Prefix <= lit(0, width: 2)
      Inc_PC <= lit(0, width: 1)
      Inc_WZ <= lit(0, width: 1)
      IncDec_16 <= lit(0, width: 4)
      Read_To_Acc <= lit(0, width: 1)
      Read_To_Reg <= lit(0, width: 1)
      Set_BusB_To <= lit(0, width: 4)
      Set_BusA_To <= lit(0, width: 4)
      ALU_Op <= lit(0, width: 4)
      Save_ALU <= lit(0, width: 1)
      Rot_Akku <= lit(0, width: 1)
      PreserveC <= lit(0, width: 1)
      Arith16 <= lit(0, width: 1)
      Set_Addr_To <= lit(0, width: 3)
      IORQ <= lit(0, width: 1)
      Jump <= lit(0, width: 1)
      JumpE <= lit(0, width: 1)
      JumpXY <= lit(0, width: 1)
      Call <= lit(0, width: 1)
      RstP <= lit(0, width: 1)
      LDZ <= lit(0, width: 1)
      LDW <= lit(0, width: 1)
      LDSPHL <= lit(0, width: 1)
      LDHLSP <= lit(0, width: 1)
      ADDSPdd <= lit(0, width: 1)
      Special_LD <= lit(0, width: 3)
      ExchangeDH <= lit(0, width: 1)
      ExchangeRp <= lit(0, width: 1)
      ExchangeAF <= lit(0, width: 1)
      ExchangeRS <= lit(0, width: 1)
      I_DJNZ <= lit(0, width: 1)
      I_CPL <= lit(0, width: 1)
      I_CCF <= lit(0, width: 1)
      I_SCF <= lit(0, width: 1)
      I_RETN <= lit(0, width: 1)
      I_BT <= lit(0, width: 1)
      I_BC <= lit(0, width: 1)
      I_BTR <= lit(0, width: 1)
      I_RLD <= lit(0, width: 1)
      I_RRD <= lit(0, width: 1)
      I_INRC <= lit(0, width: 1)
      SetDI <= lit(0, width: 1)
      SetEI <= lit(0, width: 1)
      IMode <= lit(0, width: 2)
      Halt <= lit(0, width: 1)
      NoRead <= lit(0, width: 1)
      Write <= lit(0, width: 1)

      # Instruction decoding based on opcode
      # This is a simplified version - full implementation would decode all GB opcodes
      # The actual T80_MCode.vhd is ~1500 lines of VHDL

      # NOP (0x00)
      # LD r,r' (0x40-0x7F except 0x76)
      # LD r,n (0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E)
      # ALU A,r (0x80-0xBF)
      # etc.

      # CB prefix detection
      Prefix <= mux(IR == lit(0xCB, width: 8),
                    lit(1, width: 2),
                    lit(0, width: 2))

      # Basic instruction timing (simplified)
      # Most instructions are 1-4 machine cycles
      # Each machine cycle is 4 T-states on GB (not the 3-6 of Z80)
      TStates <= lit(4, width: 3)

      # HALT instruction (0x76)
      Halt <= (IR == lit(0x76, width: 8)) & (ISet == lit(0, width: 2))

      # STOP instruction (0x10) - shows as I_DJNZ in T80
      I_DJNZ <= (IR == lit(0x10, width: 8)) & (ISet == lit(0, width: 2))

      # DI instruction (0xF3)
      SetDI <= (IR == lit(0xF3, width: 8)) & (ISet == lit(0, width: 2))

      # EI instruction (0xFB)
      SetEI <= (IR == lit(0xFB, width: 8)) & (ISet == lit(0, width: 2))

      # CPL instruction (0x2F)
      I_CPL <= (IR == lit(0x2F, width: 8)) & (ISet == lit(0, width: 2))

      # CCF instruction (0x3F)
      I_CCF <= (IR == lit(0x3F, width: 8)) & (ISet == lit(0, width: 2))

      # SCF instruction (0x37)
      I_SCF <= (IR == lit(0x37, width: 8)) & (ISet == lit(0, width: 2))

      # RETI instruction (0xD9) - note: different from Z80's EXX
      I_RETN <= (IR == lit(0xD9, width: 8)) & (ISet == lit(0, width: 2))

      # LD SP,HL (0xF9)
      LDSPHL <= (IR == lit(0xF9, width: 8)) & (ISet == lit(0, width: 2))

      # LD HL,SP+n (0xF8)
      LDHLSP <= (IR == lit(0xF8, width: 8)) & (ISet == lit(0, width: 2))

      # ADD SP,dd (0xE8)
      ADDSPdd <= (IR == lit(0xE8, width: 8)) & (ISet == lit(0, width: 2))

      # Increment PC for most instructions during fetch
      Inc_PC <= (MCycle == lit(1, width: 3))

      # Read/Write control based on instruction type
      NoRead <= lit(0, width: 1)  # Default to allow reads
      Write <= lit(0, width: 1)   # Default to no writes
    end
  end
end
