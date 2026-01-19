module MemorySimulator
  class Memory
    def initialize
      @memory = Array.new(0x10000, 0)  # Initialize 64K of memory to zero
    end

    def read(addr)
      @memory[addr & 0xFFFF]
    end

    def write(addr, value)
      @memory[addr & 0xFFFF] = value & 0xFF
    end

    def load(program, start_addr = 0)
      program.each_with_index do |byte, i|
        write(start_addr + i, byte)
      end
    end
  end
end

RSpec.configure do |config|
  config.before(:each) do
    @memory = MemorySimulator::Memory.new
  end
end
