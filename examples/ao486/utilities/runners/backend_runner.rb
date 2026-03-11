# frozen_string_literal: true

require_relative '../display_adapter'

module RHDL
  module Examples
    module AO486
      class BackendRunner
        DEFAULT_UNLIMITED_CHUNK = 100_000
        SOFTWARE_ROOT = File.expand_path('../../software', __dir__)
        ROM_ROOT = File.join(SOFTWARE_ROOT, 'rom')
        BIN_ROOT = File.join(SOFTWARE_ROOT, 'bin')
        BOOT0_ADDR = 0xF0000
        BOOT1_ADDR = 0xC0000
        CURSOR_BDA = DisplayAdapter::CURSOR_BDA

        attr_reader :backend, :sim_backend, :cycles_run, :floppy_image, :import_runtime, :last_run_stats

        def initialize(backend:, sim: nil, debug: false, speed: nil, headless: false, cycles: nil, import_runtime: nil)
          @backend = backend.to_sym
          @sim_backend = sim&.to_sym
          @debug = !!debug
          @speed = speed
          @headless = !!headless
          @requested_cycles = cycles
          @import_runtime = import_runtime
          @memory = Hash.new(0)
          @rom = {}
          @floppy_image = nil
          @cycles_run = 0
          @last_io = nil
          @last_irq = nil
          @last_run_stats = nil
          @keyboard_buffer = +''
          @shell_prompt_detected = false
          @display_adapter = DisplayAdapter.new
          @display_buffer = Array.new(DisplayAdapter::TEXT_ROWS * DisplayAdapter::TEXT_COLUMNS * 2, 0)
          set_cursor(0, 0)
        end

        def software_root
          SOFTWARE_ROOT
        end

        def software_path(*parts)
          return software_root if parts.empty?

          File.expand_path(File.join(*parts), software_root)
        end

        def bios_paths
          {
            boot0: software_path('rom', 'boot0.rom'),
            boot1: software_path('rom', 'boot1.rom')
          }
        end

        def dos_path
          software_path('bin', 'fdboot.img')
        end

        def load_bios(boot0: bios_paths.fetch(:boot0), boot1: bios_paths.fetch(:boot1))
          boot0_path = File.expand_path(boot0)
          boot1_path = File.expand_path(boot1)
          ensure_file!(boot0_path, 'AO486 BIOS ROM')
          ensure_file!(boot1_path, 'AO486 BIOS ROM')

          boot0_bytes = File.binread(boot0_path).bytes
          boot1_bytes = File.binread(boot1_path).bytes

          load_bytes(BOOT0_ADDR, boot0_bytes, target: @rom)
          load_bytes(BOOT1_ADDR, boot1_bytes, target: @rom)

          {
            boot0: { path: boot0_path, size: boot0_bytes.length },
            boot1: { path: boot1_path, size: boot1_bytes.length }
          }
        end

        def load_dos(path: dos_path)
          dos_image_path = File.expand_path(path)
          ensure_file!(dos_image_path, 'AO486 DOS image')
          @floppy_image = File.binread(dos_image_path)

          {
            path: dos_image_path,
            size: @floppy_image.bytesize,
            bytes: @floppy_image.dup
          }
        end

        def load_bytes(base, bytes, target: @memory)
          if imported_runtime? && target.equal?(@memory)
            @import_runtime.load_bytes(base, bytes)
            return self
          end

          normalized_bytes = bytes.is_a?(String) ? bytes.bytes : Array(bytes)
          normalized_bytes.each_with_index do |byte, idx|
            target[base + idx] = byte.to_i & 0xFF
          end
          self
        end

        def read_bytes(base, length, mapped: true)
          return @import_runtime.read_bytes(base, length) if imported_runtime?

          Array.new(length) do |idx|
            addr = base + idx
            if mapped && @rom.key?(addr)
              @rom.fetch(addr)
            else
              @memory.fetch(addr, 0)
            end
          end
        end

        def write_memory(addr, value)
          return load_bytes(addr, [value]) if imported_runtime?

          @memory[addr] = value.to_i & 0xFF
        end

        def clear_memory!
          if imported_runtime?
            @import_runtime.clear_memory! if @import_runtime.respond_to?(:clear_memory!)
          else
            @memory.clear
          end
          self
        end

        def bios_loaded?
          !@rom.empty?
        end

        def dos_loaded?
          !@floppy_image.nil?
        end

        def native?
          true
        end

        def simulator_type
          :"ao486_#{backend}"
        end

        def display_buffer
          @display_buffer.dup
        end

        def memory
          imported_runtime? ? @import_runtime.memory : @memory
        end

        def sim
          return nil unless imported_runtime?
          return nil unless @import_runtime.respond_to?(:sim)

          @import_runtime.sim
        end

        def update_display_buffer(buffer)
          @display_buffer = Array(buffer).dup
          @display_buffer.each_with_index do |byte, idx|
            @memory[DisplayAdapter::TEXT_BASE + idx] = byte.to_i & 0xFF
          end
          self
        end

        def render_display(debug_lines: [])
          @display_adapter.render(memory: @memory, cursor: :auto, debug_lines: Array(debug_lines))
        end

        def cursor_position
          page = @memory.fetch(DisplayAdapter::VIDEO_PAGE_BDA, 0) & 0xFF
          base = CURSOR_BDA + (page * 2)
          {
            row: @memory.fetch(base + 1, 0),
            col: @memory.fetch(base, 0),
            page: page
          }
        end

        def reset
          @import_runtime.reset! if imported_runtime? && @import_runtime.respond_to?(:reset!)
          @cycles_run = 0
          @last_run_stats = nil
          @keyboard_buffer.clear
          @shell_prompt_detected = false
          self
        end

        def run(cycles: nil, speed: nil, headless: @headless, max_cycles: nil)
          if imported_runtime? && !max_cycles.nil? && @import_runtime.respond_to?(:run)
            return capture_run_stats(operation: :run, cycles: max_cycles) do
              @import_runtime.run(max_cycles: max_cycles)
            end
          end

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          start_cycles = @cycles_run
          chunk = cycles || @requested_cycles || speed || @speed || DEFAULT_UNLIMITED_CHUNK
          @cycles_run += tick_backend(chunk.to_i)
          @shell_prompt_detected ||= false
          record_run_stats(operation: :run, cycles: @cycles_run - start_cycles, started_at: started_at)

          state.merge(cycles: @cycles_run, speed: speed || @speed, headless: headless)
        end

        def send_keys(text)
          @keyboard_buffer << text.to_s
          self
        end

        def state
          snapshot = {
            backend: backend,
            sim_backend: sim_backend,
            simulator_type: simulator_type,
            native: native?,
            bios_loaded: bios_loaded?,
            dos_loaded: dos_loaded?,
            cycles_run: @cycles_run,
            floppy_image_size: @floppy_image&.bytesize || 0,
            last_io: @last_io,
            last_irq: @last_irq,
            keyboard_buffer_size: @keyboard_buffer.bytesize,
            shell_prompt_detected: @shell_prompt_detected,
            cursor: cursor_position,
            last_run_stats: @last_run_stats
          }
          snapshot[:import_runtime] = true if imported_runtime?
          snapshot
        end

        def run_fetch_words(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch-word traces" unless imported_runtime?

          capture_run_stats(operation: :run_fetch_words, cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK) do
            @import_runtime.run_fetch_words(max_cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK)
          end
        end

        def run_fetch_trace(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch traces" unless imported_runtime?

          capture_run_stats(operation: :run_fetch_trace, cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK) do
            @import_runtime.run_fetch_trace(max_cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK)
          end
        end

        def run_fetch_groups(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch-group traces" unless imported_runtime?

          capture_run_stats(operation: :run_fetch_groups, cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK) do
            @import_runtime.run_fetch_groups(max_cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK)
          end
        end

        def run_fetch_pc_groups(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch-pc traces" unless imported_runtime?

          capture_run_stats(operation: :run_fetch_pc_groups, cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK) do
            @import_runtime.run_fetch_pc_groups(max_cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK)
          end
        end

        def run_step_trace(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support step traces" unless imported_runtime?

          capture_run_stats(operation: :run_step_trace, cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK) do
            @import_runtime.run_step_trace(max_cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK)
          end
        end

        def run_final_state(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support final-state traces" unless imported_runtime?

          capture_run_stats(operation: :run_final_state, cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK) do
            @import_runtime.run_final_state(max_cycles: max_cycles || DEFAULT_UNLIMITED_CHUNK)
          end
        end

        def final_state_snapshot
          raise NoMethodError, "#{self.class} does not support final-state snapshots" unless imported_runtime?
          raise NoMethodError, "#{self.class} runtime does not expose final_state_snapshot" unless @import_runtime.respond_to?(:final_state_snapshot)

          @import_runtime.final_state_snapshot
        end

        def step(cycle)
          raise NoMethodError, "#{self.class} does not support single-cycle stepping" unless imported_runtime?
          raise NoMethodError, "#{self.class} runtime does not expose step" unless @import_runtime.respond_to?(:step)

          @import_runtime.step(cycle)
        end

        def peek(signal_name)
          current_sim = sim
          raise NoMethodError, "#{self.class} does not expose signal peeks" unless current_sim&.respond_to?(:peek)

          current_sim.peek(signal_name)
        end

        protected

        def imported_runtime?
          !@import_runtime.nil?
        end

        def capture_run_stats(operation:, cycles:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = yield
          record_run_stats(operation: operation, cycles: cycles, started_at: started_at)
          result
        end

        def record_run_stats(operation:, cycles:, started_at:)
          elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          cycles_per_second = elapsed_seconds.positive? ? (cycles.to_f / elapsed_seconds) : Float::INFINITY
          @last_run_stats = {
            backend: backend,
            operation: operation,
            cycles: cycles.to_i,
            elapsed_seconds: elapsed_seconds,
            cycles_per_second: cycles_per_second
          }
        end

        def tick_backend(cycles)
          [cycles, 0].max
        end

        def rom_store
          @rom
        end

        def memory_store
          @memory
        end

        def set_cursor(row, col)
          @memory[CURSOR_BDA] = col.to_i & 0xFF
          @memory[CURSOR_BDA + 1] = row.to_i & 0xFF
        end

        def ensure_file!(path, label)
          return if File.file?(path)

          raise ArgumentError, "#{label} not found: #{path}"
        end
      end
    end
  end
end
