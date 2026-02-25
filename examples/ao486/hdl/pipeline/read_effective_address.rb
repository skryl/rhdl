# ao486 Read Effective Address
# Ported from: rtl/ao486/pipeline/read_effective_address.v
#
# Combinational effective address calculator for 16-bit and 32-bit
# x86 addressing modes. Computes linear address from ModR/M + SIB +
# displacement + segment base.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class ReadEffectiveAddress < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        input :modregrm_mod, width: 2
        input :modregrm_rm, width: 3
        input :address_32bit
        input :sib, width: 8
        input :displacement, width: 32
        input :seg_base, width: 32

        # Register values for addressing
        input :reg_eax, width: 32
        input :reg_ecx, width: 32
        input :reg_edx, width: 32
        input :reg_ebx, width: 32
        input :reg_esp, width: 32
        input :reg_ebp, width: 32
        input :reg_esi, width: 32
        input :reg_edi, width: 32

        output :address, width: 32
        output :is_memory        # 1 = memory access, 0 = register (mod=3)
        output :use_ss           # 1 = default segment is SS (BP/ESP-based)

        def propagate
          mod = in_val(:modregrm_mod) & 3
          rm = in_val(:modregrm_rm) & 7
          addr32 = in_val(:address_32bit) != 0
          disp = in_val(:displacement) & 0xFFFF_FFFF
          seg_base = in_val(:seg_base) & 0xFFFF_FFFF

          if mod == 3
            out_set(:address, 0)
            out_set(:is_memory, 0)
            out_set(:use_ss, 0)
            return
          end

          out_set(:is_memory, 1)

          if addr32
            ea, ss = calc_ea_32(mod, rm, disp)
          else
            ea, ss = calc_ea_16(mod, rm, disp)
          end

          out_set(:address, (seg_base + ea) & 0xFFFF_FFFF)
          out_set(:use_ss, ss ? 1 : 0)
        end

        private

        def reg_val(index)
          names = [:reg_eax, :reg_ecx, :reg_edx, :reg_ebx,
                   :reg_esp, :reg_ebp, :reg_esi, :reg_edi]
          in_val(names[index]) & 0xFFFF_FFFF
        end

        def calc_ea_16(mod, rm, disp)
          bx = reg_val(3) & 0xFFFF
          bp = reg_val(5) & 0xFFFF
          si = reg_val(6) & 0xFFFF
          di = reg_val(7) & 0xFFFF

          use_ss = false

          base = case rm
                 when 0 then bx + si
                 when 1 then bx + di
                 when 2 then use_ss = true; bp + si
                 when 3 then use_ss = true; bp + di
                 when 4 then si
                 when 5 then di
                 when 6
                   if mod == 0
                     disp & 0xFFFF  # direct address
                   else
                     use_ss = true
                     bp
                   end
                 when 7 then bx
                 end

          ea = case mod
               when 0 then (rm == 6) ? base : base
               when 1 then base + sign_extend_8(disp & 0xFF)
               when 2 then base + (disp & 0xFFFF)
               else base
               end

          # In 16-bit mode, effective address wraps to 16 bits
          [(ea & 0xFFFF), use_ss]
        end

        def calc_ea_32(mod, rm, disp)
          use_ss = false

          if rm == 4 && mod != 3
            # SIB byte
            ea, use_ss = calc_sib(mod, disp)
            return [ea, use_ss]
          end

          base = case rm
                 when 5
                   if mod == 0
                     return [disp, false]  # [disp32], no base register
                   else
                     use_ss = true
                     reg_val(5)  # EBP
                   end
                 else
                   reg_val(rm)
                 end

          # BP/ESP as base uses SS
          use_ss = true if rm == 5 && mod != 0

          ea = case mod
               when 0 then base
               when 1 then base + sign_extend_8(disp & 0xFF)
               when 2 then base + disp
               else base
               end

          [(ea & 0xFFFF_FFFF), use_ss]
        end

        def calc_sib(mod, disp)
          sib = in_val(:sib) & 0xFF
          scale = (sib >> 6) & 3
          index_reg = (sib >> 3) & 7
          base_reg = sib & 7

          use_ss = false

          # Index (ESP/index=4 means no index)
          index_val = if index_reg == 4
                        0
                      else
                        reg_val(index_reg)
                      end
          scaled_index = index_val << scale

          # Base
          base_val = if base_reg == 5 && mod == 0
                       disp  # no base register, use disp32
                     else
                       use_ss = (base_reg == 4 || base_reg == 5)
                       reg_val(base_reg)
                     end

          ea = case mod
               when 0 then base_val + scaled_index
               when 1 then base_val + scaled_index + sign_extend_8(disp & 0xFF)
               when 2 then base_val + scaled_index + disp
               else base_val + scaled_index
               end

          [(ea & 0xFFFF_FFFF), use_ss]
        end

        def sign_extend_8(val)
          val = val & 0xFF
          (val & 0x80) != 0 ? val - 0x100 : val
        end
      end
    end
  end
end
