# MBC1 Memory Bank Controller
# Corresponds to: reference/rtl/mappers/mbc1.v
#
# MBC1 supports:
# - Up to 2MB ROM (128 banks)
# - Up to 32KB RAM (4 banks)
# - Two banking modes
#
# Memory Map:
# - 0x0000-0x3FFF: ROM Bank 0 (or 0x20/0x40/0x60 in mode 1)
# - 0x4000-0x7FFF: ROM Bank 1-127
# - 0xA000-0xBFFF: RAM Bank 0-3
#
# Registers:
# - 0x0000-0x1FFF: RAM Enable (0x0A enables)
# - 0x2000-0x3FFF: ROM Bank Number (5-bit, bank 0 maps to 1)
# - 0x4000-0x5FFF: RAM Bank Number / Upper ROM Bank Bits
# - 0x6000-0x7FFF: Banking Mode (0=ROM, 1=RAM)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class MBC1 < RHDL::HDL::SequentialComponent
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
    input :rom_mask, width: 7    # ROM bank mask
    input :ram_mask, width: 2    # RAM bank mask (0-3)

    # Outputs
    output :rom_bank, width: 7   # ROM bank for 0x4000-0x7FFF
    output :rom_bank_0, width: 7 # ROM bank for 0x0000-0x3FFF (mode 1)
    output :ram_bank, width: 2   # RAM bank for 0xA000-0xBFFF
    output :ram_enable           # RAM enabled

    # Internal registers
    wire :ram_en                 # RAM enable register
    wire :rom_bank_reg, width: 5 # 5-bit ROM bank register
    wire :ram_bank_reg, width: 2 # 2-bit RAM/upper ROM bank register
    wire :mode                   # Banking mode (0=ROM, 1=RAM)

    behavior do
      # RAM enable output
      ram_enable <= ram_en

      # ROM bank calculation
      # Bank 0 maps to 1, 0x20->0x21, 0x40->0x41, 0x60->0x61
      effective_rom_bank = mux(rom_bank_reg == lit(0, width: 5),
                               lit(1, width: 5),
                               rom_bank_reg)

      # Full 7-bit ROM bank (combining 5-bit and 2-bit registers)
      full_rom_bank = cat(ram_bank_reg, effective_rom_bank)

      # Apply ROM mask
      rom_bank <= full_rom_bank & rom_mask

      # Bank 0 ROM bank (only affected in mode 1)
      rom_bank_0 <= mux(mode,
                        cat(ram_bank_reg, lit(0, width: 5)) & rom_mask,
                        lit(0, width: 7))

      # RAM bank (only in mode 1, otherwise bank 0)
      ram_bank <= mux(mode, ram_bank_reg & ram_mask, lit(0, width: 2))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      ram_en: 0,
      rom_bank_reg: 1,
      ram_bank_reg: 0,
      mode: 0
    } do
      # Register writes (active on CPU write to ROM/RAM areas)
      # RAM Enable (0x0000-0x1FFF)
      ram_en <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(0, width: 3)),
                    (cpu_di[3..0] == lit(0x0A, width: 4)),
                    ram_en)

      # ROM Bank Number (0x2000-0x3FFF)
      rom_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(1, width: 3)),
                          cpu_di[4..0],
                          rom_bank_reg)

      # RAM Bank Number / Upper ROM (0x4000-0x5FFF)
      ram_bank_reg <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(2, width: 3)),
                          cpu_di[1..0],
                          ram_bank_reg)

      # Banking Mode (0x6000-0x7FFF)
      mode <= mux(ce & cpu_wr & (cpu_addr[15..13] == lit(3, width: 3)),
                  cpu_di[0],
                  mode)
    end
  end
end
