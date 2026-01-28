# SM83 Registers - Game Boy CPU Register File
# Corresponds to: reference/rtl/T80/T80_Reg.vhd
#
# The SM83 register file contains:
# - AF: Accumulator and Flags
# - BC: General purpose
# - DE: General purpose
# - HL: General purpose / indirect addressing
# - SP: Stack pointer
# - PC: Program counter
#
# Note: No shadow registers (AF', BC', DE', HL') unlike Z80
# Note: No IX, IY index registers unlike Z80

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SM83_Registers < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :CEN             # Clock enable

    # Write enables
    input :WE_A            # Write accumulator
    input :WE_F            # Write flags
    input :WE_B            # Write B
    input :WE_C            # Write C
    input :WE_D            # Write D
    input :WE_E            # Write E
    input :WE_H            # Write H
    input :WE_L            # Write L
    input :WE_SP_H         # Write SP high
    input :WE_SP_L         # Write SP low
    input :WE_PC           # Write PC (full 16-bit)
    input :PC_Inc          # Increment PC

    # Data inputs
    input :DI_A, width: 8
    input :DI_F, width: 8
    input :DI_B, width: 8
    input :DI_C, width: 8
    input :DI_D, width: 8
    input :DI_E, width: 8
    input :DI_H, width: 8
    input :DI_L, width: 8
    input :DI_SP_H, width: 8
    input :DI_SP_L, width: 8
    input :DI_PC, width: 16

    # Register outputs
    output :ACC_out, width: 8
    output :F_out, width: 8
    output :BC_out, width: 16
    output :DE_out, width: 16
    output :HL_out, width: 16
    output :SP_out, width: 16
    output :PC_out, width: 16

    # Individual register outputs
    output :B_out, width: 8
    output :C_out, width: 8
    output :D_out, width: 8
    output :E_out, width: 8
    output :H_out, width: 8
    output :L_out, width: 8

    # Internal registers
    wire :reg_A, width: 8
    wire :reg_F, width: 8
    wire :reg_B, width: 8
    wire :reg_C, width: 8
    wire :reg_D, width: 8
    wire :reg_E, width: 8
    wire :reg_H, width: 8
    wire :reg_L, width: 8
    wire :reg_SP, width: 16
    wire :reg_PC, width: 16

    # Combinational outputs
    behavior do
      ACC_out <= reg_A
      F_out <= reg_F
      B_out <= reg_B
      C_out <= reg_C
      D_out <= reg_D
      E_out <= reg_E
      H_out <= reg_H
      L_out <= reg_L

      BC_out <= cat(reg_B, reg_C)
      DE_out <= cat(reg_D, reg_E)
      HL_out <= cat(reg_H, reg_L)
      SP_out <= reg_SP
      PC_out <= reg_PC
    end

    # Sequential register updates
    sequential clock: :clk, reset: :rst, reset_values: {
      reg_A: 0x01,   # After boot ROM, A=0x01 (DMG) or 0x11 (CGB)
      reg_F: 0xB0,   # Z=1, N=0, H=1, C=1 after boot
      reg_B: 0x00,
      reg_C: 0x13,
      reg_D: 0x00,
      reg_E: 0xD8,
      reg_H: 0x01,
      reg_L: 0x4D,
      reg_SP: 0xFFFE,
      reg_PC: 0x0100  # Entry point after boot ROM
    } do
      # Accumulator
      reg_A <= mux(CEN & WE_A, DI_A, reg_A)

      # Flags (lower 4 bits always 0 on GB)
      reg_F <= mux(CEN & WE_F, DI_F & lit(0xF0, width: 8), reg_F)

      # BC
      reg_B <= mux(CEN & WE_B, DI_B, reg_B)
      reg_C <= mux(CEN & WE_C, DI_C, reg_C)

      # DE
      reg_D <= mux(CEN & WE_D, DI_D, reg_D)
      reg_E <= mux(CEN & WE_E, DI_E, reg_E)

      # HL
      reg_H <= mux(CEN & WE_H, DI_H, reg_H)
      reg_L <= mux(CEN & WE_L, DI_L, reg_L)

      # SP
      reg_SP <= mux(CEN & WE_SP_H,
                    cat(DI_SP_H, reg_SP[7..0]),
                    mux(CEN & WE_SP_L,
                        cat(reg_SP[15..8], DI_SP_L),
                        reg_SP))

      # PC with increment
      reg_PC <= mux(CEN & WE_PC,
                    DI_PC,
                    mux(CEN & PC_Inc,
                        reg_PC + lit(1, width: 16),
                        reg_PC))
    end
  end
end
