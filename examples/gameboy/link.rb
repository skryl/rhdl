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

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative '../../lib/rhdl/dsl/sequential'

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
    wire :sb_reg, width: 8        # Serial buffer register
    wire :shift_counter, width: 3 # Bit counter (0-7)
    wire :transfer_active         # Transfer in progress
    wire :clock_counter, width: 9 # Clock divider for 8192 Hz
    wire :prev_ext_clk            # Previous external clock state

    # Clock rate: 8192 Hz internal (4MHz / 512)
    CLOCK_DIV = 512

    behavior do
      # Output current SB value
      sb <= sb_reg

      # Control signals
      sc_start <= transfer_active
      sc_int_clock <= sc_int_clock

      # Serial data output is MSB of shift register
      serial_data_out <= sb_reg[7]

      # Clock output when using internal clock
      serial_clk_out <= mux(sc_int_clock & transfer_active,
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
      sc_int_clock: 0
    } do
      # Clear IRQ each cycle (single pulse)
      serial_irq <= lit(0, width: 1)

      # SB register write
      sb_reg <= mux(ce & sel_sb & ~cpu_wr_n,
                    sb_in,
                    sb_reg)

      # SC register write - start transfer
      transfer_active <= mux(ce & sel_sc & ~cpu_wr_n & sc_start_in,
                             lit(1, width: 1),
                             transfer_active)
      sc_int_clock <= mux(ce & sel_sc & ~cpu_wr_n,
                          sc_int_clock_in,
                          sc_int_clock)

      # Reset shift counter on transfer start
      shift_counter <= mux(ce & sel_sc & ~cpu_wr_n & sc_start_in,
                           lit(0, width: 3),
                           shift_counter)

      # Internal clock counter
      clock_counter <= mux(ce & transfer_active & sc_int_clock,
                           clock_counter + lit(1, width: 9),
                           clock_counter)

      # External clock edge detection
      prev_ext_clk <= serial_clk_in

      # Shift on clock edge (internal or external)
      internal_clock_tick = sc_int_clock & (clock_counter == lit(CLOCK_DIV - 1, width: 9))
      external_clock_tick = ~sc_int_clock & prev_ext_clk & ~serial_clk_in

      clock_tick = transfer_active & (internal_clock_tick | external_clock_tick)

      # Shift register operation
      sb_reg <= mux(ce & clock_tick,
                    cat(sb_reg[6..0], serial_data_in),
                    sb_reg)

      shift_counter <= mux(ce & clock_tick,
                           shift_counter + lit(1, width: 3),
                           shift_counter)

      # Reset clock counter after tick
      clock_counter <= mux(ce & internal_clock_tick,
                           lit(0, width: 9),
                           clock_counter)

      # Transfer complete after 8 bits
      transfer_active <= mux(ce & clock_tick & (shift_counter == lit(7, width: 3)),
                             lit(0, width: 1),
                             transfer_active)

      serial_irq <= mux(ce & clock_tick & (shift_counter == lit(7, width: 3)),
                        lit(1, width: 1),
                        serial_irq)
    end
  end
end
