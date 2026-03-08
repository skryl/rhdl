# frozen_string_literal: true

module RHDL
  module Examples
    module GameBoy
      module ClockEnableWaveform
        module_function

        def values_for_phase(phase)
          normalized = phase.to_i & 0x7
          {
            # Mirror the MiSTer/reference speedcontrol.vhd behavior used by the
            # bare imported `gb` top: ce pulses on clkdiv 0, ce_n on clkdiv 4,
            # and ce_2x on both half-rate phases.
            ce: normalized.zero? ? 1 : 0,
            ce_n: normalized == 4 ? 1 : 0,
            ce_2x: (normalized & 0x3).zero? ? 1 : 0
          }
        end

        def advance_phase(phase)
          (phase.to_i + 1) & 0x7
        end
      end
    end
  end
end
