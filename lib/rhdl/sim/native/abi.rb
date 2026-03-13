# frozen_string_literal: true

require 'json'
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'

module RHDL
  module Sim
    module Native
      module ABI
        SIM_CAP_SIGNAL_INDEX = 1 << 0
        SIM_CAP_FORCED_CLOCK = 1 << 1
        SIM_CAP_TRACE = 1 << 2
        SIM_CAP_TRACE_STREAMING = 1 << 3
        SIM_CAP_COMPILE = 1 << 4
        SIM_CAP_GENERATED_CODE = 1 << 5
        SIM_CAP_RUNNER = 1 << 6

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
        SIM_BLOB_SPARC64_WISHBONE_TRACE = 5
        SIM_BLOB_SPARC64_UNMAPPED_ACCESSES = 6

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
        RUNNER_PROBE_LCD_X = 12
        RUNNER_PROBE_LCD_Y = 13
        RUNNER_PROBE_LCD_PREV_CLKENA = 14
        RUNNER_PROBE_LCD_PREV_VSYNC = 15
        RUNNER_PROBE_LCD_FRAME_COUNT = 16
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

        class << self
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

        class Simulator
          attr_reader :lib_path, :sub_cycles, :raw_context

          def initialize(lib_path:, config: nil, sub_cycles: 14, signal_widths_by_name: {}, signal_widths_by_idx: nil,
                         backend_label: 'native HDL')
            @lib_path = File.expand_path(lib_path)
            @sub_cycles = sub_cycles.to_i
            @backend_label = backend_label
            @config_json = prepare_config_json(config)
            @signal_widths_by_name = stringify_keys(signal_widths_by_name || {})
            @signal_widths_by_idx = Array(signal_widths_by_idx)

            load_library
            create_simulator
            hydrate_signal_widths!
            load_caps!
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
            destroy.call(ptr) if destroy && ABI.pointer_alive?(ptr)
            true
          end

          def closed?
            return true unless defined?(@ctx_state) && @ctx_state

            @ctx_state[:closed]
          end

          def native?
            true
          end

          def cap?(flag)
            (@sim_caps_flags.to_i & flag) != 0
          end

          def trace_supported?
            cap?(SIM_CAP_TRACE)
          end

          def trace_streaming_supported?
            cap?(SIM_CAP_TRACE_STREAMING)
          end

          def runner_supported?
            cap?(SIM_CAP_RUNNER)
          end

          def input_names
            csv = core_blob(SIM_BLOB_INPUT_NAMES)
            csv.empty? ? [] : csv.split(',')
          end

          def output_names
            csv = core_blob(SIM_BLOB_OUTPUT_NAMES)
            csv.empty? ? [] : csv.split(',')
          end

          def signal_count
            core_exec(SIM_EXEC_SIGNAL_COUNT)[:value]
          end

          def reg_count
            core_exec(SIM_EXEC_REG_COUNT)[:value]
          end

          def has_signal?(name)
            core_signal(SIM_SIGNAL_HAS, name: name)[:value] != 0
          end

          def get_signal_idx(name)
            result = core_signal(SIM_SIGNAL_GET_INDEX, name: name)
            result[:ok] ? result[:value] : nil
          end

          def peek(name)
            width = signal_width_by_name(name)
            return core_signal(SIM_SIGNAL_PEEK, name: name)[:value] unless width && width > 64

            peek_wide_by_name(name, width)
          end

          def poke(name, value)
            width = signal_width_by_name(name)
            return core_signal(SIM_SIGNAL_POKE, name: name, value: value)[:ok] unless width && width > 64

            poke_wide_by_name(name, normalize_signal_value(value, width), width)
          end

          def peek_by_idx(idx)
            width = signal_width_by_idx(idx)
            return core_signal(SIM_SIGNAL_PEEK_INDEX, idx: idx)[:value] unless width && width > 64

            peek_wide_by_idx(idx, width)
          end

          def poke_by_idx(idx, value)
            width = signal_width_by_idx(idx)
            return core_signal(SIM_SIGNAL_POKE_INDEX, idx: idx, value: value)[:ok] unless width && width > 64

            poke_wide_by_idx(idx, normalize_signal_value(value, width), width)
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
            core_exec(SIM_EXEC_RESET)
          end

          def run_ticks(n)
            core_exec(SIM_EXEC_RUN_TICKS, n)
          end

          def compiled?
            return false unless cap?(SIM_CAP_COMPILE)

            core_exec(SIM_EXEC_IS_COMPILED)[:value] != 0
          end

          def compile
            return false unless cap?(SIM_CAP_COMPILE)

            error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
            clear_pointer_ptr!(error_ptr)
            result = core_exec(SIM_EXEC_COMPILE, 0, 0, error_ptr)
            return result[:value] != 0 if result[:ok]

            error_str_ptr = read_pointer_ptr(error_ptr)
            if error_str_ptr != 0
              error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
              @fn_free_error.call(error_str_ptr)
              raise RuntimeError, "Compilation failed: #{error_msg}"
            end
            false
          end

          def generated_code
            return '' unless cap?(SIM_CAP_GENERATED_CODE)

            core_blob(SIM_BLOB_GENERATED_CODE)
          end

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

          def runner_kind
            return nil unless runner_supported?

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
            return nil unless @fn_runner_run

            result_buf = Fiddle::Pointer.malloc(20)
            ok = @fn_runner_run.call(@ctx, n, key_data, key_ready ? 1 : 0, RUNNER_RUN_MODE_BASIC, result_buf)
            return nil if ok == 0

            values = result_buf[0, 20].unpack('llLLL')
            {
              text_dirty: values[0] != 0,
              key_cleared: values[1] != 0,
              cycles_run: values[2],
              speaker_toggles: values[3],
              frames_completed: values[4]
            }
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

          def runner_load_boot_rom(data, offset = 0)
            data = data.pack('C*') if data.is_a?(Array)
            return false if data.nil? || data.bytesize.zero?

            runner_mem(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_BOOT_ROM, offset, data, 0) > 0
          end

          def runner_read_boot_rom(offset, length)
            runner_read_memory_space(RUNNER_MEM_SPACE_BOOT_ROM, offset, length)
          end

          def runner_load_vram(data, offset = 0)
            runner_load_memory_space(RUNNER_MEM_SPACE_VRAM, data, offset)
          end

          def runner_read_vram(offset, length)
            runner_read_memory_space(RUNNER_MEM_SPACE_VRAM, offset, length)
          end

          def runner_write_vram(offset, data)
            runner_write_memory_space(RUNNER_MEM_SPACE_VRAM, offset, data)
          end

          def runner_load_zpram(data, offset = 0)
            runner_load_memory_space(RUNNER_MEM_SPACE_ZPRAM, data, offset)
          end

          def runner_read_zpram(offset, length)
            runner_read_memory_space(RUNNER_MEM_SPACE_ZPRAM, offset, length)
          end

          def runner_write_zpram(offset, data)
            runner_write_memory_space(RUNNER_MEM_SPACE_ZPRAM, offset, data)
          end

          def runner_load_wram(data, offset = 0)
            runner_load_memory_space(RUNNER_MEM_SPACE_WRAM, data, offset)
          end

          def runner_read_wram(offset, length)
            runner_read_memory_space(RUNNER_MEM_SPACE_WRAM, offset, length)
          end

          def runner_write_wram(offset, data)
            runner_write_memory_space(RUNNER_MEM_SPACE_WRAM, offset, data)
          end

          def runner_read_framebuffer(offset = 0, length = nil)
            total = runner_framebuffer_len
            return [] if total <= 0

            offset = offset.to_i
            available = [total - offset, 0].max
            requested = length.nil? ? available : [length.to_i, 0].max
            runner_read_memory_space(RUNNER_MEM_SPACE_FRAMEBUFFER, offset, [requested, available].min)
          end

          def runner_framebuffer_len
            runner_probe(RUNNER_PROBE_FRAMEBUFFER_LEN).to_i
          end

          def runner_frame_count
            runner_probe(RUNNER_PROBE_FRAME_COUNT).to_i
          end

          def runner_v_cnt
            runner_probe(RUNNER_PROBE_V_CNT).to_i
          end

          def runner_h_cnt
            runner_probe(RUNNER_PROBE_H_CNT).to_i
          end

          def runner_vblank_irq?
            runner_probe(RUNNER_PROBE_VBLANK_IRQ).to_i != 0
          end

          def runner_if_r
            runner_probe(RUNNER_PROBE_IF_R).to_i
          end

          def runner_probe_signal(signal_idx)
            runner_probe(RUNNER_PROBE_SIGNAL, signal_idx).to_i
          end

          def runner_lcdc_on?
            runner_probe(RUNNER_PROBE_LCDC_ON).to_i != 0
          end

          def runner_h_div_cnt
            runner_probe(RUNNER_PROBE_H_DIV_CNT).to_i
          end

          def runner_lcd_x
            runner_probe(RUNNER_PROBE_LCD_X).to_i
          end

          def runner_lcd_y
            runner_probe(RUNNER_PROBE_LCD_Y).to_i
          end

          def runner_lcd_prev_clkena
            runner_probe(RUNNER_PROBE_LCD_PREV_CLKENA).to_i
          end

          def runner_lcd_prev_vsync
            runner_probe(RUNNER_PROBE_LCD_PREV_VSYNC).to_i
          end

          def runner_lcd_frame_count
            runner_probe(RUNNER_PROBE_LCD_FRAME_COUNT).to_i
          end

          def runner_set_reset_vector(addr)
            return false unless @fn_runner_control

            vector = addr.to_i & 0xFFFF_FFFF
            @fn_runner_control.call(@ctx, RUNNER_CONTROL_SET_RESET_VECTOR, vector, 0) != 0
          end

          def runner_speaker_toggles
            runner_probe(RUNNER_PROBE_SPEAKER_TOGGLES)
          end

          def runner_reset_speaker_toggles
            return nil unless @fn_runner_control

            @fn_runner_control.call(@ctx, RUNNER_CONTROL_RESET_SPEAKER_TOGGLES, 0, 0)
            nil
          end

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

          def runner_riscv_uart_receive_bytes(bytes)
            return false unless riscv_mode?

            payload = bytes.is_a?(String) ? bytes.b : Array(bytes).pack('C*')
            return true if payload.empty?

            runner_mem(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_UART_RX, 0, payload, 0) > 0
          end

          def runner_riscv_uart_receive_byte(byte)
            runner_riscv_uart_receive_bytes([byte.to_i & 0xFF])
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

          def runner_ao486_last_io_read
            runner_probe(RUNNER_PROBE_AO486_LAST_IO_READ).to_i
          end

          def runner_ao486_last_io_write_meta
            runner_probe(RUNNER_PROBE_AO486_LAST_IO_WRITE_META).to_i
          end

          def runner_ao486_last_io_write_data
            runner_probe(RUNNER_PROBE_AO486_LAST_IO_WRITE_DATA).to_i
          end

          def runner_ao486_last_irq_vector
            runner_probe(RUNNER_PROBE_AO486_LAST_IRQ_VECTOR).to_i
          end

          def runner_ao486_dos_int13_state
            runner_probe(RUNNER_PROBE_AO486_DOS_INT13_STATE).to_i
          end

          def runner_ao486_dos_int10_state
            runner_probe(RUNNER_PROBE_AO486_DOS_INT10_STATE).to_i
          end

          def runner_ao486_dos_int16_state
            runner_probe(RUNNER_PROBE_AO486_DOS_INT16_STATE).to_i
          end

          def runner_ao486_dos_int1a_state
            runner_probe(RUNNER_PROBE_AO486_DOS_INT1A_STATE).to_i
          end

          def runner_ao486_dos_int13_bx
            runner_probe(RUNNER_PROBE_AO486_DOS_INT13_BX).to_i
          end

          def runner_ao486_dos_int13_cx
            runner_probe(RUNNER_PROBE_AO486_DOS_INT13_CX).to_i
          end

          def runner_ao486_dos_int13_dx
            runner_probe(RUNNER_PROBE_AO486_DOS_INT13_DX).to_i
          end

          def runner_ao486_dos_int13_es
            runner_probe(RUNNER_PROBE_AO486_DOS_INT13_ES).to_i
          end

          private

          def load_library
            raise LoadError, "native HDL shared library not found: #{@lib_path}" unless File.exist?(@lib_path)

            @lib = dlopen_library(@lib_path)

            @fn_create = Fiddle::Function.new(
              @lib['sim_create'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOIDP
            )
            @fn_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @fn_free_error = Fiddle::Function.new(@lib['sim_free_error'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @fn_sim_get_caps = Fiddle::Function.new(@lib['sim_get_caps'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
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
            @fn_runner_get_caps = load_optional_function('runner_get_caps', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
            @fn_runner_mem = load_optional_function(
              'runner_mem',
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_UINT],
              Fiddle::TYPE_SIZE_T
            )
            @fn_runner_run = load_optional_function(
              'runner_run',
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_CHAR, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_INT
            )
            @fn_runner_control = load_optional_function(
              'runner_control',
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
              Fiddle::TYPE_INT
            )
            @fn_runner_probe = load_optional_function(
              'runner_probe',
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
              Fiddle::TYPE_LONG_LONG
            )
          end

          def create_simulator
            error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
            clear_pointer_ptr!(error_ptr)
            @ctx = @fn_create.call(@config_json, @config_json.bytesize, @sub_cycles, error_ptr)

            if @ctx.nil? || (@ctx.respond_to?(:null?) && @ctx.null?)
              error_str_ptr = read_pointer_ptr(error_ptr)
              if error_str_ptr != 0
                error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
                @fn_free_error.call(error_str_ptr)
                raise RuntimeError, "Failed to create #{@backend_label} simulator: #{error_msg}"
              end
              raise RuntimeError, "Failed to create #{@backend_label} simulator"
            end

            @ctx_state = { ptr: @ctx, destroy: @fn_destroy, closed: false }
            @raw_context = @ctx
            ObjectSpace.define_finalizer(self, ABI.finalizer_for(@ctx_state))
          end

          def load_caps!
            caps_buf = Fiddle::Pointer.malloc(4)
            caps_buf[0, 4] = [0].pack('L')
            @sim_caps_flags = @fn_sim_get_caps.call(@ctx, caps_buf) != 0 ? caps_buf[0, 4].unpack1('L') : 0

            runner_caps = Fiddle::Pointer.malloc(16)
            runner_caps[0, 16] = "\0" * 16
            if @fn_runner_get_caps && @fn_runner_get_caps.call(@ctx, runner_caps) != 0
              @runner_caps_kind, @runner_caps_mem_spaces, @runner_caps_control_ops, @runner_caps_probe_ops =
                runner_caps[0, 16].unpack('lLLL')
            else
              @runner_caps_kind = RUNNER_KIND_NONE
              @runner_caps_mem_spaces = 0
              @runner_caps_control_ops = 0
              @runner_caps_probe_ops = 0
            end
          end

          def prepare_config_json(config)
            return '{}' if config.nil?
            return config if config.is_a?(String)

            JSON.generate(config, max_nesting: false)
          end

          def stringify_keys(hash)
            hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v.to_i }
          end

          def hydrate_signal_widths!
            return unless @signal_widths_by_idx.empty?
            return if @signal_widths_by_name.empty?

            @signal_widths_by_idx = (input_names + output_names).map { |name| @signal_widths_by_name[name.to_s] }
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
              return core_signal_wide(SIM_SIGNAL_POKE_INDEX, idx: idx, value: value)[:ok]
            end
            raise RangeError, "no wide signal API available for #{idx}" unless @fn_sim_poke_word_by_idx

            split_wide_words(value, width).each_with_index.all? do |word, word_idx|
              @fn_sim_poke_word_by_idx.call(@ctx, idx, word_idx, word) != 0
            end
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

          def core_signal(op, name: nil, idx: 0, value: 0)
            out = scratch_ulong_ptr
            clear_ulong_ptr!(out)
            rc = @fn_sim_signal.call(@ctx, op, name, idx, value, out)
            { ok: rc != 0, value: read_ulong_ptr(out) }
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
            { ok: rc != 0, value: join_wide_words([lo, hi]) }
          end

          def core_exec(op, arg0 = 0, arg1 = 0, error_out = nil)
            out = scratch_ulong_ptr
            clear_ulong_ptr!(out)
            rc = @fn_sim_exec.call(@ctx, op, arg0, arg1, out, error_out)
            { ok: rc != 0, value: read_ulong_ptr(out) }
          end

          def core_trace(op, str_arg = nil)
            out = scratch_ulong_ptr
            clear_ulong_ptr!(out)
            rc = @fn_sim_trace.call(@ctx, op, str_arg, out)
            { ok: rc != 0, value: read_ulong_ptr(out) }
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
            return 0 unless @fn_runner_mem

            @fn_runner_mem.call(@ctx, op, space, offset, data, data.bytesize, flags)
          end

          def runner_load_memory_space(space, data, offset = 0)
            data = data.pack('C*') if data.is_a?(Array)
            return false if data.nil? || data.bytesize.zero?

            runner_mem(RUNNER_MEM_OP_LOAD, space, offset, data, 0) > 0
          end

          def runner_write_memory_space(space, offset, data)
            data = data.pack('C*') if data.is_a?(Array)
            return 0 if data.nil? || data.bytesize.zero?

            runner_mem(RUNNER_MEM_OP_WRITE, space, offset, data, 0)
          end

          def runner_read_memory_space(space, offset, length)
            length = [length.to_i, 0].max
            return [] if length.zero?

            runner_mem_read(space, offset, length, 0)
          end

          def runner_mem_read(space, offset, length, flags)
            return [] unless @fn_runner_mem

            buf = Fiddle::Pointer.malloc(length)
            read_len = @fn_runner_mem.call(@ctx, RUNNER_MEM_OP_READ, space, offset, buf, length, flags)
            buf[0, read_len].unpack('C*')
          end

          def runner_probe(op, arg0 = 0)
            return 0 unless @fn_runner_probe

            @fn_runner_probe.call(@ctx, op, arg0)
          end

          public

          def bind_function(symbol_name, arg_types, return_type)
            Fiddle::Function.new(@lib[symbol_name], arg_types, return_type)
          end

          def bind_optional_function(symbol_name, arg_types, return_type)
            load_optional_function(symbol_name, arg_types, return_type)
          end

          private

          def load_optional_function(symbol_name, arg_types, return_type)
            Fiddle::Function.new(@lib[symbol_name], arg_types, return_type)
          rescue Fiddle::DLError
            nil
          end

          def dlopen_library(lib_path)
            sign_darwin_shared_library(lib_path)
            Fiddle.dlopen(lib_path)
          rescue Fiddle::DLError
            raise unless RbConfig::CONFIG['host_os'] =~ /darwin/

            sign_darwin_shared_library(lib_path)
            sleep 0.1
            Fiddle.dlopen(lib_path)
          end

          def sign_darwin_shared_library(lib_path)
            return unless RbConfig::CONFIG['host_os'] =~ /darwin/
            return unless File.exist?(lib_path)
            return unless system('which', 'codesign', out: File::NULL, err: File::NULL)

            system('codesign', '--force', '--sign', '-', '--timestamp=none', lib_path, out: File::NULL, err: File::NULL)
          end

          def scratch_ulong_ptr
            @scratch_ulong_ptr ||= Fiddle::Pointer.malloc(Fiddle::SIZEOF_LONG)
          end

          def clear_ulong_ptr!(ptr)
            ptr[0, Fiddle::SIZEOF_LONG] = packed_zero_ulong
          end

          def read_ulong_ptr(ptr)
            ptr[0, Fiddle::SIZEOF_LONG].unpack1(packed_ulong_format)
          end

          def packed_zero_ulong
            @packed_zero_ulong ||= [0].pack(packed_ulong_format)
          end

          def packed_ulong_format
            @packed_ulong_format ||= (Fiddle::SIZEOF_LONG == 8 ? 'Q' : 'L')
          end

          def scratch_wide_in_ptr
            @scratch_wide_in_ptr ||= Fiddle::Pointer.malloc(16)
          end

          def scratch_wide_out_ptr
            @scratch_wide_out_ptr ||= Fiddle::Pointer.malloc(16)
          end

          def clear_pointer_ptr!(ptr)
            ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack(pointer_pack_format)
          end

          def read_pointer_ptr(ptr)
            ptr[0, Fiddle::SIZEOF_VOIDP].unpack1(pointer_pack_format)
          end

          def pointer_pack_format
            @pointer_pack_format ||= (Fiddle::SIZEOF_VOIDP == 8 ? 'Q' : 'L')
          end
        end
      end
    end
  end
end
