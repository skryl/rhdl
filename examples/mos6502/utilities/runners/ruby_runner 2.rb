# frozen_string_literal: true

# Ruby HDL runner for MOS6502/Apple II.
# This is the explicit :ruby mode backend (cycle-accurate HDL simulation).

require_relative '../apple2/harness'

module RHDL
  module Examples
    module MOS6502
      class RubyRunner < RHDL::Examples::MOS6502::Apple2Harness::Runner
        def simulator_type
          :hdl_ruby
        end
      end
    end
  end
end
