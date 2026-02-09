# Game Boy Speed Control / Clock Enable Generator
# Corresponds to: reference/rtl/speedcontrol.vhd

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class SpeedControl < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk_sys
        input :reset
        input :pause
        input :speedup
        input :cart_act
        input :dma_on

        output :ce
        output :ce_n
        output :ce_2x
        output :refresh
        output :ff_on

        # Internal state
        wire :clkdiv, width: 3
        wire :cart_act_1
        wire :unpause_cnt, width: 4
        wire :fastforward_cnt, width: 4
        wire :refreshcnt, width: 7
        wire :sdram_busy
        wire :state, width: 3
        wire :ff_on_reg

        # Combinational helpers for outputs.
        behavior do
          state_normal = state == lit(0, width: 3)
          state_paused = state == lit(1, width: 3)
          state_ff = state == lit(3, width: 3)

          normal_to_paused = pause & (clkdiv == lit(7, width: 3)) & ~cart_act
          normal_to_ffstart = speedup & ~pause & ~dma_on & (clkdiv == lit(0, width: 3))
          normal_run = state_normal & ~normal_to_paused & ~normal_to_ffstart

          ff_exit = pause | ~speedup | dma_on
          ff_cart_edge = cart_act & ~cart_act_1
          ff_refresh_req = ~cart_act & (refreshcnt == lit(0, width: 7))
          ff_run = state_ff & ~ff_exit & ~ff_cart_edge & ~ff_refresh_req

          ce <= mux((normal_run & (clkdiv == lit(0, width: 3))) | (ff_run & ~clkdiv[0]),
                    lit(1, width: 1), lit(0, width: 1))
          ce_n <= mux((normal_run & (clkdiv == lit(4, width: 3))) | (ff_run & clkdiv[0]),
                      lit(1, width: 1), lit(0, width: 1))
          ce_2x <= mux((normal_run & (clkdiv[1..0] == lit(0, width: 2))) | ff_run,
                       lit(1, width: 1), lit(0, width: 1))
          refresh <= mux((state_paused & (unpause_cnt == lit(0, width: 4))) |
                         (state_ff & ff_refresh_req),
                         lit(1, width: 1), lit(0, width: 1))
          ff_on <= ff_on_reg
        end

        sequential clock: :clk_sys, reset: :reset, reset_values: {
          clkdiv: 0,
          cart_act_1: 0,
          unpause_cnt: 0,
          fastforward_cnt: 0,
          refreshcnt: 0,
          sdram_busy: 0,
          state: 0,
          ff_on_reg: 0
        } do
          state_normal = state == lit(0, width: 3)
          state_paused = state == lit(1, width: 3)
          state_ffstart = state == lit(2, width: 3)
          state_ff = state == lit(3, width: 3)
          state_ffend = state == lit(4, width: 3)
          state_ram = state == lit(5, width: 3)

          normal_to_paused = state_normal & pause & (clkdiv == lit(7, width: 3)) & ~cart_act
          normal_to_ffstart = state_normal & speedup & ~pause & ~dma_on & (clkdiv == lit(0, width: 3))
          ffstart_to_ff = state_ffstart & (fastforward_cnt == lit(15, width: 4))
          ff_exit = state_ff & (pause | ~speedup | dma_on)
          ff_cart_edge = state_ff & cart_act & ~cart_act_1
          ff_refresh_req = state_ff & ~cart_act & (refreshcnt == lit(0, width: 7))
          ff_to_ram = ff_cart_edge | ff_refresh_req
          paused_to_normal = state_paused & ~pause & (unpause_cnt == lit(15, width: 4))
          ffend_to_normal = state_ffend & (fastforward_cnt == lit(15, width: 4))
          ram_to_ff = state_ram & (sdram_busy == lit(0, width: 1))

          normal_run = state_normal & ~normal_to_paused & ~normal_to_ffstart
          ff_run = state_ff & ~ff_exit & ~ff_to_ram

          # Keep previous cart activity for edge detection.
          cart_act_1 <= cart_act

          # Refresh countdown and request scheduling.
          refreshcnt <= mux(ff_refresh_req, lit(127, width: 7),
                        mux(refreshcnt > lit(0, width: 7),
                            refreshcnt - lit(1, width: 7),
                            refreshcnt))

          # RAM access hold counter.
          sdram_busy <= mux(ff_to_ram, lit(1, width: 1),
                        mux(state_ram & (sdram_busy > lit(0, width: 1)),
                            sdram_busy - lit(1, width: 1),
                            sdram_busy))

          # Pause exit debounce counter.
          unpause_cnt <= mux(normal_to_paused, lit(0, width: 4),
                         mux(state_paused & ~pause & (unpause_cnt < lit(15, width: 4)),
                             unpause_cnt + lit(1, width: 4),
                             unpause_cnt))

          # Fast-forward transition counter.
          fastforward_cnt <= mux(normal_to_ffstart | ff_exit, lit(0, width: 4),
                             mux((state_ffstart | state_ffend) & (fastforward_cnt < lit(15, width: 4)),
                                 fastforward_cnt + lit(1, width: 4),
                                 fastforward_cnt))

          # Fast-forward latch output.
          ff_on_reg <= mux(ffstart_to_ff, lit(1, width: 1),
                       mux(ffend_to_normal, lit(0, width: 1), ff_on_reg))

          # 3-bit divider:
          # - normal mode: full 0..7 cycle
          # - fast-forward run: toggle bit 0 only
          # - fast-forward exit alignment: force phase 4 if needed
          clkdiv <= mux(normal_run,
                        (clkdiv + lit(1, width: 3)) & lit(7, width: 3),
                        mux(ff_run,
                            cat(clkdiv[2..1], ~clkdiv[0]),
                            mux(ff_exit & clkdiv[0],
                                lit(4, width: 3),
                                clkdiv)))

          # Main state machine.
          state <= mux(normal_to_paused, lit(1, width: 3),
                   mux(normal_to_ffstart, lit(2, width: 3),
                   mux(ffstart_to_ff, lit(3, width: 3),
                   mux(ff_exit, lit(4, width: 3),
                   mux(ff_to_ram, lit(5, width: 3),
                   mux(paused_to_normal, lit(0, width: 3),
                   mux(ffend_to_normal, lit(0, width: 3),
                   mux(ram_to_ff, lit(3, width: 3),
                       state))))))))
        end
      end
    end
  end
end
