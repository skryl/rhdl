# Apple ][ test harness for MOS6502 CPU

require_relative '../hdl/harness'
require_relative 'apple2_bus'
require_relative 'isa_simulator_native'
require_relative 'isa_simulator'

module Apple2Harness
  # HDL-based runner using cycle-accurate simulation
  class Runner
    attr_reader :cpu, :bus

    def initialize
      @bus = MOS6502::Apple2Bus.new("apple2_bus")
      @cpu = MOS6502::Harness.new(@bus)
    end

    def load_rom(bytes, base_addr:)
      @bus.load_rom(bytes, base_addr: base_addr)
    end

    def load_ram(bytes, base_addr:)
      @bus.load_ram(bytes, base_addr: base_addr)
    end

    def load_disk(path_or_bytes, drive: 0)
      @bus.load_disk(path_or_bytes, drive: drive)
    end

    def disk_loaded?(drive: 0)
      @bus.disk_loaded?(drive: drive)
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
      {
        pc: @cpu.pc,
        a: @cpu.a,
        x: @cpu.x,
        y: @cpu.y,
        sp: @cpu.sp,
        p: @cpu.p,
        cycles: @cpu.clock_count,
        halted: @cpu.halted?,
        simulator_type: simulator_type
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

    # Get the simulator type
    # @return [Symbol] :hdl for cycle-accurate HDL simulation
    def simulator_type
      :hdl
    end

    # Check if using native implementation (HDL is not native)
    def native?
      false
    end

    # Return dry-run information for testing without starting emulation
    # @return [Hash] Information about engine configuration and memory state
    def dry_run_info
      {
        mode: :hdl,
        simulator_type: simulator_type,
        native: native?,
        backend: nil,  # HDL mode doesn't use IR backend
        cpu_state: cpu_state,
        memory_sample: memory_sample
      }
    end

    private

    # Return a sample of memory for verification
    def memory_sample
      {
        zero_page: (0...256).map { |i| @bus.read(i) },
        stack: (0...256).map { |i| @bus.read(0x0100 + i) },
        text_page: (0...1024).map { |i| @bus.read(0x0400 + i) },
        program_area: (0...256).map { |i| @bus.read(0x0800 + i) },
        reset_vector: [@bus.read(0xFFFC), @bus.read(0xFFFD)]
      }
    end
  end

  # ISA-level runner using fast instruction-level simulation
  # Provides the same interface as Runner but uses ISASimulator for performance
  #
  # Memory Model (Native):
  # - CPU has internal 64KB memory for fast execution
  # - I/O region ($C000-$CFFF) calls back to Ruby bus for memory-mapped I/O
  # - External devices read/write via cpu.peek/poke
  #
  # Falls back to pure Ruby ISASimulator if native extension is not available.
  class ISARunner
    attr_reader :cpu, :bus

    def initialize
      @bus = MOS6502::Apple2Bus.new("apple2_bus")
      # Use native Rust implementation with I/O handler for $C000-$CFFF
      # Falls back to pure Ruby if native extension is not available
      if MOS6502::NATIVE_AVAILABLE
        @cpu = MOS6502::ISASimulatorNative.new(@bus)
        # Give bus a reference to CPU for screen reading via peek
        @bus.instance_variable_set(:@native_cpu, @cpu)
      else
        @cpu = MOS6502::ISASimulator.new(@bus)
      end
      # Track speaker toggles synced from native CPU to Ruby speaker
      @synced_speaker_toggles = 0
      @last_speaker_sync = nil
    end

    # Check if using native implementation
    def native?
      @cpu.respond_to?(:native?) && @cpu.native?
    end

    def load_rom(bytes, base_addr:)
      bytes_array = to_bytes(bytes)
      if native?
        # Always load ROM into CPU memory for fast access
        # This includes expansion ROM ($C100-$CFFF) which doesn't need I/O callbacks
        @cpu.load_bytes(bytes_array, base_addr)
        # Also load into bus for non-native fallback paths
        @bus.load_rom(bytes_array, base_addr: base_addr)
      else
        @bus.load_rom(bytes_array, base_addr: base_addr)
      end
    end

    def load_ram(bytes, base_addr:)
      bytes_array = to_bytes(bytes)
      if native?
        # RAM goes directly to CPU memory for fast access
        @cpu.load_bytes(bytes_array, base_addr)
      else
        @bus.load_ram(bytes_array, base_addr: base_addr)
      end
    end

    # Write a single byte to memory (handles native vs non-native mode)
    # Use this for setting up test vectors, reset vector, etc.
    def write_memory(addr, value)
      if native?
        @cpu.poke(addr, value)
      else
        @bus.write(addr, value)
      end
    end

    # Read a single byte from memory (handles native vs non-native mode)
    def read_memory(addr)
      if native?
        @cpu.peek(addr)
      else
        @bus.read(addr)
      end
    end

    private

    def to_bytes(source)
      return source.bytes if source.is_a?(String)
      source
    end

    public

    def load_disk(path_or_bytes, drive: 0)
      @bus.load_disk(path_or_bytes, drive: drive)
    end

    def disk_loaded?(drive: 0)
      @bus.disk_loaded?(drive: drive)
    end

    def reset
      # Both native and Ruby implementations have a reset method
      # that reads the reset vector from memory and initializes registers
      @cpu.reset
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
      if native?
        # Inject key directly into native CPU's I/O state (fast, no FFI callback needed)
        @cpu.inject_key(ascii)
      else
        @bus.inject_key(ascii)
      end
    end

    def key_ready?
      if native?
        @cpu.key_ready?
      else
        @bus.key_ready
      end
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

    # Sync video state from native CPU to Ruby bus (for rendering)
    def sync_video_state
      return unless native?
      video = @cpu.video_state
      @bus.video[:text] = video[:text]
      @bus.video[:mixed] = video[:mixed]
      @bus.video[:page2] = video[:page2]
      @bus.video[:hires] = video[:hires]
    end

    # Sync video state from Ruby bus to native CPU (for initialization)
    # Call this after setting soft switches on the bus to push state to native CPU
    def sync_video_to_native
      return unless native?
      @cpu.set_video_state(
        @bus.video[:text],
        @bus.video[:mixed],
        @bus.video[:page2],
        @bus.video[:hires]
      )
    end

    # Sync speaker toggles from native CPU to Ruby speaker (for audio generation)
    # Called each frame to forward any new speaker toggles to the audio system
    def sync_speaker_state
      return unless native?

      current_toggles = @cpu.speaker_toggles
      new_toggles = current_toggles - @synced_speaker_toggles

      if new_toggles > 0
        # Calculate elapsed time since last sync for timing estimation
        now = Time.now
        elapsed = @last_speaker_sync ? (now - @last_speaker_sync) : 0.016  # Default to ~60fps
        @last_speaker_sync = now

        # Forward toggles to speaker with timing info for proper audio generation
        @bus.speaker.sync_toggles(new_toggles, elapsed)
        @synced_speaker_toggles = current_toggles
      end
    end

    # Get speaker toggle count from native CPU
    def speaker_toggles
      native? ? @cpu.speaker_toggles : @bus.speaker_toggles
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
        halted: @cpu.halted?,
        simulator_type: simulator_type
      }
    end

    def halted?
      @cpu.halted?
    end

    def cycle_count
      @cpu.cycles
    end

    # Get the simulator type
    # @return [Symbol] :native for Rust implementation, :ruby for pure Ruby
    def simulator_type
      native? ? :native : :ruby
    end

    # Return dry-run information for testing without starting emulation
    # @return [Hash] Information about engine configuration and memory state
    def dry_run_info
      {
        mode: :isa,
        simulator_type: simulator_type,
        native: native?,
        backend: nil,  # ISA mode doesn't use IR backend
        cpu_state: cpu_state,
        memory_sample: memory_sample
      }
    end

    private

    # Return a sample of memory for verification
    def memory_sample
      if native?
        # For native mode, read from CPU memory
        {
          zero_page: (0...256).map { |i| @cpu.peek(i) },
          stack: (0...256).map { |i| @cpu.peek(0x0100 + i) },
          text_page: (0...1024).map { |i| @cpu.peek(0x0400 + i) },
          program_area: (0...256).map { |i| @cpu.peek(0x0800 + i) },
          reset_vector: [@cpu.peek(0xFFFC), @cpu.peek(0xFFFD)]
        }
      else
        # For Ruby mode, read from bus using read method
        {
          zero_page: (0...256).map { |i| @bus.read(i) },
          stack: (0...256).map { |i| @bus.read(0x0100 + i) },
          text_page: (0...1024).map { |i| @bus.read(0x0400 + i) },
          program_area: (0...256).map { |i| @bus.read(0x0800 + i) },
          reset_vector: [@bus.read(0xFFFC), @bus.read(0xFFFD)]
        }
      end
    end
  end
end
