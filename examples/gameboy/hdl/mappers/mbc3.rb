# MBC3 Memory Bank Controller with RTC
# Corresponds to: reference/rtl/mappers/mbc3.v
#
# MBC3 supports:
# - Up to 2MB ROM (128 banks, MBC30: 256 banks)
# - Up to 32KB RAM (4 banks)
# - Real Time Clock (RTC)
# - RTC timestamp/save-state plumbing used by MiSTer-style integrations

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class MBC3 < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :ce
        input :reset
        input :enable

        # MBC30 mode (extended ROM)
        input :mbc30

        # CPU/cart-side interface (simplified)
        input :cpu_addr, width: 16
        input :cpu_di, width: 8
        input :cpu_wr
        input :cpu_rd
        input :cram_di, width: 8

        # RTC clock (32.768 kHz)
        input :ce_32k

        # Host-side RTC sync
        input :rtc_time, width: 33

        # RTC backup restore interface
        input :bk_rtc_wr
        input :bk_addr, width: 17
        input :bk_data, width: 16

        # Savestate plumbing
        input :savestate_load
        input :savestate_data, width: 16

        # Cart size info
        input :rom_mask, width: 8
        input :ram_mask, width: 3
        input :has_ram

        # Cart type for battery detection
        input :cart_mbc_type, width: 8

        # Outputs
        output :rom_bank, width: 8
        output :ram_bank, width: 3
        output :ram_enable
        output :has_battery
        output :rtc_mode
        output :cram_do, width: 8
        output :cart_oe
        output :savestate_back, width: 16

        # RTC outputs
        output :rtc_seconds, width: 6
        output :rtc_minutes, width: 6
        output :rtc_hours, width: 5
        output :rtc_days, width: 9
        output :rtc_halt
        output :rtc_overflow
        output :rtc_timestamp_out, width: 32
        output :rtc_savedtime_out, width: 48
        output :rtc_inuse

        # Internal registers
        wire :ram_en
        wire :rom_bank_reg, width: 8
        wire :ram_bank_reg, width: 3
        wire :mode
        wire :rtc_index, width: 3

        # RTC internal state
        wire :rtc_subseconds, width: 16
        wire :rtc_secs, width: 6
        wire :rtc_mins, width: 6
        wire :rtc_hrs, width: 5
        wire :rtc_dys, width: 10
        wire :rtc_hlt
        wire :rtc_ovf
        wire :rtc_change
        wire :diff_seconds, width: 32

        # RTC latch registers
        wire :rtc_latch
        wire :rtc_seconds_latch, width: 6
        wire :rtc_minutes_latch, width: 6
        wire :rtc_hours_latch, width: 5
        wire :rtc_days_latch, width: 10
        wire :rtc_halt_latch
        wire :rtc_overflow_latch

        # Host sync / persistence state
        wire :rtc_timestamp, width: 32
        wire :rtc_timestamp_saved, width: 32
        wire :rtc_savedtime_in, width: 32
        wire :rtc_savedtime_out_reg, width: 48
        wire :rtc_timestamp_new_1
        wire :rtc_inuse_reg

        behavior do
          # RTC mode output
          rtc_mode <= mode

          # RAM enable output (only when not in RTC mode and has RAM)
          ram_enable <= ram_en & ~mode & has_ram

          # ROM bank calculation - bank 0 maps to 1
          effective_rom_bank = mux(rom_bank_reg == lit(0, width: 8),
                                   lit(1, width: 8),
                                   rom_bank_reg)
          rom_bank <= effective_rom_bank & rom_mask

          # RAM bank with mask
          ram_bank <= ram_bank_reg & ram_mask

          # Latched RTC read mux used for RTC-mode RAM reads.
          rtc_return = mux(rtc_index == lit(0, width: 3),
                           rtc_seconds_latch,
                       mux(rtc_index == lit(1, width: 3),
                           rtc_minutes_latch,
                       mux(rtc_index == lit(2, width: 3),
                           rtc_hours_latch,
                       mux(rtc_index == lit(3, width: 3),
                           rtc_days_latch[7..0],
                       mux(rtc_index == lit(4, width: 3),
                           cat(rtc_overflow_latch, rtc_halt_latch, lit(0, width: 5), rtc_days_latch[8]),
                           lit(0xFF, width: 8))))))

          # Cart RAM/RTC data-out behavior.
          cram_do <= mux(ram_en,
                         mux(mode, rtc_return, mux(has_ram, cram_di, lit(0xFF, width: 8))),
                         lit(0xFF, width: 8))

          # cart_oe follows ROM reads or enabled RAM/RTC reads.
          rom_access = ~cpu_addr[15]
          cram_access = cpu_addr[15..13] == lit(5, width: 3) # A000-BFFF
          cart_oe <= cpu_rd & (rom_access | (cram_access & ram_en & (mode | has_ram)))

          # RTC outputs (latched values)
          rtc_seconds <= rtc_seconds_latch
          rtc_minutes <= rtc_minutes_latch
          rtc_hours <= rtc_hours_latch
          rtc_days <= rtc_days_latch[8..0]
          rtc_halt <= rtc_halt_latch
          rtc_overflow <= rtc_overflow_latch

          # Has battery if type 0x0F, 0x10, or 0x13
          has_battery <= (cart_mbc_type == lit(0x0F, width: 8)) |
                         (cart_mbc_type == lit(0x10, width: 8)) |
                         (cart_mbc_type == lit(0x13, width: 8))

          # Savestate packing mirrors reference bit layout.
          savestate_back <= cat(ram_en, mode, lit(0, width: 2), ram_bank_reg, lit(0, width: 1), rom_bank_reg)

          rtc_timestamp_out <= rtc_timestamp
          rtc_savedtime_out <= rtc_savedtime_out_reg
          rtc_inuse <= rtc_inuse_reg
        end

        sequential clock: :clk, reset: :reset, reset_values: {
          ram_en: 0,
          rom_bank_reg: 1,
          ram_bank_reg: 0,
          mode: 0,
          rtc_index: 0,
          rtc_subseconds: 0,
          rtc_secs: 0,
          rtc_mins: 0,
          rtc_hrs: 0,
          rtc_dys: 0,
          rtc_hlt: 0,
          rtc_ovf: 0,
          rtc_change: 0,
          diff_seconds: 0,
          rtc_latch: 0,
          rtc_seconds_latch: 0,
          rtc_minutes_latch: 0,
          rtc_hours_latch: 0,
          rtc_days_latch: 0,
          rtc_halt_latch: 0,
          rtc_overflow_latch: 0,
          rtc_timestamp: 0,
          rtc_timestamp_saved: 0,
          rtc_savedtime_in: 0,
          rtc_savedtime_out_reg: 0,
          rtc_timestamp_new_1: 0,
          rtc_inuse_reg: 0
        } do
          write_cycle = enable & ce & cpu_wr
          wr_region_0 = write_cycle & (cpu_addr[15..13] == lit(0, width: 3))
          wr_region_1 = write_cycle & (cpu_addr[15..13] == lit(1, width: 3))
          wr_region_2 = write_cycle & (cpu_addr[15..13] == lit(2, width: 3))
          wr_region_3 = write_cycle & (cpu_addr[15..13] == lit(3, width: 3))
          wr_rtc_reg = write_cycle & (cpu_addr[15..13] == lit(5, width: 3)) & mode

          # RTC timestamp host sync edge and backup-load trigger.
          rtc_time_edge = enable & (rtc_time[32] != rtc_timestamp_new_1)
          load_from_backup = enable & bk_rtc_wr & (bk_addr[7..0] == lit(4, width: 8))

          # RTC 32k divider.
          rtc_subseconds_end = rtc_subseconds >= lit(32767, width: 16)
          second_tick = enable & ce_32k & rtc_subseconds_end & ~rtc_hlt

          rtc_subseconds <= mux(enable & ce_32k & ~rtc_hlt,
                                mux(rtc_subseconds_end, lit(0, width: 16), rtc_subseconds + lit(1, width: 16)),
                                rtc_subseconds)

          # Fast-forward loaded save timestamps when host time is ahead.
          diff_fast_count = enable & (diff_seconds > lit(0, width: 32)) & ~rtc_change
          second_or_fast = second_tick | diff_fast_count

          # Track RTC changes to rate-limit saved-state packing.
          rtc_change <= mux(second_or_fast & ~rtc_hlt, lit(1, width: 1), lit(0, width: 1))

          # Core RTC counters
          rtc_secs <= mux(load_from_backup, rtc_savedtime_in[5..0],
                      mux(wr_rtc_reg & (rtc_index == lit(0, width: 3)),
                          cpu_di[5..0],
                      mux(second_or_fast & ~rtc_hlt,
                          mux(rtc_secs == lit(59, width: 6), lit(0, width: 6), rtc_secs + lit(1, width: 6)),
                          rtc_secs)))

          minute_tick = second_or_fast & ~rtc_hlt & (rtc_secs == lit(59, width: 6))
          rtc_mins <= mux(load_from_backup, rtc_savedtime_in[11..6],
                      mux(wr_rtc_reg & (rtc_index == lit(1, width: 3)),
                          cpu_di[5..0],
                      mux(minute_tick,
                          mux(rtc_mins == lit(59, width: 6), lit(0, width: 6), rtc_mins + lit(1, width: 6)),
                          rtc_mins)))

          hour_tick = minute_tick & (rtc_mins == lit(59, width: 6))
          rtc_hrs <= mux(load_from_backup, rtc_savedtime_in[16..12],
                     mux(wr_rtc_reg & (rtc_index == lit(2, width: 3)),
                         cpu_di[4..0],
                     mux(hour_tick,
                         mux(rtc_hrs == lit(23, width: 5), lit(0, width: 5), rtc_hrs + lit(1, width: 5)),
                         rtc_hrs)))

          day_tick = hour_tick & (rtc_hrs == lit(23, width: 5))
          rtc_dys <= mux(load_from_backup, rtc_savedtime_in[26..17],
                     mux(wr_rtc_reg & (rtc_index == lit(3, width: 3)),
                         cat(rtc_dys[9], cpu_di),
                     mux(wr_rtc_reg & (rtc_index == lit(4, width: 3)),
                         cat(cpu_di[0], rtc_dys[7..0]),
                     mux(day_tick,
                         mux(rtc_dys == lit(511, width: 10), lit(0, width: 10), rtc_dys + lit(1, width: 10)),
                         rtc_dys))))

          rtc_hlt <= mux(load_from_backup, rtc_savedtime_in[28],
                     mux(wr_rtc_reg & (rtc_index == lit(4, width: 3)), cpu_di[6], rtc_hlt))

          rtc_ovf <= mux(load_from_backup, rtc_savedtime_in[27],
                     mux(wr_rtc_reg & (rtc_index == lit(4, width: 3)), cpu_di[7],
                     mux(day_tick & (rtc_dys == lit(511, width: 10)), lit(1, width: 1), rtc_ovf)))

          # RAM Enable (0x0000-0x1FFF)
          ram_en <= mux(~enable, lit(0, width: 1),
                    mux(savestate_load & enable, savestate_data[15],
                    mux(wr_region_0, cpu_di[3..0] == lit(0x0A, width: 4), ram_en)))

          # ROM Bank Number (0x2000-0x3FFF)
          new_rom_bank = mux(mbc30, cpu_di, cat(lit(0, width: 1), cpu_di[6..0]))
          new_rom_bank_adjusted = mux(new_rom_bank == lit(0, width: 8), lit(1, width: 8), new_rom_bank)
          rom_bank_reg <= mux(~enable, lit(1, width: 8),
                          mux(savestate_load & enable, savestate_data[7..0],
                          mux(wr_region_1, new_rom_bank_adjusted, rom_bank_reg)))

          # RAM Bank / RTC Select (0x4000-0x5FFF)
          mode <= mux(~enable, lit(0, width: 1),
                  mux(savestate_load & enable, savestate_data[14],
                  mux(wr_region_2, cpu_di[3], mode)))

          rtc_index <= mux(wr_region_2 & cpu_di[3], cpu_di[2..0], rtc_index)
          ram_bank_reg <= mux(~enable, lit(0, width: 3),
                          mux(savestate_load & enable, savestate_data[11..9],
                          mux(wr_region_2 & ~cpu_di[3], cpu_di[2..0], ram_bank_reg)))

          # Latch Clock Data (0x6000-0x7FFF), latch on 0->1 edge
          old_latch = rtc_latch
          rtc_latch <= mux(wr_region_3, cpu_di[0], rtc_latch)
          latch_trigger = wr_region_3 & ~old_latch & cpu_di[0]

          rtc_seconds_latch <= mux(latch_trigger, rtc_secs, rtc_seconds_latch)
          rtc_minutes_latch <= mux(latch_trigger, rtc_mins, rtc_minutes_latch)
          rtc_hours_latch <= mux(latch_trigger, rtc_hrs, rtc_hours_latch)
          rtc_days_latch <= mux(latch_trigger, rtc_dys, rtc_days_latch)
          rtc_halt_latch <= mux(latch_trigger, rtc_hlt, rtc_halt_latch)
          rtc_overflow_latch <= mux(latch_trigger, rtc_ovf, rtc_overflow_latch)

          # Host timestamp capture.
          rtc_timestamp_new_1 <= mux(enable, rtc_time[32], rtc_timestamp_new_1)
          rtc_timestamp <= mux(rtc_time_edge, rtc_time[31..0],
                           mux(second_tick, rtc_timestamp + lit(1, width: 32), rtc_timestamp))

          # Backup stream loading.
          rtc_timestamp_saved <= mux(enable & bk_rtc_wr & (bk_addr[7..0] == lit(0, width: 8)),
                                     cat(rtc_timestamp_saved[31..16], bk_data),
                                 mux(enable & bk_rtc_wr & (bk_addr[7..0] == lit(1, width: 8)),
                                     cat(bk_data, rtc_timestamp_saved[15..0]),
                                     rtc_timestamp_saved))

          rtc_savedtime_in <= mux(enable & bk_rtc_wr & (bk_addr[7..0] == lit(2, width: 8)),
                                  cat(rtc_savedtime_in[31..16], bk_data),
                              mux(enable & bk_rtc_wr & (bk_addr[7..0] == lit(3, width: 8)),
                                  cat(bk_data, rtc_savedtime_in[15..0]),
                                  rtc_savedtime_in))

          diff_seconds <= mux(load_from_backup & (rtc_timestamp > rtc_timestamp_saved),
                              rtc_timestamp - rtc_timestamp_saved,
                          mux(diff_fast_count, diff_seconds - lit(1, width: 32), diff_seconds))

          # Track whether RTC is actively used.
          rtc_inuse_reg <= mux(~enable, lit(0, width: 1),
                           mux(mode | load_from_backup, lit(1, width: 1), rtc_inuse_reg))

          # Persist packed RTC state (matching reference low 29-bit layout).
          packed_rtc_state = cat(rtc_hlt, rtc_ovf, rtc_dys, rtc_hrs, rtc_mins, rtc_secs)
          rtc_savedtime_out_reg <= mux(~enable, lit(0, width: 48),
                                   mux(rtc_change == lit(0, width: 1),
                                       cat(rtc_savedtime_out_reg[47..29], packed_rtc_state),
                                       rtc_savedtime_out_reg))
        end
      end
    end
  end
end
