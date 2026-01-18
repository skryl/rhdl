# CPU HDL Module
# Gate-level CPU implementation

require_relative 'cpu/instruction_decoder'
require_relative 'cpu/accumulator'
require_relative 'cpu/synth_datapath'
require_relative 'cpu/datapath'
require_relative 'cpu/memory_adapter'
require_relative 'cpu/cpu_adapter'

module RHDL
  module HDL
    module CPU
      # Full CPU wrapper with memory interface
      class CPU < Datapath
        # Convenience methods matching behavior CPU interface
        def reset
          set_input(:rst, 1)
          step
          set_input(:rst, 0)
        end

        # Run until halted or max cycles
        def execute(max_cycles: 10000)
          reset
          run(max_cycles)
        end
      end
    end
  end
end
