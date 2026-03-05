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

      # 64K memory view backed by the native runner memory ABI.
      class RunnerMemory64K
        def initialize(sim)
          @sim = sim
        end

        def read(addr)
          @sim.runner_read_memory(addr & 0xFFFF, 1, mapped: false).first.to_i & 0xFF
        end
        alias read_mem read

        def write(addr, value)
          @sim.runner_write_memory(addr & 0xFFFF, [value & 0xFF], mapped: false)
          value & 0xFF
        end
        alias write_mem write

        def load(program, start_addr = 0)
          bytes = program.is_a?(String) ? program.b.bytes : Array(program)
          return if bytes.empty?

          @sim.runner_load_memory(bytes, start_addr & 0xFFFF, false)
        end
      end

      # Fast Harness using IR Compiler for high-performance simulation
      # Uses native Rust backend instead of Ruby behavioral simulation
      class FastHarness
        attr_reader :memory, :halted, :cycle_count

        def self.arcilator_gpu_status
          require_relative '../../utilities/runners/arcilator_gpu_runner'
          RHDL::Examples::CPU8Bit::ArcilatorGpuRunner.status
        rescue LoadError, NameError => e
          {
            ready: false,
            missing_tools: [],
            missing_capabilities: ["arcilator_gpu runner unavailable: #{e.message}"]
          }
        end

        def self.ensure_arcilator_gpu_available!
          status = arcilator_gpu_status
          return true if status[:ready]

          details = []
          details << "missing tools: #{status[:missing_tools].join(', ')}" unless status[:missing_tools].empty?
          details << "missing capabilities: #{status[:missing_capabilities].join(', ')}" unless status[:missing_capabilities].empty?
          raise ArgumentError,
            "arcilator_gpu backend unavailable (#{details.join('; ')}). " \
            "Install an ArcToGPU-enabled arcilator build plus Metal/SPIR-V toolchain support."
        end

        def self.synth_to_gpu_status
          require_relative '../../utilities/runners/synth_to_gpu_runner'
          RHDL::Examples::CPU8Bit::SynthToGpuRunner.status(pipeline: :synth_to_gpu)
        rescue LoadError, NameError => e
          {
            ready: false,
            missing_tools: ["synth_to_gpu runner unavailable: #{e.message}"]
          }
        end

        def self.ensure_synth_to_gpu_available!
          status = synth_to_gpu_status
          return true if status[:ready]

          raise ArgumentError,
            "synth_to_gpu backend unavailable (missing tools: #{status[:missing_tools].join(', ')}). " \
            'Install CIRCT tools and the macOS Metal toolchain.'
        end

        def self.metal_arc_to_gpu_status
          require_relative '../../utilities/runners/synth_to_gpu_runner'
          RHDL::Examples::CPU8Bit::SynthToGpuRunner.status(pipeline: :arc_to_gpu)
        rescue LoadError, NameError => e
          {
            ready: false,
            missing_tools: ["metal_arc_to_gpu runner unavailable: #{e.message}"]
          }
        end

        def self.ensure_metal_arc_to_gpu_available!
          status = metal_arc_to_gpu_status
          return true if status[:ready]

          raise ArgumentError,
            "metal_arc_to_gpu backend unavailable (missing tools: #{status[:missing_tools].join(', ')}). " \
            'Install CIRCT/arcilator tools and the macOS Metal toolchain.'
        end

        def self.gem_gpu_status
          require_relative '../../utilities/runners/synth_to_gpu_runner'
          RHDL::Examples::CPU8Bit::SynthToGpuRunner.status(pipeline: :gem_gpu)
        rescue LoadError, NameError => e
          {
            ready: false,
            missing_tools: ["gem_gpu runner unavailable: #{e.message}"]
          }
        end

        def self.ensure_gem_gpu_available!
          status = gem_gpu_status
          return true if status[:ready]

          raise ArgumentError,
            "gem_gpu backend unavailable (missing tools: #{status[:missing_tools].join(', ')}). " \
            'Install CIRCT tools and the macOS Metal toolchain.'
        end

        def initialize(external_memory = nil, sim: :compile)
          require 'rhdl/codegen'

          @cycle_count = 0
          @halted = false
          @sim_backend = normalize_sim_backend(sim)

          if arcilator_gpu_mode?
            self.class.ensure_arcilator_gpu_available!
            require_relative '../../utilities/runners/arcilator_gpu_runner'
            @sim = RHDL::Examples::CPU8Bit::ArcilatorGpuRunner.new
            @memory = RunnerMemory64K.new(@sim)
            ensure_runner_cpu8bit_mode!
          elsif synth_to_gpu_mode?
            self.class.ensure_synth_to_gpu_available!
            require_relative '../../utilities/runners/synth_to_gpu_runner'
            @sim = RHDL::Examples::CPU8Bit::SynthToGpuRunner.new(pipeline: :synth_to_gpu)
            @memory = RunnerMemory64K.new(@sim)
            ensure_runner_cpu8bit_mode!
          elsif metal_arc_to_gpu_mode?
            self.class.ensure_metal_arc_to_gpu_available!
            require_relative '../../utilities/runners/synth_to_gpu_runner'
            @sim = RHDL::Examples::CPU8Bit::SynthToGpuRunner.new(pipeline: :arc_to_gpu)
            @memory = RunnerMemory64K.new(@sim)
            ensure_runner_cpu8bit_mode!
          elsif gem_gpu_mode?
            self.class.ensure_gem_gpu_available!
            require_relative '../../utilities/runners/synth_to_gpu_runner'
            @sim = RHDL::Examples::CPU8Bit::SynthToGpuRunner.new(pipeline: :gem_gpu)
            @memory = RunnerMemory64K.new(@sim)
            ensure_runner_cpu8bit_mode!
          else
            # Generate IR from CPU component
            ir = RHDL::HDL::CPU::CPU.to_flat_ir
            ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

            require 'rhdl/codegen/ir/sim/ir_simulator'
            @sim = RHDL::Codegen::IR::IrSimulator.new(
              ir_json,
              backend: simulator_backend,
              allow_fallback: true
            )
            @memory = Memory64K.new
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
          return :arcilator_gpu if arcilator_gpu_mode?
          return :synth_to_gpu if synth_to_gpu_mode?
          return :metal_arc_to_gpu if metal_arc_to_gpu_mode?
          return :gem_gpu if gem_gpu_mode?

          @sim.backend
        end

        def parallel_instances
          return 1 unless runner_backend_mode?
          return 1 unless @sim.respond_to?(:runner_parallel_instances)

          instances = @sim.runner_parallel_instances.to_i
          instances.positive? ? instances : 1
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

          if runner_backend_mode?
            @sim.poke('rst', 1)
            run_runner_cycles(1)
            @sim.poke('rst', 0)
            @sim.evaluate
            @halted = true if @sim.peek('halted') == 1
            return
          end

          @sim.poke('rst', 1)
          @sim.poke('mem_data_in', 0)
          clock_cycle
          @sim.poke('rst', 0)
          @sim.evaluate
        end

        def clock_cycle
          if runner_backend_mode?
            run_runner_cycles(1)
            @halted = true if @sim.peek('halted') == 1
            return
          end

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

        def run_cycles(count, batch_size: 1024)
          n = count.to_i
          return 0 if n <= 0

          unless runner_backend_mode?
            ran = 0
            n.times do
              break if @halted

              clock_cycle
              ran += 1
              @cycle_count += 1
            end
            return ran
          end

          # Native runner backends handle internal batching/scheduling.
          # Keep host-side execution as a single call to avoid extra sync points.
          ran = run_runner_cycles(n)
          @cycle_count += ran
          @halted = true if @sim.peek('halted') == 1
          ran
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

        private

        def normalize_sim_backend(sim)
          sym = sim.to_sym
          return :compile if sym == :compiler
          return :gem_gpu if sym == :gem

          sym
        end

        def simulator_backend
          @sim_backend
        end

        def arcilator_gpu_mode?
          @sim_backend == :arcilator_gpu
        end

        def synth_to_gpu_mode?
          @sim_backend == :synth_to_gpu
        end

        def metal_arc_to_gpu_mode?
          @sim_backend == :metal_arc_to_gpu
        end

        def gem_gpu_mode?
          @sim_backend == :gem_gpu
        end

        def runner_backend_mode?
          arcilator_gpu_mode? || synth_to_gpu_mode? || metal_arc_to_gpu_mode? || gem_gpu_mode?
        end

        def ensure_runner_cpu8bit_mode!
          return if @sim.runner_mode? && @sim.runner_kind == :cpu8bit

          raise ArgumentError,
            "#{@sim_backend} backend requires native cpu8bit runner mode " \
            "(runner_mode=#{@sim.runner_mode?}, runner_kind=#{@sim.runner_kind.inspect})"
        end

        def run_runner_cycles(n)
          result = @sim.runner_run_cycles(n, 0, false)
          cycles = if result.is_a?(Hash)
            result.fetch(:cycles_run, n).to_i
          else
            n
          end
          [[cycles, 0].max, n].min
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
