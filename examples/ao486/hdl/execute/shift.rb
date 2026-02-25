# ao486 Shift Unit
# Ported from: rtl/ao486/pipeline/execute_shift.v
#
# Combinational barrel shifter handling SHL, SHR, SAR, ROL, ROR.
# (RCL/RCR/SHLD/SHRD can be added in a later phase.)

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module RHDL
  module Examples
    module AO486
      class Shift < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        # Shift operation (ModR/M reg field encoding)
        # 0=ROL, 1=ROR, 2=RCL, 3=RCR, 4=SHL/SAL, 5=SHR, 6=SAL, 7=SAR
        input :shift_op, width: 3
        input :value, width: 32
        input :count, width: 5     # masked to 5 bits (0-31)
        input :operand_size, width: 6  # 8, 16, 32
        input :cflag_in

        output :result, width: 32
        output :cflag
        output :oflag

        ROL = 0
        ROR = 1
        SHL = 4
        SHR = 5
        SAR = 7

        def propagate
          op = in_val(:shift_op) & 7
          val = in_val(:value) & 0xFFFF_FFFF
          cnt = in_val(:count) & 0x1F
          size = in_val(:operand_size)
          mask = size_mask(size)
          msb = msb_position(size)

          val = val & mask  # mask to operand size

          if cnt == 0
            out_set(:result, val)
            out_set(:cflag, in_val(:cflag_in) & 1)
            out_set(:oflag, 0)
            return
          end

          case op
          when SHL
            result, cf = shift_left(val, cnt, size, msb)
          when SHR
            result, cf = shift_right_logical(val, cnt, size, msb)
          when SAR
            result, cf = shift_right_arithmetic(val, cnt, size, msb)
          when ROL
            result, cf = rotate_left(val, cnt, size, msb)
          when ROR
            result, cf = rotate_right(val, cnt, size, msb)
          else
            result = val
            cf = 0
          end

          result &= mask

          # Overflow flag (only defined for count=1)
          of = compute_oflag(op, result, cf, msb, cnt)

          out_set(:result, result & 0xFFFF_FFFF)
          out_set(:cflag, cf)
          out_set(:oflag, of)
        end

        private

        def size_mask(size)
          case size
          when 8 then 0xFF
          when 16 then 0xFFFF
          else 0xFFFF_FFFF
          end
        end

        def msb_position(size)
          case size
          when 8 then 7
          when 16 then 15
          else 31
          end
        end

        def shift_left(val, cnt, size, msb)
          result = (val << cnt) & 0xFFFF_FFFF
          # Carry = last bit shifted out (bit at position msb+1-cnt before shift)
          cf = cnt <= msb + 1 ? (val >> (msb + 1 - cnt)) & 1 : 0
          [result, cf]
        end

        def shift_right_logical(val, cnt, size, msb)
          result = val >> cnt
          # Carry = last bit shifted out
          cf = cnt > 0 ? (val >> (cnt - 1)) & 1 : 0
          [result, cf]
        end

        def shift_right_arithmetic(val, cnt, size, msb)
          sign = (val >> msb) & 1
          if sign == 1
            # Fill with 1s from MSB
            fill = size_mask(in_val(:operand_size))
            result = (val >> cnt) | (fill << ([msb + 1 - cnt, 0].max))
          else
            result = val >> cnt
          end
          cf = cnt > 0 ? (val >> (cnt - 1)) & 1 : 0
          [result, cf]
        end

        def rotate_left(val, cnt, size, msb)
          bits = msb + 1
          cnt_mod = cnt % bits
          if cnt_mod == 0
            cf = val & 1  # LSB becomes carry for full rotation
            return [val, cf]
          end
          result = ((val << cnt_mod) | (val >> (bits - cnt_mod)))
          cf = result & 1  # after ROL, CF = LSB of result
          [result, cf]
        end

        def rotate_right(val, cnt, size, msb)
          bits = msb + 1
          cnt_mod = cnt % bits
          if cnt_mod == 0
            cf = (val >> msb) & 1  # MSB becomes carry for full rotation
            return [val, cf]
          end
          result = ((val >> cnt_mod) | (val << (bits - cnt_mod)))
          cf = (result >> msb) & 1  # after ROR, CF = MSB of result
          [result, cf]
        end

        def compute_oflag(op, result, cf, msb, cnt)
          res_msb = (result >> msb) & 1
          case op
          when ROL then res_msb ^ (result & 1)  # MSB XOR LSB (really MSB XOR CF)
          when ROR then res_msb ^ ((result >> (msb - 1)) & 1)  # MSB XOR (MSB-1)
          when SHL then res_msb ^ cf  # MSB XOR CF
          when SHR then (in_val(:value) >> msb) & 1  # original MSB (OF = MSB before shift)
          when SAR then 0  # always 0 for SAR
          else 0
          end
        end
      end
    end
  end
end
