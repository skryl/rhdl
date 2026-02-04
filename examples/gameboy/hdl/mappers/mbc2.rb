# MBC2 Memory Bank Controller
# Corresponds to: reference/rtl/mappers/mbc2.v
#
# MBC2 supports:
# - Up to 256KB ROM (16 banks)
# - Built-in 512x4-bit RAM (no external RAM)
#
# Memory Map:
# - 0x0000-0x3FFF: ROM Bank 0
# - 0x4000-0x7FFF: ROM Bank 1-15
# - 0xA000-0xA1FF: Built-in 512x4 RAM
#
# Registers:
# - 0x0000-0x1FFF (A8=0): RAM Enable (0x0A enables)
# - 0x2000-0x3FFF (A8=1): ROM Bank Number (4-bit, bank 0 maps to 1)

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class MBC2 < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :ce
    input :reset

    # CPU interface
    input :cpu_addr, width: 16
    input :cpu_di, width: 8
    input :cpu_wr

    # Cart size info
    input :rom_mask, width: 4    # ROM bank mask (0-15)

    # Cart type for battery detection
    input :cart_mbc_type, width: 8

    # Outputs
    output :rom_bank, width: 4   # ROM bank for 0x4000-0x7FFF
    output :ram_addr, width: 9   # RAM address (512 bytes)
    output :ram_enable           # RAM enabled
    output :has_battery          # Battery backed

    # Internal registers
    wire :ram_en                 # RAM enable register
    wire :rom_bank_reg, width: 4 # 4-bit ROM bank register

    behavior do
      # RAM enable output
      ram_enable <= ram_en

      # ROM bank calculation
      # Bank 0 maps to 1
      effective_rom_bank = mux(rom_bank_reg == lit(0, width: 4),
                               lit(1, width: 4),
                               rom_bank_reg)

      # Apply ROM mask
      rom_bank <= effective_rom_bank & rom_mask

      # RAM address - only 512 bytes (9 bits), mapped at 0xA000-0xA1FF
      ram_addr <= cpu_addr[8..0]

      # Has battery if type 0x06
      has_battery <= (cart_mbc_type == lit(0x06, width: 8))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      ram_en: 0,
      rom_bank_reg: 1
    } do
      # Register writes (active on CPU write to ROM areas)
      # Address bit 8 determines register:
      # - A8=0 (0x0000-0x1FFF): RAM Enable
      # - A8=1 (0x2000-0x3FFF): ROM Bank

      # RAM Enable (0x0000-0x1FFF, A8=0)
      ram_en <= mux(ce & cpu_wr & ~cpu_addr[15] & ~cpu_addr[14] & ~cpu_addr[8],
                    (cpu_di[3..0] == lit(0x0A, width: 4)),
                    ram_en)

      # ROM Bank Number (0x2000-0x3FFF, A8=1)
      # Bank 0 writes become bank 1
      new_bank = mux(cpu_di[3..0] == lit(0, width: 4),
                     lit(1, width: 4),
                     cpu_di[3..0])

      rom_bank_reg <= mux(ce & cpu_wr & ~cpu_addr[15] & ~cpu_addr[14] & cpu_addr[8],
                          new_bank,
                          rom_bank_reg)
    end
      end
    end
  end
end
