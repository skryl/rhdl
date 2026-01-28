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

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SM83 < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

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
    output :wr_n           # write_sig
    output :rfsh_n         # Refresh (unused in GB)
    output :halt_n         # halt_sig status
    output :busak_n        # Bus acknowledge

    # Address and data
    output :addr_bus, width: 16   # Address bus
    input :data_in, width: 8    # Data in
    output :data_out, width: 8   # Data out

    # Game Boy specific
    output :stop_out           # stop_out instruction executed
    input :is_gbc           # Game Boy Color mode

    # Internal signals - T80 core interface
    wire :int_cycle_n
    wire :no_read
    wire :write_sig
    wire :iorq
    wire :di_reg, width: 8
    wire :m_cycle, width: 3
    wire :t_state, width: 3

    # Registers (exposed for debugging)
    wire :acc, width: 8        # Accumulator
    wire :flags, width: 8          # Flags: ZNHC----
    wire :bc, width: 16        # bc register pair
    wire :de, width: 16        # de register pair
    wire :hl, width: 16        # hl register pair
    wire :sp, width: 16        # Stack pointer
    wire :pc, width: 16        # Program counter

    # Internal state
    wire :ir, width: 8         # Instruction register
    wire :i_set, width: 2       # Instruction set (always 00 for GB)
    wire :int_e_ff1             # Interrupt enable flag 1 (IME)
    wire :int_e_ff2             # Interrupt enable flag 2
    wire :halt_ff              # halt_sig flag
    wire :nmi_cycle             # NMI cycle active
    wire :int_cycle             # Interrupt cycle active

    # Micro-code control signals
    wire :m_cycles, width: 3    # Machine cycles for current instruction
    wire :t_states_wire, width: 3  # T-states for current M-cycle
    wire :inc_pc
    wire :inc_wz
    wire :inc_dec_16, width: 4
    wire :read_to_acc
    wire :read_to_reg
    wire :set_bus_b_to, width: 4
    wire :set_bus_a_to, width: 4
    wire :alu_op, width: 4
    wire :save_alu
    wire :preserve_c
    wire :arith16
    wire :set_addr_to, width: 3
    wire :jump
    wire :jump_e
    wire :jump_xy
    wire :call_out
    wire :rst_p
    wire :ldz
    wire :ldw
    wire :ldsphl
    wire :ldhlsp
    wire :addsp_dd
    wire :special_ld, width: 3
    wire :exchange_dh
    wire :i_djnz
    wire :i_cpl
    wire :i_ccf
    wire :i_scf
    wire :halt_sig
    wire :set_di
    wire :set_ei

    # ALU signals
    wire :bus_a, width: 8
    wire :bus_b, width: 8
    wire :alu_q, width: 8
    wire :f_out, width: 8

    # Sub-component instances
    instance :alu, SM83_ALU
    instance :mcode, SM83_MCode
    instance :regs, SM83_Registers

    # Clock to subcomponents
    port :clk => [[:alu, :clk], [:mcode, :clk], [:regs, :clk]]

    # MCode connections
    port :ir => [:mcode, :ir]
    port :i_set => [:mcode, :i_set]
    port :m_cycle => [:mcode, :m_cycle]
    port :flags => [:mcode, :flags]
    port :nmi_cycle => [:mcode, :nmi_cycle]
    port :int_cycle => [:mcode, :int_cycle]
    port [:mcode, :m_cycles] => :m_cycles
    port [:mcode, :t_states] => :t_states_wire
    port [:mcode, :inc_pc] => :inc_pc
    port [:mcode, :alu_op] => :alu_op
    port [:mcode, :save_alu] => :save_alu
    port [:mcode, :set_addr_to] => :set_addr_to
    port [:mcode, :jump] => :jump
    port [:mcode, :jump_e] => :jump_e
    port [:mcode, :call_out] => :call_out
    port [:mcode, :halt_sig] => :halt_sig
    port [:mcode, :no_read] => :no_read
    port [:mcode, :write_sig] => :write_sig
    port [:mcode, :i_cpl] => :i_cpl
    port [:mcode, :i_ccf] => :i_ccf
    port [:mcode, :i_scf] => :i_scf
    port [:mcode, :set_di] => :set_di
    port [:mcode, :set_ei] => :set_ei

    # ALU connections
    port :bus_a => [:alu, :addr_bus]
    port :bus_b => [:alu, :B]
    port :alu_op => [:alu, :Op]
    port :flags => [:alu, :F_In]
    port [:alu, :Q] => :alu_q
    port [:alu, :f_out] => :f_out

    # Register file connections
    port :acc => [:regs, :acc_out]
    port :flags => [:regs, :f_out]
    port :bc => [:regs, :bc_out]
    port :de => [:regs, :de_out]
    port :hl => [:regs, :hl_out]
    port :sp => [:regs, :sp_out]
    port :pc => [:regs, :pc_out]

    # Combinational logic
    behavior do
      # stop_out instruction detection (GB specific)
      stop_out <= i_djnz

      # Interrupt cycle signal
      int_cycle_n <= ~int_cycle

      # Data input register (directly connected in GB mode)
      di_reg <= data_in

      # Bus acknowledge
      busak_n <= lit(1, width: 1)

      # Refresh (not used in GB, always high)
      rfsh_n <= lit(1, width: 1)

      # halt_sig output
      halt_n <= ~halt_ff
    end

    # Main state machine (from T80.vhd lines 196-1309)
    sequential clock: :clk, reset: :reset_n, reset_values: {
      m1_n: 1, mreq_n: 1, iorq_n: 1, rd_n: 1, wr_n: 1,
      m_cycle: 1, t_state: 0, int_e_ff1: 0, int_e_ff2: 0,
      halt_ff: 0, int_cycle: 0, nmi_cycle: 0
    } do
      # This implements the T80 state machine for Game Boy mode (Mode=3)
      # The state machine controls:
      # - Memory/IO access timing
      # - Instruction fetch and decode
      # - Interrupt handling
      # - Register updates

      # Update T-state counter
      t_state <= mux(clken,
                    mux(t_state == t_states_wire,
                        lit(1, width: 3),
                        t_state + lit(1, width: 3)),
                    t_state)

      # Machine cycle state machine (simplified)
      # Full implementation would include all the T80 state logic
      m_cycle <= mux(clken & (t_state == t_states_wire),
                    mux(m_cycle == m_cycles,
                        lit(1, width: 3),
                        m_cycle + lit(1, width: 3)),
                    m_cycle)

      # M1 (opcode fetch) indicator
      m1_n <= mux(m_cycle == lit(1, width: 3), lit(0, width: 1), lit(1, width: 1))

      # Memory request timing (active during T1-T2)
      mreq_n <= mux(clken,
                    mux((t_state == lit(1, width: 3)) | (t_state == lit(2, width: 3)),
                        mux(~no_read | write_sig, lit(0, width: 1), lit(1, width: 1)),
                        lit(1, width: 1)),
                    mreq_n)

      # Read timing
      rd_n <= mux(clken,
                  mux((t_state == lit(1, width: 3)) | (t_state == lit(2, width: 3)),
                      mux(~no_read & ~write_sig, lit(0, width: 1), lit(1, width: 1)),
                      lit(1, width: 1)),
                  rd_n)

      # write_sig timing
      wr_n <= mux(clken,
                  mux((t_state == lit(1, width: 3)) | (t_state == lit(2, width: 3)),
                      mux(write_sig, lit(0, width: 1), lit(1, width: 1)),
                      lit(1, width: 1)),
                  wr_n)

      # Interrupt enable handling
      int_e_ff1 <= mux(clken & set_ei & (t_state == lit(2, width: 3)),
                      lit(1, width: 1),
                      mux(clken & set_di & (t_state == lit(3, width: 3)),
                          lit(0, width: 1),
                          mux(int_cycle, lit(0, width: 1), int_e_ff1)))

      int_e_ff2 <= mux(clken & set_ei & (t_state == lit(2, width: 3)),
                      lit(1, width: 1),
                      mux(clken & set_di & (t_state == lit(3, width: 3)),
                          lit(0, width: 1),
                          int_e_ff2))

      # halt_sig flag
      halt_ff <= mux(halt_sig & ~int_cycle & ~nmi_cycle,
                     lit(1, width: 1),
                     mux(int_cycle | nmi_cycle, lit(0, width: 1), halt_ff))

      # Interrupt cycle detection
      int_cycle <= mux(clken & (m_cycle == m_cycles) & (t_state == t_states_wire) &
                      int_e_ff1 & ~int_n,
                      lit(1, width: 1),
                      mux(m_cycle == lit(1, width: 3), lit(0, width: 1), int_cycle))
    end

  end
end
