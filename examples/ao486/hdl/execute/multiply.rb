# ao486 Multiply Unit
# Ported from: rtl/ao486/pipeline/execute_multiply.v
#
# Combinational unsigned/signed multiply with overflow detection.
# Handles 8, 16, and 32-bit operands.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module RHDL
  module Examples
    module AO486
      class Multiply < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        input :src, width: 32
        input :dst, width: 32
        input :operand_size, width: 6  # 8, 16, 32
        input :is_signed               # 0=MUL, 1=IMUL

        output :result_lo, width: 32   # low half (AL/AX/EAX)
        output :result_hi, width: 32   # high half (AH/DX/EDX)
        output :overflow               # CF=OF=1 when high half is significant

        def propagate
          src = in_val(:src) & 0xFFFF_FFFF
          dst = in_val(:dst) & 0xFFFF_FFFF
          size = in_val(:operand_size)
          signed = in_val(:is_signed) != 0

          # Sign-extend operands if signed
          if signed
            a = sign_extend(src, size)
            b = sign_extend(dst, size)
          else
            a = mask_to_size(src, size)
            b = mask_to_size(dst, size)
          end

          product = a * b

          case size
          when 8
            lo = product & 0xFF
            hi = (product >> 8) & 0xFF
            if signed
              # Overflow when result doesn't fit in signed 8-bit
              overflow = (product != sign_extend(lo, 8)) ? 1 : 0
            else
              overflow = hi != 0 ? 1 : 0
            end
          when 16
            lo = product & 0xFFFF
            hi = (product >> 16) & 0xFFFF
            if signed
              overflow = (product != sign_extend(lo, 16)) ? 1 : 0
            else
              overflow = hi != 0 ? 1 : 0
            end
          else # 32
            lo = product & 0xFFFF_FFFF
            hi = (product >> 32) & 0xFFFF_FFFF
            if signed
              overflow = (product != sign_extend(lo, 32)) ? 1 : 0
            else
              overflow = hi != 0 ? 1 : 0
            end
          end

          out_set(:result_lo, lo & 0xFFFF_FFFF)
          out_set(:result_hi, hi & 0xFFFF_FFFF)
          out_set(:overflow, overflow)
        end

        private

        def mask_to_size(val, size)
          case size
          when 8 then val & 0xFF
          when 16 then val & 0xFFFF
          else val & 0xFFFF_FFFF
          end
        end

        def sign_extend(val, size)
          case size
          when 8
            val = val & 0xFF
            (val & 0x80) != 0 ? (val | ~0xFF) : val
          when 16
            val = val & 0xFFFF
            (val & 0x8000) != 0 ? (val | ~0xFFFF) : val
          else
            val = val & 0xFFFF_FFFF
            (val & 0x8000_0000) != 0 ? (val | ~0xFFFF_FFFF) : val
          end
        end
      end
    end
  end
end
