# frozen_string_literal: true

require 'tmpdir'
require 'thread'

require 'rhdl/codegen'
require 'rhdl/sim/native/ir/simulator'

require_relative 'backend_runner'
require_relative '../import/cpu_importer'

module RHDL
  module Examples
    module AO486
      class IrRunner < BackendRunner
        DEFAULT_UNLIMITED_CHUNK = 100_000
        RESET_VECTOR_PHYSICAL = 0xFFFF0
        DEFAULT_FETCH_BURST_BEATS = 8
        PARITY_DEFAULT_MAX_CYCLES = 200
        STARTUP_CS_BASE = 0xF0000
        FINAL_STATE_SIGNALS = %w[
          trace_arch_new_export
          trace_arch_eax
          trace_arch_ebx
          trace_arch_ecx
          trace_arch_edx
          trace_arch_esi
          trace_arch_edi
          trace_arch_esp
          trace_arch_ebp
          trace_arch_eip
          trace_wr_eip
          trace_wr_consumed
          trace_wr_hlt_in_progress
          trace_wr_finished
          trace_wr_ready
          trace_retired
        ].freeze
        POST_INIT_IVT_CALL_OFFSET = 0xE0C6
        POST_INIT_IVT_CALL_PATCH = [0x90, 0x90, 0x90].freeze
        DOS_POST_BOOTSTRAP_HELPER_OFFSET = 0x1080
        DOS_POST_BOOTSTRAP_PATCH = [0xE9, 0xB7, 0x2F].freeze
        DOS_BOOT_SECTOR_ADDR = 0x7C00
        DOS_RELOCATED_BOOT_SECTOR_ADDR = 0x27A00
        DOS_INT19_STUB_ADDR = 0x0500
        DOS_INT19_VECTOR_ADDR = 0x19 * 4
        DOS_INT10_STUB_ADDR = 0x05E0
        DOS_INT10_VECTOR_ADDR = 0x10 * 4
        DOS_INT13_STUB_ADDR = 0x0540
        DOS_INT13_SCRATCH_ADDR = 0x0740
        DOS_INT1A_STUB_OFFSET = 0x1130
        DOS_INT1A_STUB_SEGMENT = 0xF000
        DOS_INT1A_VECTOR_ADDR = 0x1A * 4
        DOS_INT16_STUB_OFFSET = 0x1100
        DOS_INT16_STUB_SEGMENT = 0xF000
        DOS_INT16_VECTOR_ADDR = 0x16 * 4
        DOS_DISKETTE_PARAM_VECTOR_ADDR = 0x1E * 4
        DOS_DISKETTE_PARAM_TABLE_OFFSET = 0xEFDE
        FLOPPY_POST_BDA_ADDR = 0x043E
        BDA_EBDA_SEGMENT_ADDR = 0x040E
        BDA_EQUIPMENT_WORD_ADDR = 0x0410
        BDA_BASE_MEMORY_WORD_ADDR = 0x0413
        BDA_HARD_DISK_COUNT_ADDR = 0x0475
        DOS_EBDA_SEGMENT = 0x9FC0
        DOS_BASE_MEMORY_KIB = 639
        DOS_EQUIPMENT_WORD = 0x000D
        POST_FAST_PATH_CALL_PATCH = [0x90, 0x90, 0x90].freeze
        POST_FAST_PATH_CALL_OFFSETS = [
          0xE134, # _keyboard_init
          0xE14E, # detect_parport (LPT1)
          0xE154, # detect_parport (LPT2)
          0xE178, # detect_serial (COM1)
          0xE17E, # detect_serial (COM2)
          0xE184, # detect_serial (COM3)
          0xE18A, # detect_serial (COM4)
          0xE1BF, # timer_tick_post
          0xE1FB, # VGA ROM init via rom_scan
          0xE1FE, # _print_bios_banner
          0xE204, # hard_drive_post
          0xE207, # _ata_init
          0xE20A, # _ata_detect
          0xE20D, # _cdemu_init
          0xE219  # late option ROM scan
        ].freeze
        POST_INIT_IVT_DEFAULT_SEGMENT = 0xF000
        POST_INIT_IVT_DEFAULT_HANDLER = 0xFF53
        POST_INIT_IVT_MASTER_PIC_HANDLER = 0xE9E6
        POST_INIT_IVT_SLAVE_PIC_HANDLER = 0xE9EC
        POST_INIT_IVT_RUNTIME_VECTORS = {
          0x08 => 0xFEA5,
          0x09 => 0xE987,
          0x0E => 0xEF57,
          0x10 => 0xF065,
          0x13 => 0xE3FE,
          0x14 => 0xE739,
          0x16 => 0xE82E,
          0x1A => 0xFE6E,
          0x40 => 0xEC59,
          0x70 => 0xFE6E,
          0x71 => 0xE987,
          0x75 => 0xE2C3
        }.freeze
        POST_INIT_IVT_SPECIAL_VECTORS = {
          0x11 => 0xF84D,
          0x12 => 0xF841,
          0x15 => 0xF859,
          0x17 => 0xEFD2,
          0x18 => 0x8666,
          0x19 => 0xE6F2
        }.freeze
        StepEvent = Struct.new(:cycle, :eip, :consumed, :bytes, keyword_init: true)
        FetchWordEvent = Struct.new(:cycle, :address, :word, keyword_init: true)
        FetchGroupEvent = Struct.new(:cycle, :address, :bytes, keyword_init: true)
        FetchPcGroupEvent = Struct.new(:cycle, :pc, :bytes, keyword_init: true)

        class << self
          def preferred_import_backend
            return :compiler if RHDL::Sim::Native::IR::COMPILER_AVAILABLE
            return :jit if RHDL::Sim::Native::IR::JIT_AVAILABLE

            nil
          end

          def runtime_bundle(backend:)
            mutex.synchronize do
              runtime_cache[backend] ||= build_runtime_bundle(backend: backend)
            end
          end

          private

          def runtime_cache
            @runtime_cache ||= {}
          end

          def mutex
            @mutex ||= Mutex.new
          end

          def build_runtime_bundle(backend:)
            out_dir = Dir.mktmpdir('rhdl_ao486_ir_runner_out')
            workspace_dir = Dir.mktmpdir('rhdl_ao486_ir_runner_ws')
            import_result = RHDL::Examples::AO486::Import::CpuImporter.new(
              output_dir: out_dir,
              workspace_dir: workspace_dir,
              keep_workspace: true,
              patch_profile: :runner,
              strict: false
            ).run
            raise Array(import_result.diagnostics).join("\n") unless import_result.success?

            cleaned_mlir = File.read(import_result.normalized_core_mlir_path)
            imported = RHDL::Codegen.import_circt_mlir(cleaned_mlir, strict: false, top: 'ao486')
            raise Array(imported.diagnostics).join("\n") unless imported.success?

            flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(imported.modules, top: 'ao486')
            {
              backend: backend,
              ir_json: RHDL::Sim::Native::IR.sim_json(flat, backend: backend),
              import_result: import_result
            }
          end
        end

        def self.build_from_cleaned_mlir(mlir_text, backend: preferred_import_backend)
          raise ArgumentError, 'IrRunner imported AO486 runtime requires an IR compiler or JIT backend' unless backend

          imported = RHDL::Codegen.import_circt_mlir(mlir_text, strict: false, top: 'ao486')
          raise ArgumentError, Array(imported.diagnostics).join("\n") unless imported.success?

          flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(imported.modules, top: 'ao486')
          ir_json = RHDL::Sim::Native::IR.sim_json(flat, backend: backend)

          new(backend: backend, headless: true).tap do |runner|
            runner.send(:initialize_imported_parity_runtime!, ir_json)
          end
        end

        def initialize(backend: nil, sim: nil, runner_backend: :ir, **kwargs)
          backend ||= sim || :compile
          super(backend: runner_backend, sim: backend, **kwargs)
          @sim = nil
          @runtime_loaded = false
          @imported_parity_mode = false
          @parity_sim_factory = nil
          @read_burst = nil
          @delivered_read_beat = false
          @previous_trace_key = nil
          @last_fetch_word = nil
        end

        def simulator_type
          :"ao486_ir_#{sim_backend}"
        end

        def load_bios(**kwargs)
          metadata = super
          patch_runner_bios_post_init_ivt_call!
          patch_runner_bios_post_fast_path!
          seed_post_init_ivt_memory!
          if @sim
            sync_rom_segment(POST_INIT_IVT_CALL_PATCH, BOOT0_ADDR + POST_INIT_IVT_CALL_OFFSET)
            POST_FAST_PATH_CALL_OFFSETS.each do |offset|
              sync_rom_segment(POST_FAST_PATH_CALL_PATCH, BOOT0_ADDR + offset)
            end
          end
          metadata
        end

        def load_dos(**kwargs)
          metadata = super
          seed_dos_boot_sector_memory!(metadata.fetch(:bytes))
          seed_dos_bootstrap_helper_rom!
          seed_dos_int19_stub_memory!
          seed_dos_int10_stub_memory!
          seed_dos_int13_stub_memory!
          seed_dos_int1a_stub_rom!
          seed_dos_int16_stub_rom!
          seed_dos_post_state_memory!
          seed_floppy_post_state_memory!
          patch_runner_bios_dos_bootstrap!
          @sim&.runner_load_disk(metadata.fetch(:bytes), 0)
          metadata
        end

        def load_bytes(base, bytes, target: memory_store)
          normalized_bytes = bytes.is_a?(String) ? bytes.bytes : Array(bytes)
          super(base, normalized_bytes, target: target)
          return self if imported_parity_mode?

          @sim&.runner_load_memory(normalized_bytes, base, false)
          self
        end

        def read_bytes(base, length, mapped: true)
          return super if imported_parity_mode?
          return super unless @sim

          @sim.runner_read_memory(base, length, mapped: mapped)
        end

        def write_memory(addr, value)
          super
          return if imported_parity_mode?

          @sim&.runner_write_memory(addr, [value.to_i & 0xFF], mapped: false)
        end

        def reset
          if imported_parity_mode?
            reset_imported_parity_runtime!
            @cycles_run = 0
            @last_run_stats = nil
            return self
          end

          super
          return self unless @sim

          @sim.reset
          sync_runtime_windows!
          self
        end

        def run(cycles: nil, speed: nil, headless: @headless, max_cycles: nil)
          if imported_parity_mode?
            cycles_to_run = max_cycles || cycles || speed || @requested_cycles || @speed || PARITY_DEFAULT_MAX_CYCLES
            return capture_run_stats(operation: :run, cycles: cycles_to_run) do
              run_imported_parity(cycles_to_run)
            end
          end
          return super(cycles: cycles, speed: speed, headless: headless, max_cycles: max_cycles) if !max_cycles.nil?

          ensure_sim!
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          start_cycles = @cycles_run
          chunk = cycles || @requested_cycles || speed || @speed || DEFAULT_UNLIMITED_CHUNK
          remaining = chunk.to_i
          text_dirty = false

          while remaining.positive?
            key_data = @keyboard_buffer.getbyte(0) || 0
            key_ready = !@keyboard_buffer.empty?
            run_chunk = key_ready ? 1 : remaining
            result = @sim.runner_run_cycles(run_chunk, key_data, key_ready) || { cycles_run: 0 }
            cycles_run = result[:cycles_run].to_i
            break if cycles_run <= 0

            remaining -= cycles_run
            @cycles_run += cycles_run
            text_dirty ||= result[:text_dirty]
            @keyboard_buffer.slice!(0) if result[:key_cleared] && !@keyboard_buffer.empty?
          end

          sync_runtime_windows!(display: text_dirty || chunk.to_i != 1 || !headless || @debug)
          @last_io = @sim.runner_ao486_last_io_write || @sim.runner_ao486_last_io_read
          @last_irq = @sim.runner_ao486_last_irq_vector
          @shell_prompt_detected ||= render_display.match?(/[A-Z]:\\>/)
          record_run_stats(operation: :run, cycles: @cycles_run - start_cycles, started_at: started_at)
          state.merge(cycles: @cycles_run, speed: speed || @speed, headless: headless)
        end

        def peek(signal_name)
          ensure_sim!
          @sim.peek(signal_name)
        end

        def sim
          @sim
        end

        def step(cycle)
          raise NoMethodError, "#{self.class} does not support single-cycle stepping" unless imported_parity_mode?

          step_imported_parity(cycle)
        end

        def run_fetch_words(max_cycles: PARITY_DEFAULT_MAX_CYCLES)
          raise NoMethodError, "#{self.class} does not support fetch-word traces" unless imported_parity_mode?

          capture_run_stats(operation: :run_fetch_words, cycles: max_cycles) do
            run_fetch_trace(max_cycles: max_cycles).map(&:word)
          end
        end

        def run_fetch_trace(max_cycles: PARITY_DEFAULT_MAX_CYCLES)
          raise NoMethodError, "#{self.class} does not support fetch traces" unless imported_parity_mode?

          capture_run_stats(operation: :run_fetch_trace, cycles: max_cycles) do
            reset_imported_parity_runtime!
            events = []

            max_cycles.times do |cycle|
              step_imported_parity(cycle)
              event = capture_fetch_word_event(cycle)
              events << event if event
            end

            events
          end
        end

        def run_fetch_groups(max_cycles: PARITY_DEFAULT_MAX_CYCLES)
          raise NoMethodError, "#{self.class} does not support fetch-group traces" unless imported_parity_mode?

          capture_run_stats(operation: :run_fetch_groups, cycles: max_cycles) do
            run_fetch_trace(max_cycles: max_cycles).map do |event|
              FetchGroupEvent.new(
                cycle: event.cycle,
                address: event.address,
                bytes: word_to_bytes(event.word)
              )
            end
          end
        end

        def run_fetch_pc_groups(max_cycles: PARITY_DEFAULT_MAX_CYCLES)
          raise NoMethodError, "#{self.class} does not support fetch-pc traces" unless imported_parity_mode?

          capture_run_stats(operation: :run_fetch_pc_groups, cycles: max_cycles) do
            run_fetch_groups(max_cycles: max_cycles).map do |event|
              next if event.address < STARTUP_CS_BASE

              FetchPcGroupEvent.new(
                cycle: event.cycle,
                pc: event.address - STARTUP_CS_BASE,
                bytes: event.bytes
              )
            end.compact
          end
        end

        def run_step_trace(max_cycles: PARITY_DEFAULT_MAX_CYCLES)
          raise NoMethodError, "#{self.class} does not support step traces" unless imported_parity_mode?

          capture_run_stats(operation: :run_step_trace, cycles: max_cycles) do
            run_imported_parity(max_cycles)
          end
        end

        def run_final_state(max_cycles: PARITY_DEFAULT_MAX_CYCLES)
          raise NoMethodError, "#{self.class} does not support final-state traces" unless imported_parity_mode?

          capture_run_stats(operation: :run_final_state, cycles: max_cycles) do
            reset_imported_parity_runtime!
            max_cycles.times { |cycle| step_imported_parity(cycle) }
            final_state_snapshot
          end
        end

        def final_state_snapshot
          raise NoMethodError, "#{self.class} does not support final-state snapshots" unless imported_parity_mode?

          FINAL_STATE_SIGNALS.each_with_object({}) do |name, state|
            state[name] = @sim.peek(name)
          end
        end

        def state
          snapshot = super
          return snapshot if imported_parity_mode?
          return snapshot unless @sim

          snapshot.merge(
            pc: {
              trace: snapshot_signal('trace_wr_eip'),
              decode: snapshot_signal('pipeline_inst__decode_inst__eip'),
              read: snapshot_signal('pipeline_inst__read_inst__rd_eip'),
              execute: snapshot_signal('pipeline_inst__execute_inst__exe_eip'),
              arch: snapshot_signal('trace_arch_eip')
            },
            exception_vector: snapshot_signal('exception_inst__exc_vector'),
            active_video_page: memory_store.fetch(DisplayAdapter::VIDEO_PAGE_BDA, 0),
            dos_bridge: {
              int13: @sim.runner_ao486_dos_int13_state,
              int10: @sim.runner_ao486_dos_int10_state,
              int16: @sim.runner_ao486_dos_int16_state,
              int1a: @sim.runner_ao486_dos_int1a_state
            }
          )
        end

        private

        def imported_parity_mode?
          @imported_parity_mode
        end

        def initialize_imported_parity_runtime!(ir_json)
          @parity_sim_factory = lambda {
            RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: sim_backend || self.class.preferred_import_backend)
          }
          @imported_parity_mode = true
          @sim = nil
          reset_imported_parity_runtime!
        end

        def reset_imported_parity_runtime!
          @sim = build_imported_parity_simulator!
          @read_burst = nil
          @delivered_read_beat = false
          @previous_trace_key = nil
          @last_fetch_word = nil
          apply_imported_parity_inputs
          @sim.poke('clk', 0)
          @sim.poke('rst_n', 0)
          @sim.evaluate
          @sim.poke('clk', 1)
          @sim.tick
        end

        def build_imported_parity_simulator!
          return @parity_sim_factory.call if @parity_sim_factory
          raise ArgumentError, 'IrRunner imported parity runtime requires a simulator factory'
        end

        def apply_imported_parity_inputs
          {
            'a20_enable' => 1,
            'cache_disable' => 1,
            'interrupt_do' => 0,
            'interrupt_vector' => 0,
            'avm_waitrequest' => 0,
            'avm_readdatavalid' => 0,
            'avm_readdata' => 0,
            'dma_address' => 0,
            'dma_16bit' => 0,
            'dma_write' => 0,
            'dma_writedata' => 0,
            'dma_read' => 0,
            'io_read_data' => 0,
            'io_read_done' => 0,
            'io_write_done' => 0
          }.each do |name, value|
            @sim.poke(name, value)
          end
        end

        def run_imported_parity(max_cycles)
          reset_imported_parity_runtime!
          events = []

          max_cycles.times do |cycle|
            event = step_imported_parity(cycle)
            events << event if event
          end

          events
        end

        def step_imported_parity(cycle)
          drive_imported_parity_read_data_inputs

          @sim.poke('clk', 0)
          @sim.poke('rst_n', 1)
          @sim.evaluate
          arm_imported_parity_read_burst_if_needed

          @sim.poke('clk', 1)
          @sim.poke('rst_n', 1)
          @sim.tick

          commit_imported_parity_write_if_needed
          advance_imported_parity_read_burst

          capture_step_event(cycle)
        end

        def snapshot_signal(signal_name)
          @sim.peek(signal_name)
        rescue StandardError
          nil
        end

        def ensure_sim!
          return @sim if @sim
          return @sim = build_imported_parity_simulator! if imported_parity_mode?

          bundle = self.class.runtime_bundle(backend: sim_backend || :compile)
          @sim = RHDL::Sim::Native::IR::Simulator.new(
            bundle.fetch(:ir_json),
            backend: bundle.fetch(:backend)
          )
          raise "Imported AO486 runner did not bind to native :ao486 mode" unless @sim.runner_kind == :ao486

          @sim.reset
          sync_loaded_artifacts_to_sim!
          sync_runtime_windows!
          @runtime_loaded = true
          @sim
        end

        def drive_imported_parity_read_data_inputs
          @delivered_read_beat = deliver_imported_parity_read_beat?

          if @delivered_read_beat
            addr = @read_burst[:base] + (@read_burst[:beat_index] * 4)
            @last_fetch_word = { address: addr, word: little_endian_word(addr) }
            @sim.poke('avm_readdatavalid', 1)
            @sim.poke('avm_readdata', @last_fetch_word[:word])
          else
            @last_fetch_word = nil
            @sim.poke('avm_readdatavalid', 0)
            @sim.poke('avm_readdata', 0)
          end
        end

        def little_endian_word(addr)
          4.times.reduce(0) do |acc, idx|
            acc | ((memory_store[addr + idx] || 0) << (8 * idx))
          end
        end

        def commit_imported_parity_write_if_needed
          return unless @sim.peek('avm_write') == 1

          write_word(
            @sim.peek('avm_address') << 2,
            @sim.peek('avm_writedata'),
            @sim.peek('avm_byteenable')
          )
        end

        def advance_imported_parity_read_burst
          return unless @read_burst

          if @delivered_read_beat
            @read_burst[:beat_index] += 1
            @read_burst = nil if @read_burst[:beat_index] >= @read_burst[:beats_total]
          else
            @read_burst[:started] = true
          end
        end

        def arm_imported_parity_read_burst_if_needed
          return unless @read_burst.nil?
          return unless @sim.peek('avm_read') == 1

          @read_burst = {
            base: @sim.peek('avm_address') << 2,
            beat_index: 0,
            beats_total: [@sim.peek('avm_burstcount'), 1].max,
            started: false
          }
        end

        def deliver_imported_parity_read_beat?
          @read_burst && @read_burst[:started]
        end

        def capture_step_event(cycle)
          trace_key = [@sim.peek('trace_wr_eip'), @sim.peek('trace_wr_consumed')]
          return nil if trace_key == [0, 0]
          return nil if trace_key == @previous_trace_key

          retired = @sim.peek('trace_retired') == 1
          return nil unless retired

          @previous_trace_key = trace_key
          consumed = trace_key[1]
          start_eip = trace_key[0] - consumed

          StepEvent.new(
            cycle: cycle,
            eip: start_eip,
            consumed: consumed,
            bytes: read_bytes(STARTUP_CS_BASE + start_eip, consumed)
          )
        end

        def capture_fetch_word_event(cycle)
          return nil unless @sim.peek('avm_readdatavalid') == 1
          return nil unless @last_fetch_word

          FetchWordEvent.new(
            cycle: cycle,
            address: @last_fetch_word[:address],
            word: @last_fetch_word[:word]
          )
        end

        def word_to_bytes(word)
          Array.new(4) { |idx| (word >> (idx * 8)) & 0xFF }
        end

        def write_word(addr, word, byteenable)
          4.times do |idx|
            next unless ((byteenable >> idx) & 1) == 1

            memory_store[addr + idx] = (word >> (idx * 8)) & 0xFF
          end
        end

        def sync_loaded_artifacts_to_sim!
          sync_sparse_store!(rom_store, rom: true)
          sync_sparse_store!(memory_store, rom: false)
          sync_disk_image!
        end

        def sync_sparse_store!(store, rom:)
          contiguous_ranges(store).each do |offset, bytes|
            if rom
              @sim.runner_load_rom(bytes, offset)
            else
              @sim.runner_load_memory(bytes, offset, false)
            end
          end
        end

        def contiguous_ranges(store)
          return [] if store.empty?

          ranges = []
          current_start = nil
          current_end = nil
          current_bytes = []

          store.keys.sort.each do |addr|
            if current_start.nil?
              current_start = addr
              current_end = addr
              current_bytes = [store.fetch(addr)]
              next
            end

            if addr == current_end + 1
              current_end = addr
              current_bytes << store.fetch(addr)
            else
              ranges << [current_start, current_bytes]
              current_start = addr
              current_end = addr
              current_bytes = [store.fetch(addr)]
            end
          end

          ranges << [current_start, current_bytes] unless current_start.nil?
          ranges
        end

        def sync_rom_segment(bytes, base)
          return unless @sim

          @sim.runner_load_rom(bytes, base)
        end

        def sync_disk_image!
          return unless @sim
          return unless dos_loaded?

          @sim.runner_load_disk(@floppy_image.bytes, 0)
        end

        def patch_runner_bios_post_init_ivt_call!
          POST_INIT_IVT_CALL_PATCH.each_with_index do |byte, idx|
            rom_store[BOOT0_ADDR + POST_INIT_IVT_CALL_OFFSET + idx] = byte
          end
        end

        def patch_runner_bios_post_fast_path!
          POST_FAST_PATH_CALL_OFFSETS.each do |offset|
            POST_FAST_PATH_CALL_PATCH.each_with_index do |byte, idx|
              rom_store[BOOT0_ADDR + offset + idx] = byte
            end
          end
        end

        def patch_runner_bios_dos_bootstrap!
          DOS_POST_BOOTSTRAP_PATCH.each_with_index do |byte, idx|
            rom_store[BOOT0_ADDR + POST_INIT_IVT_CALL_OFFSET + idx] = byte
          end
          sync_rom_segment(DOS_POST_BOOTSTRAP_PATCH, BOOT0_ADDR + POST_INIT_IVT_CALL_OFFSET)
        end

        def seed_post_init_ivt_memory!
          load_bytes(0x0000, post_init_ivt_image)
        end

        def seed_dos_boot_sector_memory!(dos_bytes)
          byte_slice = dos_bytes.is_a?(String) ? dos_bytes.bytes.first(512) : Array(dos_bytes).first(512)
          load_bytes(DOS_BOOT_SECTOR_ADDR, byte_slice)
          load_bytes(DOS_RELOCATED_BOOT_SECTOR_ADDR, byte_slice)
        end

        def seed_dos_int19_stub_memory!
          load_bytes(DOS_INT19_STUB_ADDR, dos_bootstrap_bytes)
          load_bytes(DOS_INT19_VECTOR_ADDR, [DOS_INT19_STUB_ADDR & 0xFF, (DOS_INT19_STUB_ADDR >> 8) & 0xFF, 0x00, 0x00])
        end

        def seed_dos_bootstrap_helper_rom!
          dos_bootstrap_bytes.each_with_index do |byte, idx|
            rom_store[BOOT0_ADDR + DOS_POST_BOOTSTRAP_HELPER_OFFSET + idx] = byte
          end
          sync_rom_segment(dos_bootstrap_bytes, BOOT0_ADDR + DOS_POST_BOOTSTRAP_HELPER_OFFSET)
        end

        def seed_dos_int13_stub_memory!
          load_bytes(DOS_INT13_STUB_ADDR, dos_int13_bootstrap_bytes)
        end

        def seed_dos_int10_stub_memory!
          load_bytes(DOS_INT10_STUB_ADDR, dos_int10_bootstrap_bytes)
        end

        def seed_dos_int1a_stub_rom!
          dos_int1a_bootstrap_bytes.each_with_index do |byte, idx|
            rom_store[BOOT0_ADDR + DOS_INT1A_STUB_OFFSET + idx] = byte
          end
          sync_rom_segment(dos_int1a_bootstrap_bytes, BOOT0_ADDR + DOS_INT1A_STUB_OFFSET)
        end

        def seed_dos_int16_stub_rom!
          dos_int16_bootstrap_bytes.each_with_index do |byte, idx|
            rom_store[BOOT0_ADDR + DOS_INT16_STUB_OFFSET + idx] = byte
          end
          sync_rom_segment(dos_int16_bootstrap_bytes, BOOT0_ADDR + DOS_INT16_STUB_OFFSET)
        end

        def seed_floppy_post_state_memory!
          load_bytes(FLOPPY_POST_BDA_ADDR, floppy_post_bda_image)
        end

        def seed_dos_post_state_memory!
          load_bytes(BDA_EBDA_SEGMENT_ADDR, [DOS_EBDA_SEGMENT & 0xFF, (DOS_EBDA_SEGMENT >> 8) & 0xFF])
          load_bytes(BDA_EQUIPMENT_WORD_ADDR, [DOS_EQUIPMENT_WORD & 0xFF, (DOS_EQUIPMENT_WORD >> 8) & 0xFF])
          load_bytes(BDA_BASE_MEMORY_WORD_ADDR, [DOS_BASE_MEMORY_KIB & 0xFF, (DOS_BASE_MEMORY_KIB >> 8) & 0xFF])
          load_bytes(BDA_HARD_DISK_COUNT_ADDR, [0x00])
          load_bytes(
            DOS_DISKETTE_PARAM_VECTOR_ADDR,
            [
              DOS_DISKETTE_PARAM_TABLE_OFFSET & 0xFF,
              (DOS_DISKETTE_PARAM_TABLE_OFFSET >> 8) & 0xFF,
              POST_INIT_IVT_DEFAULT_SEGMENT & 0xFF,
              (POST_INIT_IVT_DEFAULT_SEGMENT >> 8) & 0xFF
            ]
          )
        end


        def dos_bootstrap_bytes
          [
            0xFA,             # cli
            0xFC,             # cld
            0x9C,             # pushf
            0x58,             # pop ax
            0x80, 0xE4, 0xFE, # and ah, 0xfe ; clear TF
            0x50,             # push ax
            0x9D,             # popf
            0x31, 0xC0,       # xor ax, ax
            0x8E, 0xD8,       # mov ds, ax
            0xBD, 0x00, 0x7C, # mov bp, 0x7c00
            0xC7, 0x06, 0x40, 0x00, DOS_INT10_STUB_ADDR & 0xFF, (DOS_INT10_STUB_ADDR >> 8) & 0xFF, # mov word ptr [0x0040], int10 stub
            0xC7, 0x06, 0x42, 0x00, 0x00, 0x00, # mov word ptr [0x0042], 0x0000
            0xC7, 0x06, 0x58, 0x00, DOS_INT16_STUB_OFFSET & 0xFF, (DOS_INT16_STUB_OFFSET >> 8) & 0xFF, # mov word ptr [0x0058], int16 stub
            0xC7, 0x06, 0x5A, 0x00, DOS_INT16_STUB_SEGMENT & 0xFF, (DOS_INT16_STUB_SEGMENT >> 8) & 0xFF, # mov word ptr [0x005a], 0xf000
            0xC7, 0x06, 0x4C, 0x00, DOS_INT13_STUB_ADDR & 0xFF, (DOS_INT13_STUB_ADDR >> 8) & 0xFF, # mov word ptr [0x004c], int13 stub
            0xC7, 0x06, 0x4E, 0x00, 0x00, 0x00, # mov word ptr [0x004e], 0x0000
            0xC7, 0x06, 0x68, 0x00, DOS_INT1A_STUB_OFFSET & 0xFF, (DOS_INT1A_STUB_OFFSET >> 8) & 0xFF, # mov word ptr [0x0068], int1a stub
            0xC7, 0x06, 0x6A, 0x00, DOS_INT1A_STUB_SEGMENT & 0xFF, (DOS_INT1A_STUB_SEGMENT >> 8) & 0xFF, # mov word ptr [0x006a], 0xf000
            0xC7, 0x06, BDA_EBDA_SEGMENT_ADDR & 0xFF, (BDA_EBDA_SEGMENT_ADDR >> 8) & 0xFF,
            DOS_EBDA_SEGMENT & 0xFF, (DOS_EBDA_SEGMENT >> 8) & 0xFF, # mov word ptr [0x040e], 0x9fc0
            0xC7, 0x06, BDA_EQUIPMENT_WORD_ADDR & 0xFF, (BDA_EQUIPMENT_WORD_ADDR >> 8) & 0xFF,
            DOS_EQUIPMENT_WORD & 0xFF, (DOS_EQUIPMENT_WORD >> 8) & 0xFF, # mov word ptr [0x0410], 0x000d
            0xC7, 0x06, BDA_BASE_MEMORY_WORD_ADDR & 0xFF, (BDA_BASE_MEMORY_WORD_ADDR >> 8) & 0xFF,
            DOS_BASE_MEMORY_KIB & 0xFF, (DOS_BASE_MEMORY_KIB >> 8) & 0xFF, # mov word ptr [0x0413], 0x027f
            0xC6, 0x06, BDA_HARD_DISK_COUNT_ADDR & 0xFF, (BDA_HARD_DISK_COUNT_ADDR >> 8) & 0xFF, 0x00, # mov byte ptr [0x0475], 0x00
            0xC7, 0x06, DOS_DISKETTE_PARAM_VECTOR_ADDR & 0xFF, (DOS_DISKETTE_PARAM_VECTOR_ADDR >> 8) & 0xFF,
            DOS_DISKETTE_PARAM_TABLE_OFFSET & 0xFF, (DOS_DISKETTE_PARAM_TABLE_OFFSET >> 8) & 0xFF, # mov word ptr [0x0078], 0xefde
            0xC7, 0x06, (DOS_DISKETTE_PARAM_VECTOR_ADDR + 2) & 0xFF, ((DOS_DISKETTE_PARAM_VECTOR_ADDR + 2) >> 8) & 0xFF,
            POST_INIT_IVT_DEFAULT_SEGMENT & 0xFF, (POST_INIT_IVT_DEFAULT_SEGMENT >> 8) & 0xFF, # mov word ptr [0x007a], 0xf000
            0xB2, 0x00,       # mov dl, 0x00
            0xB8, 0xE0, 0x1F, # mov ax, 0x1fe0
            0x8E, 0xC0,       # mov es, ax
            0xEA, 0x5E, 0x7C, 0xE0, 0x1F # jmp 0x1fe0:0x7c5e
          ]
        end

        def dos_int13_bootstrap_bytes
          return_ip = DOS_INT13_SCRATCH_ADDR
          return_cs = DOS_INT13_SCRATCH_ADDR + 2
          return_flags = DOS_INT13_SCRATCH_ADDR + 4
          result_ax = DOS_INT13_SCRATCH_ADDR + 6
          carry_flag = DOS_INT13_SCRATCH_ADDR + 8
          original_dx = DOS_INT13_SCRATCH_ADDR + 10

          [
            0x80, 0xFC, 0x08,       # cmp ah, 0x08
            0x75, 0x2C,             # jne generic
            0x8F, 0x06, return_ip & 0xFF, (return_ip >> 8) & 0xFF, # pop word ptr [return_ip]
            0x8F, 0x06, return_cs & 0xFF, (return_cs >> 8) & 0xFF, # pop word ptr [return_cs]
            0x8F, 0x06, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # pop word ptr [return_flags]
            0xA1, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # mov ax, [return_flags]
            0x24, 0xFE,             # and al, 0xfe
            0xA3, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # mov [return_flags], ax
            0x31, 0xC0,             # xor ax, ax
            0xBB, 0x00, 0x04,       # mov bx, 0x0400
            0xB9, 0x12, 0x4F,       # mov cx, 0x4f12
            0xBA, 0x02, 0x01,       # mov dx, 0x0102
            0xFF, 0x36, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # push word ptr [return_flags]
            0xFF, 0x36, return_cs & 0xFF, (return_cs >> 8) & 0xFF, # push word ptr [return_cs]
            0xFF, 0x36, return_ip & 0xFF, (return_ip >> 8) & 0xFF, # push word ptr [return_ip]
            0xCF,                   # iret
            0x52,                   # push dx
            0xBA, 0xD0, 0x0E,       # mov dx, 0x0ed0
            0xEF,                   # out dx, ax
            0x93,                   # xchg ax, bx
            0xBA, 0xD2, 0x0E,       # mov dx, 0x0ed2
            0xEF,                   # out dx, ax
            0x93,                   # xchg ax, bx
            0x91,                   # xchg ax, cx
            0xBA, 0xD4, 0x0E,       # mov dx, 0x0ed4
            0xEF,                   # out dx, ax
            0x91,                   # xchg ax, cx
            0x8C, 0xC0,             # mov ax, es
            0xBA, 0xD8, 0x0E,       # mov dx, 0x0ed8
            0xEF,                   # out dx, ax
            0x58,                   # pop ax ; original DX
            0xA3, original_dx & 0xFF, (original_dx >> 8) & 0xFF, # mov [original_dx], ax
            0xBA, 0xD6, 0x0E,       # mov dx, 0x0ed6
            0xEF,                   # out dx, ax
            0x8F, 0x06, return_ip & 0xFF, (return_ip >> 8) & 0xFF, # pop word ptr [return_ip]
            0x8F, 0x06, return_cs & 0xFF, (return_cs >> 8) & 0xFF, # pop word ptr [return_cs]
            0x8F, 0x06, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # pop word ptr [return_flags]
            0xBA, 0xDA, 0x0E,       # mov dx, 0x0eda
            0x30, 0xC0,             # xor al, al
            0xEE,                   # out dx, al
            0xBA, 0xDC, 0x0E,       # mov dx, 0x0edc
            0xED,                   # in ax, dx
            0xA3, result_ax & 0xFF, (result_ax >> 8) & 0xFF, # mov [result_ax], ax
            0xBA, 0x16, 0x0F,       # mov dx, 0x0f16
            0xEC,                   # in al, dx
            0x24, 0x01,             # and al, 0x01
            0xA2, carry_flag & 0xFF, (carry_flag >> 8) & 0xFF, # mov [carry_flag], al
            0xA1, result_ax & 0xFF, (result_ax >> 8) & 0xFF, # mov ax, [result_ax]
            0x8B, 0x16, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # mov dx, [return_flags]
            0x80, 0xE2, 0xFE,       # and dl, 0xfe
            0x0A, 0x16, carry_flag & 0xFF, (carry_flag >> 8) & 0xFF, # or dl, [carry_flag]
            0x89, 0x16, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # mov [return_flags], dx
            0xFF, 0x36, return_flags & 0xFF, (return_flags >> 8) & 0xFF, # push word ptr [return_flags]
            0xFF, 0x36, return_cs & 0xFF, (return_cs >> 8) & 0xFF, # push word ptr [return_cs]
            0xFF, 0x36, return_ip & 0xFF, (return_ip >> 8) & 0xFF, # push word ptr [return_ip]
            0x8B, 0x16, original_dx & 0xFF, (original_dx >> 8) & 0xFF, # mov dx, [original_dx]
            0xCF                    # iret
          ]
        end

        def dos_int10_bootstrap_bytes
          [
            0x55,                   # push bp
            0x89, 0xE5,             # mov bp, sp
            0x50,                   # push ax
            0x53,                   # push bx
            0x51,                   # push cx
            0x52,                   # push dx
            0x06,                   # push es
            0x8B, 0x46, 0xFE,       # mov ax, [bp-2]
            0xBA, 0xE0, 0x0E,       # mov dx, 0x0ee0
            0xEF,                   # out dx, ax
            0x8B, 0x46, 0xFC,       # mov ax, [bp-4]
            0xBA, 0xE2, 0x0E,       # mov dx, 0x0ee2
            0xEF,                   # out dx, ax
            0x8B, 0x46, 0xFA,       # mov ax, [bp-6]
            0xBA, 0xE4, 0x0E,       # mov dx, 0x0ee4
            0xEF,                   # out dx, ax
            0x8B, 0x46, 0xF8,       # mov ax, [bp-8]
            0xBA, 0xE6, 0x0E,       # mov dx, 0x0ee6
            0xEF,                   # out dx, ax
            0x8B, 0x46, 0x00,       # mov ax, [bp]
            0xBA, 0xF2, 0x0E,       # mov dx, 0x0ef2
            0xEF,                   # out dx, ax
            0x8B, 0x46, 0xF6,       # mov ax, [bp-10]
            0xBA, 0xF4, 0x0E,       # mov dx, 0x0ef4
            0xEF,                   # out dx, ax
            0xBA, 0xE8, 0x0E,       # mov dx, 0x0ee8
            0x30, 0xC0,             # xor al, al
            0xEE,                   # out dx, al
            0xBA, 0xEA, 0x0E,       # mov dx, 0x0eea
            0xED,                   # in ax, dx
            0x89, 0x46, 0xFE,       # mov [bp-2], ax
            0xBA, 0xEC, 0x0E,       # mov dx, 0x0eec
            0xED,                   # in ax, dx
            0x89, 0x46, 0xFC,       # mov [bp-4], ax
            0xBA, 0xEE, 0x0E,       # mov dx, 0x0eee
            0xED,                   # in ax, dx
            0x89, 0x46, 0xFA,       # mov [bp-6], ax
            0xBA, 0xF0, 0x0E,       # mov dx, 0x0ef0
            0xED,                   # in ax, dx
            0x89, 0x46, 0xF8,       # mov [bp-8], ax
            0x07,                   # pop es
            0x5A,                   # pop dx
            0x59,                   # pop cx
            0x5B,                   # pop bx
            0x58,                   # pop ax
            0x5D,                   # pop bp
            0xCF                    # iret
          ]
        end

        def dos_int1a_bootstrap_bytes
          [
            0x55,
            0x89, 0xE5,
            0x50,
            0x51,
            0x52,
            0x8B, 0x46, 0xFE,
            0xBA, 0x00, 0x0F,
            0xEF,
            0x8B, 0x46, 0xFC,
            0xBA, 0x02, 0x0F,
            0xEF,
            0x8B, 0x46, 0xFA,
            0xBA, 0x04, 0x0F,
            0xEF,
            0xBA, 0x06, 0x0F,
            0x30, 0xC0,
            0xEE,
            0xBA, 0x08, 0x0F,
            0xED,
            0x89, 0x46, 0xFE,
            0xBA, 0x0A, 0x0F,
            0xED,
            0x89, 0x46, 0xFC,
            0xBA, 0x0C, 0x0F,
            0xED,
            0x89, 0x46, 0xFA,
            0xBA, 0x0E, 0x0F,
            0xEC,
            0x84, 0xC0,
            0x74, 0x06,
            0x80, 0x4E, 0x06, 0x01,
            0xEB, 0x04,
            0x80, 0x66, 0x06, 0xFE,
            0x8B, 0x46, 0xFE,
            0x8B, 0x4E, 0xFC,
            0x8B, 0x56, 0xFA,
            0x83, 0xC4, 0x06,
            0x5D,
            0xCF
          ]
        end

        def dos_int16_bootstrap_bytes
          [
            0x55,
            0x89, 0xE5,
            0x50,
            0x52,
            0xBA, 0xF8, 0x0E,
            0xEF,
            0xBA, 0xFA, 0x0E,
            0x30, 0xC0,
            0xEE,
            0xBA, 0xFC, 0x0E,
            0xED,
            0x89, 0x46, 0xFE,
            0xBA, 0xFE, 0x0E,
            0xEC,
            0xA8, 0x01,
            0x75, 0x06,
            0x80, 0x4E, 0x06, 0x40,
            0xEB, 0x04,
            0x80, 0x66, 0x06, 0xBF,
            0x5A,
            0x58,
            0x5D,
            0xCF
          ]
        end

        def post_init_ivt_image
          image = Array.new(0x400, 0)

          0x00.upto(0x77) do |vector|
            write_interrupt_vector!(image, vector, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_DEFAULT_HANDLER)
          end

          0x08.upto(0x0F) do |vector|
            write_interrupt_vector!(image, vector, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_MASTER_PIC_HANDLER)
          end

          0x70.upto(0x77) do |vector|
            write_interrupt_vector!(image, vector, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_SLAVE_PIC_HANDLER)
          end

          POST_INIT_IVT_SPECIAL_VECTORS.each do |vector, offset|
            write_interrupt_vector!(image, vector, POST_INIT_IVT_DEFAULT_SEGMENT, offset)
          end

          POST_INIT_IVT_RUNTIME_VECTORS.each do |vector, offset|
            write_interrupt_vector!(image, vector, POST_INIT_IVT_DEFAULT_SEGMENT, offset)
          end

          clear_interrupt_vector!(image, 0x1D)
          clear_interrupt_vector!(image, 0x1F)

          0x60.upto(0x67) do |vector|
            clear_interrupt_vector!(image, vector)
          end

          image
        end

        def floppy_post_bda_image
          image = Array.new(0x58, 0)
          image[0x00] = 0x01 # 0x043e: drive0 recalibrated, no pending interrupt
          image[0x51] = 0x07 # 0x048f: drive0 present, multi-rate, changed-line capable
          image[0x52] = 0x17 # 0x0490: drive0 media state established as 1.44MB
          image
        end

        def write_interrupt_vector!(image, vector, segment, offset)
          base = vector * 4
          image[base] = offset & 0xFF
          image[base + 1] = (offset >> 8) & 0xFF
          image[base + 2] = segment & 0xFF
          image[base + 3] = (segment >> 8) & 0xFF
        end

        def clear_interrupt_vector!(image, vector)
          write_interrupt_vector!(image, vector, 0x0000, 0x0000)
        end

        def sync_runtime_windows!(display: true)
          sync_display_window! if display
          sync_cursor_window!
        end

        def sync_display_window!
          active_page = @sim.runner_read_memory(DisplayAdapter::VIDEO_PAGE_BDA, 1, mapped: true).fetch(0, 0) &
            (DisplayAdapter::TEXT_PAGES - 1)
          page_base = DisplayAdapter::TEXT_BASE + (active_page * DisplayAdapter::BUFFER_SIZE)
          bytes = @sim.runner_read_memory(
            page_base,
            DisplayAdapter::BUFFER_SIZE,
            mapped: true
          )
          bytes.each_with_index do |byte, idx|
            memory_store[page_base + idx] = byte
          end
          @display_buffer = bytes
        end

        def sync_cursor_window!
          bytes = @sim.runner_read_memory(DisplayAdapter::CURSOR_BDA, DisplayAdapter::TEXT_PAGES * 2, mapped: true)
          bytes.each_with_index do |byte, idx|
            memory_store[DisplayAdapter::CURSOR_BDA + idx] = byte
          end
          memory_store[DisplayAdapter::VIDEO_PAGE_BDA] =
            @sim.runner_read_memory(DisplayAdapter::VIDEO_PAGE_BDA, 1, mapped: true).fetch(0, 0)
        end
      end
    end
  end
end
