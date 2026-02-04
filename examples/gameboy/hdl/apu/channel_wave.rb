# Game Boy Wave Channel (Channel 3)
# Corresponds to: parts of reference/rtl/gbc_snd.vhd
#
# Programmable wave channel with:
# - 32 4-bit samples in wave RAM (FF30-FF3F)
# - Selectable output volume (0%, 25%, 50%, 100%)
# - Length counter

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class ChannelWave < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :ce
    input :reset

    # Control registers
    input :dac_enable, width: 8   # NR30
    input :length_reg, width: 8   # NR31
    input :volume_reg, width: 8   # NR32
    input :freq_lo, width: 8      # NR33
    input :freq_hi, width: 8      # NR34

    # Frame sequencer (from APU)
    input :frame_seq, width: 3

    # Trigger
    input :trigger

    # Wave RAM interface
    input :wave_ram_data, width: 4
    output :wave_ram_addr, width: 5

    # Outputs
    output :output, width: 4
    output :enabled

    # Internal state
    wire :frequency, width: 11    # 11-bit frequency
    wire :timer, width: 12        # Frequency timer
    wire :position, width: 5      # Wave RAM position (0-31)
    wire :sample, width: 4        # Current sample
    wire :length_counter, width: 8 # Length counter (256 values)
    wire :volume_shift, width: 2  # Volume shift amount

    behavior do
      # Extract frequency from registers
      frequency <= cat(freq_hi[2..0], freq_lo)

      # Volume shift: 00=mute, 01=100%, 10=50%, 11=25%
      volume_shift <= volume_reg[6..5]

      # Wave RAM address
      wave_ram_addr <= position

      # Sample from wave RAM
      sample <= wave_ram_data

      # DAC enabled (bit 7 of NR30)
      dac_enabled = dac_enable[7]

      # Channel enabled
      enabled <= dac_enabled & (length_counter > lit(0, width: 8))

      # Apply volume (right shift)
      output <= mux(~enabled | (volume_shift == lit(0, width: 2)),
                    lit(0, width: 4),
                    case_select(volume_shift, {
                      1 => sample,
                      2 => sample >> lit(1, width: 4),
                      3 => sample >> lit(2, width: 4)
                    }, default: lit(0, width: 4)))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      timer: 0,
      position: 0,
      length_counter: 0
    } do
      # Frequency timer (wave channel timer = (2048 - freq) * 2)
      timer <= mux(ce,
                   mux(timer == lit(0, width: 12),
                       cat(lit(0b1, width: 1), ~frequency, lit(0, width: 1)),
                       timer - lit(1, width: 12)),
                   timer)

      # Advance position when timer expires
      position <= mux(ce & (timer == lit(0, width: 12)),
                      position + lit(1, width: 5),
                      position)

      # Length counter (clocked at 256Hz = frame_seq[0])
      length_counter <= mux(frame_seq == lit(0, width: 3) & freq_hi[6] &
                            (length_counter > lit(0, width: 8)),
                            length_counter - lit(1, width: 8),
                            length_counter)

      # Trigger handling
      timer <= mux(trigger, cat(lit(0b1, width: 1), ~frequency, lit(0, width: 1)), timer)
      position <= mux(trigger, lit(0, width: 5), position)
      length_counter <= mux(trigger & (length_counter == lit(0, width: 8)),
                            lit(256, width: 8),
                            length_counter)

      # Length load
      length_counter <= mux(ce & trigger,
                            lit(256, width: 8) - cat(lit(0, width: 0), length_reg),
                            length_counter)
    end
      end
    end
  end
end
