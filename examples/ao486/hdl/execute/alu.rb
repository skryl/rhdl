# ao486 ALU
# Ported from: rtl/ao486/pipeline/execute_commands.v (arithmetic wires)
#              rtl/ao486/pipeline/write_commands.v (flag computation)
#
# Combinational ALU: ADD, ADC, SUB, SBB, AND, OR, XOR, CMP
# with full flag computation (CF, PF, AF, ZF, SF, OF).

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class ALU < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        input :arith_index, width: 3   # ARITH_ADD..ARITH_CMP
        input :src, width: 32
        input :dst, width: 32
        input :operand_size, width: 6  # 8, 16, or 32
        input :cflag_in                # carry-in for ADC/SBB

        output :result, width: 32
        output :cflag
        output :pflag
        output :aflag
        output :zflag
        output :sflag
        output :oflag

        def propagate
          op = in_val(:arith_index)
          src = in_val(:src) & 0xFFFF_FFFF
          dst = in_val(:dst) & 0xFFFF_FFFF
          size = in_val(:operand_size)
          cf_in = in_val(:cflag_in) & 1

          # 33-bit arithmetic for carry detection
          result33 = case op
                     when Constants::ARITH_ADD then dst + src
                     when Constants::ARITH_OR  then dst | src
                     when Constants::ARITH_ADC then dst + src + cf_in
                     when Constants::ARITH_SBB then dst - src - cf_in
                     when Constants::ARITH_AND then dst & src
                     when Constants::ARITH_SUB then dst - src
                     when Constants::ARITH_XOR then dst ^ src
                     when Constants::ARITH_CMP then dst - src  # same as SUB
                     else 0
                     end

          result = result33 & 0xFFFF_FFFF
          is_logic = [Constants::ARITH_AND, Constants::ARITH_OR, Constants::ARITH_XOR].include?(op)

          # Mask result for operand size
          mask = size_mask(size)
          masked = result & mask

          # --- Flag computation ---

          # Sign flag: MSB of result
          msb_pos = msb_position(size)
          sf = (result >> msb_pos) & 1

          # Zero flag
          zf = (masked == 0) ? 1 : 0

          # Parity flag: even parity of low byte
          low_byte = result & 0xFF
          pf = ((0..7).count { |i| (low_byte >> i) & 1 == 1 }).even? ? 1 : 0

          # Auxiliary flag: half-carry from bit 3
          af = is_logic ? 0 : ((src ^ dst ^ result) >> 4) & 1

          # Carry flag
          if is_logic
            cf = 0
          else
            carry_bit = case size
                        when 8 then 8
                        when 16 then 16
                        else 32
                        end
            cf = (result33 >> carry_bit) & 1
          end

          # Overflow flag
          if is_logic
            of = 0
          else
            src_msb = (src >> msb_pos) & 1
            dst_msb = (dst >> msb_pos) & 1
            res_msb = (result >> msb_pos) & 1

            is_sub = [Constants::ARITH_SUB, Constants::ARITH_SBB, Constants::ARITH_CMP].include?(op)
            if is_sub
              # SUB overflow: dst and src have different signs, result sign differs from dst
              of = (src_msb != dst_msb && res_msb != dst_msb) ? 1 : 0
            else
              # ADD overflow: src and dst same sign, result sign differs
              of = (src_msb == dst_msb && res_msb != dst_msb) ? 1 : 0
            end
          end

          out_set(:result, result & 0xFFFF_FFFF)
          out_set(:cflag, cf)
          out_set(:pflag, pf)
          out_set(:aflag, af)
          out_set(:zflag, zf)
          out_set(:sflag, sf)
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
      end
    end
  end
end
