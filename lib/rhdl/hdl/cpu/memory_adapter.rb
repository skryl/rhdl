# Memory adapter that wraps HDL RAM with behavioral Memory interface

module RHDL
  module HDL
    module CPU
      class MemoryAdapter
        def initialize(ram)
          @ram = ram
        end

        def read(addr)
          @ram.read_mem(addr & 0xFFFF)
        end

        def write(addr, value)
          @ram.write_mem(addr & 0xFFFF, value & 0xFF)
        end

        def load(program, start_addr = 0)
          program.each_with_index do |byte, i|
            write(start_addr + i, byte)
          end
        end
      end
    end
  end
end
