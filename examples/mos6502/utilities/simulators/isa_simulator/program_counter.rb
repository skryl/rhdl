module RHDL
  module Examples
    module MOS6502
      module Components
        module CPU
          class ProgramCounter < RHDL::Component
            class << self
              def define_ports
                input :clk
                input :reset
                input :load
                input :increment
                input :data_in, width: 8
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

            def increment
              @value = (@value + 1) & 0xFF
            end
          end
        end
      end
    end
  end
end
