# ao486 Divide Unit
# Ported from: rtl/ao486/pipeline/execute_divide.v
#
# Combinational unsigned/signed divide with exception detection.
# Handles 8, 16, and 32-bit operands.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module RHDL
  module Examples
    module AO486
      class Divide < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        input :numer, width: 64   # dividend (AX for 8-bit, DX:AX for 16, EDX:EAX for 32)
        input :denom, width: 32   # divisor
        input :operand_size, width: 6  # 8, 16, 32
        input :is_signed               # 0=DIV, 1=IDIV

        output :quotient, width: 32
        output :remainder, width: 32
        output :exception            # #DE (divide error)

        def propagate
          numer = in_val(:numer)
          denom = in_val(:denom) & 0xFFFF_FFFF
          size = in_val(:operand_size)
          signed = in_val(:is_signed) != 0

          # Mask operands to appropriate sizes
          denom_masked = mask_to_size(denom, size)

          # Check divide by zero
          if denom_masked == 0
            out_set(:quotient, 0)
            out_set(:remainder, 0)
            out_set(:exception, 1)
            return
          end

          if signed
            numer_s = sign_extend_numer(numer, size)
            denom_s = sign_extend(denom_masked, size)

            # Ruby handles signed division natively
            quot = numer_s / denom_s
            # Ruby truncates toward negative infinity; x86 truncates toward zero
            rem = numer_s - (quot * denom_s)
            if rem != 0 && (rem < 0) != (numer_s < 0)
              # Adjust for truncation toward zero
              quot += (numer_s < 0) != (denom_s < 0) ? 1 : -1
              rem = numer_s - (quot * denom_s)
            end

            # Check overflow
            overflow = case size
                       when 8 then quot > 127 || quot < -128
                       when 16 then quot > 32767 || quot < -32768
                       else quot > 2147483647 || quot < -2147483648
                       end

            if overflow
              out_set(:quotient, 0)
              out_set(:remainder, 0)
              out_set(:exception, 1)
              return
            end

            out_set(:quotient, quot & 0xFFFF_FFFF)
            out_set(:remainder, rem & 0xFFFF_FFFF)
          else
            numer_u = mask_numer(numer, size)

            quot = numer_u / denom_masked
            rem = numer_u % denom_masked

            # Check overflow
            overflow = case size
                       when 8 then quot > 0xFF
                       when 16 then quot > 0xFFFF
                       else quot > 0xFFFF_FFFF
                       end

            if overflow
              out_set(:quotient, 0)
              out_set(:remainder, 0)
              out_set(:exception, 1)
              return
            end

            out_set(:quotient, quot & 0xFFFF_FFFF)
            out_set(:remainder, rem & 0xFFFF_FFFF)
          end

          out_set(:exception, 0)
        end

        private

        def mask_to_size(val, size)
          case size
          when 8 then val & 0xFF
          when 16 then val & 0xFFFF
          else val & 0xFFFF_FFFF
          end
        end

        def mask_numer(numer, size)
          case size
          when 8 then numer & 0xFFFF       # AX
          when 16 then numer & 0xFFFF_FFFF  # DX:AX
          else numer & 0xFFFF_FFFF_FFFF_FFFF  # EDX:EAX
          end
        end

        def sign_extend_numer(numer, size)
          case size
          when 8
            val = numer & 0xFFFF
            (val & 0x8000) != 0 ? val - 0x10000 : val
          when 16
            val = numer & 0xFFFF_FFFF
            (val & 0x8000_0000) != 0 ? val - 0x1_0000_0000 : val
          else
            val = numer & 0xFFFF_FFFF_FFFF_FFFF
            (val & 0x8000_0000_0000_0000) != 0 ? val - 0x1_0000_0000_0000_0000 : val
          end
        end

        def sign_extend(val, size)
          case size
          when 8
            val = val & 0xFF
            (val & 0x80) != 0 ? val - 0x100 : val
          when 16
            val = val & 0xFFFF
            (val & 0x8000) != 0 ? val - 0x10000 : val
          else
            val = val & 0xFFFF_FFFF
            (val & 0x8000_0000) != 0 ? val - 0x1_0000_0000 : val
          end
        end
      end
    end
  end
end
