# SM83 CPU - Game Boy CPU Core
# Corresponds to: reference/rtl/T80/GBse.vhd and T80.vhd
#
# The SM83 is a custom Sharp CPU used in the Game Boy.
# It's similar to the Z80 but with some differences:
# - No IX, IY index registers
# - No shadow registers
# - Different flag bit positions
# - Different instruction set (subset of Z80 + GB-specific)
#
# This implementation follows the T80 core with Mode=3 (Game Boy mode)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SM83 < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Control signals
    input :RESET_n         # Active-low reset
    input :CLK_n           # Clock
    input :CLKEN           # Clock enable
    input :WAIT_n          # Wait signal
    input :INT_n           # Interrupt request (active low)
    input :NMI_n, default: 1  # Non-maskable interrupt (unused in GB)
    input :BUSRQ_n, default: 1  # Bus request

    # Bus signals
    output :M1_n           # Machine cycle 1 (opcode fetch)
    output :MREQ_n         # Memory request
    output :IORQ_n         # I/O request
    output :RD_n           # Read
    output :WR_n           # Write
    output :RFSH_n         # Refresh (unused in GB)
    output :HALT_n         # Halt status
    output :BUSAK_n        # Bus acknowledge

    # Address and data
    output :A, width: 16   # Address bus
    input :DI, width: 8    # Data in
    output :DO, width: 8   # Data out

    # Game Boy specific
    output :STOP           # STOP instruction executed
    input :isGBC           # Game Boy Color mode

    # Internal signals - T80 core interface
    wire :IntCycle_n
    wire :NoRead
    wire :Write
    wire :IORQ
    wire :DI_Reg, width: 8
    wire :MCycle, width: 3
    wire :TState, width: 3

    # Registers (exposed for debugging)
    wire :ACC, width: 8        # Accumulator
    wire :F, width: 8          # Flags: ZNHC----
    wire :BC, width: 16        # BC register pair
    wire :DE, width: 16        # DE register pair
    wire :HL, width: 16        # HL register pair
    wire :SP, width: 16        # Stack pointer
    wire :PC, width: 16        # Program counter

    # Internal state
    wire :IR, width: 8         # Instruction register
    wire :ISet, width: 2       # Instruction set (always 00 for GB)
    wire :IntE_FF1             # Interrupt enable flag 1 (IME)
    wire :IntE_FF2             # Interrupt enable flag 2
    wire :Halt_FF              # Halt flag
    wire :NMICycle             # NMI cycle active
    wire :IntCycle             # Interrupt cycle active

    # Micro-code control signals
    wire :MCycles, width: 3    # Machine cycles for current instruction
    wire :TStates_wire, width: 3  # T-states for current M-cycle
    wire :Inc_PC
    wire :Inc_WZ
    wire :IncDec_16, width: 4
    wire :Read_To_Acc
    wire :Read_To_Reg
    wire :Set_BusB_To, width: 4
    wire :Set_BusA_To, width: 4
    wire :ALU_Op, width: 4
    wire :Save_ALU
    wire :PreserveC
    wire :Arith16
    wire :Set_Addr_To, width: 3
    wire :Jump
    wire :JumpE
    wire :JumpXY
    wire :Call
    wire :RstP
    wire :LDZ
    wire :LDW
    wire :LDSPHL
    wire :LDHLSP
    wire :ADDSPdd
    wire :Special_LD, width: 3
    wire :ExchangeDH
    wire :I_DJNZ
    wire :I_CPL
    wire :I_CCF
    wire :I_SCF
    wire :Halt
    wire :SetDI
    wire :SetEI

    # ALU signals
    wire :BusA, width: 8
    wire :BusB, width: 8
    wire :ALU_Q, width: 8
    wire :F_Out, width: 8

    # Sub-component instances
    instance :alu, SM83_ALU
    instance :mcode, SM83_MCode
    instance :regs, SM83_Registers

    # Clock to subcomponents
    port :CLK_n => [[:alu, :clk], [:mcode, :clk], [:regs, :clk]]

    # MCode connections
    port :IR => [:mcode, :IR]
    port :ISet => [:mcode, :ISet]
    port :MCycle => [:mcode, :MCycle]
    port :F => [:mcode, :F]
    port :NMICycle => [:mcode, :NMICycle]
    port :IntCycle => [:mcode, :IntCycle]
    port [:mcode, :MCycles] => :MCycles
    port [:mcode, :TStates] => :TStates_wire
    port [:mcode, :Inc_PC] => :Inc_PC
    port [:mcode, :ALU_Op] => :ALU_Op
    port [:mcode, :Save_ALU] => :Save_ALU
    port [:mcode, :Set_Addr_To] => :Set_Addr_To
    port [:mcode, :Jump] => :Jump
    port [:mcode, :JumpE] => :JumpE
    port [:mcode, :Call] => :Call
    port [:mcode, :Halt] => :Halt
    port [:mcode, :NoRead] => :NoRead
    port [:mcode, :Write] => :Write
    port [:mcode, :I_CPL] => :I_CPL
    port [:mcode, :I_CCF] => :I_CCF
    port [:mcode, :I_SCF] => :I_SCF
    port [:mcode, :SetDI] => :SetDI
    port [:mcode, :SetEI] => :SetEI

    # ALU connections
    port :BusA => [:alu, :A]
    port :BusB => [:alu, :B]
    port :ALU_Op => [:alu, :Op]
    port :F => [:alu, :F_In]
    port [:alu, :Q] => :ALU_Q
    port [:alu, :F_Out] => :F_Out

    # Register file connections
    port :ACC => [:regs, :ACC_out]
    port :F => [:regs, :F_out]
    port :BC => [:regs, :BC_out]
    port :DE => [:regs, :DE_out]
    port :HL => [:regs, :HL_out]
    port :SP => [:regs, :SP_out]
    port :PC => [:regs, :PC_out]

    # Combinational logic
    behavior do
      # STOP instruction detection (GB specific)
      STOP <= I_DJNZ

      # Interrupt cycle signal
      IntCycle_n <= ~IntCycle

      # Data input register (directly connected in GB mode)
      DI_Reg <= DI

      # Bus acknowledge
      BUSAK_n <= lit(1, width: 1)

      # Refresh (not used in GB, always high)
      RFSH_n <= lit(1, width: 1)

      # Halt output
      HALT_n <= ~Halt_FF
    end

    # Main state machine (from T80.vhd lines 196-1309)
    sequential clock: :CLK_n, reset: :RESET_n, reset_values: {
      M1_n: 1, MREQ_n: 1, IORQ_n: 1, RD_n: 1, WR_n: 1,
      MCycle: 1, TState: 0, IntE_FF1: 0, IntE_FF2: 0,
      Halt_FF: 0, IntCycle: 0, NMICycle: 0
    } do
      # This implements the T80 state machine for Game Boy mode (Mode=3)
      # The state machine controls:
      # - Memory/IO access timing
      # - Instruction fetch and decode
      # - Interrupt handling
      # - Register updates

      # Update T-state counter
      TState <= mux(CLKEN,
                    mux(TState == TStates_wire,
                        lit(1, width: 3),
                        TState + lit(1, width: 3)),
                    TState)

      # Machine cycle state machine (simplified)
      # Full implementation would include all the T80 state logic
      MCycle <= mux(CLKEN & (TState == TStates_wire),
                    mux(MCycle == MCycles,
                        lit(1, width: 3),
                        MCycle + lit(1, width: 3)),
                    MCycle)

      # M1 (opcode fetch) indicator
      M1_n <= mux(MCycle == lit(1, width: 3), lit(0, width: 1), lit(1, width: 1))

      # Memory request timing (active during T1-T2)
      MREQ_n <= mux(CLKEN,
                    mux((TState == lit(1, width: 3)) | (TState == lit(2, width: 3)),
                        mux(~NoRead | Write, lit(0, width: 1), lit(1, width: 1)),
                        lit(1, width: 1)),
                    MREQ_n)

      # Read timing
      RD_n <= mux(CLKEN,
                  mux((TState == lit(1, width: 3)) | (TState == lit(2, width: 3)),
                      mux(~NoRead & ~Write, lit(0, width: 1), lit(1, width: 1)),
                      lit(1, width: 1)),
                  RD_n)

      # Write timing
      WR_n <= mux(CLKEN,
                  mux((TState == lit(1, width: 3)) | (TState == lit(2, width: 3)),
                      mux(Write, lit(0, width: 1), lit(1, width: 1)),
                      lit(1, width: 1)),
                  WR_n)

      # Interrupt enable handling
      IntE_FF1 <= mux(CLKEN & SetEI & (TState == lit(2, width: 3)),
                      lit(1, width: 1),
                      mux(CLKEN & SetDI & (TState == lit(3, width: 3)),
                          lit(0, width: 1),
                          mux(IntCycle, lit(0, width: 1), IntE_FF1)))

      IntE_FF2 <= mux(CLKEN & SetEI & (TState == lit(2, width: 3)),
                      lit(1, width: 1),
                      mux(CLKEN & SetDI & (TState == lit(3, width: 3)),
                          lit(0, width: 1),
                          IntE_FF2))

      # Halt flag
      Halt_FF <= mux(Halt & ~IntCycle & ~NMICycle,
                     lit(1, width: 1),
                     mux(IntCycle | NMICycle, lit(0, width: 1), Halt_FF))

      # Interrupt cycle detection
      IntCycle <= mux(CLKEN & (MCycle == MCycles) & (TState == TStates_wire) &
                      IntE_FF1 & ~INT_n,
                      lit(1, width: 1),
                      mux(MCycle == lit(1, width: 3), lit(0, width: 1), IntCycle))
    end

  end
end
