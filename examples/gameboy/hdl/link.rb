# Game Boy Link Port
# Corresponds to: reference/rtl/link.v
#
# Serial communication port for:
# - Link cable multiplayer
# - Game Boy Printer
# - Other peripherals
#
# Registers:
# - FF01: SB - Serial transfer data
# - FF02: SC - Serial transfer control

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class Link < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk_sys
    input :ce
    input :rst

    # CPU interface
    input :sel_sc             # SC register selected
    input :sel_sb             # SB register selected
    input :cpu_wr_n           # CPU write (active low)
    input :sc_start_in        # Bit 7 of SC write
    input :sc_int_clock_in    # Bit 0 of SC write
    input :sb_in, width: 8    # SB data in

    # External serial interface
    input :serial_clk_in
    input :serial_data_in
    output :serial_clk_out
    output :serial_data_out

    # Outputs
    output :sb, width: 8      # SB register value
    output :serial_irq        # Transfer complete interrupt
    output :sc_start          # Transfer in progress
    output :sc_int_clock      # Internal clock selected

    # Internal state
    wire :sb_reg, width: 8            # Serial buffer register
    wire :shift_counter, width: 3     # Bit counter (0-7)
    wire :transfer_active             # Transfer in progress
    wire :clock_counter, width: 9     # Clock divider for 8192 Hz
    wire :prev_ext_clk                # Previous external clock state
    wire :sc_int_clock_reg            # Internal clock select latch

    # Clock rate: 8192 Hz internal (4MHz / 512)
    CLOCK_DIV = 512

    behavior do
      # Output current SB value
      sb <= sb_reg

      # Control signals
      sc_start <= transfer_active
      sc_int_clock <= sc_int_clock_reg

      # Serial data output is MSB of shift register
      serial_data_out <= sb_reg[7]

      # Clock output when using internal clock
      serial_clk_out <= mux(sc_int_clock_reg & transfer_active,
                            clock_counter[8],
                            lit(1, width: 1))
    end

    sequential clock: :clk_sys, reset: :rst, reset_values: {
      sb_reg: 0,
      shift_counter: 0,
      transfer_active: 0,
      clock_counter: 0,
      prev_ext_clk: 0,
      serial_irq: 0,
      sc_int_clock_reg: 0
    } do
      write_sb = ce & sel_sb & ~cpu_wr_n
      write_sc = ce & sel_sc & ~cpu_wr_n
      start_transfer = write_sc & sc_start_in

      # Shift on clock edge (internal or external)
      internal_clock_tick = sc_int_clock_reg & (clock_counter == lit(CLOCK_DIV - 1, width: 9))
      external_clock_tick = ~sc_int_clock_reg & prev_ext_clk & ~serial_clk_in
      clock_tick = transfer_active & (internal_clock_tick | external_clock_tick)
      transfer_done = ce & clock_tick & (shift_counter == lit(7, width: 3))

      # Build deterministic next-state values once per register.
      sb_next = sb_reg
      shift_counter_next = shift_counter
      transfer_active_next = transfer_active
      clock_counter_next = clock_counter
      sc_int_clock_next = sc_int_clock_reg
      serial_irq_next = lit(0, width: 1)

      # CPU register writes.
      sb_next = mux(write_sb, sb_in, sb_next)
      sc_int_clock_next = mux(write_sc, sc_int_clock_in, sc_int_clock_next)
      transfer_active_next = mux(start_transfer, lit(1, width: 1), transfer_active_next)
      shift_counter_next = mux(start_transfer, lit(0, width: 3), shift_counter_next)

      # Internal clock divider.
      clock_counter_next = mux(ce & transfer_active & sc_int_clock_reg,
                               clock_counter + lit(1, width: 9),
                               clock_counter_next)

      # Transfer shift + counter updates.
      sb_next = mux(ce & clock_tick, cat(sb_reg[6..0], serial_data_in), sb_next)
      shift_counter_next = mux(ce & clock_tick,
                               shift_counter + lit(1, width: 3),
                               shift_counter_next)
      clock_counter_next = mux(ce & internal_clock_tick,
                               lit(0, width: 9),
                               clock_counter_next)

      # Transfer completion and IRQ pulse.
      transfer_active_next = mux(transfer_done, lit(0, width: 1), transfer_active_next)
      serial_irq_next = mux(transfer_done, lit(1, width: 1), serial_irq_next)

      sb_reg <= sb_next
      shift_counter <= shift_counter_next
      transfer_active <= transfer_active_next
      clock_counter <= clock_counter_next
      sc_int_clock_reg <= sc_int_clock_next
      serial_irq <= serial_irq_next
      prev_ext_clk <= serial_clk_in
    end
      end
    end
  end
end
