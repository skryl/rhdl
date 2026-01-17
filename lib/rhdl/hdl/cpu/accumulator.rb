# Accumulator Register (8-bit)

module RHDL
  module HDL
    module CPU
      class Accumulator < Register
        def initialize(name = nil)
          super(name, width: 8)
        end
      end
    end
  end
end
