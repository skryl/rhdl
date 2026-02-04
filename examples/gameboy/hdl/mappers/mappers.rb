# Game Boy Memory Mappers
# Corresponds to: reference/rtl/mappers/*.v
#
# This file loads all mapper implementations.
# Mappers handle bank switching for cartridges with:
# - More than 32KB ROM
# - External RAM (save data)
# - Special features (RTC, rumble, etc.)

require_relative 'mbc1'
require_relative 'mbc2'
require_relative 'mbc3'
require_relative 'mbc5'

module RHDL
  module Examples
    module GameBoy
      module Mappers
    # Mapper type constants (from cart header byte 0x147)
    ROM_ONLY         = 0x00
    MBC1             = 0x01
    MBC1_RAM         = 0x02
    MBC1_RAM_BATTERY = 0x03
    MBC2             = 0x05
    MBC2_BATTERY     = 0x06
    ROM_RAM          = 0x08
    ROM_RAM_BATTERY  = 0x09
    MMM01            = 0x0B
    MMM01_RAM        = 0x0C
    MMM01_RAM_BATTERY = 0x0D
    MBC3_TIMER_BATTERY = 0x0F
    MBC3_TIMER_RAM_BATTERY = 0x10
    MBC3             = 0x11
    MBC3_RAM         = 0x12
    MBC3_RAM_BATTERY = 0x13
    MBC5             = 0x19
    MBC5_RAM         = 0x1A
    MBC5_RAM_BATTERY = 0x1B
    MBC5_RUMBLE      = 0x1C
    MBC5_RUMBLE_RAM  = 0x1D
    MBC5_RUMBLE_RAM_BATTERY = 0x1E
    MBC6             = 0x20
    MBC7_SENSOR_RUMBLE_RAM_BATTERY = 0x22
    POCKET_CAMERA    = 0xFC
    BANDAI_TAMA5     = 0xFD
    HUC3             = 0xFE
    HUC1_RAM_BATTERY = 0xFF

    # ROM size constants (from cart header byte 0x148)
    ROM_SIZES = {
      0x00 => 32 * 1024,    # 32KB (no banking)
      0x01 => 64 * 1024,    # 64KB (4 banks)
      0x02 => 128 * 1024,   # 128KB (8 banks)
      0x03 => 256 * 1024,   # 256KB (16 banks)
      0x04 => 512 * 1024,   # 512KB (32 banks)
      0x05 => 1024 * 1024,  # 1MB (64 banks)
      0x06 => 2048 * 1024,  # 2MB (128 banks)
      0x07 => 4096 * 1024,  # 4MB (256 banks)
      0x08 => 8192 * 1024,  # 8MB (512 banks)
      0x52 => 1152 * 1024,  # 1.1MB (72 banks)
      0x53 => 1280 * 1024,  # 1.2MB (80 banks)
      0x54 => 1536 * 1024   # 1.5MB (96 banks)
    }

    # RAM size constants (from cart header byte 0x149)
    RAM_SIZES = {
      0x00 => 0,            # None
      0x01 => 2 * 1024,     # 2KB (unused)
      0x02 => 8 * 1024,     # 8KB (1 bank)
      0x03 => 32 * 1024,    # 32KB (4 banks)
      0x04 => 128 * 1024,   # 128KB (16 banks)
      0x05 => 64 * 1024     # 64KB (8 banks)
    }
      end
    end
  end
end
