# Minimal CPU Harness - Pure Memory Interface
# This harness contains NO control logic - all sequencing is in the CPU.
# The harness only:
#   1. Connects CPU to memory
#   2. Drives the clock
#
# This is the target architecture that matches the MOS6502 harness pattern.

require_relative 'cpu_with_control'

module RHDL
  module HDL
    module CPU
      # Memory interface for the minimal harness
      class MinimalMemory
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

      # Minimal Harness - pure memory interface
      class MinimalHarness
        attr_reader :memory, :halted, :cycle_count
        attr_reader :cpu, :ram

        def initialize(external_memory = nil, name: nil, memory_contents: [])
          @cycle_count = 0
          @halted = false

          # Create CPU (with internal control unit) and RAM
          @cpu = CPUWithControl.new(name || "cpu")
          @ram = RAM.new("mem", data_width: 8, addr_width: 16)
          @memory = MinimalMemory.new(@ram)

          # Load initial memory contents
          memory_contents.each_with_index do |byte, addr|
            @ram.write_mem(addr, byte)
          end

          # Copy external memory if provided
          if external_memory && !external_memory.is_a?(String)
            (0..0xFFFF).each do |addr|
              val = external_memory.read(addr)
              @memory.write(addr, val) if val != 0
            end
          end

          reset
        end

        # Read CPU state through output ports
        def acc
          @cpu.get_output(:acc_out)
        end

        def pc
          @cpu.get_output(:pc_out)
        end

        def sp
          @cpu.get_output(:sp_out)
        end

        def state
          @cpu.get_output(:state_out)
        end

        # Legacy accessors
        def acc_value; acc; end
        def pc_value; pc; end
        def sp_value; sp; end

        # Reset the CPU
        def reset
          @halted = false
          @cycle_count = 0

          @cpu.set_input(:rst, 1)
          clock_cycle
          @cpu.set_input(:rst, 0)
          @cpu.propagate
        end

        # Execute one clock cycle
        def clock_cycle
          # Get memory address from CPU
          addr = @cpu.get_output(:mem_addr)
          write_en = @cpu.get_output(:mem_write_en)
          read_en = @cpu.get_output(:mem_read_en)

          # Memory write (on current cycle)
          if write_en == 1
            data = @cpu.get_output(:mem_data_out)
            @ram.write_mem(addr, data)
          end

          # Provide memory data BEFORE clock edge (for register latching)
          data = @ram.read_mem(addr)
          @cpu.set_input(:mem_data_in, data)
          @cpu.propagate

          # Clock the CPU (rising edge latches data)
          @cpu.set_input(:clk, 0)
          @cpu.propagate
          @cpu.set_input(:clk, 1)
          @cpu.propagate

          # Check for halt
          if @cpu.get_output(:halted) == 1
            @halted = true
          end
        end

        # Step one instruction (may take multiple cycles)
        def step
          return if @halted

          # Run clock cycles until instruction completes
          initial_pc = pc
          max_cycles = 20  # Safety limit

          max_cycles.times do
            clock_cycle
            @cycle_count += 1
            break if @halted
            break if pc != initial_pc  # PC changed = instruction complete
          end
        end

        # Run until halted or max cycles
        def run(max_cycles = 10000)
          cycles = 0
          until @halted || cycles >= max_cycles
            clock_cycle
            cycles += 1
            @cycle_count += 1
          end
          cycles
        end

        # Execute from reset
        def execute(max_cycles: 10000)
          reset
          run(max_cycles)
        end

        # Memory convenience methods
        def read_memory(addr)
          @memory.read(addr)
        end

        def write_memory(addr, value)
          @memory.write(addr, value)
        end

        def load_program(program, start_addr = 0)
          @memory.load(program, start_addr)
        end
      end
    end
  end
end
