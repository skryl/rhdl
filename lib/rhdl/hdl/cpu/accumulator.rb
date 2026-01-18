# Accumulator Register (8-bit)

module RHDL
  module HDL
    module CPU
      class Accumulator < Register
        parameter :width, default: 8
      end
    end
  end
end
