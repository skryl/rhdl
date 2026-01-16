# Apple ][ test harness for MOS6502 CPU

require_relative '../../examples/mos6502/cpu'
require_relative '../../examples/mos6502/apple2_bus'

module Apple2Harness
  class Runner
    attr_reader :cpu, :bus

    def initialize
      @bus = MOS6502::Apple2Bus.new("apple2_bus")
      @cpu = MOS6502::CPU.new(@bus)
    end

    def load_rom(bytes, base_addr:)
      @bus.load_rom(bytes, base_addr: base_addr)
    end

    def load_ram(bytes, base_addr:)
      @bus.load_ram(bytes, base_addr: base_addr)
    end

    def reset
      @cpu.reset
    end

    def run_steps(steps)
      steps.times { @cpu.clock_cycle }
    end

    def run_until(max_cycles: 200_000)
      cycles = 0
      while cycles < max_cycles
        @cpu.clock_cycle
        cycles += 1
        break if yield
      end
      cycles
    end
  end
end
