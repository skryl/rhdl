module RHDL
  module Examples
    module MOS6502
      module Components
        module CPU
          class MemoryUnit < RHDL::Component
            class << self
              def define_ports
                input :clk
                input :reset
                input :address, width: 8
                input :data_in, width: 8
                input :write_enable
                output :data_out, width: 8
              end
            end

            define_ports

            def initialize
              @memory = Hash.new(0)
            end

            def reset
              @memory.clear
            end

            def read(address)
              @memory[address] || 0
            end

            def write(address, data)
              @memory[address] = data & 0xFF
            end

            def load_program(program)
              program.each_with_index do |instruction, index|
                write(index, instruction)
              end
            end

            def dump(start_addr = 0, length = 16)
              result = []
              length.times do |i|
                addr = start_addr + i
                result << sprintf("0x%02X: 0x%02X", addr, @memory[addr])
              end
              result.join("\n")
            end
          end

          class MemoryAddressRegister < Component
            def initialize(width = 8)
              @width = width

              input :clk
              input :load
              input :data_in, width: width
              output :address, width: width
            end
          end

          class InstructionRegister < Component
            def initialize(width = 8)
              @width = width

              input :clk
              input :load
              input :data_in, width: width
              output :instruction, width: width
              output :address, width: width  # Lower bits used as address
            end
          end
        end
      end
    end
  end
end
