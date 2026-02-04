module RHDL
  module Examples
    module MOS6502
      module Components
        module CPU
          class CpuALU < RHDL::Component
            class << self
              def define_ports
                input :clk
                input :reset
                input :a, width: 8
                input :b, width: 8
                input :op, width: 4
                output :result, width: 8
                output :zero_flag
              end
            end

            define_ports
            attr_accessor :a, :b, :op, :result, :zero_flag


            def initialize
              reset
            end

            def reset
              @a = 0
              @b = 0
              @op = 0
              @result = 0
              @zero_flag = false
            end

            def operate
              case @op
              when :ADD
                @result = (@a + @b) & 0xFF
              when :SUB
                @result = (@a - @b) & 0xFF
              when :AND
                @result = (@a & @b) & 0xFF
              when :OR
                @result = (@a | @b) & 0xFF
              when :XOR
                @result = (@a ^ @b) & 0xFF
              when :NOT
                @result = (~@a) & 0xFF
              when :MUL
                @result = (@a * @b) & 0xFF
              when :DIV
                if @b == 0
                  @result = 0
                  @zero_flag = true
                else
                  @result = (@a / @b) & 0xFF
                  @zero_flag = (@result == 0)
                end
              else
                @result = 0
              end
              @zero_flag = (@result == 0)
            end

          end
        end
      end
    end
  end
end
