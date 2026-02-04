# SM83 Registers - Game Boy CPU Register File
# Corresponds to: reference/rtl/T80/T80_Reg.vhd
#
# The SM83 register file contains:
# - AF: Accumulator and Flags
# - bc: General purpose
# - de: General purpose
# - hl: General purpose / indirect addressing
# - sp: Stack pointer
# - pc: Program counter
#
# Note: No shadow registers (AF', bc', de', hl') unlike Z80
# Note: No IX, IY index registers unlike Z80

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class SM83_Registers < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :cen             # Clock enable

    # write_sig enables
    input :we_a            # write_sig accumulator
    input :we_f            # write_sig flags
    input :we_b            # write_sig B
    input :we_c            # write_sig C
    input :we_d            # write_sig D
    input :we_e            # write_sig E
    input :we_h            # write_sig H
    input :we_l            # write_sig L
    input :we_sp_h         # write_sig sp high
    input :we_sp_l         # write_sig sp low
    input :we_pc           # write_sig pc (full 16-bit)
    input :pc_inc          # Increment pc

    # Data inputs
    input :di_a, width: 8
    input :di_f, width: 8
    input :di_b, width: 8
    input :di_c, width: 8
    input :di_d, width: 8
    input :di_e, width: 8
    input :di_h, width: 8
    input :di_l, width: 8
    input :di_sp_h, width: 8
    input :di_sp_l, width: 8
    input :di_pc, width: 16

    # Register outputs
    output :acc_out, width: 8
    output :f_out, width: 8
    output :bc_out, width: 16
    output :de_out, width: 16
    output :hl_out, width: 16
    output :sp_out, width: 16
    output :pc_out, width: 16

    # Individual register outputs
    output :b_out, width: 8
    output :c_out, width: 8
    output :d_out, width: 8
    output :e_out, width: 8
    output :h_out, width: 8
    output :l_out, width: 8

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
      acc_out <= reg_A
      f_out <= reg_F
      b_out <= reg_B
      c_out <= reg_C
      d_out <= reg_D
      e_out <= reg_E
      h_out <= reg_H
      l_out <= reg_L

      bc_out <= cat(reg_B, reg_C)
      de_out <= cat(reg_D, reg_E)
      hl_out <= cat(reg_H, reg_L)
      sp_out <= reg_SP
      pc_out <= reg_PC
    end

    # Sequential register updates
    sequential clock: :clk, reset: :rst, reset_values: {
      reg_A: 0x01,   # After boot ROM, addr_bus=0x01 (DMG) or 0x11 (CGB)
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
      reg_A <= mux(cen & we_a, di_a, reg_A)

      # Flags (lower 4 bits always 0 on GB)
      reg_F <= mux(cen & we_f, di_f & lit(0xF0, width: 8), reg_F)

      # bc
      reg_B <= mux(cen & we_b, di_b, reg_B)
      reg_C <= mux(cen & we_c, di_c, reg_C)

      # de
      reg_D <= mux(cen & we_d, di_d, reg_D)
      reg_E <= mux(cen & we_e, di_e, reg_E)

      # hl
      reg_H <= mux(cen & we_h, di_h, reg_H)
      reg_L <= mux(cen & we_l, di_l, reg_L)

      # sp
      reg_SP <= mux(cen & we_sp_h,
                    cat(di_sp_h, reg_SP[7..0]),
                    mux(cen & we_sp_l,
                        cat(reg_SP[15..8], di_sp_l),
                        reg_SP))

      # pc with increment
      reg_PC <= mux(cen & we_pc,
                    di_pc,
                    mux(cen & pc_inc,
                        reg_PC + lit(1, width: 16),
                        reg_PC))
    end
      end
    end
  end
end
