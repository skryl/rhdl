# Game Boy Timer
# Corresponds to: reference/rtl/timer.v
#
# The Game Boy timer consists of:
# - DIV (FF04): Divider register - increments at 16384 Hz
# - TIMA (FF05): Timer counter - increments at selected frequency
# - TMA (FF06): Timer modulo - value loaded into TIMA on overflow
# - TAC (FF07): Timer control - enable and frequency select
#
# Timer frequencies (when enabled):
# - TAC[1:0] = 00: 4096 Hz (CPU clock / 1024)
# - TAC[1:0] = 01: 262144 Hz (CPU clock / 16)
# - TAC[1:0] = 10: 65536 Hz (CPU clock / 64)
# - TAC[1:0] = 11: 16384 Hz (CPU clock / 256)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class Timer < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :reset
    input :clk_sys
    input :ce              # 4 MHz CPU clock enable

    # Interrupt output
    output :irq

    # CPU interface
    input :cpu_sel         # Timer registers selected
    input :cpu_addr, width: 2  # Register address (0=DIV, 1=TIMA, 2=TMA, 3=TAC)
    input :cpu_wr          # CPU write
    input :cpu_di, width: 8    # CPU data in
    output :cpu_do, width: 8   # CPU data out

    # Internal registers
    wire :clk_div, width: 10      # Internal clock divider
    wire :div, width: 8           # DIV register (increments at 16384 Hz)
    wire :tima, width: 8          # TIMA register
    wire :tma, width: 8           # TMA register
    wire :tac, width: 3           # TAC register (only bits 0-2 used)

    # Overflow detection chain (4 cycle delay as in reference)
    wire :tima_overflow
    wire :tima_overflow_1
    wire :tima_overflow_2
    wire :tima_overflow_3
    wire :tima_overflow_4

    # Previous clock divider bits for edge detection
    wire :clk_div_1_9
    wire :clk_div_1_7
    wire :clk_div_1_5
    wire :clk_div_1_3

    # Timer tick detection
    wire :timer_tick
    wire :timer_enabled

    # write_sig to DIV resets internal counter
    wire :reset_div

    # Combinational logic
    behavior do
      # Timer enabled bit
      timer_enabled <= tac[2]

      # Reset divider on write to DIV (address 0)
      reset_div <= cpu_sel & cpu_wr & (cpu_addr == lit(0, width: 2))

      # Timer tick edge detection based on TAC frequency select
      # Timer increments when the selected bit transitions from 1 to 0
      timer_tick <= timer_enabled &
        case_select(tac[1..0], {
          0 => (~clk_div[9] & clk_div_1_9),  # 4096 Hz
          1 => (~clk_div[3] & clk_div_1_3),  # 262144 Hz
          2 => (~clk_div[5] & clk_div_1_5),  # 65536 Hz
          3 => (~clk_div[7] & clk_div_1_7)   # 16384 Hz
        }, default: lit(0, width: 1))

      # CPU read data mux
      cpu_do <= case_select(cpu_addr, {
        0 => div,
        1 => tima,
        2 => tma,
        3 => cat(lit(0b11111, width: 5), tac)
      }, default: lit(0xFF, width: 8))
    end

    # Sequential logic
    sequential clock: :clk_sys, reset: :reset, reset_values: {
      clk_div: 8,  # Initial value as per reference
      div: 0,      # DIV register starts at 0
      tima: 0,
      tma: 0,
      tac: 0,
      irq: 0,
      tima_overflow: 0,
      tima_overflow_1: 0,
      tima_overflow_2: 0,
      tima_overflow_3: 0,
      tima_overflow_4: 0,
      clk_div_1_9: 0,
      clk_div_1_7: 0,
      clk_div_1_5: 0,
      clk_div_1_3: 0
    } do
      # Clock divider - reset_div clears it, else increment on ce
      clk_div <= mux(reset_div,
                     lit(2, width: 10),  # Reset to 2 on DIV write
                     mux(ce,
                         clk_div + lit(1, width: 10),
                         clk_div))

      # DIV register - combined logic for increment and reset
      # Priority: reset on write > increment when clk_div[7:0]==0 > keep same
      div <= mux(ce,
                 mux(cpu_sel & cpu_wr & (cpu_addr == lit(0, width: 2)),
                     lit(0, width: 8),                              # Reset DIV on write
                     mux(clk_div[7..0] == lit(0, width: 8),
                         div + lit(1, width: 8),                    # Increment at 16384 Hz
                         div)),                                     # Keep same
                 div)                                               # Not ce: keep same

      # Edge detection registers - update on ce
      clk_div_1_9 <= mux(ce, clk_div[9], clk_div_1_9)
      clk_div_1_7 <= mux(ce, clk_div[7], clk_div_1_7)
      clk_div_1_5 <= mux(ce, clk_div[5], clk_div_1_5)
      clk_div_1_3 <= mux(ce, clk_div[3], clk_div_1_3)

      # TIMA overflow flag - combined logic:
      # Set when timer_tick AND tima==0xFF, else clear each ce cycle
      tima_overflow <= mux(ce,
                           mux(timer_tick & (tima == lit(0xFF, width: 8)),
                               lit(1, width: 1),
                               lit(0, width: 1)),
                           tima_overflow)

      # Overflow chain - tima_overflow_1 is also cleared on TIMA write
      tima_overflow_1 <= mux(ce,
                             mux(cpu_sel & cpu_wr & (cpu_addr == lit(1, width: 2)),
                                 lit(0, width: 1),    # Cancel on TIMA write
                                 tima_overflow),      # Else shift from overflow
                             tima_overflow_1)
      tima_overflow_2 <= mux(ce, tima_overflow_1, tima_overflow_2)
      tima_overflow_3 <= mux(ce, tima_overflow_2, tima_overflow_3)
      tima_overflow_4 <= mux(ce, tima_overflow_3, tima_overflow_4)

      # IRQ - combined logic: set on overflow_3, else clear each ce cycle
      irq <= mux(ce,
                 mux(tima_overflow_3,
                     lit(1, width: 1),
                     lit(0, width: 1)),
                 irq)

      # TIMA register - combined logic with priority:
      # 1. TMA write during overflow_4: instant effect on TIMA
      # 2. TIMA write (not during overflow_4): write cpu_di
      # 3. overflow_3: reload from TMA
      # 4. timer_tick: increment
      # 5. else: keep same
      tima <= mux(ce,
                  mux(tima_overflow_4 & cpu_sel & cpu_wr & (cpu_addr == lit(2, width: 2)),
                      cpu_di,                                         # TMA write during overflow_4
                      mux(cpu_sel & cpu_wr & (cpu_addr == lit(1, width: 2)) & ~tima_overflow_4,
                          cpu_di,                                     # TIMA write
                          mux(tima_overflow_3,
                              tma,                                    # Reload from TMA
                              mux(timer_tick,
                                  tima + lit(1, width: 8),            # Increment
                                  tima)))),                           # Keep same
                  tima)                                               # Not ce: keep same

      # TMA register - simple write
      tma <= mux(ce & cpu_sel & cpu_wr & (cpu_addr == lit(2, width: 2)),
                 cpu_di,
                 tma)

      # TAC register - simple write (only bits 0-2)
      tac <= mux(ce & cpu_sel & cpu_wr & (cpu_addr == lit(3, width: 2)),
                 cpu_di[2..0],
                 tac)
    end
  end
end
