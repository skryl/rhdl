# MBC3 Memory Bank Controller with RTC
# Corresponds to: reference/rtl/mappers/mbc3.v
#
# MBC3 supports:
# - Up to 2MB ROM (128 banks, MBC30: 256 banks)
# - Up to 32KB RAM (4 banks)
# - Real Time Clock (RTC)
#
# Memory Map:
# - 0x0000-0x3FFF: ROM Bank 0
# - 0x4000-0x7FFF: ROM Bank 1-127 (or 1-255 for MBC30)
# - 0xA000-0xBFFF: RAM Bank 0-3 or RTC registers
#
# Registers:
# - 0x0000-0x1FFF: RAM/RTC Enable (0x0A enables)
# - 0x2000-0x3FFF: ROM Bank Number (7-bit, bank 0 maps to 1)
# - 0x4000-0x5FFF: RAM Bank or RTC Register Select
# - 0x6000-0x7FFF: Latch Clock Data

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module GameBoy
  class MBC3 < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :ce
    input :reset

    # MBC30 mode (extended ROM)
    input :mbc30

    # CPU interface
    input :cpu_addr, width: 16
    input :cpu_di, width: 8
    input :cpu_wr
    input :cpu_rd

    # RTC clock (32.768 kHz)
    input :ce_32k

    # Cart size info
    input :rom_mask, width: 8    # ROM bank mask
    input :ram_mask, width: 3    # RAM bank mask (0-7)
    input :has_ram               # Cart has RAM

    # Cart type for battery detection
    input :cart_mbc_type, width: 8

    # Outputs
    output :rom_bank, width: 8   # ROM bank for 0x4000-0x7FFF
    output :ram_bank, width: 3   # RAM bank for 0xA000-0xBFFF
    output :ram_enable           # RAM enabled (not RTC mode)
    output :has_battery          # Battery backed
    output :rtc_mode             # RTC mode active

    # RTC outputs
    output :rtc_seconds, width: 6
    output :rtc_minutes, width: 6
    output :rtc_hours, width: 5
    output :rtc_days, width: 9
    output :rtc_halt
    output :rtc_overflow

    # Internal registers
    wire :ram_en                 # RAM/RTC enable register
    wire :rom_bank_reg, width: 8 # 8-bit ROM bank register
    wire :ram_bank_reg, width: 3 # 3-bit RAM bank register
    wire :mode                   # 0=RAM mode, 1=RTC mode
    wire :rtc_index, width: 3    # RTC register index

    # RTC internal state
    wire :rtc_subseconds, width: 16
    wire :rtc_secs, width: 6
    wire :rtc_mins, width: 6
    wire :rtc_hrs, width: 5
    wire :rtc_dys, width: 10
    wire :rtc_hlt
    wire :rtc_ovf

    # RTC latch registers
    wire :rtc_latch
    wire :rtc_seconds_latch, width: 6
    wire :rtc_minutes_latch, width: 6
    wire :rtc_hours_latch, width: 5
    wire :rtc_days_latch, width: 10
    wire :rtc_halt_latch
    wire :rtc_overflow_latch

    behavior do
      # RTC mode output
      rtc_mode <= mode

      # RAM enable output (only when not in RTC mode and has RAM)
      ram_enable <= ram_en & ~mode & has_ram

      # ROM bank calculation - bank 0 maps to 1
      effective_rom_bank = mux(rom_bank_reg == lit(0, width: 8),
                               lit(1, width: 8),
                               rom_bank_reg)

      # Apply ROM mask
      rom_bank <= effective_rom_bank & rom_mask

      # RAM bank with mask
      ram_bank <= ram_bank_reg & ram_mask

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
      rtc_latch: 0,
      rtc_seconds_latch: 0,
      rtc_minutes_latch: 0,
      rtc_hours_latch: 0,
      rtc_days_latch: 0,
      rtc_halt_latch: 0,
      rtc_overflow_latch: 0
    } do
      # RTC counter (when not halted)
      rtc_subseconds <= mux(ce_32k & ~rtc_hlt,
                            mux(rtc_subseconds >= lit(32767, width: 16),
                                lit(0, width: 16),
                                rtc_subseconds + lit(1, width: 16)),
                            rtc_subseconds)

      # Seconds increment
      second_tick = ce_32k & (rtc_subseconds >= lit(32767, width: 16)) & ~rtc_hlt

      rtc_secs <= mux(second_tick,
                      mux(rtc_secs == lit(59, width: 6),
                          lit(0, width: 6),
                          rtc_secs + lit(1, width: 6)),
                      rtc_secs)

      # Minutes increment
      minute_tick = second_tick & (rtc_secs == lit(59, width: 6))

      rtc_mins <= mux(minute_tick,
                      mux(rtc_mins == lit(59, width: 6),
                          lit(0, width: 6),
                          rtc_mins + lit(1, width: 6)),
                      rtc_mins)

      # Hours increment
      hour_tick = minute_tick & (rtc_mins == lit(59, width: 6))

      rtc_hrs <= mux(hour_tick,
                     mux(rtc_hrs == lit(23, width: 5),
                         lit(0, width: 5),
                         rtc_hrs + lit(1, width: 5)),
                     rtc_hrs)

      # Days increment
      day_tick = hour_tick & (rtc_hrs == lit(23, width: 5))

      rtc_dys <= mux(day_tick,
                     mux(rtc_dys == lit(511, width: 10),
                         lit(0, width: 10),
                         rtc_dys + lit(1, width: 10)),
                     rtc_dys)

      # Overflow flag
      rtc_ovf <= mux(day_tick & (rtc_dys == lit(511, width: 10)),
                     lit(1, width: 1),
                     rtc_ovf)

      # Register writes
      # RAM Enable (0x0000-0x1FFF)
      ram_en <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(0, width: 3)),
                    (cpu_di[3..0] == lit(0x0A, width: 4)),
                    ram_en)

      # ROM Bank Number (0x2000-0x3FFF)
      # For MBC30, use full 8 bits, otherwise mask bit 7
      new_rom_bank = mux(mbc30, cpu_di, cat(lit(0, width: 1), cpu_di[6..0]))
      new_rom_bank_adjusted = mux(new_rom_bank == lit(0, width: 8),
                                   lit(1, width: 8),
                                   new_rom_bank)

      rom_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(1, width: 3)),
                          new_rom_bank_adjusted,
                          rom_bank_reg)

      # RAM Bank / RTC Select (0x4000-0x5FFF)
      # If bit 3 set, enable RTC mode
      mode <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(2, width: 3)),
                  cpu_di[3],
                  mode)

      rtc_index <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(2, width: 3)) & cpu_di[3],
                       cpu_di[2..0],
                       rtc_index)

      ram_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(2, width: 3)) & ~cpu_di[3],
                          cpu_di[2..0],
                          ram_bank_reg)

      # Latch Clock Data (0x6000-0x7FFF)
      # Writing 0x00 then 0x01 latches current time
      old_latch = rtc_latch
      rtc_latch <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(3, width: 3)),
                       cpu_di[0],
                       rtc_latch)

      # Latch on rising edge (0->1)
      latch_trigger = ce & cpu_wr & (cpu_addr[15..13] == lit(3, width: 3)) &
                      ~old_latch & cpu_di[0]

      rtc_seconds_latch <= mux(latch_trigger, rtc_secs, rtc_seconds_latch)
      rtc_minutes_latch <= mux(latch_trigger, rtc_mins, rtc_minutes_latch)
      rtc_hours_latch <= mux(latch_trigger, rtc_hrs, rtc_hours_latch)
      rtc_days_latch <= mux(latch_trigger, rtc_dys, rtc_days_latch)
      rtc_halt_latch <= mux(latch_trigger, rtc_hlt, rtc_halt_latch)
      rtc_overflow_latch <= mux(latch_trigger, rtc_ovf, rtc_overflow_latch)
    end
  end
end
