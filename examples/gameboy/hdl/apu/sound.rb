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

module RHDL
  module Examples
    module GameBoy
      class Sound < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :ce
        input :reset

        input :is_gbc
        input :remove_pops

        # CPU interface
        input :s1_read
        input :s1_write
        input :s1_addr, width: 7
        output :s1_readdata, width: 8
        input :s1_writedata, width: 8

        # Audio output (16-bit stereo)
        output :snd_left, width: 16
        output :snd_right, width: 16

        # Channel registers
        wire :nr10, width: 8
        wire :nr11, width: 8
        wire :nr12, width: 8
        wire :nr13, width: 8
        wire :nr14, width: 8

        wire :nr21, width: 8
        wire :nr22, width: 8
        wire :nr23, width: 8
        wire :nr24, width: 8

        wire :nr30, width: 8
        wire :nr31, width: 8
        wire :nr32, width: 8
        wire :nr33, width: 8
        wire :nr34, width: 8

        wire :nr41, width: 8
        wire :nr42, width: 8
        wire :nr43, width: 8
        wire :nr44, width: 8

        wire :nr50, width: 8
        wire :nr51, width: 8
        wire :nr52, width: 8

        # Channel outputs/status
        wire :ch1_out, width: 4
        wire :ch2_out, width: 4
        wire :ch3_out, width: 4
        wire :ch4_out, width: 4
        wire :ch1_on
        wire :ch2_on
        wire :ch3_on
        wire :ch4_on

        # Frame sequencer state
        wire :frame_seq, width: 3
        wire :frame_div, width: 14
        wire :en_len
        wire :en_env
        wire :en_sweep

        # Trigger delay bookkeeping
        wire :ch1_trigger
        wire :ch2_trigger
        wire :ch3_trigger
        wire :ch4_trigger
        wire :ch1_trigger_cnt, width: 3
        wire :ch2_trigger_cnt, width: 3
        wire :ch3_trigger_cnt, width: 3
        wire :ch4_trigger_cnt, width: 3

        # Length-quirk pulses (one-shot)
        wire :ch1_len_quirk
        wire :ch2_len_quirk
        wire :ch3_len_quirk
        wire :ch4_len_quirk

        # First-sample suppression state
        wire :ch1_suppressed
        wire :ch2_suppressed
        wire :ch3_suppressed
        wire :ch4_suppressed

        # DAC decay model used for remove_pops mode
        wire :ch1_dac, width: 8
        wire :ch2_dac, width: 8
        wire :ch3_dac, width: 8
        wire :ch4_dac, width: 8
        wire :ch1_decay, width: 7
        wire :ch2_decay, width: 7
        wire :ch3_decay, width: 7
        wire :ch4_decay, width: 7

        # Debug/event latches used by specs
        wire :zombie_sq1
        wire :zombie_sq2
        wire :zombie_noi

        # Minimal wave RAM plumbing (data source can be expanded later).
        wire :wave_ram_addr, width: 5
        wire :wave_ram_data, width: 4

        instance :channel1, ChannelSquare, has_sweep: true
        instance :channel2, ChannelSquare, has_sweep: false
        instance :channel3, ChannelWave
        instance :channel4, ChannelNoise

        # Shared clocks/reset
        port :clk => [[:channel1, :clk], [:channel2, :clk], [:channel3, :clk], [:channel4, :clk]]
        port :ce => [[:channel1, :ce], [:channel2, :ce], [:channel3, :ce], [:channel4, :ce]]
        port :reset => [[:channel1, :reset], [:channel2, :reset], [:channel3, :reset], [:channel4, :reset]]

        # Frame sequencer routing
        port :frame_seq => [[:channel1, :frame_seq], [:channel2, :frame_seq], [:channel3, :frame_seq], [:channel4, :frame_seq]]

        # Channel register routing
        port :nr10 => [:channel1, :sweep_reg]
        port :nr11 => [:channel1, :length_duty]
        port :nr12 => [:channel1, :envelope]
        port :nr13 => [:channel1, :freq_lo]
        port :nr14 => [:channel1, :freq_hi]
        port :ch1_trigger => [:channel1, :trigger]
        port :ch1_len_quirk => [:channel1, :len_quirk]

        port :nr10 => [:channel2, :sweep_reg]
        port :nr21 => [:channel2, :length_duty]
        port :nr22 => [:channel2, :envelope]
        port :nr23 => [:channel2, :freq_lo]
        port :nr24 => [:channel2, :freq_hi]
        port :ch2_trigger => [:channel2, :trigger]
        port :ch2_len_quirk => [:channel2, :len_quirk]

        port :nr30 => [:channel3, :dac_enable]
        port :nr31 => [:channel3, :length_reg]
        port :nr32 => [:channel3, :volume_reg]
        port :nr33 => [:channel3, :freq_lo]
        port :nr34 => [:channel3, :freq_hi]
        port :ch3_trigger => [:channel3, :trigger]
        port :ch3_len_quirk => [:channel3, :len_quirk]
        port :wave_ram_data => [:channel3, :wave_ram_data]
        port [:channel3, :wave_ram_addr] => :wave_ram_addr

        port :nr41 => [:channel4, :length_reg]
        port :nr42 => [:channel4, :envelope]
        port :nr43 => [:channel4, :poly_reg]
        port :nr44 => [:channel4, :control]
        port :ch4_trigger => [:channel4, :trigger]
        port :ch4_len_quirk => [:channel4, :len_quirk]

        # Channel output/status routing
        port [:channel1, :output] => :ch1_out
        port [:channel2, :output] => :ch2_out
        port [:channel3, :output] => :ch3_out
        port [:channel4, :output] => :ch4_out
        port [:channel1, :enabled] => :ch1_on
        port [:channel2, :enabled] => :ch2_on
        port [:channel3, :enabled] => :ch3_on
        port [:channel4, :enabled] => :ch4_on

        behavior do
          sound_on = nr52[7]
          wave_ram_data <= lit(0, width: 4)

          ch1_eff = mux(ch1_suppressed, lit(0, width: 4), ch1_out)
          ch2_eff = mux(ch2_suppressed, lit(0, width: 4), ch2_out)
          ch3_eff = mux(ch3_suppressed, lit(0, width: 4), ch3_out)
          ch4_eff = mux(ch4_suppressed, lit(0, width: 4), ch4_out)

          ch1_mix_src = mux(remove_pops, ch1_dac[7..4], ch1_eff)
          ch2_mix_src = mux(remove_pops, ch2_dac[7..4], ch2_eff)
          ch3_mix_src = mux(remove_pops, ch3_dac[7..4], ch3_eff)
          ch4_mix_src = mux(remove_pops, ch4_dac[7..4], ch4_eff)

          left_ch1 = mux(mux(remove_pops, nr51[4], nr51[4] & ch1_on), ch1_mix_src, lit(0, width: 4))
          left_ch2 = mux(mux(remove_pops, nr51[5], nr51[5] & ch2_on), ch2_mix_src, lit(0, width: 4))
          left_ch3 = mux(mux(remove_pops, nr51[6], nr51[6] & ch3_on), ch3_mix_src, lit(0, width: 4))
          left_ch4 = mux(mux(remove_pops, nr51[7], nr51[7] & ch4_on), ch4_mix_src, lit(0, width: 4))

          right_ch1 = mux(mux(remove_pops, nr51[0], nr51[0] & ch1_on), ch1_mix_src, lit(0, width: 4))
          right_ch2 = mux(mux(remove_pops, nr51[1], nr51[1] & ch2_on), ch2_mix_src, lit(0, width: 4))
          right_ch3 = mux(mux(remove_pops, nr51[2], nr51[2] & ch3_on), ch3_mix_src, lit(0, width: 4))
          right_ch4 = mux(mux(remove_pops, nr51[3], nr51[3] & ch4_on), ch4_mix_src, lit(0, width: 4))

          left_mix = cat(lit(0, width: 2), left_ch1) + cat(lit(0, width: 2), left_ch2) +
                     cat(lit(0, width: 2), left_ch3) + cat(lit(0, width: 2), left_ch4)
          right_mix = cat(lit(0, width: 2), right_ch1) + cat(lit(0, width: 2), right_ch2) +
                      cat(lit(0, width: 2), right_ch3) + cat(lit(0, width: 2), right_ch4)

          left_vol = nr50[6..4] + lit(1, width: 4)
          right_vol = nr50[2..0] + lit(1, width: 4)

          snd_left <= mux(sound_on,
                          cat(left_mix, lit(0, width: 10)) * cat(lit(0, width: 12), left_vol),
                          lit(0, width: 16))
          snd_right <= mux(sound_on,
                           cat(right_mix, lit(0, width: 10)) * cat(lit(0, width: 12), right_vol),
                           lit(0, width: 16))

          pcm12 = cat(mux(ch2_on, ch2_out, lit(0, width: 4)),
                      mux(ch1_on, ch1_out, lit(0, width: 4)))
          pcm34 = cat(mux(ch4_on, ch4_out, lit(0, width: 4)),
                      mux(ch3_on, ch3_out, lit(0, width: 4)))

          s1_readdata <= case_select(s1_addr, {
            0x00 => nr10 | lit(0x80, width: 8),
            0x01 => nr11 | lit(0x3F, width: 8),
            0x02 => nr12,
            0x03 => lit(0xFF, width: 8),
            0x04 => nr14 | lit(0xBF, width: 8),
            0x05 => lit(0xFF, width: 8),
            0x06 => nr21 | lit(0x3F, width: 8),
            0x07 => nr22,
            0x08 => lit(0xFF, width: 8),
            0x09 => nr24 | lit(0xBF, width: 8),
            0x0A => nr30 | lit(0x7F, width: 8),
            0x0B => lit(0xFF, width: 8),
            0x0C => nr32 | lit(0x9F, width: 8),
            0x0D => lit(0xFF, width: 8),
            0x0E => nr34 | lit(0xBF, width: 8),
            0x0F => lit(0xFF, width: 8),
            0x10 => lit(0xFF, width: 8),
            0x11 => nr42,
            0x12 => nr43,
            0x13 => nr44 | lit(0xBF, width: 8),
            0x14 => nr50,
            0x15 => nr51,
            0x16 => cat(nr52[7], lit(0b111, width: 3), ch4_on, ch3_on, ch2_on, ch1_on),
            0x76 => mux(is_gbc, pcm12, lit(0xFF, width: 8)),
            0x77 => mux(is_gbc, pcm34, lit(0xFF, width: 8))
          }, default: lit(0xFF, width: 8))
        end

        sequential clock: :clk, reset: :reset, reset_values: {
          nr10: 0x80, nr11: 0x3F, nr12: 0x00, nr13: 0x00, nr14: 0xBF,
          nr21: 0x3F, nr22: 0x00, nr23: 0x00, nr24: 0xBF,
          nr30: 0x7F, nr31: 0xFF, nr32: 0x9F, nr33: 0x00, nr34: 0xBF,
          nr41: 0xFF, nr42: 0x00, nr43: 0x00, nr44: 0xBF,
          nr50: 0x77, nr51: 0xF3, nr52: 0xF1,
          frame_seq: 0, frame_div: 0, en_len: 0, en_env: 0, en_sweep: 0,
          ch1_trigger: 0, ch2_trigger: 0, ch3_trigger: 0, ch4_trigger: 0,
          ch1_trigger_cnt: 0, ch2_trigger_cnt: 0, ch3_trigger_cnt: 0, ch4_trigger_cnt: 0,
          ch1_len_quirk: 0, ch2_len_quirk: 0, ch3_len_quirk: 0, ch4_len_quirk: 0,
          ch1_suppressed: 1, ch2_suppressed: 1, ch3_suppressed: 1, ch4_suppressed: 1,
          ch1_dac: 0, ch2_dac: 0, ch3_dac: 0, ch4_dac: 0,
          ch1_decay: 100, ch2_decay: 100, ch3_decay: 100, ch4_decay: 100,
          zombie_sq1: 0, zombie_sq2: 0, zombie_noi: 0
        } do
          wr_nr10 = ce & s1_write & nr52[7] & (s1_addr == lit(0x00, width: 7))
          wr_nr11 = ce & s1_write & nr52[7] & (s1_addr == lit(0x01, width: 7))
          wr_nr12 = ce & s1_write & nr52[7] & (s1_addr == lit(0x02, width: 7))
          wr_nr13 = ce & s1_write & nr52[7] & (s1_addr == lit(0x03, width: 7))
          wr_nr14 = ce & s1_write & nr52[7] & (s1_addr == lit(0x04, width: 7))

          wr_nr21 = ce & s1_write & nr52[7] & (s1_addr == lit(0x06, width: 7))
          wr_nr22 = ce & s1_write & nr52[7] & (s1_addr == lit(0x07, width: 7))
          wr_nr23 = ce & s1_write & nr52[7] & (s1_addr == lit(0x08, width: 7))
          wr_nr24 = ce & s1_write & nr52[7] & (s1_addr == lit(0x09, width: 7))

          wr_nr30 = ce & s1_write & nr52[7] & (s1_addr == lit(0x0A, width: 7))
          wr_nr31 = ce & s1_write & nr52[7] & (s1_addr == lit(0x0B, width: 7))
          wr_nr32 = ce & s1_write & nr52[7] & (s1_addr == lit(0x0C, width: 7))
          wr_nr33 = ce & s1_write & nr52[7] & (s1_addr == lit(0x0D, width: 7))
          wr_nr34 = ce & s1_write & nr52[7] & (s1_addr == lit(0x0E, width: 7))

          wr_nr41 = ce & s1_write & nr52[7] & (s1_addr == lit(0x10, width: 7))
          wr_nr42 = ce & s1_write & nr52[7] & (s1_addr == lit(0x11, width: 7))
          wr_nr43 = ce & s1_write & nr52[7] & (s1_addr == lit(0x12, width: 7))
          wr_nr44 = ce & s1_write & nr52[7] & (s1_addr == lit(0x13, width: 7))

          wr_nr50 = ce & s1_write & nr52[7] & (s1_addr == lit(0x14, width: 7))
          wr_nr51 = ce & s1_write & nr52[7] & (s1_addr == lit(0x15, width: 7))
          wr_nr52 = ce & s1_write & (s1_addr == lit(0x16, width: 7))

          power_off_event = wr_nr52 & ~s1_writedata[7]
          power_on_event = wr_nr52 & ~nr52[7] & s1_writedata[7]

          nr10 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr10, s1_writedata, nr10))
          nr11 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr11, s1_writedata, nr11))
          nr12 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr12, s1_writedata, nr12))
          nr13 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr13, s1_writedata, nr13))
          nr14 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr14, s1_writedata, nr14))

          nr21 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr21, s1_writedata, nr21))
          nr22 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr22, s1_writedata, nr22))
          nr23 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr23, s1_writedata, nr23))
          nr24 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr24, s1_writedata, nr24))

          nr30 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr30, s1_writedata, nr30))
          nr31 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr31, s1_writedata, nr31))
          nr32 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr32, s1_writedata, nr32))
          nr33 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr33, s1_writedata, nr33))
          nr34 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr34, s1_writedata, nr34))

          nr41 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr41, s1_writedata, nr41))
          nr42 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr42, s1_writedata, nr42))
          nr43 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr43, s1_writedata, nr43))
          nr44 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr44, s1_writedata, nr44))

          nr50 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr50, s1_writedata, nr50))
          nr51 <= mux(power_off_event, lit(0, width: 8), mux(wr_nr51, s1_writedata, nr51))
          nr52 <= mux(wr_nr52, cat(s1_writedata[7], lit(0, width: 7)), nr52)

          frame_wrap = ce & nr52[7] & (frame_div == lit(16383, width: 14))
          en_len <= mux(power_off_event,
                        lit(0, width: 1),
                        mux(frame_wrap & ((frame_seq == lit(0, width: 3)) |
                                          (frame_seq == lit(2, width: 3)) |
                                          (frame_seq == lit(4, width: 3)) |
                                          (frame_seq == lit(6, width: 3))),
                            lit(1, width: 1),
                            lit(0, width: 1)))
          en_sweep <= mux(power_off_event,
                          lit(0, width: 1),
                          mux(frame_wrap & ((frame_seq == lit(2, width: 3)) |
                                            (frame_seq == lit(6, width: 3))),
                              lit(1, width: 1),
                              lit(0, width: 1)))
          en_env <= mux(power_off_event,
                        lit(0, width: 1),
                        mux(frame_wrap & (frame_seq == lit(7, width: 3)),
                            lit(1, width: 1),
                            lit(0, width: 1)))

          frame_div_next = mux(ce & nr52[7],
                               mux(frame_wrap, lit(0, width: 14), frame_div + lit(1, width: 14)),
                               lit(0, width: 14))
          frame_seq_next = mux(ce & nr52[7],
                               mux(frame_wrap,
                                   mux(frame_seq == lit(7, width: 3), lit(0, width: 3), frame_seq + lit(1, width: 3)),
                                   frame_seq),
                               lit(0, width: 3))
          frame_div <= mux(power_off_event, lit(0, width: 14), frame_div_next)
          frame_seq <= mux(power_off_event, lit(0, width: 3), frame_seq_next)

          ch1_trigger <= mux(power_off_event, lit(0, width: 1),
                             mux(ce & (ch1_trigger_cnt == lit(1, width: 3)), lit(1, width: 1), lit(0, width: 1)))
          ch2_trigger <= mux(power_off_event, lit(0, width: 1),
                             mux(ce & (ch2_trigger_cnt == lit(1, width: 3)), lit(1, width: 1), lit(0, width: 1)))
          ch3_trigger <= mux(power_off_event, lit(0, width: 1),
                             mux(ce & (ch3_trigger_cnt == lit(1, width: 3)), lit(1, width: 1), lit(0, width: 1)))
          ch4_trigger <= mux(power_off_event, lit(0, width: 1),
                             mux(ce & (ch4_trigger_cnt == lit(1, width: 3)), lit(1, width: 1), lit(0, width: 1)))

          ch1_cnt_dec = mux(ce & (ch1_trigger_cnt > lit(0, width: 3)),
                            ch1_trigger_cnt - lit(1, width: 3),
                            ch1_trigger_cnt)
          ch2_cnt_dec = mux(ce & (ch2_trigger_cnt > lit(0, width: 3)),
                            ch2_trigger_cnt - lit(1, width: 3),
                            ch2_trigger_cnt)
          ch3_cnt_dec = mux(ce & (ch3_trigger_cnt > lit(0, width: 3)),
                            ch3_trigger_cnt - lit(1, width: 3),
                            ch3_trigger_cnt)
          ch4_cnt_dec = mux(ce & (ch4_trigger_cnt > lit(0, width: 3)),
                            ch4_trigger_cnt - lit(1, width: 3),
                            ch4_trigger_cnt)

          ch1_trigger_cnt <= mux(power_off_event,
                                 lit(0, width: 3),
                                 mux(wr_nr14 & s1_writedata[7],
                                     mux(ch1_on, lit(2, width: 3), lit(4, width: 3)),
                                     ch1_cnt_dec))
          ch2_trigger_cnt <= mux(power_off_event,
                                 lit(0, width: 3),
                                 mux(wr_nr24 & s1_writedata[7],
                                     mux(ch2_on, lit(2, width: 3), lit(4, width: 3)),
                                     ch2_cnt_dec))
          ch3_trigger_cnt <= mux(power_off_event,
                                 lit(0, width: 3),
                                 mux(wr_nr34 & s1_writedata[7],
                                     lit(2, width: 3),
                                     ch3_cnt_dec))
          ch4_trigger_cnt <= mux(power_off_event,
                                 lit(0, width: 3),
                                 mux(wr_nr44 & s1_writedata[7],
                                     mux(ch4_on, lit(4, width: 3), lit(2, width: 3)),
                                     ch4_cnt_dec))

          ch1_len_quirk <= mux(power_off_event, lit(0, width: 1),
                               mux(wr_nr14 & ~nr14[6] & s1_writedata[6] & frame_seq[0], lit(1, width: 1), lit(0, width: 1)))
          ch2_len_quirk <= mux(power_off_event, lit(0, width: 1),
                               mux(wr_nr24 & ~nr24[6] & s1_writedata[6] & frame_seq[0], lit(1, width: 1), lit(0, width: 1)))
          ch3_len_quirk <= mux(power_off_event, lit(0, width: 1),
                               mux(wr_nr34 & ~nr34[6] & s1_writedata[6] & frame_seq[0], lit(1, width: 1), lit(0, width: 1)))
          ch4_len_quirk <= mux(power_off_event, lit(0, width: 1),
                               mux(wr_nr44 & ~nr44[6] & s1_writedata[6] & frame_seq[0], lit(1, width: 1), lit(0, width: 1)))

          zombie_sq1 <= mux(wr_nr12 & ch1_on, lit(1, width: 1), lit(0, width: 1))
          zombie_sq2 <= mux(wr_nr22 & ch2_on, lit(1, width: 1), lit(0, width: 1))
          zombie_noi <= mux(wr_nr42 & ch4_on, lit(1, width: 1), lit(0, width: 1))

          ch1_set = power_off_event | power_on_event | (ce & (ch1_trigger_cnt == lit(1, width: 3)) & ~ch1_on)
          ch2_set = power_off_event | power_on_event | (ce & (ch2_trigger_cnt == lit(1, width: 3)) & ~ch2_on)
          ch3_set = power_off_event | power_on_event | (ce & (ch3_trigger_cnt == lit(1, width: 3)) & ~ch3_on)
          ch4_set = power_off_event | power_on_event | (ce & (ch4_trigger_cnt == lit(1, width: 3)) & ~ch4_on)
          ch1_clear = ce & ch1_suppressed & (ch1_out != lit(0, width: 4))
          ch2_clear = ce & ch2_suppressed & (ch2_out != lit(0, width: 4))
          ch3_clear = ce & ch3_suppressed & (ch3_out != lit(0, width: 4))
          ch4_clear = ce & ch4_suppressed & (ch4_out != lit(0, width: 4))

          ch1_suppressed <= mux(ch1_set, lit(1, width: 1), mux(ch1_clear, lit(0, width: 1), ch1_suppressed))
          ch2_suppressed <= mux(ch2_set, lit(1, width: 1), mux(ch2_clear, lit(0, width: 1), ch2_suppressed))
          ch3_suppressed <= mux(ch3_set, lit(1, width: 1), mux(ch3_clear, lit(0, width: 1), ch3_suppressed))
          ch4_suppressed <= mux(ch4_set, lit(1, width: 1), mux(ch4_clear, lit(0, width: 1), ch4_suppressed))

          ch1_decay <= mux(power_off_event,
                           lit(100, width: 7),
                           mux(ce & ((nr12[7..4] != lit(0, width: 4)) | nr12[3]),
                               lit(100, width: 7),
                               mux(ce & (ch1_decay > lit(0, width: 7)),
                                   ch1_decay - lit(1, width: 7),
                                   mux(ce, lit(100, width: 7), ch1_decay))))
          ch2_decay <= mux(power_off_event,
                           lit(100, width: 7),
                           mux(ce & ((nr22[7..4] != lit(0, width: 4)) | nr22[3]),
                               lit(100, width: 7),
                               mux(ce & (ch2_decay > lit(0, width: 7)),
                                   ch2_decay - lit(1, width: 7),
                                   mux(ce, lit(100, width: 7), ch2_decay))))
          ch3_decay <= mux(power_off_event,
                           lit(100, width: 7),
                           mux(ce & nr30[7],
                               lit(100, width: 7),
                               mux(ce & (ch3_decay > lit(0, width: 7)),
                                   ch3_decay - lit(1, width: 7),
                                   mux(ce, lit(100, width: 7), ch3_decay))))
          ch4_decay <= mux(power_off_event,
                           lit(100, width: 7),
                           mux(ce & ((nr42[7..4] != lit(0, width: 4)) | nr42[3]),
                               lit(100, width: 7),
                               mux(ce & (ch4_decay > lit(0, width: 7)),
                                   ch4_decay - lit(1, width: 7),
                                   mux(ce, lit(100, width: 7), ch4_decay))))

          ch1_dac <= mux(power_off_event,
                         lit(0, width: 8),
                         mux(ce & ((nr12[7..4] != lit(0, width: 4)) | nr12[3]),
                             cat(ch1_out, lit(0, width: 4)),
                             mux(ce & (ch1_decay == lit(0, width: 7)) & (ch1_dac > lit(0, width: 8)),
                                 ch1_dac - lit(1, width: 8),
                                 ch1_dac)))
          ch2_dac <= mux(power_off_event,
                         lit(0, width: 8),
                         mux(ce & ((nr22[7..4] != lit(0, width: 4)) | nr22[3]),
                             cat(ch2_out, lit(0, width: 4)),
                             mux(ce & (ch2_decay == lit(0, width: 7)) & (ch2_dac > lit(0, width: 8)),
                                 ch2_dac - lit(1, width: 8),
                                 ch2_dac)))
          ch3_dac <= mux(power_off_event,
                         lit(0, width: 8),
                         mux(ce & nr30[7],
                             cat(ch3_out, lit(0, width: 4)),
                             mux(ce & (ch3_decay == lit(0, width: 7)) & (ch3_dac > lit(0, width: 8)),
                                 ch3_dac - lit(1, width: 8),
                                 ch3_dac)))
          ch4_dac <= mux(power_off_event,
                         lit(0, width: 8),
                         mux(ce & ((nr42[7..4] != lit(0, width: 4)) | nr42[3]),
                             cat(ch4_out, lit(0, width: 4)),
                             mux(ce & (ch4_decay == lit(0, width: 7)) & (ch4_dac > lit(0, width: 8)),
                                 ch4_dac - lit(1, width: 8),
                                 ch4_dac)))
        end
      end
    end
  end
end
