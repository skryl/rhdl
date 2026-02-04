# CPU Harness - Pure Memory Interface
# This harness contains NO control logic - all sequencing is in the CPU.
# The harness only:
#   1. Connects CPU to memory
#   2. Drives the clock
#
# This is the target architecture that matches the MOS6502 harness pattern.

require_relative 'cpu'

module RHDL
  module HDL
    module CPU
      # 64K Memory for harness (16-bit addressing)
      # Uses a simple Ruby array instead of HDL RAM component
      # to support full 16-bit address space
      class Memory64K
        def initialize
          @data = Array.new(0x10000, 0)
        end

        def read(addr)
          @data[addr & 0xFFFF] || 0
        end
        alias read_mem read

        def write(addr, value)
          @data[addr & 0xFFFF] = value & 0xFF
        end
        alias write_mem write

        def load(program, start_addr = 0)
          program.each_with_index do |byte, i|
            write(start_addr + i, byte)
          end
        end
      end

      # Fast Harness using IR Compiler for high-performance simulation
      # Uses native Rust backend instead of Ruby behavioral simulation
      class FastHarness
        attr_reader :memory, :halted, :cycle_count

        def initialize(external_memory = nil, sim: :compile)
          require 'rhdl/codegen'

          @cycle_count = 0
          @halted = false
          @memory = Memory64K.new
          @sim_backend = sim

          # Generate IR from CPU component
          ir = RHDL::HDL::CPU::CPU.to_flat_ir
          ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

          # Create simulator based on backend
          @sim = case sim
          when :interpret
            require 'rhdl/codegen/ir/sim/ir_interpreter'
            RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json, allow_fallback: true)
          when :jit
            require 'rhdl/codegen/ir/sim/ir_jit'
            RHDL::Codegen::IR::IrJitWrapper.new(ir_json, allow_fallback: true)
          when :compile
            require 'rhdl/codegen/ir/sim/ir_compiler'
            RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json, allow_fallback: true)
          else
            raise "Unknown sim backend: #{sim}"
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

        def native?
          @sim.native?
        end

        def backend
          @sim.backend
        end

        # Read CPU state
        def acc
          @sim.peek('acc_out')
        end

        def pc
          @sim.peek('pc_out')
        end

        def sp
          @sim.peek('sp_out')
        end

        def pc=(value)
          # Set PC by poking the register value directly
          @sim.poke('pc_reg__q', value & 0xFFFF)
          @sim.evaluate
        end

        def state
          @sim.peek('state_out')
        end

        def zero_flag
          @sim.peek('zero_flag_out') == 1
        end

        # Legacy accessors
        def acc_value; acc; end
        def pc_value; pc; end
        def sp_value; sp; end
        def zero_flag_value; zero_flag ? 1 : 0; end

        def reset
          @halted = false
          @cycle_count = 0

          @sim.poke('rst', 1)
          @sim.poke('mem_data_in', 0)
          clock_cycle
          @sim.poke('rst', 0)
          @sim.evaluate
        end

        def clock_cycle
          # Get memory address and control signals
          addr = @sim.peek('mem_addr')
          write_en = @sim.peek('mem_write_en')

          # Memory write
          if write_en == 1
            data = @sim.peek('mem_data_out')
            @memory.write(addr, data)
          end

          # Provide memory data
          data = @memory.read(addr)
          @sim.poke('mem_data_in', data)
          @sim.evaluate

          # Clock edge
          @sim.poke('clk', 0)
          @sim.evaluate
          @sim.poke('clk', 1)
          @sim.tick

          # Check for halt
          @halted = true if @sim.peek('halted') == 1
        end

        def run(max_cycles = 10000)
          cycles = 0
          until @halted || cycles >= max_cycles
            clock_cycle
            cycles += 1
            @cycle_count += 1
          end
          cycles
        end

        # Expose ram for backwards compatibility
        def ram
          @memory
        end

        # Expose cpu-like interface for test compatibility
        def cpu
          self
        end

        def get_output(name)
          @sim.peek(name.to_s)
        end

        def get_input(name)
          # Not directly supported in IR sim
          0
        end
      end

      # Harness - pure memory interface
      class Harness
        attr_reader :memory, :halted, :cycle_count
        attr_reader :cpu, :ram

        def initialize(external_memory = nil, name: nil, memory_contents: [])
          @cycle_count = 0
          @halted = false

          # Create CPU (with internal control unit) and 64K memory
          @cpu = CPU.new(name || "cpu")
          @memory = Memory64K.new
          @ram = @memory  # Alias for backwards compatibility

          # Load initial memory contents
          memory_contents.each_with_index do |byte, addr|
            @memory.write(addr, byte)
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

        # Set PC directly (for loading programs at non-zero addresses)
        def pc=(value)
          # Directly set the PC register's state using write_reg
          subcomponents = @cpu.instance_variable_get(:@subcomponents)
          pc_reg = subcomponents[:pc_reg] if subcomponents
          if pc_reg
            pc_reg.write_reg(:q, value & 0xFFFF)
            @cpu.propagate
          end
        end

        def state
          @cpu.get_output(:state_out)
        end

        # Zero flag accessor (read from CPU output)
        def zero_flag
          @cpu.get_output(:zero_flag_out) == 1
        end

        # Legacy accessors
        def acc_value; acc; end
        def pc_value; pc; end
        def sp_value; sp; end
        def zero_flag_value; zero_flag ? 1 : 0; end

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
        # State machine: RESET(0) -> FETCH(1) -> DECODE(2) -> [operand fetch] -> [READ_MEM] -> EXECUTE(6) -> FETCH(1)
        S_FETCH = 0x01
        S_DECODE = 0x02

        def step
          return if @halted

          max_cycles = 50  # Safety limit

          # First, advance past any reset state to get to FETCH
          max_cycles.times do
            break if state == S_FETCH
            clock_cycle
            @cycle_count += 1
            break if @halted
          end

          # Now run through the instruction until we return to FETCH
          # (or pass through DECODE, which starts the next instruction)
          left_fetch = false
          max_cycles.times do
            clock_cycle
            @cycle_count += 1
            break if @halted

            if state != S_FETCH
              left_fetch = true
            end

            # Stop when we're back at FETCH after leaving it
            break if left_fetch && state == S_FETCH
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
