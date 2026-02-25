# ao486 Condition Evaluator
# Ported from: rtl/ao486/pipeline/condition.v
#
# Evaluates all 16 x86 Jcc condition codes from EFLAGS.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module RHDL
  module Examples
    module AO486
      class ConditionEval < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        input :condition_index, width: 4
        input :oflag
        input :cflag
        input :zflag
        input :sflag
        input :pflag

        output :condition_met

        def propagate
          idx = in_val(:condition_index) & 0xF
          of = in_val(:oflag) & 1
          cf = in_val(:cflag) & 1
          zf = in_val(:zflag) & 1
          sf = in_val(:sflag) & 1
          pf = in_val(:pflag) & 1

          met = case idx
                when 0  then of          # O
                when 1  then 1 - of      # NO
                when 2  then cf          # B/C
                when 3  then 1 - cf      # NB/NC
                when 4  then zf          # Z/E
                when 5  then 1 - zf      # NZ/NE
                when 6  then (cf | zf) > 0 ? 1 : 0  # BE/NA
                when 7  then (cf == 0 && zf == 0) ? 1 : 0  # NBE/A
                when 8  then sf          # S
                when 9  then 1 - sf      # NS
                when 10 then pf          # P/PE
                when 11 then 1 - pf      # NP/PO
                when 12 then (sf ^ of)   # L/NGE
                when 13 then 1 - (sf ^ of)  # NL/GE
                when 14 then ((sf ^ of) | zf) > 0 ? 1 : 0  # LE/NG
                when 15 then ((sf ^ of) == 0 && zf == 0) ? 1 : 0  # NLE/G
                else 0
                end

          out_set(:condition_met, met)
        end
      end
    end
  end
end
