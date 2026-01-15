# CPU HDL Module
# Gate-level CPU implementation

require_relative 'cpu/datapath'

module RHDL
  module HDL
    module CPU
      # Full CPU wrapper with memory interface
      class CPU < Datapath
        def initialize(name = nil)
          super(name)
        end

        # Convenience methods matching behavioral CPU interface
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
