# frozen_string_literal: true

# IR-level bytecode interpreter with Rust backend (Fiddle-based)
#
# This simulator operates at the IR level, interpreting Behavior IR using
# a stack-based bytecode interpreter. It's faster than gate-level netlist
# simulation because it operates on whole words instead of individual bits.
#
# Uses Fiddle (Ruby's built-in FFI) to call the Rust library directly,
# similar to the JIT and Verilator runners.

require 'json'
require 'stringio'
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'

module RHDL
  module Sim
    module Native
      module IR
        def self.sim_lib_name(base)
          case RbConfig::CONFIG['host_os']
          when /darwin/ then "#{base}.dylib"
          when /mswin|mingw/ then "#{base}.dll"
          else "#{base}.so"
          end
        end

        def self.cargo_cdylib_name(crate_name)
          case RbConfig::CONFIG['host_os']
          when /darwin/ then "lib#{crate_name}.dylib"
          when /mswin|mingw/ then "#{crate_name}.dll"
          else "lib#{crate_name}.so"
          end
        end

        def self.backend_lib_candidates(ext_dir, staged_lib_name, crate_name:)
          crate_root = File.dirname(ext_dir)
          cargo_name = cargo_cdylib_name(crate_name)

          [
            File.join(crate_root, 'target', 'release', cargo_name),
            File.join(crate_root, 'target', 'release', 'deps', cargo_name),
            File.join(ext_dir, staged_lib_name)
          ]
        end

        def self.resolve_backend_lib_path(ext_dir, staged_lib_name, crate_name:)
          backend_lib_candidates(ext_dir, staged_lib_name, crate_name: crate_name).find do |path|
            File.exist?(path)
          end || File.join(ext_dir, staged_lib_name)
        end

        def self.sim_backend_available?(lib_path)
          return false if lib_path.nil?
          return false unless File.exist?(lib_path)
          return true unless ENV['RHDL_NATIVE_EAGER_PROBE'] == '1'

          _test_lib = Fiddle.dlopen(lib_path)
          _test_lib['sim_create']
          _test_lib['sim_signal']
          _test_lib['sim_exec']
          true
        rescue Fiddle::DLError
          false
        end

      IR_INTERPRETER_EXT_DIR = File.expand_path('ir_interpreter/lib', __dir__)
      IR_INTERPRETER_LIB_NAME = sim_lib_name('ir_interpreter')
      IR_INTERPRETER_LIB_PATH =
        resolve_backend_lib_path(IR_INTERPRETER_EXT_DIR, IR_INTERPRETER_LIB_NAME, crate_name: 'ir_interpreter')

      JIT_EXT_DIR = File.expand_path('ir_jit/lib', __dir__)
      JIT_LIB_NAME = sim_lib_name('ir_jit')
      JIT_LIB_PATH =
        resolve_backend_lib_path(JIT_EXT_DIR, JIT_LIB_NAME, crate_name: 'ir_jit')

      COMPILER_EXT_DIR = File.expand_path('ir_compiler/lib', __dir__)
      COMPILER_LIB_NAME = sim_lib_name('ir_compiler')
      COMPILER_LIB_PATH =
        resolve_backend_lib_path(COMPILER_EXT_DIR, COMPILER_LIB_NAME, crate_name: 'ir_compiler')

      INTERPRETER_AVAILABLE = sim_backend_available?(IR_INTERPRETER_LIB_PATH)
      JIT_AVAILABLE = sim_backend_available?(JIT_LIB_PATH)
      COMPILER_AVAILABLE = sim_backend_available?(COMPILER_LIB_PATH)

      # Unified IR simulator wrapper for interpreter, JIT and compiler backends.
      class Simulator
        attr_reader :ir_json, :sub_cycles, :input_format, :effective_input_format

        RUNNER_KIND_NONE = 0
        RUNNER_KIND_APPLE2 = 1
        RUNNER_KIND_MOS6502 = 2
        RUNNER_KIND_GAMEBOY = 3
        RUNNER_KIND_CPU8BIT = 4
        RUNNER_KIND_RISCV = 5
        RUNNER_KIND_SPARC64 = 6
        RUNNER_KIND_AO486 = 7

        RUNNER_MEM_OP_LOAD = 0
        RUNNER_MEM_OP_READ = 1
        RUNNER_MEM_OP_WRITE = 2

        RUNNER_MEM_SPACE_MAIN = 0
        RUNNER_MEM_SPACE_ROM = 1
        RUNNER_MEM_SPACE_BOOT_ROM = 2
        RUNNER_MEM_SPACE_VRAM = 3
        RUNNER_MEM_SPACE_ZPRAM = 4
        RUNNER_MEM_SPACE_WRAM = 5
        RUNNER_MEM_SPACE_FRAMEBUFFER = 6
        RUNNER_MEM_SPACE_DISK = 7
        RUNNER_MEM_SPACE_UART_TX = 8
        RUNNER_MEM_SPACE_UART_RX = 9

        RUNNER_MEM_FLAG_MAPPED = 1

        RUNNER_RUN_MODE_BASIC = 0
        RUNNER_RUN_MODE_FULL = 1

        RUNNER_CONTROL_SET_RESET_VECTOR = 0
        RUNNER_CONTROL_RESET_SPEAKER_TOGGLES = 1
        RUNNER_CONTROL_RESET_LCD = 2
        RUNNER_CONTROL_RISCV_SET_IRQS = 3
        RUNNER_CONTROL_RISCV_SET_PLIC_SOURCES = 4
        RUNNER_CONTROL_RISCV_UART_PUSH_RX = 5
        RUNNER_CONTROL_RISCV_CLEAR_UART_TX = 6

        RUNNER_PROBE_KIND = 0
        RUNNER_PROBE_IS_MODE = 1
        RUNNER_PROBE_SPEAKER_TOGGLES = 2
        RUNNER_PROBE_FRAMEBUFFER_LEN = 3
        RUNNER_PROBE_FRAME_COUNT = 4
        RUNNER_PROBE_V_CNT = 5
        RUNNER_PROBE_H_CNT = 6
        RUNNER_PROBE_VBLANK_IRQ = 7
        RUNNER_PROBE_IF_R = 8
        RUNNER_PROBE_SIGNAL = 9
        RUNNER_PROBE_LCDC_ON = 10
        RUNNER_PROBE_H_DIV_CNT = 11
        RUNNER_PROBE_RISCV_UART_TX_LEN = 17
        RUNNER_PROBE_AO486_LAST_IO_READ = 18
        RUNNER_PROBE_AO486_LAST_IO_WRITE_META = 19
        RUNNER_PROBE_AO486_LAST_IO_WRITE_DATA = 20
        RUNNER_PROBE_AO486_LAST_IRQ_VECTOR = 21
        RUNNER_PROBE_AO486_DOS_INT13_STATE = 22
        RUNNER_PROBE_AO486_DOS_INT10_STATE = 23
        RUNNER_PROBE_AO486_DOS_INT16_STATE = 24
        RUNNER_PROBE_AO486_DOS_INT1A_STATE = 25
        RUNNER_PROBE_AO486_DOS_INT13_BX = 26
        RUNNER_PROBE_AO486_DOS_INT13_CX = 27
        RUNNER_PROBE_AO486_DOS_INT13_DX = 28
        RUNNER_PROBE_AO486_DOS_INT13_ES = 29

        SIM_CAP_SIGNAL_INDEX = 1 << 0
        SIM_CAP_FORCED_CLOCK = 1 << 1
        SIM_CAP_TRACE = 1 << 2
        SIM_CAP_TRACE_STREAMING = 1 << 3
        SIM_CAP_COMPILE = 1 << 4

        SIM_SIGNAL_HAS = 0
        SIM_SIGNAL_GET_INDEX = 1
        SIM_SIGNAL_PEEK = 2
        SIM_SIGNAL_POKE = 3
        SIM_SIGNAL_PEEK_INDEX = 4
        SIM_SIGNAL_POKE_INDEX = 5

        SIM_EXEC_EVALUATE = 0
        SIM_EXEC_TICK = 1
        SIM_EXEC_TICK_FORCED = 2
        SIM_EXEC_SET_PREV_CLOCK = 3
        SIM_EXEC_GET_CLOCK_LIST_IDX = 4
        SIM_EXEC_RESET = 5
        SIM_EXEC_RUN_TICKS = 6
        SIM_EXEC_SIGNAL_COUNT = 7
        SIM_EXEC_REG_COUNT = 8
        SIM_EXEC_COMPILE = 9
        SIM_EXEC_IS_COMPILED = 10
        SIM_EXEC_RELEASE_BATCHED_GAMEBOY_STATE = 11

        SIM_TRACE_START = 0
        SIM_TRACE_START_STREAMING = 1
        SIM_TRACE_STOP = 2
        SIM_TRACE_ENABLED = 3
        SIM_TRACE_CAPTURE = 4
        SIM_TRACE_ADD_SIGNAL = 5
        SIM_TRACE_ADD_SIGNALS_MATCHING = 6
        SIM_TRACE_ALL_SIGNALS = 7
        SIM_TRACE_CLEAR_SIGNALS = 8
        SIM_TRACE_CLEAR = 9
        SIM_TRACE_CHANGE_COUNT = 10
        SIM_TRACE_SIGNAL_COUNT = 11
        SIM_TRACE_SET_TIMESCALE = 12
        SIM_TRACE_SET_MODULE_NAME = 13
        SIM_TRACE_SAVE_VCD = 14

        SIM_BLOB_INPUT_NAMES = 0
        SIM_BLOB_OUTPUT_NAMES = 1
        SIM_BLOB_TRACE_TO_VCD = 2
        SIM_BLOB_TRACE_TAKE_LIVE_VCD = 3
        SIM_BLOB_GENERATED_CODE = 4
        SIM_BLOB_SPARC64_WISHBONE_TRACE = 5
        SIM_BLOB_SPARC64_UNMAPPED_ACCESSES = 6

        BACKEND_CONFIGS = {
          interpreter: {
            available: INTERPRETER_AVAILABLE,
            lib_path: IR_INTERPRETER_LIB_PATH,
            native_symbol: :interpret,
            label: 'interpreter'
          },
          jit: {
            available: JIT_AVAILABLE,
            lib_path: JIT_LIB_PATH,
            native_symbol: :jit,
            label: 'jit'
          },
          compiler: {
            available: COMPILER_AVAILABLE,
            lib_path: COMPILER_LIB_PATH,
            native_symbol: :compile,
            label: 'compiler'
          }
        }.freeze

        DEFAULT_INPUT_FORMAT = :auto
        INPUT_FORMATS = %i[auto circt mlir].freeze
        BACKEND_INPUT_FORMAT_DEFAULTS = {
          interpreter: :auto,
          jit: :auto,
          compiler: :auto
        }.freeze

        class << self
          def normalize_input_format(format)
            value = (format || DEFAULT_INPUT_FORMAT).to_sym
            return value if INPUT_FORMATS.include?(value)

            raise ArgumentError, "Unknown IR input format: #{format.inspect}. Valid: #{INPUT_FORMATS.map { |item| ":#{item}" }.join(', ')}"
          end

          def normalize_backend_name(backend)
            value = backend.to_sym
            value = :interpreter if value == :interpret
            value = :compiler if value == :compile
            return value if BACKEND_CONFIGS.key?(value) || value == :auto

            raise ArgumentError, "Unknown IR backend: #{backend.inspect}"
          end

          def input_format_for_backend(backend, env: ENV)
            normalized_backend = normalize_backend_name(backend)
            normalized_backend = :interpreter if normalized_backend == :auto

            specific_key = "RHDL_IR_INPUT_FORMAT_#{normalized_backend.to_s.upcase}"
            specific = env[specific_key]
            return normalize_input_format(specific.strip.downcase.to_sym) if specific && !specific.strip.empty?

            global = env['RHDL_IR_INPUT_FORMAT']
            return normalize_input_format(global.strip.downcase.to_sym) if global && !global.strip.empty?

            BACKEND_INPUT_FORMAT_DEFAULTS.fetch(normalized_backend, DEFAULT_INPUT_FORMAT)
          end

          def resolve_input_format(backend, explicit_input_format = nil, env: ENV)
            return normalize_input_format(explicit_input_format) if explicit_input_format

            input_format_for_backend(backend, env: env)
          end

          def detect_input_format(payload)
            return :circt unless payload.is_a?(String)

            parsed = JSON.parse(payload, max_nesting: false)
            return :circt if valid_circt_runtime_payload?(parsed)
            return :circt if malformed_circt_runtime_payload?(parsed)
          rescue JSON::ParserError
            return :mlir if looks_like_mlir?(payload)
          end

          def looks_like_mlir?(payload)
            text = payload.to_s
            text.match?(/^\s*hw\.module\b/) ||
              text.match?(/^\s*module\s*\{/i) ||
              text.match?(/\b(seq\.firreg|seq\.compreg|hw\.instance|comb\.)\b/)
          end

          def valid_circt_runtime_payload?(payload)
            return false unless payload.is_a?(Hash)
            return false unless payload.key?('circt_json_version')

            modules = payload['modules']
            modules.is_a?(Array) && !modules.empty?
          end

          def malformed_circt_runtime_payload?(payload)
            payload.is_a?(Hash) && (payload.key?('circt_json_version') || payload.key?('modules'))
          end

          def finalizer_for(ctx_state)
            proc do
              next if ctx_state[:closed]

              ptr = ctx_state[:ptr]
              destroy = ctx_state[:destroy]
              begin
                destroy.call(ptr) if destroy && pointer_alive?(ptr)
              rescue StandardError
                nil
              ensure
                ctx_state[:closed] = true
                ctx_state[:ptr] = nil
              end
            end
          end

          def pointer_alive?(ptr)
            !ptr.nil? && (!ptr.respond_to?(:null?) || !ptr.null?)
          end
        end

        # @param ir_json [String] JSON representation of the IR
        # @param backend [Symbol] :interpreter, :jit, :compiler, or :auto
        # @param input_format [Symbol, nil] :circt (nil => backend default/env)
        # @param sub_cycles [Integer] Number of sub-cycles per CPU cycle (default: 14)
        # @param skip_signal_widths [Boolean] Skip Ruby-side width extraction when callers
        #   only use narrow signal accessors and want to avoid parsing huge CIRCT payloads.
        # @param retain_ir_json [Boolean] Keep the full input JSON string available via
        #   `ir_json` after native simulator creation. Disable for large one-shot inputs.
        # @param trim_batched_gameboy_state [Boolean] Drop compiler-side runtime/IR
        #   bookkeeping that the Game Boy batched runner does not use. Only applies
        #   to compiler-backed Game Boy simulators.
        def initialize(ir_json, backend: :interpreter, input_format: nil, sub_cycles: 14,
                       skip_signal_widths: false, retain_ir_json: true,
                       trim_batched_gameboy_state: false)

          @sub_cycles = sub_cycles.clamp(1, 14)
          @requested_backend = self.class.normalize_backend_name(backend)
          selected = select_backend(@requested_backend)
          @input_format = self.class.resolve_input_format(@requested_backend, input_format)
          prepared = prepare_ir_json(ir_json, @input_format)
          @ir_json = prepared[:json]
          @effective_input_format = prepared[:effective_format]
          @signal_widths_by_name, @signal_widths_by_idx =
            if skip_signal_widths
              [{}, []]
            else
              extract_signal_widths(@ir_json)
            end

          if selected
            configure_backend(selected)
            load_library
            create_simulator
            compile if @backend == :compile
            release_batched_gameboy_state if trim_batched_gameboy_state
            @ir_json = nil unless retain_ir_json
          else
            raise LoadError, unavailable_backend_error_message(@requested_backend)
          end
        end

        def close
          return false unless defined?(@ctx_state) && @ctx_state
          return false if @ctx_state[:closed]

          ptr = @ctx_state[:ptr]
          destroy = @ctx_state[:destroy]
          @ctx_state[:closed] = true
          @ctx_state[:ptr] = nil
          @ctx = nil
          ObjectSpace.undefine_finalizer(self)
          destroy.call(ptr) if destroy && self.class.pointer_alive?(ptr)
          true
        end

        def closed?
          return true unless defined?(@ctx_state) && @ctx_state

          @ctx_state[:closed]
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          @backend != :ruby
        end

        def backend
          @backend
        end

        def poke(name, value)
          width = signal_width_by_name(name)
          return core_signal(SIM_SIGNAL_POKE, name: name, value: value)[:ok] unless width && width > 64

          poke_wide_by_name(name, normalize_signal_value(value, width), width)
        end

        def peek(name)
          width = signal_width_by_name(name)
          return core_signal(SIM_SIGNAL_PEEK, name: name)[:value] unless width && width > 64

          peek_wide_by_name(name, width)
        end

        def has_signal?(name)
          core_signal(SIM_SIGNAL_HAS, name: name)[:value] != 0
        end

        def evaluate
          core_exec(SIM_EXEC_EVALUATE)
        end

        def tick
          core_exec(SIM_EXEC_TICK)
        end

        def tick_forced
          core_exec(SIM_EXEC_TICK_FORCED)
        end

        def set_prev_clock(clock_list_idx, value)
          core_exec(SIM_EXEC_SET_PREV_CLOCK, clock_list_idx, value)
        end

        def get_clock_list_idx(signal_idx)
          result = core_exec(SIM_EXEC_GET_CLOCK_LIST_IDX, signal_idx)
          result[:ok] ? result[:value] : -1
        end

        def reset
          @sim_runner_speaker_toggles = 0
          core_exec(SIM_EXEC_RESET)
        end

        def signal_count
          core_exec(SIM_EXEC_SIGNAL_COUNT)[:value]
        end

        def reg_count
          core_exec(SIM_EXEC_REG_COUNT)[:value]
        end

        def compiled?
          core_exec(SIM_EXEC_IS_COMPILED)[:value] != 0
        end

        def compile
          error_ptr = scratch_pointer_ptr
          clear_pointer_ptr!(error_ptr)
          result = core_exec(SIM_EXEC_COMPILE, 0, 0, error_ptr)
          return result[:value] != 0 if result[:ok]

          error_str_ptr = read_pointer_ptr(error_ptr)
          if error_str_ptr != 0
            error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
            @fn_free_error.call(error_str_ptr)
            raise RuntimeError, "Compilation failed: #{error_msg}"
          end

          raise RuntimeError,
                'Compilation failed: native compiler backend rejected the design; compile fast path is required and no runtime fallback is allowed'
        end

        def generated_code
          core_blob(SIM_BLOB_GENERATED_CODE)
        end

        def input_names
          csv = core_blob(SIM_BLOB_INPUT_NAMES)
          csv.empty? ? [] : csv.split(',')
        end

        def output_names
          csv = core_blob(SIM_BLOB_OUTPUT_NAMES)
          csv.empty? ? [] : csv.split(',')
        end

        # VCD tracing methods
        def trace_start
          core_trace(SIM_TRACE_START)[:ok]
        end

        def trace_start_streaming(path)
          core_trace(SIM_TRACE_START_STREAMING, path)[:ok]
        end

        def trace_stop
          core_trace(SIM_TRACE_STOP)
        end

        def trace_enabled?
          core_trace(SIM_TRACE_ENABLED)[:value] != 0
        end

        def trace_capture
          core_trace(SIM_TRACE_CAPTURE)
        end

        def trace_add_signal(name)
          core_trace(SIM_TRACE_ADD_SIGNAL, name)[:ok]
        end

        def trace_add_signals_matching(pattern)
          core_trace(SIM_TRACE_ADD_SIGNALS_MATCHING, pattern)[:value]
        end

        def trace_all_signals
          core_trace(SIM_TRACE_ALL_SIGNALS)
        end

        def trace_clear_signals
          core_trace(SIM_TRACE_CLEAR_SIGNALS)
        end

        def trace_to_vcd
          core_blob(SIM_BLOB_TRACE_TO_VCD)
        end

        def trace_take_live_vcd
          core_blob(SIM_BLOB_TRACE_TAKE_LIVE_VCD)
        end

        def trace_save_vcd(path)
          core_trace(SIM_TRACE_SAVE_VCD, path)[:ok]
        end

        def trace_clear
          core_trace(SIM_TRACE_CLEAR)
        end

        def trace_change_count
          core_trace(SIM_TRACE_CHANGE_COUNT)[:value]
        end

        def trace_signal_count
          core_trace(SIM_TRACE_SIGNAL_COUNT)[:value]
        end

        def trace_set_timescale(timescale)
          core_trace(SIM_TRACE_SET_TIMESCALE, timescale)[:ok]
        end

        def trace_set_module_name(name)
          core_trace(SIM_TRACE_SET_MODULE_NAME, name)[:ok]
        end

        def stats
          runner_kind = runner_kind
          {
            signals: signal_count,
            regs: reg_count,
            runner_kind: runner_kind,
            runner_mode: runner_mode?,
            apple2_mode: runner_kind == :apple2,
            gameboy_mode: gameboy_mode?,
            mos6502_mode: runner_kind == :mos6502,
            cpu8bit_mode: runner_kind == :cpu8bit,
            riscv_mode: runner_kind == :riscv
          }
        end

        # Batched tick execution
        def run_ticks(n)
          core_exec(SIM_EXEC_RUN_TICKS, n)
        end

        # Get signal index by name (for caching)
        def get_signal_idx(name)
          result = core_signal(SIM_SIGNAL_GET_INDEX, name: name)
          result[:ok] ? result[:value] : nil
        end

        # Poke by index - faster than by name when index is cached
        def poke_by_idx(idx, value)
          width = signal_width_by_idx(idx)
          return core_signal(SIM_SIGNAL_POKE_INDEX, idx: idx, value: value) unless width && width > 64

          poke_wide_by_idx(idx, normalize_signal_value(value, width), width)
        end

        # Peek by index - faster than by name when index is cached
        def peek_by_idx(idx)
          width = signal_width_by_idx(idx)
          return core_signal(SIM_SIGNAL_PEEK_INDEX, idx: idx)[:value] unless width && width > 64

          peek_wide_by_idx(idx, width)
        end

        # ====================================================================
        # Unified Runner Extension Methods
        # ====================================================================

        def runner_kind

          case runner_probe(RUNNER_PROBE_KIND)
          when RUNNER_KIND_APPLE2 then :apple2
          when RUNNER_KIND_MOS6502 then :mos6502
          when RUNNER_KIND_GAMEBOY then :gameboy
          when RUNNER_KIND_CPU8BIT then :cpu8bit
          when RUNNER_KIND_RISCV then :riscv
          when RUNNER_KIND_SPARC64 then :sparc64
          when RUNNER_KIND_AO486 then :ao486
          else nil
          end
        end

        def runner_mode?
          runner_probe(RUNNER_PROBE_IS_MODE) != 0
        end

        def runner_load_memory(data, offset = 0, is_rom = false)
          data = data.pack('C*') if data.is_a?(Array)
          return false if data.nil? || data.bytesize.zero?

          space = is_rom ? RUNNER_MEM_SPACE_ROM : RUNNER_MEM_SPACE_MAIN
          runner_mem(RUNNER_MEM_OP_LOAD, space, offset, data, 0) > 0
        end

        def runner_read_memory(offset, length, mapped: true)
          length = [length.to_i, 0].max
          return [] if length.zero?

          flags = mapped ? RUNNER_MEM_FLAG_MAPPED : 0
          runner_mem_read(RUNNER_MEM_SPACE_MAIN, offset, length, flags)
        end

        def runner_write_memory(offset, data, mapped: true)
          data = data.pack('C*') if data.is_a?(Array)
          return 0 if data.nil? || data.bytesize.zero?

          flags = mapped ? RUNNER_MEM_FLAG_MAPPED : 0
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_MAIN, offset, data, flags)
        end

        def runner_load_disk(data, offset = 0)
          data = data.pack('C*') if data.is_a?(Array)
          return false if data.nil? || data.bytesize.zero?

          runner_mem(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_DISK, offset, data, 0) > 0
        end

        def runner_read_disk(offset, length)
          length = [length.to_i, 0].max
          return [] if length.zero?

          runner_mem_read(RUNNER_MEM_SPACE_DISK, offset, length, 0)
        end

        def runner_run_cycles(n, key_data = 0, key_ready = false)

          result_buf = Fiddle::Pointer.malloc(20)
          ok = @fn_runner_run.call(
            @ctx,
            n,
            key_data,
            key_ready ? 1 : 0,
            RUNNER_RUN_MODE_BASIC,
            result_buf
          )
          return nil if ok == 0

          values = result_buf[0, 20].unpack('llLLL')
          result = {
            text_dirty: values[0] != 0,
            key_cleared: values[1] != 0,
            cycles_run: values[2],
            speaker_toggles: values[3]
          }
          @sim_runner_speaker_toggles = ((@sim_runner_speaker_toggles || 0) + result[:speaker_toggles]) & 0xFFFFFFFF
          result
        end

        def runner_load_rom(data, offset = 0)

          data = data.pack('C*') if data.is_a?(Array)
          return false if data.nil? || data.bytesize.zero?
          runner_mem(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM, offset, data, 0) > 0
        end

        def runner_read_rom(offset, length)
          length = [length.to_i, 0].max
          return [] if length.zero?

          runner_mem_read(RUNNER_MEM_SPACE_ROM, offset, length, 0)
        end

        def runner_set_reset_vector(addr)
          vector = addr.to_i & 0xFFFF_FFFF
          return false unless @fn_runner_control

          @fn_runner_control.call(@ctx, RUNNER_CONTROL_SET_RESET_VECTOR, vector, 0) != 0
        end

        def runner_speaker_toggles
          return runner_probe(RUNNER_PROBE_SPEAKER_TOGGLES) if runner_kind == :mos6502
          @sim_runner_speaker_toggles || 0
        end

        def runner_sparc64_wishbone_trace
          return [] unless runner_kind == :sparc64

          parse_runner_json_blob(SIM_BLOB_SPARC64_WISHBONE_TRACE).map do |event|
            event[:op] = event[:op].to_sym if event[:op].is_a?(String)
            event
          end
        end

        def runner_sparc64_unmapped_accesses
          return [] unless runner_kind == :sparc64

          parse_runner_json_blob(SIM_BLOB_SPARC64_UNMAPPED_ACCESSES).map do |fault|
            fault[:op] = fault[:op].to_sym if fault[:op].is_a?(String)
            fault
          end
        end

        def runner_reset_speaker_toggles
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RESET_SPEAKER_TOGGLES, 0, 0)
          @sim_runner_speaker_toggles = 0
          nil
        end

        # ====================================================================
        # RISC-V Extension Methods
        # ====================================================================

        def riscv_mode?
          runner_kind == :riscv
        end

        def runner_riscv_set_interrupts(software: false, timer: false, external: false)
          return false unless riscv_mode?
          bits = 0
          bits |= 0x1 if software
          bits |= 0x2 if timer
          bits |= 0x4 if external
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RISCV_SET_IRQS, bits, 0) != 0
        end

        def runner_riscv_set_plic_sources(source1: false, source10: false)
          return false unless riscv_mode?
          bits = 0
          bits |= 0x1 if source1
          bits |= 0x2 if source10
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RISCV_SET_PLIC_SOURCES, bits, 0) != 0
        end

        def runner_riscv_uart_receive_byte(byte)
          runner_riscv_uart_receive_bytes([byte.to_i & 0xFF])
        end

        def runner_riscv_uart_receive_bytes(bytes)
          return false unless riscv_mode?

          payload = if bytes.is_a?(String)
            bytes.b
          elsif bytes.respond_to?(:pack)
            bytes.pack('C*')
          else
            Array(bytes).pack('C*')
          end
          return true if payload.empty?

          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_UART_RX, 0, payload, 0) > 0
        end

        def runner_riscv_uart_receive_text(text)
          runner_riscv_uart_receive_bytes(text.to_s.b)
        end

        def runner_riscv_uart_tx_bytes
          return [] unless riscv_mode?
          len = runner_probe(RUNNER_PROBE_RISCV_UART_TX_LEN).to_i
          return [] if len <= 0
          runner_mem_read(RUNNER_MEM_SPACE_UART_TX, 0, len, 0)
        end

        def runner_riscv_clear_uart_tx_bytes
          return nil unless riscv_mode?
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RISCV_CLEAR_UART_TX, 0, 0)
          nil
        end

        def runner_riscv_load_disk(data, offset = 0)
          return false unless riscv_mode?
          runner_load_disk(data, offset)
        end

        def runner_riscv_read_disk(offset, length)
          return [] unless riscv_mode?
          runner_read_disk(offset, length)
        end

        # ====================================================================
        # AO486 Extension Methods
        # ====================================================================

        def ao486_mode?
          runner_kind == :ao486
        end

        def runner_ao486_last_io_read
          return nil unless ao486_mode?

          unpack_ao486_io_meta(runner_probe(RUNNER_PROBE_AO486_LAST_IO_READ))
        end

        def runner_ao486_last_io_write
          return nil unless ao486_mode?

          meta = unpack_ao486_io_meta(runner_probe(RUNNER_PROBE_AO486_LAST_IO_WRITE_META))
          return nil unless meta

          meta.merge(data: runner_probe(RUNNER_PROBE_AO486_LAST_IO_WRITE_DATA).to_i & 0xFFFF_FFFF)
        end

        def runner_ao486_last_irq_vector
          return nil unless ao486_mode?

          value = runner_probe(RUNNER_PROBE_AO486_LAST_IRQ_VECTOR).to_i & 0xFF
          value.zero? ? nil : value
        end

        def runner_ao486_dos_int13_state
          return nil unless ao486_mode?

          unpack_ao486_dos_state(runner_probe(RUNNER_PROBE_AO486_DOS_INT13_STATE), with_flags: true).merge(
            bx: runner_probe(RUNNER_PROBE_AO486_DOS_INT13_BX).to_i & 0xFFFF,
            cx: runner_probe(RUNNER_PROBE_AO486_DOS_INT13_CX).to_i & 0xFFFF,
            dx: runner_probe(RUNNER_PROBE_AO486_DOS_INT13_DX).to_i & 0xFFFF,
            es: runner_probe(RUNNER_PROBE_AO486_DOS_INT13_ES).to_i & 0xFFFF
          )
        end

        def runner_ao486_dos_int10_state
          return nil unless ao486_mode?

          unpack_ao486_dos_state(runner_probe(RUNNER_PROBE_AO486_DOS_INT10_STATE), with_flags: false)
        end

        def runner_ao486_dos_int16_state
          return nil unless ao486_mode?

          unpack_ao486_dos_state(runner_probe(RUNNER_PROBE_AO486_DOS_INT16_STATE), with_flags: true)
        end

        def runner_ao486_dos_int1a_state
          return nil unless ao486_mode?

          unpack_ao486_dos_state(runner_probe(RUNNER_PROBE_AO486_DOS_INT1A_STATE), with_flags: true)
        end

        # ====================================================================
        # Game Boy Extension Methods
        # ====================================================================

        def gameboy_mode?
          runner_kind == :gameboy
        end

        def load_rom(data)
          runner_load_rom(data, 0)
        end

        def load_boot_rom(data)
          data = data.pack('C*') if data.is_a?(Array)
          runner_mem(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_BOOT_ROM, 0, data, 0)
        end

        def run_gb_cycles(n)

          result_buf = Fiddle::Pointer.malloc(20)
          ok = @fn_runner_run.call(@ctx, n, 0, 0, RUNNER_RUN_MODE_FULL, result_buf)
          return { cycles_run: 0, frames_completed: 0 } if ok == 0
          values = result_buf[0, 20].unpack('llLLL')
          {
            cycles_run: values[2],
            frames_completed: values[4]
          }
        end

        def release_batched_gameboy_state
          return false unless native?
          return false unless gameboy_mode?

          core_exec(SIM_EXEC_RELEASE_BATCHED_GAMEBOY_STATE)[:ok]
        end

        def read_vram(addr)
          bytes = runner_mem_read(RUNNER_MEM_SPACE_VRAM, addr, 1, 0)
          bytes.empty? ? 0 : (bytes[0] & 0xFF)
        end

        def write_vram(addr, data)
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_VRAM, addr, [data].pack('C'), 0)
        end

        def read_zpram(addr)
          bytes = runner_mem_read(RUNNER_MEM_SPACE_ZPRAM, addr, 1, 0)
          bytes.empty? ? 0 : (bytes[0] & 0xFF)
        end

        def write_zpram(addr, data)
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_ZPRAM, addr, [data].pack('C'), 0)
        end

        def read_wram(addr)
          bytes = runner_mem_read(RUNNER_MEM_SPACE_WRAM, addr, 1, 0)
          bytes.empty? ? 0 : (bytes[0] & 0xFF)
        end

        def write_wram(addr, data)
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_WRAM, addr, [data].pack('C'), 0)
        end

        def read_framebuffer

          len = runner_probe(RUNNER_PROBE_FRAMEBUFFER_LEN)
          return [] if len <= 0
          runner_mem_read(RUNNER_MEM_SPACE_FRAMEBUFFER, 0, len, 0)
        end

        def frame_count
          runner_probe(RUNNER_PROBE_FRAME_COUNT)
        end

        def reset_lcd_state
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RESET_LCD, 0, 0)
        end

        def get_v_cnt
          runner_probe(RUNNER_PROBE_V_CNT)
        end

        def get_h_cnt
          runner_probe(RUNNER_PROBE_H_CNT)
        end

        def get_vblank_irq
          runner_probe(RUNNER_PROBE_VBLANK_IRQ)
        end

        def get_if_r
          runner_probe(RUNNER_PROBE_IF_R)
        end

        def get_signal(idx)
          runner_probe(RUNNER_PROBE_SIGNAL, idx)
        end

        def get_lcdc_on
          runner_probe(RUNNER_PROBE_LCDC_ON)
        end

        def get_h_div_cnt
          runner_probe(RUNNER_PROBE_H_DIV_CNT)
        end

        def core_signal(op, name: nil, idx: 0, value: 0)
          out = scratch_ulong_ptr
          clear_ulong_ptr!(out)
          rc = @fn_sim_signal.call(@ctx, op, name, idx, value, out)
          {
            ok: rc != 0,
            value: read_ulong_ptr(out)
          }
        end

        def core_signal_wide(op, name: nil, idx: 0, value: 0)
          in_ptr = scratch_wide_in_ptr
          low = value.to_i & 0xFFFF_FFFF_FFFF_FFFF
          high = (value.to_i >> 64) & 0xFFFF_FFFF_FFFF_FFFF
          in_ptr[0, 16] = [low, high].pack('QQ')

          out = scratch_wide_out_ptr
          out[0, 16] = [0, 0].pack('QQ')
          rc = @fn_sim_signal_wide.call(@ctx, op, name, idx, in_ptr, out)
          lo, hi = out[0, 16].unpack('QQ')
          {
            ok: rc != 0,
            value: join_wide_words([lo, hi])
          }
        end

        def core_exec(op, arg0 = 0, arg1 = 0, error_out = nil)
          out = scratch_ulong_ptr
          clear_ulong_ptr!(out)
          rc = @fn_sim_exec.call(@ctx, op, arg0, arg1, out, error_out)
          {
            ok: rc != 0,
            value: read_ulong_ptr(out)
          }
        end

        def core_trace(op, str_arg = nil)
          out = scratch_ulong_ptr
          clear_ulong_ptr!(out)
          rc = @fn_sim_trace.call(@ctx, op, str_arg, out)
          {
            ok: rc != 0,
            value: read_ulong_ptr(out)
          }
        end

        def core_blob(op)
          len = @fn_sim_blob.call(@ctx, op, nil, 0)
          return '' if len.nil? || len.to_i <= 0
          buf = Fiddle::Pointer.malloc(len)
          actual = @fn_sim_blob.call(@ctx, op, buf, len)
          return '' if actual.nil? || actual.to_i <= 0
          buf[0, actual]
        end

        def parse_runner_json_blob(op)
          payload = core_blob(op)
          return [] if payload.nil? || payload.empty?

          parsed = JSON.parse(payload, symbolize_names: true)
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError
          []
        end

        def runner_mem(op, space, offset, data, flags)
          @fn_runner_mem.call(@ctx, op, space, offset, data, data.bytesize, flags)
        end

        def runner_mem_read(space, offset, length, flags)
          length = [length.to_i, 0].max
          return [] if length.zero?

          buf = Fiddle::Pointer.malloc(length)
          read_len = @fn_runner_mem.call(@ctx, RUNNER_MEM_OP_READ, space, offset, buf, length, flags)
          buf[0, read_len].unpack('C*')
        end

        def runner_probe(op, arg0 = 0)
          @fn_runner_probe.call(@ctx, op, arg0)
        end

        def unpack_ao486_io_meta(packed)
          value = packed.to_i
          length = value & 0xFF
          return nil if length.zero?

          {
            address: (value >> 8) & 0xFFFF,
            length: length
          }
        end

        def unpack_ao486_dos_state(packed, with_flags:)
          value = packed.to_i
          state = {
            ax: value & 0xFFFF,
            result_ax: (value >> 16) & 0xFFFF
          }
          state[:flags] = (value >> 32) & 0xFF if with_flags
          state
        end

        def backend_candidates(requested)
          case requested
          when :interpreter then %i[interpreter]
          when :jit then %i[jit]
          when :compiler then %i[compiler]
          when :auto then %i[compiler jit interpreter]
          else []
          end
        end

        def select_backend(requested)
          backend_candidates(requested).find { |name| BACKEND_CONFIGS[name][:available] }
        end

        def configure_backend(name)
          config = BACKEND_CONFIGS[name]
          @lib_path = config[:lib_path]
          @backend = config[:native_symbol]
          @backend_label = config[:label]
        end

        def unavailable_backend_error_message(requested)
          case requested
          when :interpreter
            "IR interpreter extension not found at: #{IR_INTERPRETER_LIB_PATH}\nRun 'rake native:build' to build it."
          when :jit
            "IR JIT extension not found at: #{JIT_LIB_PATH}\nRun 'rake native:build' to build it."
          when :compiler
            "IR compiler extension not found at: #{COMPILER_LIB_PATH}\nRun 'rake native:build' to build it."
          when :auto
            "No IR backend extension found (searched compiler, jit, interpreter).\nRun 'rake native:build' to build them."
          else
            "IR backend not available."
          end
        end

        def load_library
          @lib = Fiddle.dlopen(@lib_path)

          # Core functions
          @fn_create = Fiddle::Function.new(
            @lib['sim_create'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_destroy = Fiddle::Function.new(
            @lib['sim_destroy'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_free_error = Fiddle::Function.new(
            @lib['sim_free_error'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_sim_get_caps = Fiddle::Function.new(
            @lib['sim_get_caps'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_signal = Fiddle::Function.new(
            @lib['sim_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_ULONG, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_signal_wide = load_optional_function(
            'sim_signal_wide',
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_poke_word_by_name = load_optional_function(
            'sim_poke_word_by_name',
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_INT
          )

          @fn_sim_peek_word_by_name = load_optional_function(
            'sim_peek_word_by_name',
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_poke_word_by_idx = load_optional_function(
            'sim_poke_word_by_idx',
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_INT
          )

          @fn_sim_peek_word_by_idx = load_optional_function(
            'sim_peek_word_by_idx',
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_exec = Fiddle::Function.new(
            @lib['sim_exec'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_ULONG, Fiddle::TYPE_ULONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_trace = Fiddle::Function.new(
            @lib['sim_trace'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_sim_blob = Fiddle::Function.new(
            @lib['sim_blob'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_SIZE_T
          )

          # Unified runner functions
          @fn_runner_get_caps = Fiddle::Function.new(
            @lib['runner_get_caps'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_runner_mem = Fiddle::Function.new(
            @lib['runner_mem'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_UINT],
            Fiddle::TYPE_SIZE_T
          )

          @fn_runner_run = Fiddle::Function.new(
            @lib['runner_run'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_CHAR, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_runner_control = Fiddle::Function.new(
            @lib['runner_control'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
            Fiddle::TYPE_INT
          )

          @fn_runner_probe = Fiddle::Function.new(
            @lib['runner_probe'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
            Fiddle::TYPE_LONG_LONG
          )
        end

        def create_simulator
          error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          error_ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack('Q')

          @ctx = @fn_create.call(@ir_json, @ir_json.bytesize, @sub_cycles, error_ptr)

          if @ctx.null?
            error_str_ptr = error_ptr[0, Fiddle::SIZEOF_VOIDP].unpack1('Q')
            if error_str_ptr != 0
              error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
              @fn_free_error.call(error_str_ptr)
              raise RuntimeError, "Failed to create #{@backend_label} simulator: #{error_msg}"
            end
            raise RuntimeError, "Failed to create #{@backend_label} simulator"
          end

          @sim_runner_speaker_toggles = 0
          @ctx_state = { ptr: @ctx, destroy: @fn_destroy, closed: false }
          ObjectSpace.define_finalizer(self, self.class.finalizer_for(@ctx_state))
        end

        def load_optional_function(symbol_name, arg_types, return_type)
          Fiddle::Function.new(@lib[symbol_name], arg_types, return_type)
        rescue Fiddle::DLError
          nil
        end

        def prepare_ir_json(ir_json, input_format)
          case input_format
          when :auto
            detected = self.class.detect_input_format(ir_json)
            return prepare_ir_json(ir_json, detected) if detected

            raise ArgumentError, 'Unable to autodetect IR input format; expected CIRCT runtime JSON or hw/comb/seq MLIR text'
          when :circt
            json = ir_json.is_a?(String) ? ir_json : JSON.generate(ir_json, max_nesting: false)
            { json: json, effective_format: :circt }
          when :mlir
            raise ArgumentError, 'MLIR input must be provided as text' unless ir_json.is_a?(String)

            { json: ir_json, effective_format: :mlir }
          else
            raise ArgumentError, "Unsupported IR input format: #{input_format.inspect}. Valid: #{self.class::INPUT_FORMATS.map { |item| ":#{item}" }.join(', ')}"
          end
        end

        def extract_signal_widths(ir_json)
          payload = JSON.parse(ir_json, max_nesting: false)
          mod = payload.is_a?(Hash) ? (payload['modules']&.first || payload) : {}
          entries = Array(mod['ports']) + Array(mod['nets']) + Array(mod['regs'])

          by_name = {}
          by_idx = []

          entries.each do |entry|
            width = entry['width']&.to_i
            name = entry['name']&.to_s
            next unless width && name

            by_name[name] = width
            by_idx << width
          end

          [by_name, by_idx]
        rescue JSON::ParserError, TypeError
          [{}, []]
        end

        def signal_width_by_name(name)
          @signal_widths_by_name[name.to_s]
        end

        def signal_width_by_idx(idx)
          @signal_widths_by_idx[idx.to_i]
        end

        def normalize_signal_value(value, width)
          width = width.to_i
          return 0 if width <= 0

          value.to_i & ((1 << width) - 1)
        end

        def wide_word_count(width)
          (width.to_i + 63) / 64
        end

        def split_wide_words(value, width)
          normalized = value.to_i
          Array.new(wide_word_count(width)) do |word_idx|
            (normalized >> (word_idx * 64)) & 0xFFFF_FFFF_FFFF_FFFF
          end
        end

        def join_wide_words(words)
          words.each_with_index.reduce(0) do |acc, (word, word_idx)|
            acc | (word.to_i << (word_idx * 64))
          end
        end

        def legacy_wide_signal_api?(width)
          width.to_i <= 128 && @fn_sim_signal_wide
        end

        def poke_wide_by_name(name, value, width)
          if legacy_wide_signal_api?(width)
            return core_signal_wide(SIM_SIGNAL_POKE, name: name, value: value)[:ok]
          end
          raise RangeError, "no wide signal API available for #{name}" unless @fn_sim_poke_word_by_name

          split_wide_words(value, width).each_with_index.all? do |word, word_idx|
            @fn_sim_poke_word_by_name.call(@ctx, name.to_s, word_idx, word) != 0
          end
        end

        def peek_wide_by_name(name, width)
          if legacy_wide_signal_api?(width)
            return core_signal_wide(SIM_SIGNAL_PEEK, name: name)[:value]
          end
          raise RangeError, "no wide signal API available for #{name}" unless @fn_sim_peek_word_by_name

          words = Array.new(wide_word_count(width)) { |word_idx| wide_word_by_name(name, word_idx) }
          join_wide_words(words)
        end

        def poke_wide_by_idx(idx, value, width)
          if legacy_wide_signal_api?(width)
            return core_signal_wide(SIM_SIGNAL_POKE_INDEX, idx: idx, value: value)
          end
          raise RangeError, "no wide signal API available for #{idx}" unless @fn_sim_poke_word_by_idx

          ok = split_wide_words(value, width).each_with_index.all? do |word, word_idx|
            @fn_sim_poke_word_by_idx.call(@ctx, idx, word_idx, word) != 0
          end
          { ok: ok, value: 0 }
        end

        def peek_wide_by_idx(idx, width)
          if legacy_wide_signal_api?(width)
            return core_signal_wide(SIM_SIGNAL_PEEK_INDEX, idx: idx)[:value]
          end
          raise RangeError, "no wide signal API available for #{idx}" unless @fn_sim_peek_word_by_idx

          words = Array.new(wide_word_count(width)) { |word_idx| wide_word_by_idx(idx, word_idx) }
          join_wide_words(words)
        end

        def wide_word_by_name(name, word_idx)
          out = scratch_ulong_ptr
          clear_ulong_ptr!(out)
          rc = @fn_sim_peek_word_by_name.call(@ctx, name.to_s, word_idx, out)
          return 0 if rc == 0

          read_ulong_ptr(out)
        end

        def wide_word_by_idx(idx, word_idx)
          out = scratch_ulong_ptr
          clear_ulong_ptr!(out)
          rc = @fn_sim_peek_word_by_idx.call(@ctx, idx, word_idx, out)
          return 0 if rc == 0

          read_ulong_ptr(out)
        end

        def scratch_ulong_ptr
          @scratch_ulong_ptr ||= Fiddle::Pointer.malloc(Fiddle::SIZEOF_LONG)
        end

        def scratch_pointer_ptr
          @scratch_pointer_ptr ||= Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
        end

        def clear_ulong_ptr!(ptr)
          ptr[0, Fiddle::SIZEOF_LONG] = packed_zero_ulong
        end

        def clear_pointer_ptr!(ptr)
          ptr[0, Fiddle::SIZEOF_VOIDP] = packed_zero_pointer
        end

        def read_ulong_ptr(ptr)
          ptr[0, Fiddle::SIZEOF_LONG].unpack1(packed_ulong_format)
        end

        def read_pointer_ptr(ptr)
          ptr[0, Fiddle::SIZEOF_VOIDP].unpack1(packed_pointer_format)
        end

        def packed_zero_ulong
          @packed_zero_ulong ||= [0].pack(packed_ulong_format)
        end

        def packed_zero_pointer
          @packed_zero_pointer ||= [0].pack(packed_pointer_format)
        end

        def packed_ulong_format
          @packed_ulong_format ||= (Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
        end

        def packed_pointer_format
          @packed_pointer_format ||= (Fiddle::SIZEOF_VOIDP == 8 ? 'Q' : 'L')
        end

        def scratch_wide_in_ptr
          @scratch_wide_in_ptr ||= Fiddle::Pointer.malloc(16)
        end

        def scratch_wide_out_ptr
          @scratch_wide_out_ptr ||= Fiddle::Pointer.malloc(16)
        end
      end

      class << self
        def input_format_for_backend(backend, env: ENV)
          Simulator.input_format_for_backend(backend, env: env)
        end

        def resolve_input_format(backend, explicit_input_format = nil, env: ENV)
          Simulator.resolve_input_format(backend, explicit_input_format, env: env)
        end

        def sim_json(ir_obj, backend: :interpreter, format: nil, env: ENV)
          input_format = format ? Simulator.normalize_input_format(format) : input_format_for_backend(backend, env: env)
          case input_format
          when :auto, :circt
            circt_runtime_json(ir_obj)
          when :mlir
            raise ArgumentError, 'sim_json only exports CIRCT runtime JSON; use to_mlir_hierarchy for MLIR text'
          else
            raise ArgumentError, "Unsupported IR input format: #{input_format.inspect}. Valid: #{Simulator::INPUT_FORMATS.map { |item| ":#{item}" }.join(', ')}"
          end
        end

        private

        def circt_runtime_json(ir_obj)
          if ir_obj.is_a?(String)
            parsed = parse_json_string(ir_obj)
            return ir_obj if Simulator.valid_circt_runtime_payload?(parsed)
            raise ArgumentError, 'CIRCT runtime JSON must include circt_json_version and non-empty modules' if Simulator.malformed_circt_runtime_payload?(parsed)
          end

          if ir_obj.is_a?(Hash)
            payload = stringify_hash_keys(ir_obj)
            return JSON.generate(payload, max_nesting: false) if Simulator.valid_circt_runtime_payload?(payload)
            raise ArgumentError, 'CIRCT runtime JSON must include circt_json_version and non-empty modules' if Simulator.malformed_circt_runtime_payload?(payload)
          end

          require_relative '../../../codegen/circt/runtime_json' unless defined?(RHDL::Codegen::CIRCT::RuntimeJSON)
          nodes = circt_nodes_for_runtime(ir_obj)
          io = StringIO.new
          RHDL::Codegen::CIRCT::RuntimeJSON.dump_to_io(nodes, io, compact_exprs: true)
          io.string
        end

        def circt_nodes_for_runtime(ir_obj)
          return ir_obj if circt_ir_object?(ir_obj)

          raise ArgumentError, "Unsupported IR object for CIRCT runtime JSON: #{ir_obj.class}"
        end

        def parse_json_string(text)
          JSON.parse(text, max_nesting: false)
        rescue JSON::ParserError
          nil
        end

        def stringify_hash_keys(hash)
          hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
        end

        def circt_ir_object?(ir_obj)
          class_name = ir_obj.class.name.to_s
          return true if class_name.include?('::CIRCT::IR::')

          ir_obj.respond_to?(:modules) &&
            Array(ir_obj.modules).all? { |mod| mod.class.name.to_s.include?('::CIRCT::IR::') }
        end
      end
      end
    end
  end
end
