# Apple ][ test harness for MOS6502 CPU

require_relative '../hdl/cpu_harness'
require_relative 'apple2_bus'
require_relative 'isa_simulator'

module Apple2Harness
  # HDL-based runner using cycle-accurate simulation
  class Runner
    attr_reader :cpu, :bus

    def initialize
      @bus = MOS6502::Apple2Bus.new("apple2_bus")
      @cpu = MOS6502::CPUHarness.new(@bus)
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

    # Terminal I/O helpers

    # Inject a key into the keyboard buffer
    def inject_key(ascii)
      @bus.inject_key(ascii)
    end

    # Check if a key is ready to be read
    def key_ready?
      @bus.key_ready
    end

    # Clear the keyboard ready flag
    def clear_key
      @bus.clear_key
    end

    # Read the text page as 24 lines of strings
    def read_screen
      @bus.read_text_page_string
    end

    # Read the text page as a 2D array of character codes
    def read_screen_array
      @bus.read_text_page
    end

    # Check if the screen has been modified since last clear
    def screen_dirty?
      @bus.text_page_dirty?
    end

    # Clear the screen dirty flag
    def clear_screen_dirty
      @bus.clear_text_page_dirty
    end

    # Get CPU state for debugging
    def cpu_state
      dp = @cpu.datapath
      {
        pc: dp.read_pc,
        a: dp.read_a,
        x: dp.read_x,
        y: dp.read_y,
        sp: dp.read_sp,
        p: dp.read_p,
        cycles: @cpu.clock_count,
        halted: @cpu.halted?
      }
    end

    # Check if CPU is halted
    def halted?
      @cpu.halted?
    end

    # Get total CPU cycles
    def cycle_count
      @cpu.clock_count
    end
  end

  # ISA-level runner using fast instruction-level simulation
  # Provides the same interface as Runner but uses ISASimulator for performance
  class ISARunner
    attr_reader :cpu, :bus

    def initialize
      @bus = MOS6502::Apple2Bus.new("apple2_bus")
      @cpu = MOS6502::ISASimulator.new(@bus)
    end

    def load_rom(bytes, base_addr:)
      @bus.load_rom(bytes, base_addr: base_addr)
    end

    def load_ram(bytes, base_addr:)
      @bus.load_ram(bytes, base_addr: base_addr)
    end

    def reset
      # Read reset vector from bus
      lo = @bus.read(MOS6502::ISASimulator::RESET_VECTOR)
      hi = @bus.read(MOS6502::ISASimulator::RESET_VECTOR + 1)
      @cpu.pc = (hi << 8) | lo
      @cpu.instance_variable_set(:@sp, 0xFD)
      @cpu.instance_variable_set(:@p, 0x24)
      @cpu.instance_variable_set(:@a, 0)
      @cpu.instance_variable_set(:@x, 0)
      @cpu.instance_variable_set(:@y, 0)
      @cpu.instance_variable_set(:@cycles, 0)
      @cpu.instance_variable_set(:@halted, false)
    end

    def run_steps(steps)
      # Run approximately this many cycles worth of instructions
      @cpu.run_cycles(steps)
    end

    def run_until(max_cycles: 200_000)
      cycles = 0
      start_cycles = @cpu.cycles
      while (@cpu.cycles - start_cycles) < max_cycles && !@cpu.halted?
        @cpu.step
        break if yield
      end
      @cpu.cycles - start_cycles
    end

    # Terminal I/O helpers

    def inject_key(ascii)
      @bus.inject_key(ascii)
    end

    def key_ready?
      @bus.key_ready
    end

    def clear_key
      @bus.clear_key
    end

    def read_screen
      @bus.read_text_page_string
    end

    def read_screen_array
      @bus.read_text_page
    end

    def screen_dirty?
      @bus.text_page_dirty?
    end

    def clear_screen_dirty
      @bus.clear_text_page_dirty
    end

    def cpu_state
      {
        pc: @cpu.pc,
        a: @cpu.a,
        x: @cpu.x,
        y: @cpu.y,
        sp: @cpu.sp,
        p: @cpu.p,
        cycles: @cpu.cycles,
        halted: @cpu.halted?
      }
    end

    def halted?
      @cpu.halted?
    end

    def cycle_count
      @cpu.cycles
    end
  end
end
