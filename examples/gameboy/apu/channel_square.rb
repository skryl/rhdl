# Game Boy Square Wave Channel
# Corresponds to: parts of reference/rtl/gbc_snd.vhd
#
# Square wave channel with:
# - Optional frequency sweep (Channel 1 only)
# - 4 duty cycle patterns (12.5%, 25%, 50%, 75%)
# - Volume envelope
# - Length counter

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class ChannelSquare < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    parameter :has_sweep, default: false

    input :clk
    input :ce
    input :reset

    # Control registers
    input :sweep_reg, width: 8    # NRx0 (if has_sweep)
    input :length_duty, width: 8  # NRx1
    input :envelope, width: 8     # NRx2
    input :freq_lo, width: 8      # NRx3
    input :freq_hi, width: 8      # NRx4

    # Frame sequencer (from APU)
    input :frame_seq, width: 3

    # Trigger
    input :trigger

    # Outputs
    output :output, width: 4
    output :enabled

    # Internal state
    wire :frequency, width: 11    # 11-bit frequency
    wire :timer, width: 12        # Frequency timer
    wire :duty_pos, width: 3      # Duty cycle position (0-7)
    wire :volume, width: 4        # Current volume
    wire :length_counter, width: 6 # Length counter
    wire :envelope_timer, width: 3 # Envelope timer
    wire :sweep_timer, width: 3   # Sweep timer (if has_sweep)
    wire :sweep_enabled          # Sweep active
    wire :sweep_freq, width: 11  # Shadow frequency for sweep

    # Duty cycle patterns (indexed by duty[1:0] and duty_pos[2:0])
    # 0: 00000001 (12.5%)
    # 1: 10000001 (25%)
    # 2: 10000111 (50%)
    # 3: 01111110 (75%)
    wire :duty_pattern, width: 8
    wire :duty_bit

    behavior do
      # Extract frequency from registers
      frequency <= cat(freq_hi[2..0], freq_lo)

      # Duty cycle selection
      duty = length_duty[7..6]
      duty_pattern <= case_select(duty, {
        0 => lit(0b00000001, width: 8),
        1 => lit(0b10000001, width: 8),
        2 => lit(0b10000111, width: 8),
        3 => lit(0b01111110, width: 8)
      }, default: lit(0b10000111, width: 8))

      # Current duty bit (indexed by duty_pos)
      duty_bit <= duty_pattern[duty_pos]

      # DAC enabled if envelope start volume != 0 or envelope add mode
      dac_enabled = (envelope[7..4] != lit(0, width: 4)) | envelope[3]

      # Channel enabled
      enabled <= dac_enabled & (length_counter > lit(0, width: 6))

      # Output (0 if duty_bit low, volume if high)
      output <= mux(enabled & duty_bit, volume, lit(0, width: 4))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      timer: 0,
      duty_pos: 0,
      volume: 0,
      length_counter: 0,
      envelope_timer: 0,
      sweep_timer: 0,
      sweep_enabled: 0,
      sweep_freq: 0
    } do
      # Frequency timer
      timer <= mux(ce,
                   mux(timer == lit(0, width: 12),
                       cat(lit(0b1, width: 1), ~frequency),  # Reload: (2048 - freq) * 4
                       timer - lit(1, width: 12)),
                   timer)

      # Advance duty position when timer expires
      duty_pos <= mux(ce & (timer == lit(0, width: 12)),
                      duty_pos + lit(1, width: 3),
                      duty_pos)

      # Length counter (clocked at 256Hz = frame_seq[0])
      length_counter <= mux(frame_seq == lit(0, width: 3) & freq_hi[6] &
                            (length_counter > lit(0, width: 6)),
                            length_counter - lit(1, width: 6),
                            length_counter)

      # Envelope (clocked at 64Hz = frame_seq[7])
      envelope_timer <= mux(frame_seq == lit(7, width: 3) & (envelope[2..0] != lit(0, width: 3)),
                            mux(envelope_timer == lit(0, width: 3),
                                envelope[2..0],
                                envelope_timer - lit(1, width: 3)),
                            envelope_timer)

      # Adjust volume on envelope tick
      volume <= mux(frame_seq == lit(7, width: 3) &
                    (envelope[2..0] != lit(0, width: 3)) &
                    (envelope_timer == lit(0, width: 3)),
                    mux(envelope[3],  # Direction: 1=increase, 0=decrease
                        mux(volume < lit(15, width: 4), volume + lit(1, width: 4), volume),
                        mux(volume > lit(0, width: 4), volume - lit(1, width: 4), volume)),
                    volume)

      # Trigger handling
      timer <= mux(trigger, cat(lit(0b1, width: 1), ~frequency), timer)
      volume <= mux(trigger, envelope[7..4], volume)
      envelope_timer <= mux(trigger, envelope[2..0], envelope_timer)
      length_counter <= mux(trigger & (length_counter == lit(0, width: 6)),
                            lit(64, width: 6),
                            length_counter)

      # Length load
      length_counter <= mux(ce & trigger,
                            lit(64, width: 6) - cat(lit(0, width: 2), length_duty[5..0]),
                            length_counter)
    end
  end
end
