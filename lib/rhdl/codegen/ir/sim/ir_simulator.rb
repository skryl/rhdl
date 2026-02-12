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
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'

module RHDL
  module Codegen
    module IR
      def self.sim_lib_name(base)
        case RbConfig::CONFIG['host_os']
        when /darwin/ then "#{base}.dylib"
        when /mswin|mingw/ then "#{base}.dll"
        else "#{base}.so"
        end
      end

      def self.sim_backend_available?(lib_path)
        return false unless File.exist?(lib_path)

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
      IR_INTERPRETER_LIB_PATH = File.join(IR_INTERPRETER_EXT_DIR, IR_INTERPRETER_LIB_NAME)

      JIT_EXT_DIR = File.expand_path('ir_jit/lib', __dir__)
      JIT_LIB_NAME = sim_lib_name('ir_jit')
      JIT_LIB_PATH = File.join(JIT_EXT_DIR, JIT_LIB_NAME)

      COMPILER_EXT_DIR = File.expand_path('ir_compiler/lib', __dir__)
      COMPILER_LIB_NAME = sim_lib_name('ir_compiler')
      COMPILER_LIB_PATH = File.join(COMPILER_EXT_DIR, COMPILER_LIB_NAME)

      IR_INTERPRETER_AVAILABLE = sim_backend_available?(IR_INTERPRETER_LIB_PATH)
      JIT_AVAILABLE = sim_backend_available?(JIT_LIB_PATH)
      COMPILER_AVAILABLE = sim_backend_available?(COMPILER_LIB_PATH)

      # Backwards compatibility aliases
      RTL_INTERPRETER_AVAILABLE = IR_INTERPRETER_AVAILABLE
      IR_JIT_AVAILABLE = JIT_AVAILABLE
      IR_COMPILER_AVAILABLE = COMPILER_AVAILABLE

      # Unified IR simulator wrapper for interpreter, JIT and compiler backends.
      class IrSimulator
        attr_reader :ir_json, :sub_cycles

        RUNNER_KIND_NONE = 0
        RUNNER_KIND_APPLE2 = 1
        RUNNER_KIND_MOS6502 = 2
        RUNNER_KIND_GAMEBOY = 3
        RUNNER_KIND_CPU8BIT = 4

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

        RUNNER_MEM_FLAG_MAPPED = 1

        RUNNER_RUN_MODE_BASIC = 0
        RUNNER_RUN_MODE_FULL = 1

        RUNNER_CONTROL_SET_RESET_VECTOR = 0
        RUNNER_CONTROL_RESET_SPEAKER_TOGGLES = 1
        RUNNER_CONTROL_RESET_LCD = 2

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

        BACKEND_CONFIGS = {
          interpreter: {
            available: IR_INTERPRETER_AVAILABLE,
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

        # @param ir_json [String] JSON representation of the IR
        # @param backend [Symbol] :interpreter, :jit, :compiler, or :auto
        # @param allow_fallback [Boolean] Allow fallback to another backend or Ruby implementation
        # @param sub_cycles [Integer] Number of sub-cycles per CPU cycle (default: 14)
        def initialize(ir_json, backend: :interpreter, allow_fallback: true, sub_cycles: 14)
          @ir_json = ir_json
          @sub_cycles = sub_cycles.clamp(1, 14)
          @requested_backend = normalize_backend(backend)

          selected = select_backend(@requested_backend)

          if selected
            configure_backend(selected)
            load_library
            create_simulator
            compile if @backend == :compile
          elsif allow_fallback
            @sim = RubyIrSim.new(ir_json)
            @backend = :ruby
            @fallback = true
          else
            raise LoadError, unavailable_backend_error_message(@requested_backend)
          end
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          !@fallback && @backend != :ruby
        end

        def backend
          @backend
        end

        def poke(name, value)
          return @sim.poke(name, value) if @fallback
          core_signal(SIM_SIGNAL_POKE, name: name, value: value)[:ok]
        end

        def peek(name)
          return @sim.peek(name) if @fallback
          core_signal(SIM_SIGNAL_PEEK, name: name)[:value]
        end

        def has_signal?(name)
          return @sim.respond_to?(:has_signal?) && @sim.has_signal?(name) if @fallback
          core_signal(SIM_SIGNAL_HAS, name: name)[:value] != 0
        end

        def evaluate
          return @sim.evaluate if @fallback
          core_exec(SIM_EXEC_EVALUATE)
        end

        def tick
          return @sim.tick if @fallback
          core_exec(SIM_EXEC_TICK)
        end

        def tick_forced
          return @sim.tick if @fallback  # Ruby fallback doesn't need edge detection
          core_exec(SIM_EXEC_TICK_FORCED)
        end

        def set_prev_clock(clock_list_idx, value)
          return if @fallback  # Ruby fallback doesn't track prev clocks
          core_exec(SIM_EXEC_SET_PREV_CLOCK, clock_list_idx, value)
        end

        def get_clock_list_idx(signal_idx)
          return -1 if @fallback
          result = core_exec(SIM_EXEC_GET_CLOCK_LIST_IDX, signal_idx)
          result[:ok] ? result[:value] : -1
        end

        def reset
          return @sim.reset if @fallback
          @sim_runner_speaker_toggles = 0
          core_exec(SIM_EXEC_RESET)
        end

        def signal_count
          return @sim.signal_count if @fallback
          core_exec(SIM_EXEC_SIGNAL_COUNT)[:value]
        end

        def reg_count
          return @sim.reg_count if @fallback
          core_exec(SIM_EXEC_REG_COUNT)[:value]
        end

        def compiled?
          return false if @fallback
          core_exec(SIM_EXEC_IS_COMPILED)[:value] != 0
        end

        def compile
          return true if @fallback

          error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          error_ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack('Q')
          result = core_exec(SIM_EXEC_COMPILE, 0, 0, error_ptr)
          return result[:value] != 0 if result[:ok]

          error_str_ptr = error_ptr[0, Fiddle::SIZEOF_VOIDP].unpack1('Q')
          if error_str_ptr != 0
            error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
            @fn_free_error.call(error_str_ptr)
            raise RuntimeError, "Compilation failed: #{error_msg}"
          end
          false
        end

        def generated_code
          return '' if @fallback
          core_blob(SIM_BLOB_GENERATED_CODE)
        end

        def input_names
          return @sim.input_names if @fallback
          csv = core_blob(SIM_BLOB_INPUT_NAMES)
          csv.empty? ? [] : csv.split(',')
        end

        def output_names
          return @sim.output_names if @fallback
          csv = core_blob(SIM_BLOB_OUTPUT_NAMES)
          csv.empty? ? [] : csv.split(',')
        end

        # VCD tracing methods
        def trace_start
          return @sim.trace_start if @fallback && @sim.respond_to?(:trace_start)
          return false if @fallback
          core_trace(SIM_TRACE_START)[:ok]
        end

        def trace_start_streaming(path)
          return @sim.trace_start_streaming(path) if @fallback && @sim.respond_to?(:trace_start_streaming)
          return false if @fallback
          core_trace(SIM_TRACE_START_STREAMING, path)[:ok]
        end

        def trace_stop
          return @sim.trace_stop if @fallback && @sim.respond_to?(:trace_stop)
          return nil if @fallback
          core_trace(SIM_TRACE_STOP)
        end

        def trace_enabled?
          return @sim.trace_enabled? if @fallback && @sim.respond_to?(:trace_enabled?)
          return false if @fallback
          core_trace(SIM_TRACE_ENABLED)[:value] != 0
        end

        def trace_capture
          return @sim.trace_capture if @fallback && @sim.respond_to?(:trace_capture)
          return nil if @fallback
          core_trace(SIM_TRACE_CAPTURE)
        end

        def trace_add_signal(name)
          return @sim.trace_add_signal(name) if @fallback && @sim.respond_to?(:trace_add_signal)
          return false if @fallback
          core_trace(SIM_TRACE_ADD_SIGNAL, name)[:ok]
        end

        def trace_add_signals_matching(pattern)
          return @sim.trace_add_signals_matching(pattern) if @fallback && @sim.respond_to?(:trace_add_signals_matching)
          return 0 if @fallback
          core_trace(SIM_TRACE_ADD_SIGNALS_MATCHING, pattern)[:value]
        end

        def trace_all_signals
          return @sim.trace_all_signals if @fallback && @sim.respond_to?(:trace_all_signals)
          return nil if @fallback
          core_trace(SIM_TRACE_ALL_SIGNALS)
        end

        def trace_clear_signals
          return @sim.trace_clear_signals if @fallback && @sim.respond_to?(:trace_clear_signals)
          return nil if @fallback
          core_trace(SIM_TRACE_CLEAR_SIGNALS)
        end

        def trace_to_vcd
          return @sim.trace_to_vcd if @fallback && @sim.respond_to?(:trace_to_vcd)
          return '' if @fallback
          core_blob(SIM_BLOB_TRACE_TO_VCD)
        end

        def trace_take_live_vcd
          return @sim.trace_take_live_vcd if @fallback && @sim.respond_to?(:trace_take_live_vcd)
          return '' if @fallback
          core_blob(SIM_BLOB_TRACE_TAKE_LIVE_VCD)
        end

        def trace_save_vcd(path)
          return @sim.trace_save_vcd(path) if @fallback && @sim.respond_to?(:trace_save_vcd)
          return false if @fallback
          core_trace(SIM_TRACE_SAVE_VCD, path)[:ok]
        end

        def trace_clear
          return @sim.trace_clear if @fallback && @sim.respond_to?(:trace_clear)
          return nil if @fallback
          core_trace(SIM_TRACE_CLEAR)
        end

        def trace_change_count
          return @sim.trace_change_count if @fallback && @sim.respond_to?(:trace_change_count)
          return 0 if @fallback
          core_trace(SIM_TRACE_CHANGE_COUNT)[:value]
        end

        def trace_signal_count
          return @sim.trace_signal_count if @fallback && @sim.respond_to?(:trace_signal_count)
          return 0 if @fallback
          core_trace(SIM_TRACE_SIGNAL_COUNT)[:value]
        end

        def trace_set_timescale(timescale)
          return @sim.trace_set_timescale(timescale) if @fallback && @sim.respond_to?(:trace_set_timescale)
          return false if @fallback
          core_trace(SIM_TRACE_SET_TIMESCALE, timescale)[:ok]
        end

        def trace_set_module_name(name)
          return @sim.trace_set_module_name(name) if @fallback && @sim.respond_to?(:trace_set_module_name)
          return false if @fallback
          core_trace(SIM_TRACE_SET_MODULE_NAME, name)[:ok]
        end

        def stats
          return @sim.stats if @fallback
          runner_kind = runner_kind
          {
            signals: signal_count,
            regs: reg_count,
            runner_kind: runner_kind,
            runner_mode: runner_mode?,
            apple2_mode: runner_kind == :apple2,
            gameboy_mode: gameboy_mode?,
            mos6502_mode: runner_kind == :mos6502,
            cpu8bit_mode: runner_kind == :cpu8bit
          }
        end

        # Batched tick execution
        def run_ticks(n)
          return @sim.respond_to?(:run_ticks) ? @sim.run_ticks(n) : n.times { @sim.tick } if @fallback
          core_exec(SIM_EXEC_RUN_TICKS, n)
        end

        # Get signal index by name (for caching)
        def get_signal_idx(name)
          return @sim.respond_to?(:get_signal_idx) ? @sim.get_signal_idx(name) : nil if @fallback
          result = core_signal(SIM_SIGNAL_GET_INDEX, name: name)
          result[:ok] ? result[:value] : nil
        end

        # Poke by index - faster than by name when index is cached
        def poke_by_idx(idx, value)
          return @sim.poke_by_idx(idx, value) if @fallback && @sim.respond_to?(:poke_by_idx)
          core_signal(SIM_SIGNAL_POKE_INDEX, idx: idx, value: value)
        end

        # Peek by index - faster than by name when index is cached
        def peek_by_idx(idx)
          return @sim.peek_by_idx(idx) if @fallback && @sim.respond_to?(:peek_by_idx)
          core_signal(SIM_SIGNAL_PEEK_INDEX, idx: idx)[:value]
        end

        # ====================================================================
        # Unified Runner Extension Methods
        # ====================================================================

        def runner_kind
          if @fallback
            return @sim.runner_kind if @sim.respond_to?(:runner_kind)
            return nil
          end

          case runner_probe(RUNNER_PROBE_KIND)
          when RUNNER_KIND_APPLE2 then :apple2
          when RUNNER_KIND_MOS6502 then :mos6502
          when RUNNER_KIND_GAMEBOY then :gameboy
          when RUNNER_KIND_CPU8BIT then :cpu8bit
          else nil
          end
        end

        def runner_mode?
          if @fallback
            return @sim.runner_mode? if @sim.respond_to?(:runner_mode?)
            return !runner_kind.nil?
          end
          runner_probe(RUNNER_PROBE_IS_MODE) != 0
        end

        def runner_load_memory(data, offset = 0, is_rom = false)
          if @fallback
            return @sim.runner_load_memory(data, offset, is_rom) if @sim.respond_to?(:runner_load_memory)
            return false
          end
          data = data.pack('C*') if data.is_a?(Array)
          return false if data.nil? || data.bytesize.zero?

          space = is_rom ? RUNNER_MEM_SPACE_ROM : RUNNER_MEM_SPACE_MAIN
          runner_mem(RUNNER_MEM_OP_LOAD, space, offset, data, 0) > 0
        end

        def runner_read_memory(offset, length, mapped: true)
          length = [length.to_i, 0].max
          if @fallback
            return @sim.runner_read_memory(offset, length, mapped: mapped) if @sim.respond_to?(:runner_read_memory)
            return Array.new(length, 0)
          end
          return [] if length.zero?

          flags = mapped ? RUNNER_MEM_FLAG_MAPPED : 0
          runner_mem_read(RUNNER_MEM_SPACE_MAIN, offset, length, flags)
        end

        def runner_write_memory(offset, data, mapped: true)
          if @fallback
            return @sim.runner_write_memory(offset, data, mapped: mapped) if @sim.respond_to?(:runner_write_memory)
            return 0
          end
          data = data.pack('C*') if data.is_a?(Array)
          return 0 if data.nil? || data.bytesize.zero?

          flags = mapped ? RUNNER_MEM_FLAG_MAPPED : 0
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_MAIN, offset, data, flags)
        end

        def runner_run_cycles(n, key_data = 0, key_ready = false)
          if @fallback
            return @sim.runner_run_cycles(n, key_data, key_ready) if @sim.respond_to?(:runner_run_cycles)
            return { text_dirty: false, key_cleared: false, cycles_run: 0, speaker_toggles: 0 }
          end

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
          if @fallback
            return @sim.runner_load_rom(data, offset) if @sim.respond_to?(:runner_load_rom)
          end

          data = data.pack('C*') if data.is_a?(Array)
          return false if data.nil? || data.bytesize.zero?
          runner_mem(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM, offset, data, 0) > 0
        end

        def runner_set_reset_vector(addr)
          vector = addr.to_i & 0xFFFF
          if @fallback
            return @sim.runner_set_reset_vector(vector) if @sim.respond_to?(:runner_set_reset_vector)
          end

          @fn_runner_control.call(@ctx, RUNNER_CONTROL_SET_RESET_VECTOR, vector, 0) != 0
        end

        def runner_speaker_toggles
          if @fallback
            return @sim.runner_speaker_toggles if @sim.respond_to?(:runner_speaker_toggles)
            return 0
          end
          return runner_probe(RUNNER_PROBE_SPEAKER_TOGGLES) if runner_kind == :mos6502
          @sim_runner_speaker_toggles || 0
        end

        def runner_reset_speaker_toggles
          if @fallback
            return @sim.runner_reset_speaker_toggles if @sim.respond_to?(:runner_reset_speaker_toggles)
            return nil
          end
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RESET_SPEAKER_TOGGLES, 0, 0)
          @sim_runner_speaker_toggles = 0
          nil
        end

        # ====================================================================
        # Game Boy Extension Methods
        # ====================================================================

        def gameboy_mode?
          return @sim.gameboy_mode? if @fallback && @sim.respond_to?(:gameboy_mode?)
          return false if @fallback
          runner_kind == :gameboy
        end

        def load_rom(data)
          return @sim.load_rom(data) if @fallback && @sim.respond_to?(:load_rom)
          return if @fallback
          runner_load_rom(data, 0)
        end

        def load_boot_rom(data)
          return @sim.load_boot_rom(data) if @fallback && @sim.respond_to?(:load_boot_rom)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          runner_mem(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_BOOT_ROM, 0, data, 0)
        end

        def run_gb_cycles(n)
          return @sim.run_gb_cycles(n) if @fallback && @sim.respond_to?(:run_gb_cycles)
          return { cycles_run: 0, frames_completed: 0 } if @fallback

          result_buf = Fiddle::Pointer.malloc(20)
          ok = @fn_runner_run.call(@ctx, n, 0, 0, RUNNER_RUN_MODE_FULL, result_buf)
          return { cycles_run: 0, frames_completed: 0 } if ok == 0
          values = result_buf[0, 20].unpack('llLLL')
          {
            cycles_run: values[2],
            frames_completed: values[4]
          }
        end

        def read_vram(addr)
          return @sim.read_vram(addr) if @fallback && @sim.respond_to?(:read_vram)
          return 0 if @fallback
          bytes = runner_mem_read(RUNNER_MEM_SPACE_VRAM, addr, 1, 0)
          bytes.empty? ? 0 : (bytes[0] & 0xFF)
        end

        def write_vram(addr, data)
          return @sim.write_vram(addr, data) if @fallback && @sim.respond_to?(:write_vram)
          return if @fallback
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_VRAM, addr, [data].pack('C'), 0)
        end

        def read_zpram(addr)
          return @sim.read_zpram(addr) if @fallback && @sim.respond_to?(:read_zpram)
          return 0 if @fallback
          bytes = runner_mem_read(RUNNER_MEM_SPACE_ZPRAM, addr, 1, 0)
          bytes.empty? ? 0 : (bytes[0] & 0xFF)
        end

        def write_zpram(addr, data)
          return @sim.write_zpram(addr, data) if @fallback && @sim.respond_to?(:write_zpram)
          return if @fallback
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_ZPRAM, addr, [data].pack('C'), 0)
        end

        def read_wram(addr)
          return @sim.read_wram(addr) if @fallback && @sim.respond_to?(:read_wram)
          return 0 if @fallback
          bytes = runner_mem_read(RUNNER_MEM_SPACE_WRAM, addr, 1, 0)
          bytes.empty? ? 0 : (bytes[0] & 0xFF)
        end

        def write_wram(addr, data)
          return @sim.write_wram(addr, data) if @fallback && @sim.respond_to?(:write_wram)
          return if @fallback
          runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_WRAM, addr, [data].pack('C'), 0)
        end

        def read_framebuffer
          return @sim.read_framebuffer if @fallback && @sim.respond_to?(:read_framebuffer)
          return [] if @fallback

          len = runner_probe(RUNNER_PROBE_FRAMEBUFFER_LEN)
          return [] if len <= 0
          runner_mem_read(RUNNER_MEM_SPACE_FRAMEBUFFER, 0, len, 0)
        end

        def frame_count
          return @sim.frame_count if @fallback && @sim.respond_to?(:frame_count)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_FRAME_COUNT)
        end

        def reset_lcd_state
          return @sim.reset_lcd_state if @fallback && @sim.respond_to?(:reset_lcd_state)
          return if @fallback
          @fn_runner_control.call(@ctx, RUNNER_CONTROL_RESET_LCD, 0, 0)
        end

        def get_v_cnt
          return @sim.get_v_cnt if @fallback && @sim.respond_to?(:get_v_cnt)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_V_CNT)
        end

        def get_h_cnt
          return @sim.get_h_cnt if @fallback && @sim.respond_to?(:get_h_cnt)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_H_CNT)
        end

        def get_vblank_irq
          return @sim.get_vblank_irq if @fallback && @sim.respond_to?(:get_vblank_irq)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_VBLANK_IRQ)
        end

        def get_if_r
          return @sim.get_if_r if @fallback && @sim.respond_to?(:get_if_r)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_IF_R)
        end

        def get_signal(idx)
          return @sim.get_signal(idx) if @fallback && @sim.respond_to?(:get_signal)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_SIGNAL, idx)
        end

        def get_lcdc_on
          return @sim.get_lcdc_on if @fallback && @sim.respond_to?(:get_lcdc_on)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_LCDC_ON)
        end

        def get_h_div_cnt
          return @sim.get_h_div_cnt if @fallback && @sim.respond_to?(:get_h_div_cnt)
          return 0 if @fallback
          runner_probe(RUNNER_PROBE_H_DIV_CNT)
        end

        def core_signal(op, name: nil, idx: 0, value: 0)
          out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_LONG)
          out[0, Fiddle::SIZEOF_LONG] = [0].pack(Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
          rc = @fn_sim_signal.call(@ctx, op, name, idx, value, out)
          {
            ok: rc != 0,
            value: out[0, Fiddle::SIZEOF_LONG].unpack1(Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
          }
        end

        def core_exec(op, arg0 = 0, arg1 = 0, error_out = nil)
          out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_LONG)
          out[0, Fiddle::SIZEOF_LONG] = [0].pack(Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
          rc = @fn_sim_exec.call(@ctx, op, arg0, arg1, out, error_out)
          {
            ok: rc != 0,
            value: out[0, Fiddle::SIZEOF_LONG].unpack1(Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
          }
        end

        def core_trace(op, str_arg = nil)
          out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_LONG)
          out[0, Fiddle::SIZEOF_LONG] = [0].pack(Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
          rc = @fn_sim_trace.call(@ctx, op, str_arg, out)
          {
            ok: rc != 0,
            value: out[0, Fiddle::SIZEOF_LONG].unpack1(Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
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

        def respond_to_missing?(method_name, include_private = false)
          (@fallback && @sim.respond_to?(method_name)) || super
        end

        def method_missing(method_name, *args, &block)
          if @fallback && @sim.respond_to?(method_name)
            @sim.send(method_name, *args, &block)
          else
            super
          end
        end

        private

        def normalize_backend(backend)
          value = backend.to_sym
          value = :interpreter if value == :interpret
          value = :compiler if value == :compile
          return value if BACKEND_CONFIGS.key?(value) || value == :auto
          raise ArgumentError, "Unknown IR backend: #{backend.inspect}"
        end

        def backend_candidates(requested)
          case requested
          when :interpreter then %i[interpreter]
          when :jit then %i[jit interpreter]
          when :compiler then %i[compiler interpreter]
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
          @destructor = @fn_destroy
        end
      end

      # Ruby fallback simulator for when native extension is not available
      class RubyIrSim
        def initialize(json)
          @ir = JSON.parse(json, symbolize_names: true, max_nesting: false)
          @signals = {}
          @widths = {}
          @inputs = []
          @outputs = []

          # Initialize ports
          @ir[:ports]&.each do |port|
            @signals[port[:name]] = 0
            @widths[port[:name]] = port[:width]
            if port[:direction] == 'in'
              @inputs << port[:name]
            else
              @outputs << port[:name]
            end
          end

          # Initialize wires
          @ir[:nets]&.each do |net|
            @signals[net[:name]] = 0
            @widths[net[:name]] = net[:width]
          end

          # Initialize registers (with reset values if present)
          @reset_values = {}
          @ir[:regs]&.each do |reg|
            reset_val = reg[:reset_value] || 0
            @signals[reg[:name]] = reset_val
            @widths[reg[:name]] = reg[:width]
            @reset_values[reg[:name]] = reset_val
          end

          @assigns = @ir[:assigns] || []
          @processes = @ir[:processes] || []
        end

        def native?
          false
        end

        def mask(width)
          width >= 64 ? 0xFFFFFFFFFFFFFFFF : (1 << width) - 1
        end

        def eval_expr(expr)
          case expr[:type]
          when 'signal'
            (@signals[expr[:name]] || 0) & mask(expr[:width])
          when 'literal'
            expr[:value] & mask(expr[:width])
          when 'unary_op'
            val = eval_expr(expr[:operand])
            m = mask(expr[:width])
            case expr[:op]
            when '~', 'not'
              (~val) & m
            when '&', 'reduce_and'
              op_width = expr[:operand][:width]
              (val & mask(op_width)) == mask(op_width) ? 1 : 0
            when '|', 'reduce_or'
              val != 0 ? 1 : 0
            when '^', 'reduce_xor'
              val.to_s(2).count('1') & 1
            else
              val
            end
          when 'binary_op'
            l = eval_expr(expr[:left])
            r = eval_expr(expr[:right])
            m = mask(expr[:width])
            case expr[:op]
            when '&' then l & r
            when '|' then l | r
            when '^' then l ^ r
            when '+' then (l + r) & m
            when '-' then (l - r) & m
            when '*' then (l * r) & m
            when '/' then r != 0 ? l / r : 0
            when '%' then r != 0 ? l % r : 0
            when '<<' then (l << [r, 63].min) & m
            when '>>' then l >> [r, 63].min
            when '==' then l == r ? 1 : 0
            when '!=' then l != r ? 1 : 0
            when '<' then l < r ? 1 : 0
            when '>' then l > r ? 1 : 0
            when '<=', 'le' then l <= r ? 1 : 0
            when '>=' then l >= r ? 1 : 0
            else 0
            end
          when 'mux'
            cond = eval_expr(expr[:condition])
            m = mask(expr[:width])
            if cond != 0
              eval_expr(expr[:when_true]) & m
            else
              eval_expr(expr[:when_false]) & m
            end
          when 'slice'
            val = eval_expr(expr[:base])
            (val >> expr[:low]) & mask(expr[:width])
          when 'concat'
            result = 0
            shift = 0
            expr[:parts].each do |part|
              part_val = eval_expr(part)
              part_width = part[:width]
              result |= (part_val & mask(part_width)) << shift
              shift += part_width
            end
            result & mask(expr[:width])
          when 'resize'
            eval_expr(expr[:expr]) & mask(expr[:width])
          else
            0
          end
        end

        def poke(name, value)
          raise "Unknown input: #{name}" unless @inputs.include?(name)
          width = @widths[name] || 64
          @signals[name] = value & mask(width)
        end

        def peek(name)
          @signals[name] || 0
        end

        def evaluate
          10.times do
            changed = false
            @assigns.each do |assign|
              new_val = eval_expr(assign[:expr])
              width = @widths[assign[:target]] || 64
              masked = new_val & mask(width)
              if @signals[assign[:target]] != masked
                @signals[assign[:target]] = masked
                changed = true
              end
            end
            break unless changed
          end
        end

        def tick
          evaluate

          # Sample register inputs
          next_regs = {}
          @processes.each do |process|
            next unless process[:clocked]
            process[:statements]&.each do |stmt|
              new_val = eval_expr(stmt[:expr])
              width = @widths[stmt[:target]] || 64
              next_regs[stmt[:target]] = new_val & mask(width)
            end
          end

          # Update registers
          next_regs.each do |name, val|
            @signals[name] = val
          end

          evaluate
        end

        def reset
          @signals.transform_values! { 0 }
          # Apply register reset values
          @reset_values.each do |name, val|
            @signals[name] = val
          end
        end

        def signal_count
          @signals.length
        end

        def reg_count
          @processes.sum { |p| p[:statements]&.length || 0 }
        end

        def input_names
          @inputs
        end

        def output_names
          @outputs
        end

        def stats
          {
            signal_count: signal_count,
            reg_count: reg_count,
            input_count: @inputs.length,
            output_count: @outputs.length,
            assign_count: @assigns.length,
            process_count: @processes.length
          }
        end
      end

      # Convert Behavior IR to JSON format for the simulator
      module IRToJson
        module_function

        def convert(ir)
          {
            name: ir.name,
            ports: ir.ports.map { |p| port_to_hash(p) },
            nets: ir.nets.map { |n| net_to_hash(n) },
            regs: ir.regs.map { |r| reg_to_hash(r) },
            assigns: ir.assigns.map { |a| assign_to_hash(a) },
            processes: ir.processes.map { |p| process_to_hash(p) },
            memories: (ir.memories || []).map { |m| memory_to_hash(m) },
            write_ports: (ir.write_ports || []).map { |wp| write_port_to_hash(wp) },
            sync_read_ports: (ir.sync_read_ports || []).map { |rp| sync_read_port_to_hash(rp) }
          }.to_json(max_nesting: false)
        end

        def port_to_hash(port)
          {
            name: port.name.to_s,
            direction: port.direction.to_s,
            width: port.width
          }
        end

        def net_to_hash(net)
          {
            name: net.name.to_s,
            width: net.width
          }
        end

        def reg_to_hash(reg)
          hash = {
            name: reg.name.to_s,
            width: reg.width
          }
          hash[:reset_value] = reg.reset_value if reg.reset_value
          hash
        end

        def assign_to_hash(assign)
          {
            target: assign.target.to_s,
            expr: expr_to_hash(assign.expr)
          }
        end

        def process_to_hash(process)
          {
            name: process.name.to_s,
            clock: process.clock&.to_s,
            clocked: process.clocked,
            statements: flatten_statements(process.statements)
          }
        end

        def flatten_statements(stmts)
          return [] unless stmts
          result = []
          stmts.each do |stmt|
            case stmt
            when IR::SeqAssign
              result << seq_assign_to_hash(stmt)
            when IR::If
              flatten_if(stmt, result)
            end
          end
          result
        end

        def flatten_if(if_stmt, result)
          cond = expr_to_hash(if_stmt.condition)

          then_assigns = {}
          if_stmt.then_statements&.each do |s|
            case s
            when IR::SeqAssign
              then_assigns[s.target.to_s] = expr_to_hash(s.expr)
            when IR::If
              flatten_if(s, result)
            end
          end

          else_assigns = {}
          if_stmt.else_statements&.each do |s|
            case s
            when IR::SeqAssign
              else_assigns[s.target.to_s] = expr_to_hash(s.expr)
            when IR::If
              flatten_if(s, result)
            end
          end

          all_targets = (then_assigns.keys + else_assigns.keys).uniq
          all_targets.each do |target|
            then_expr = then_assigns[target]
            else_expr = else_assigns[target]
            width = (then_expr || else_expr)&.dig(:width) || 8

            if then_expr && else_expr
              result << {
                target: target,
                expr: { type: 'mux', condition: cond, when_true: then_expr, when_false: else_expr, width: width }
              }
            elsif then_expr
              result << {
                target: target,
                expr: { type: 'mux', condition: cond, when_true: then_expr, when_false: { type: 'signal', name: target, width: width }, width: width }
              }
            elsif else_expr
              inv_cond = { type: 'unary_op', op: '~', operand: cond, width: 1 }
              result << {
                target: target,
                expr: { type: 'mux', condition: inv_cond, when_true: else_expr, when_false: { type: 'signal', name: target, width: width }, width: width }
              }
            end
          end
        end

        def seq_assign_to_hash(stmt)
          {
            target: stmt.target.to_s,
            expr: expr_to_hash(stmt.expr)
          }
        end

        def memory_to_hash(mem)
          hash = {
            name: mem.name.to_s,
            depth: mem.depth,
            width: mem.width
          }
          hash[:initial_data] = mem.initial_data if mem.initial_data
          hash
        end

        def write_port_to_hash(wp)
          {
            memory: wp.memory.to_s,
            clock: wp.clock.to_s,
            addr: expr_to_hash(wp.addr),
            data: expr_to_hash(wp.data),
            enable: expr_to_hash(wp.enable)
          }
        end

        def sync_read_port_to_hash(rp)
          hash = {
            memory: rp.memory.to_s,
            clock: rp.clock.to_s,
            addr: expr_to_hash(rp.addr),
            data: rp.data.to_s
          }
          hash[:enable] = expr_to_hash(rp.enable) if rp.enable
          hash
        end

        def expr_to_hash(expr)
          case expr
          when IR::Signal
            { type: 'signal', name: expr.name.to_s, width: expr.width }
          when IR::Literal
            { type: 'literal', value: expr.value, width: expr.width }
          when IR::UnaryOp
            { type: 'unary_op', op: expr.op.to_s, operand: expr_to_hash(expr.operand), width: expr.width }
          when IR::BinaryOp
            { type: 'binary_op', op: expr.op.to_s, left: expr_to_hash(expr.left), right: expr_to_hash(expr.right), width: expr.width }
          when IR::Mux
            { type: 'mux', condition: expr_to_hash(expr.condition), when_true: expr_to_hash(expr.when_true), when_false: expr_to_hash(expr.when_false), width: expr.width }
          when IR::Slice
            low = 0
            high = expr.width - 1

            if expr.range.is_a?(Range)
              range_begin = expr.range.begin
              range_end = expr.range.end
              if range_begin.is_a?(Integer) && range_end.is_a?(Integer)
                low = [range_begin, range_end].min
                high = [range_begin, range_end].max
              end
            elsif expr.range.is_a?(Integer)
              low = expr.range
              high = expr.range
            end
            { type: 'slice', base: expr_to_hash(expr.base), low: low, high: high, width: expr.width }
          when IR::Concat
            { type: 'concat', parts: expr.parts.map { |p| expr_to_hash(p) }, width: expr.width }
          when IR::Resize
            { type: 'resize', expr: expr_to_hash(expr.expr), width: expr.width }
          when IR::Case
            if expr.cases.empty?
              expr_to_hash(expr.default)
            else
              result = expr.default ? expr_to_hash(expr.default) : { type: 'literal', value: 0, width: expr.width }
              expr.cases.each do |values, case_expr|
                values.each do |v|
                  cond = { type: 'binary_op', op: '==', left: expr_to_hash(expr.selector), right: { type: 'literal', value: v, width: expr.selector.width }, width: 1 }
                  result = { type: 'mux', condition: cond, when_true: expr_to_hash(case_expr), when_false: result, width: expr.width }
                end
              end
              result
            end
          when IR::MemoryRead
            { type: 'mem_read', memory: expr.memory.to_s, addr: expr_to_hash(expr.addr), width: expr.width }
          else
            { type: 'literal', value: 0, width: 1 }
          end
        end
      end
    end
  end
end
