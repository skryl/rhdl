# Game Boy APU (Audio Processing Unit)
# Corresponds to: reference/rtl/gbc_snd.vhd
#
# The APU contains 4 sound channels:
# - Channel 1: Square wave with sweep
# - Channel 2: Square wave
# - Channel 3: Programmable wave
# - Channel 4: Noise
#
# Audio registers: FF10-FF3F
# - FF10-FF14: Channel 1 (Sweep/Square)
# - FF15-FF19: Channel 2 (Square) - FF15 unused
# - FF1A-FF1E: Channel 3 (Wave)
# - FF1F-FF23: Channel 4 (Noise) - FF1F unused
# - FF24: Master volume
# - FF25: Channel panning
# - FF26: Sound on/off
# - FF30-FF3F: Wave pattern RAM

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module GameBoy
  class Sound < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :ce              # 8MHz clock enable (for GBC double speed)
    input :reset

    input :is_gbc          # Game Boy Color mode
    input :remove_pops     # Anti-pop filter enable

    # CPU interface
    input :s1_read
    input :s1_write
    input :s1_addr, width: 7     # Address (00-3F maps to FF10-FF3F)
    output :s1_readdata, width: 8
    input :s1_writedata, width: 8

    # Audio output (16-bit signed stereo)
    output :snd_left, width: 16
    output :snd_right, width: 16

    # Internal registers
    # NR10-NR14 (Channel 1 - Sweep/Square)
    wire :nr10, width: 8   # Sweep
    wire :nr11, width: 8   # Length/Duty
    wire :nr12, width: 8   # Envelope
    wire :nr13, width: 8   # Frequency low
    wire :nr14, width: 8   # Frequency high / Control

    # NR21-NR24 (Channel 2 - Square)
    wire :nr21, width: 8   # Length/Duty
    wire :nr22, width: 8   # Envelope
    wire :nr23, width: 8   # Frequency low
    wire :nr24, width: 8   # Frequency high / Control

    # NR30-NR34 (Channel 3 - Wave)
    wire :nr30, width: 8   # DAC enable
    wire :nr31, width: 8   # Length
    wire :nr32, width: 8   # Volume
    wire :nr33, width: 8   # Frequency low
    wire :nr34, width: 8   # Frequency high / Control

    # NR41-NR44 (Channel 4 - Noise)
    wire :nr41, width: 8   # Length
    wire :nr42, width: 8   # Envelope
    wire :nr43, width: 8   # Polynomial counter
    wire :nr44, width: 8   # Control

    # NR50-NR52 (Master control)
    wire :nr50, width: 8   # Master volume
    wire :nr51, width: 8   # Channel panning
    wire :nr52, width: 8   # Sound on/off

    # Channel outputs (4-bit each)
    wire :ch1_out, width: 4
    wire :ch2_out, width: 4
    wire :ch3_out, width: 4
    wire :ch4_out, width: 4

    # Frame sequencer (512Hz)
    wire :frame_seq, width: 3
    wire :frame_seq_clk

    # Channel enable flags
    wire :ch1_on
    wire :ch2_on
    wire :ch3_on
    wire :ch4_on

    # Sub-component instances
    instance :channel1, ChannelSquare, has_sweep: true
    instance :channel2, ChannelSquare, has_sweep: false
    instance :channel3, ChannelWave
    instance :channel4, ChannelNoise

    # Clock distribution
    port :clk => [[:channel1, :clk], [:channel2, :clk], [:channel3, :clk], [:channel4, :clk]]
    port :ce => [[:channel1, :ce], [:channel2, :ce], [:channel3, :ce], [:channel4, :ce]]

    # Frame sequencer to channels
    port :frame_seq => [[:channel1, :frame_seq], [:channel2, :frame_seq],
                        [:channel3, :frame_seq], [:channel4, :frame_seq]]

    # Channel outputs
    port [:channel1, :output] => :ch1_out
    port [:channel2, :output] => :ch2_out
    port [:channel3, :output] => :ch3_out
    port [:channel4, :output] => :ch4_out

    # Channel status
    port [:channel1, :enabled] => :ch1_on
    port [:channel2, :enabled] => :ch2_on
    port [:channel3, :enabled] => :ch3_on
    port [:channel4, :enabled] => :ch4_on

    behavior do
      # Sound master on/off
      sound_on = nr52[7]

      # Calculate left/right mix
      # Each channel can be routed to L/R independently via NR51
      left_ch1 = mux(nr51[4] & ch1_on, ch1_out, lit(0, width: 4))
      left_ch2 = mux(nr51[5] & ch2_on, ch2_out, lit(0, width: 4))
      left_ch3 = mux(nr51[6] & ch3_on, ch3_out, lit(0, width: 4))
      left_ch4 = mux(nr51[7] & ch4_on, ch4_out, lit(0, width: 4))

      right_ch1 = mux(nr51[0] & ch1_on, ch1_out, lit(0, width: 4))
      right_ch2 = mux(nr51[1] & ch2_on, ch2_out, lit(0, width: 4))
      right_ch3 = mux(nr51[2] & ch3_on, ch3_out, lit(0, width: 4))
      right_ch4 = mux(nr51[3] & ch4_on, ch4_out, lit(0, width: 4))

      # Mix channels (simple sum, could overflow - reference uses DAC model)
      left_mix = cat(lit(0, width: 2), left_ch1) + cat(lit(0, width: 2), left_ch2) +
                 cat(lit(0, width: 2), left_ch3) + cat(lit(0, width: 2), left_ch4)
      right_mix = cat(lit(0, width: 2), right_ch1) + cat(lit(0, width: 2), right_ch2) +
                  cat(lit(0, width: 2), right_ch3) + cat(lit(0, width: 2), right_ch4)

      # Apply master volume (NR50 bits 6-4 left, 2-0 right)
      left_vol = nr50[6..4] + lit(1, width: 4)
      right_vol = nr50[2..0] + lit(1, width: 4)

      # Scale to 16-bit output
      snd_left <= mux(sound_on,
                      cat(left_mix, lit(0, width: 10)) * cat(lit(0, width: 12), left_vol),
                      lit(0, width: 16))
      snd_right <= mux(sound_on,
                       cat(right_mix, lit(0, width: 10)) * cat(lit(0, width: 12), right_vol),
                       lit(0, width: 16))

      # CPU read data
      s1_readdata <= case_select(s1_addr, {
        0x00 => nr10 | lit(0x80, width: 8),
        0x01 => nr11 | lit(0x3F, width: 8),
        0x02 => nr12,
        0x03 => lit(0xFF, width: 8),  # NR13 write-only
        0x04 => nr14 | lit(0xBF, width: 8),
        0x05 => lit(0xFF, width: 8),  # Unused
        0x06 => nr21 | lit(0x3F, width: 8),
        0x07 => nr22,
        0x08 => lit(0xFF, width: 8),  # NR23 write-only
        0x09 => nr24 | lit(0xBF, width: 8),
        0x0A => nr30 | lit(0x7F, width: 8),
        0x0B => lit(0xFF, width: 8),  # NR31 write-only
        0x0C => nr32 | lit(0x9F, width: 8),
        0x0D => lit(0xFF, width: 8),  # NR33 write-only
        0x0E => nr34 | lit(0xBF, width: 8),
        0x0F => lit(0xFF, width: 8),  # Unused
        0x10 => lit(0xFF, width: 8),  # NR41 write-only
        0x11 => nr42,
        0x12 => nr43,
        0x13 => nr44 | lit(0xBF, width: 8),
        0x14 => nr50,
        0x15 => nr51,
        0x16 => cat(nr52[7], lit(0b0111, width: 4), ch4_on, ch3_on, ch2_on, ch1_on)
      }, default: lit(0xFF, width: 8))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      nr10: 0x80, nr11: 0x3F, nr12: 0x00, nr13: 0x00, nr14: 0xBF,
      nr21: 0x3F, nr22: 0x00, nr23: 0x00, nr24: 0xBF,
      nr30: 0x7F, nr31: 0xFF, nr32: 0x9F, nr33: 0x00, nr34: 0xBF,
      nr41: 0xFF, nr42: 0x00, nr43: 0x00, nr44: 0xBF,
      nr50: 0x77, nr51: 0xF3, nr52: 0xF1,
      frame_seq: 0
    } do
      # Frame sequencer (512Hz from 4MHz / 8192)
      # Steps through 0-7, triggering various events:
      # 0: Length
      # 2: Length, Sweep
      # 4: Length
      # 6: Length, Sweep
      # 7: Envelope

      # Register writes
      nr10 <= mux(ce & s1_write & (s1_addr == lit(0x00, width: 7)) & nr52[7],
                  s1_writedata, nr10)
      nr11 <= mux(ce & s1_write & (s1_addr == lit(0x01, width: 7)) & nr52[7],
                  s1_writedata, nr11)
      nr12 <= mux(ce & s1_write & (s1_addr == lit(0x02, width: 7)) & nr52[7],
                  s1_writedata, nr12)
      nr13 <= mux(ce & s1_write & (s1_addr == lit(0x03, width: 7)) & nr52[7],
                  s1_writedata, nr13)
      nr14 <= mux(ce & s1_write & (s1_addr == lit(0x04, width: 7)) & nr52[7],
                  s1_writedata, nr14)

      nr21 <= mux(ce & s1_write & (s1_addr == lit(0x06, width: 7)) & nr52[7],
                  s1_writedata, nr21)
      nr22 <= mux(ce & s1_write & (s1_addr == lit(0x07, width: 7)) & nr52[7],
                  s1_writedata, nr22)
      nr23 <= mux(ce & s1_write & (s1_addr == lit(0x08, width: 7)) & nr52[7],
                  s1_writedata, nr23)
      nr24 <= mux(ce & s1_write & (s1_addr == lit(0x09, width: 7)) & nr52[7],
                  s1_writedata, nr24)

      nr30 <= mux(ce & s1_write & (s1_addr == lit(0x0A, width: 7)) & nr52[7],
                  s1_writedata, nr30)
      nr31 <= mux(ce & s1_write & (s1_addr == lit(0x0B, width: 7)) & nr52[7],
                  s1_writedata, nr31)
      nr32 <= mux(ce & s1_write & (s1_addr == lit(0x0C, width: 7)) & nr52[7],
                  s1_writedata, nr32)
      nr33 <= mux(ce & s1_write & (s1_addr == lit(0x0D, width: 7)) & nr52[7],
                  s1_writedata, nr33)
      nr34 <= mux(ce & s1_write & (s1_addr == lit(0x0E, width: 7)) & nr52[7],
                  s1_writedata, nr34)

      nr41 <= mux(ce & s1_write & (s1_addr == lit(0x10, width: 7)) & nr52[7],
                  s1_writedata, nr41)
      nr42 <= mux(ce & s1_write & (s1_addr == lit(0x11, width: 7)) & nr52[7],
                  s1_writedata, nr42)
      nr43 <= mux(ce & s1_write & (s1_addr == lit(0x12, width: 7)) & nr52[7],
                  s1_writedata, nr43)
      nr44 <= mux(ce & s1_write & (s1_addr == lit(0x13, width: 7)) & nr52[7],
                  s1_writedata, nr44)

      nr50 <= mux(ce & s1_write & (s1_addr == lit(0x14, width: 7)) & nr52[7],
                  s1_writedata, nr50)
      nr51 <= mux(ce & s1_write & (s1_addr == lit(0x15, width: 7)) & nr52[7],
                  s1_writedata, nr51)
      nr52 <= mux(ce & s1_write & (s1_addr == lit(0x16, width: 7)),
                  cat(s1_writedata[7], lit(0, width: 7)),  # Only bit 7 writable
                  nr52)
    end
  end
end
