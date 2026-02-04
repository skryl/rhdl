module RHDL
  module Components
    module CPU
      class Accumulator < RHDL::Component
        class << self
          def define_ports
            input :clk
            input :reset
            input :data_in, width: 8
            input :load
            output :data_out, width: 8
          end
        end

        define_ports

        def initialize
          @value = 0
        end

        def reset
          @value = 0
        end

        def value=(new_value)
          @value = new_value & 0xFF  # Keep within 8 bits
        end

        def value
          @value
        end
      end
    end
  end
end
