# Game Boy Speed Control / Clock Enable Generator
# Corresponds to: reference/rtl/speedcontrol.vhd
#
# Generates clock enable signals from clk_sys:
# - ce:    4MHz clock enable (every 8th cycle in normal mode)
# - ce_n:  4MHz inverted clock enable (180° out of phase)
# - ce_2x: 8MHz clock enable for GBC double speed mode

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SpeedControl < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk_sys
    input :reset
    input :pause           # Pause the clock
    input :speedup         # Fast forward mode
    input :cart_act        # Cartridge access active
    input :dma_on          # DMA active

    output :ce             # 4MHz clock enable
    output :ce_n           # 4MHz inverted clock enable
    output :ce_2x          # 8MHz clock enable (GBC double speed)

    # Internal state
    wire :clkdiv, width: 3   # Clock divider counter

    behavior do
      # In normal mode:
      # ce    = 1 when clkdiv == 0
      # ce_n  = 1 when clkdiv == 4
      # ce_2x = 1 when clkdiv[1:0] == 0
      ce <= ~pause & (clkdiv == lit(0, width: 3))
      ce_n <= ~pause & (clkdiv == lit(4, width: 3))
      ce_2x <= ~pause & (clkdiv[1..0] == lit(0, width: 2))
    end

    sequential clock: :clk_sys, reset: :reset, reset_values: {
      clkdiv: 0
    } do
      # Simple clock divider - increment each cycle
      # When not paused, just count 0-7 continuously
      clkdiv <= mux(pause,
                    clkdiv,  # Hold when paused
                    (clkdiv + lit(1, width: 3)) & lit(7, width: 3))
    end
  end
end
