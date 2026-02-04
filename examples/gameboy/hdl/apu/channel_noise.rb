# Game Boy Noise Channel (Channel 4)
# Corresponds to: parts of reference/rtl/gbc_snd.vhd
#
# Noise channel with:
# - LFSR (Linear Feedback Shift Register) noise generator
# - 7-bit or 15-bit LFSR width
# - Volume envelope
# - Length counter

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class ChannelNoise < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :ce
    input :reset

    # Control registers
    input :length_reg, width: 8   # NR41
    input :envelope, width: 8     # NR42
    input :poly_reg, width: 8     # NR43
    input :control, width: 8      # NR44

    # Frame sequencer (from APU)
    input :frame_seq, width: 3

    # Trigger
    input :trigger

    # Outputs
    output :output, width: 4
    output :enabled

    # Internal state
    wire :timer, width: 16        # Frequency timer
    wire :lfsr, width: 15         # Linear Feedback Shift Register
    wire :volume, width: 4        # Current volume
    wire :length_counter, width: 6 # Length counter
    wire :envelope_timer, width: 3 # Envelope timer
    wire :width_mode              # LFSR width: 0=15-bit, 1=7-bit

    # Divisor table for noise frequency
    wire :divisor, width: 4

    behavior do
      # Extract LFSR width mode (bit 3 of NR43)
      width_mode <= poly_reg[3]

      # Divisor selection based on NR43 bits 2-0
      divisor <= case_select(poly_reg[2..0], {
        0 => lit(8, width: 4),
        1 => lit(16, width: 4),
        2 => lit(32, width: 4),
        3 => lit(48, width: 4),
        4 => lit(64, width: 4),
        5 => lit(80, width: 4),
        6 => lit(96, width: 4),
        7 => lit(112, width: 4)
      }, default: lit(8, width: 4))

      # DAC enabled if envelope start volume != 0 or envelope add mode
      dac_enabled = (envelope[7..4] != lit(0, width: 4)) | envelope[3]

      # Channel enabled
      enabled <= dac_enabled & (length_counter > lit(0, width: 6))

      # Output (inverted bit 0 of LFSR)
      # When LFSR bit 0 is low, output is volume; when high, output is 0
      output <= mux(enabled & ~lfsr[0], volume, lit(0, width: 4))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      timer: 0,
      lfsr: 0x7FFF,  # All 1s
      volume: 0,
      length_counter: 0,
      envelope_timer: 0
    } do
      # Frequency timer
      # Timer = divisor << clock_shift, where clock_shift = NR43 bits 7-4
      timer <= mux(ce,
                   mux(timer == lit(0, width: 16),
                       cat(divisor, lit(0, width: 12)) << poly_reg[7..4],
                       timer - lit(1, width: 16)),
                   timer)

      # LFSR update when timer expires
      # New bit = XOR of bits 0 and 1
      # In 7-bit mode, also copy to bit 6
      new_bit = lfsr[0] ^ lfsr[1]
      lfsr <= mux(ce & (timer == lit(0, width: 16)),
                  mux(width_mode,
                      # 7-bit mode: shift right, new bit goes to bit 14 and bit 6
                      cat(new_bit, lfsr[14..7], new_bit, lfsr[5..1]),
                      # 15-bit mode: shift right, new bit goes to bit 14
                      cat(new_bit, lfsr[14..1])),
                  lfsr)

      # Length counter (clocked at 256Hz = frame_seq[0])
      length_counter <= mux(frame_seq == lit(0, width: 3) & control[6] &
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
      timer <= mux(trigger, cat(divisor, lit(0, width: 12)) << poly_reg[7..4], timer)
      lfsr <= mux(trigger, lit(0x7FFF, width: 15), lfsr)
      volume <= mux(trigger, envelope[7..4], volume)
      envelope_timer <= mux(trigger, envelope[2..0], envelope_timer)
      length_counter <= mux(trigger & (length_counter == lit(0, width: 6)),
                            lit(64, width: 6),
                            length_counter)

      # Length load
      length_counter <= mux(ce & trigger,
                            lit(64, width: 6) - cat(lit(0, width: 2), length_reg[5..0]),
                            length_counter)
    end
      end
    end
  end
end
