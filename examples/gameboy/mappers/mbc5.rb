# MBC5 Memory Bank Controller
# Corresponds to: reference/rtl/mappers/mbc5.v
#
# MBC5 supports:
# - Up to 8MB ROM (512 banks)
# - Up to 128KB RAM (16 banks)
# - Rumble motor support
#
# Memory Map:
# - 0x0000-0x3FFF: ROM Bank 0
# - 0x4000-0x7FFF: ROM Bank 0-511
# - 0xA000-0xBFFF: RAM Bank 0-15
#
# Registers:
# - 0x0000-0x1FFF: RAM Enable (0x0A enables)
# - 0x2000-0x2FFF: ROM Bank Low 8 bits
# - 0x3000-0x3FFF: ROM Bank High bit (bit 8)
# - 0x4000-0x5FFF: RAM Bank Number (4-bit, bit 3 is rumble on some carts)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class MBC5 < RHDL::HDL::SequentialComponent
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
    input :rom_mask, width: 9    # ROM bank mask (0-511)
    input :ram_mask, width: 4    # RAM bank mask (0-15)
    input :has_ram               # Cart has RAM

    # Cart type for battery/rumble detection
    input :cart_mbc_type, width: 8

    # Outputs
    output :rom_bank, width: 9   # ROM bank for 0x4000-0x7FFF
    output :ram_bank, width: 4   # RAM bank for 0xA000-0xBFFF
    output :ram_enable           # RAM enabled
    output :has_battery          # Battery backed
    output :rumbling             # Rumble motor active

    # Internal registers
    wire :ram_en                 # RAM enable register
    wire :rom_bank_reg, width: 9 # 9-bit ROM bank register
    wire :ram_bank_reg, width: 4 # 4-bit RAM bank register

    behavior do
      # RAM enable output (only when has RAM)
      ram_enable <= ram_en & has_ram

      # ROM bank with mask (no bank 0->1 mapping in MBC5)
      rom_bank <= rom_bank_reg & rom_mask

      # RAM bank with mask
      ram_bank <= ram_bank_reg & ram_mask

      # Rumble from bit 3 of RAM bank register
      rumbling <= ram_bank_reg[3]

      # Has battery if type 0x1B or 0x1E
      has_battery <= (cart_mbc_type == lit(0x1B, width: 8)) |
                     (cart_mbc_type == lit(0x1E, width: 8))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      ram_en: 0,
      rom_bank_reg: 1,
      ram_bank_reg: 0
    } do
      # Register writes
      # RAM Enable (0x0000-0x1FFF)
      ram_en <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(0, width: 3)),
                    (cpu_di == lit(0x0A, width: 8)),
                    ram_en)

      # ROM Bank Low (0x2000-0x2FFF)
      rom_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..12] == lit(2, width: 4)),
                          cat(rom_bank_reg[8], cpu_di),
                          rom_bank_reg)

      # ROM Bank High (0x3000-0x3FFF)
      rom_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..12] == lit(3, width: 4)),
                          cat(cpu_di[0], rom_bank_reg[7..0]),
                          rom_bank_reg)

      # RAM Bank Number (0x4000-0x5FFF)
      ram_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(2, width: 3)),
                          cpu_di[3..0],
                          ram_bank_reg)
    end
  end
end
