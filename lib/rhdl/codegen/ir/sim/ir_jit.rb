# frozen_string_literal: true

# IR-level JIT compiler with Cranelift backend (Fiddle-based)
#
# This simulator generates native machine code at load time using Cranelift,
# eliminating all interpretation dispatch overhead. The generated code
# directly computes signal values with no runtime type checking.
#
# Uses Fiddle (Ruby's built-in FFI) to call the Rust library directly,
# similar to the Verilator runners.

require 'json'
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'
require_relative 'ir_interpreter'  # For IRToJson module and fallback

module RHDL
  module Codegen
    module IR
        # Determine library path based on platform
        JIT_EXT_DIR = File.expand_path('ir_jit/lib', __dir__)
        JIT_LIB_NAME = case RbConfig::CONFIG['host_os']
        when /darwin/ then 'ir_jit.dylib'
        when /mswin|mingw/ then 'ir_jit.dll'
        else 'ir_jit.so'
        end
        JIT_LIB_PATH = File.join(JIT_EXT_DIR, JIT_LIB_NAME)

        # Check if JIT extension is available and functional
        JIT_AVAILABLE = begin
          if File.exist?(JIT_LIB_PATH)
            # Try to load the library and check for required symbols
            _test_lib = Fiddle.dlopen(JIT_LIB_PATH)
            _test_lib['jit_sim_create']
            _test_lib['jit_sim_get_memory_idx']
            _test_lib['jit_sim_mem_write_bytes']
            true
          else
            false
          end
        rescue Fiddle::DLError
          false
        end

        # Backwards compatibility alias
        IR_JIT_AVAILABLE = JIT_AVAILABLE

        # Wrapper class that uses Fiddle to call Rust JIT
        class IrJitWrapper
        attr_reader :ir_json, :sub_cycles

        # @param ir_json [String] JSON representation of the IR
        # @param allow_fallback [Boolean] Allow fallback to interpreter
        # @param sub_cycles [Integer] Number of sub-cycles per CPU cycle (default: 14)
        def initialize(ir_json, allow_fallback: true, sub_cycles: 14)
          @ir_json = ir_json
          @sub_cycles = sub_cycles.clamp(1, 14)

          if JIT_AVAILABLE
            load_library
            create_simulator
            @backend = :jit
          elsif allow_fallback
            require_relative 'ir_interpreter'
            @sim = IrInterpreterWrapper.new(ir_json, allow_fallback: true, sub_cycles: @sub_cycles)
            @backend = @sim.native? ? :interpret : :ruby
            @fallback = true
          else
            raise LoadError, "IR JIT library not found at: #{JIT_LIB_PATH}\nRun 'rake native:build' to build it."
          end
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          JIT_AVAILABLE && @backend == :jit
        end

        def backend
          @backend
        end

        def poke(name, value)
          return @sim.poke(name, value) if @fallback
          @fn_poke.call(@ctx, name, value)
        end

        def peek(name)
          return @sim.peek(name) if @fallback
          @fn_peek.call(@ctx, name)
        end

        def has_signal?(name)
          return @sim.has_signal?(name) if @fallback && @sim.respond_to?(:has_signal?)
          @fn_has_signal.call(@ctx, name) != 0
        end

        def evaluate
          return @sim.evaluate if @fallback
          @fn_evaluate.call(@ctx)
        end

        def tick
          return @sim.tick if @fallback
          @fn_tick.call(@ctx)
        end

        def tick_forced
          return @sim.tick if @fallback  # Ruby fallback doesn't need edge detection
          @fn_tick_forced.call(@ctx)
        end

        def set_prev_clock(clock_list_idx, value)
          return if @fallback  # Ruby fallback doesn't track prev clocks
          @fn_set_prev_clock.call(@ctx, clock_list_idx, value)
        end

        def get_clock_list_idx(signal_idx)
          return -1 if @fallback
          @fn_get_clock_list_idx.call(@ctx, signal_idx)
        end

        def reset
          return @sim.reset if @fallback
          @fn_reset.call(@ctx)
        end

        def signal_count
          return @sim.signal_count if @fallback
          @fn_signal_count.call(@ctx)
        end

        def reg_count
          return @sim.reg_count if @fallback
          @fn_reg_count.call(@ctx)
        end

        def input_names
          return @sim.input_names if @fallback
          ptr = @fn_input_names.call(@ctx)
          return [] if ptr.null?
          names = ptr.to_s.split(',')
          @fn_free_string.call(ptr)
          names
        end

        def output_names
          return @sim.output_names if @fallback
          ptr = @fn_output_names.call(@ctx)
          return [] if ptr.null?
          names = ptr.to_s.split(',')
          @fn_free_string.call(ptr)
          names
        end

        # VCD tracing methods
        def trace_start
          return @sim.trace_start if @fallback && @sim.respond_to?(:trace_start)
          return false if @fallback
          @fn_trace_start.call(@ctx) == 0
        end

        def trace_start_streaming(path)
          return @sim.trace_start_streaming(path) if @fallback && @sim.respond_to?(:trace_start_streaming)
          return false if @fallback
          @fn_trace_start_streaming.call(@ctx, path) == 0
        end

        def trace_stop
          return @sim.trace_stop if @fallback && @sim.respond_to?(:trace_stop)
          return nil if @fallback
          @fn_trace_stop.call(@ctx)
        end

        def trace_enabled?
          return @sim.trace_enabled? if @fallback && @sim.respond_to?(:trace_enabled?)
          return false if @fallback
          @fn_trace_enabled.call(@ctx) != 0
        end

        def trace_capture
          return @sim.trace_capture if @fallback && @sim.respond_to?(:trace_capture)
          return nil if @fallback
          @fn_trace_capture.call(@ctx)
        end

        def trace_add_signal(name)
          return @sim.trace_add_signal(name) if @fallback && @sim.respond_to?(:trace_add_signal)
          return false if @fallback
          @fn_trace_add_signal.call(@ctx, name) == 0
        end

        def trace_add_signals_matching(pattern)
          return @sim.trace_add_signals_matching(pattern) if @fallback && @sim.respond_to?(:trace_add_signals_matching)
          return 0 if @fallback
          @fn_trace_add_signals_matching.call(@ctx, pattern)
        end

        def trace_all_signals
          return @sim.trace_all_signals if @fallback && @sim.respond_to?(:trace_all_signals)
          return nil if @fallback
          @fn_trace_all_signals.call(@ctx)
        end

        def trace_clear_signals
          return @sim.trace_clear_signals if @fallback && @sim.respond_to?(:trace_clear_signals)
          return nil if @fallback
          @fn_trace_clear_signals.call(@ctx)
        end

        def trace_to_vcd
          return @sim.trace_to_vcd if @fallback && @sim.respond_to?(:trace_to_vcd)
          return '' if @fallback
          ptr = @fn_trace_to_vcd.call(@ctx)
          return '' if ptr.null?

          vcd = ptr.to_s
          @fn_free_string.call(ptr)
          vcd
        end

        def trace_take_live_vcd
          return @sim.trace_take_live_vcd if @fallback && @sim.respond_to?(:trace_take_live_vcd)
          return '' if @fallback
          ptr = @fn_trace_take_live_vcd.call(@ctx)
          return '' if ptr.null?

          chunk = ptr.to_s
          @fn_free_string.call(ptr)
          chunk
        end

        def trace_save_vcd(path)
          return @sim.trace_save_vcd(path) if @fallback && @sim.respond_to?(:trace_save_vcd)
          return false if @fallback
          @fn_trace_save_vcd.call(@ctx, path) == 0
        end

        def trace_clear
          return @sim.trace_clear if @fallback && @sim.respond_to?(:trace_clear)
          return nil if @fallback
          @fn_trace_clear.call(@ctx)
        end

        def trace_change_count
          return @sim.trace_change_count if @fallback && @sim.respond_to?(:trace_change_count)
          return 0 if @fallback
          @fn_trace_change_count.call(@ctx)
        end

        def trace_signal_count
          return @sim.trace_signal_count if @fallback && @sim.respond_to?(:trace_signal_count)
          return 0 if @fallback
          @fn_trace_signal_count.call(@ctx)
        end

        def trace_set_timescale(timescale)
          return @sim.trace_set_timescale(timescale) if @fallback && @sim.respond_to?(:trace_set_timescale)
          return false if @fallback
          @fn_trace_set_timescale.call(@ctx, timescale) == 0
        end

        def trace_set_module_name(name)
          return @sim.trace_set_module_name(name) if @fallback && @sim.respond_to?(:trace_set_module_name)
          return false if @fallback
          @fn_trace_set_module_name.call(@ctx, name) == 0
        end

        def stats
          return @sim.stats if @fallback
          {
            signals: signal_count,
            regs: reg_count,
            apple2_mode: apple2_mode?,
            gameboy_mode: gameboy_mode?,
            mos6502_mode: mos6502_mode?
          }
        end

        # Batched tick execution
        def run_ticks(n)
          return @sim.run_ticks(n) if @fallback && @sim.respond_to?(:run_ticks)
          return n.times { tick } if @fallback
          @fn_run_ticks.call(@ctx, n)
        end

        # Get signal index by name (for caching)
        def get_signal_idx(name)
          return @sim.get_signal_idx(name) if @fallback && @sim.respond_to?(:get_signal_idx)
          idx = @fn_get_signal_idx.call(@ctx, name)
          idx >= 0 ? idx : nil
        end

        # ====================================================================
        # Memory Extension Methods (Core memories in flattened IR)
        # ====================================================================

        def get_memory_idx(name)
          return @sim.get_memory_idx(name) if @fallback && @sim.respond_to?(:get_memory_idx)
          idx = @fn_get_memory_idx.call(@ctx, name)
          idx >= 0 ? idx : nil
        end

        # Bulk write bytes into a memory array
        # @param mem_idx [Integer]
        # @param offset [Integer]
        # @param data [Array<Integer>, String]
        def mem_write_bytes(mem_idx, offset, data)
          return @sim.mem_write_bytes(mem_idx, offset, data) if @fallback && @sim.respond_to?(:mem_write_bytes)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_mem_write_bytes.call(@ctx, mem_idx, offset, data, data.bytesize)
        end

        # Poke by index - faster than by name when index is cached
        def poke_by_idx(idx, value)
          return @sim.poke_by_idx(idx, value) if @fallback && @sim.respond_to?(:poke_by_idx)
          @fn_poke_by_idx.call(@ctx, idx, value)
        end

        # Peek by index - faster than by name when index is cached
        def peek_by_idx(idx)
          return @sim.peek_by_idx(idx) if @fallback && @sim.respond_to?(:peek_by_idx)
          @fn_peek_by_idx.call(@ctx, idx)
        end

        # ====================================================================
        # MOS6502 Extension Methods
        # ====================================================================

        def mos6502_mode?
          return @sim.mos6502_mode? if @fallback && @sim.respond_to?(:mos6502_mode?)
          @fn_is_mos6502_mode.call(@ctx) != 0
        end

        def mos6502_load_memory(data, offset, is_rom)
          return @sim.mos6502_load_memory(data, offset, is_rom) if @fallback && @sim.respond_to?(:mos6502_load_memory)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_mos6502_load_memory.call(@ctx, data, data.bytesize, offset, is_rom ? 1 : 0)
        end

        def mos6502_set_reset_vector(addr)
          return @sim.mos6502_set_reset_vector(addr) if @fallback && @sim.respond_to?(:mos6502_set_reset_vector)
          @fn_mos6502_set_reset_vector.call(@ctx, addr)
        end

        def mos6502_run_cycles(n)
          return @sim.mos6502_run_cycles(n) if @fallback && @sim.respond_to?(:mos6502_run_cycles)
          @fn_mos6502_run_cycles.call(@ctx, n)
        end

        def mos6502_read_memory(addr)
          return @sim.mos6502_read_memory(addr) if @fallback && @sim.respond_to?(:mos6502_read_memory)
          # Mask to unsigned byte (Fiddle::TYPE_CHAR is signed)
          @fn_mos6502_read_memory.call(@ctx, addr) & 0xFF
        end

        def mos6502_write_memory(addr, data)
          return @sim.mos6502_write_memory(addr, data) if @fallback && @sim.respond_to?(:mos6502_write_memory)
          @fn_mos6502_write_memory.call(@ctx, addr, data)
        end

        def mos6502_speaker_toggles
          return @sim.mos6502_speaker_toggles if @fallback && @sim.respond_to?(:mos6502_speaker_toggles)
          @fn_mos6502_speaker_toggles.call(@ctx)
        end

        def mos6502_reset_speaker_toggles
          return @sim.mos6502_reset_speaker_toggles if @fallback && @sim.respond_to?(:mos6502_reset_speaker_toggles)
          @fn_mos6502_reset_speaker_toggles.call(@ctx)
        end

        # Run N instructions and return array of [pc, opcode, sp] tuples
        # Uses Rust-native instruction stepping for accurate state tracking
        def mos6502_run_instructions_with_opcodes(n)
          if @fallback && @sim.respond_to?(:mos6502_run_instructions_with_opcodes)
            return @sim.mos6502_run_instructions_with_opcodes(n)
          end

          # Allocate buffer for packed results (each is u64: pc<<16 | opcode<<8 | sp)
          buf = Fiddle::Pointer.malloc(n * 8)  # 8 bytes per u64
          count = @fn_mos6502_run_instructions_with_opcodes.call(@ctx, n, buf, n)

          # Unpack results
          packed = buf[0, count * 8].unpack('Q*')
          packed.map do |v|
            pc = (v >> 16) & 0xFFFF
            opcode = (v >> 8) & 0xFF
            sp = v & 0xFF
            [pc, opcode, sp]
          end
        end

        # ====================================================================
        # Apple II Extension Methods
        # ====================================================================

        def apple2_mode?
          return @sim.apple2_mode? if @fallback && @sim.respond_to?(:apple2_mode?)
          @fn_is_apple2_mode.call(@ctx) != 0
        end

        def apple2_load_rom(data)
          return @sim.apple2_load_rom(data) if @fallback && @sim.respond_to?(:apple2_load_rom)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_apple2_load_rom.call(@ctx, data, data.bytesize)
        end

        def apple2_load_ram(data, offset)
          return @sim.apple2_load_ram(data, offset) if @fallback && @sim.respond_to?(:apple2_load_ram)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_apple2_load_ram.call(@ctx, data, data.bytesize, offset)
        end

        def apple2_run_cpu_cycles(n, key_data, key_ready)
          if @fallback && @sim.respond_to?(:apple2_run_cpu_cycles)
            return @sim.apple2_run_cpu_cycles(n, key_data, key_ready)
          end

          # Result struct: text_dirty (int), key_cleared (int), cycles_run (uint), speaker_toggles (uint)
          result_buf = Fiddle::Pointer.malloc(16)  # 4 x 4 bytes
          @fn_apple2_run_cpu_cycles.call(@ctx, n, key_data, key_ready ? 1 : 0, result_buf)

          values = result_buf[0, 16].unpack('llLL')
          {
            text_dirty: values[0] != 0,
            key_cleared: values[1] != 0,
            cycles_run: values[2],
            speaker_toggles: values[3]
          }
        end

        def apple2_read_ram(offset, length)
          if @fallback && @sim.respond_to?(:apple2_read_ram)
            return @sim.apple2_read_ram(offset, length)
          end
          buf = Fiddle::Pointer.malloc(length)
          actual_len = @fn_apple2_read_ram.call(@ctx, offset, buf, length)
          buf[0, actual_len].unpack('C*')
        end

        def apple2_write_ram(offset, data)
          return @sim.apple2_write_ram(offset, data) if @fallback && @sim.respond_to?(:apple2_write_ram)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_apple2_write_ram.call(@ctx, offset, data, data.bytesize)
        end

        # ====================================================================
        # Game Boy Extension Methods
        # ====================================================================

        def gameboy_mode?
          return @sim.gameboy_mode? if @fallback && @sim.respond_to?(:gameboy_mode?)
          return false unless @gameboy_available
          @fn_is_gameboy_mode.call(@ctx) != 0
        end

        def load_rom(data)
          return @sim.load_rom(data) if @fallback && @sim.respond_to?(:load_rom)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_gameboy_load_rom.call(@ctx, data, data.bytesize)
        end

        def load_boot_rom(data)
          return @sim.load_boot_rom(data) if @fallback && @sim.respond_to?(:load_boot_rom)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_gameboy_load_boot_rom.call(@ctx, data, data.bytesize)
        end

        def run_gb_cycles(n)
          return @sim.run_gb_cycles(n) if @fallback && @sim.respond_to?(:run_gb_cycles)
          # Result struct: cycles_run (usize), frames_completed (u32)
          result_buf = Fiddle::Pointer.malloc(16)  # usize + u32 with padding
          @fn_gameboy_run_cycles_full.call(@ctx, n, result_buf)

          # Unpack: usize (8 bytes on 64-bit) + u32 (4 bytes)
          values = result_buf[0, 16].unpack('QL')
          {
            cycles_run: values[0],
            frames_completed: values[1]
          }
        end

        def read_vram(addr)
          return @sim.read_vram(addr) if @fallback && @sim.respond_to?(:read_vram)
          @fn_gameboy_read_vram.call(@ctx, addr) & 0xFF
        end

        def write_vram(addr, data)
          return @sim.write_vram(addr, data) if @fallback && @sim.respond_to?(:write_vram)
          @fn_gameboy_write_vram.call(@ctx, addr, data)
        end

        def read_zpram(addr)
          return @sim.read_zpram(addr) if @fallback && @sim.respond_to?(:read_zpram)
          @fn_gameboy_read_zpram.call(@ctx, addr) & 0xFF
        end

        def write_zpram(addr, data)
          return @sim.write_zpram(addr, data) if @fallback && @sim.respond_to?(:write_zpram)
          @fn_gameboy_write_zpram.call(@ctx, addr, data)
        end

        def read_framebuffer
          return @sim.read_framebuffer if @fallback && @sim.respond_to?(:read_framebuffer)
          len = @fn_gameboy_framebuffer_len.call(@ctx)
          return [] if len == 0

          ptr = @fn_gameboy_framebuffer.call(@ctx)
          return [] if ptr.null?

          # Read the framebuffer data
          Fiddle::Pointer.new(ptr)[0, len].unpack('C*')
        end

        def frame_count
          return @sim.frame_count if @fallback && @sim.respond_to?(:frame_count)
          @fn_gameboy_frame_count.call(@ctx)
        end

        def reset_lcd_state
          return @sim.reset_lcd_state if @fallback && @sim.respond_to?(:reset_lcd_state)
          @fn_gameboy_reset_lcd.call(@ctx)
        end

        # Debug methods for PPU/interrupt signals
        def get_v_cnt
          return @sim.get_v_cnt if @fallback && @sim.respond_to?(:get_v_cnt)
          @fn_gameboy_get_v_cnt.call(@ctx)
        end

        def get_h_cnt
          return @sim.get_h_cnt if @fallback && @sim.respond_to?(:get_h_cnt)
          @fn_gameboy_get_h_cnt.call(@ctx)
        end

        def get_vblank_irq
          return @sim.get_vblank_irq if @fallback && @sim.respond_to?(:get_vblank_irq)
          @fn_gameboy_get_vblank_irq.call(@ctx)
        end

        def get_if_r
          return @sim.get_if_r if @fallback && @sim.respond_to?(:get_if_r)
          @fn_gameboy_get_if_r.call(@ctx)
        end

        def get_signal(idx)
          return @sim.get_signal(idx) if @fallback && @sim.respond_to?(:get_signal)
          @fn_gameboy_get_signal.call(@ctx, idx)
        end

        def get_lcdc_on
          return @sim.get_lcdc_on if @fallback && @sim.respond_to?(:get_lcdc_on)
          @fn_gameboy_get_lcdc_on.call(@ctx)
        end

        def get_h_div_cnt
          return @sim.get_h_div_cnt if @fallback && @sim.respond_to?(:get_h_div_cnt)
          @fn_gameboy_get_h_div_cnt.call(@ctx)
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

        def load_library
          @lib = Fiddle.dlopen(JIT_LIB_PATH)

          # Core functions
          @fn_create = Fiddle::Function.new(
            @lib['jit_sim_create'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_destroy = Fiddle::Function.new(
            @lib['jit_sim_destroy'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_free_error = Fiddle::Function.new(
            @lib['jit_sim_free_error'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_free_string = Fiddle::Function.new(
            @lib['jit_sim_free_string'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_poke = Fiddle::Function.new(
            @lib['jit_sim_poke'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_INT
          )

          @fn_peek = Fiddle::Function.new(
            @lib['jit_sim_peek'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_ULONG
          )

          @fn_has_signal = Fiddle::Function.new(
            @lib['jit_sim_has_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_get_signal_idx = Fiddle::Function.new(
            @lib['jit_sim_get_signal_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_get_memory_idx = Fiddle::Function.new(
            @lib['jit_sim_get_memory_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mem_write_bytes = Fiddle::Function.new(
            @lib['jit_sim_mem_write_bytes'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_poke_by_idx = Fiddle::Function.new(
            @lib['jit_sim_poke_by_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_VOID
          )

          @fn_peek_by_idx = Fiddle::Function.new(
            @lib['jit_sim_peek_by_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_ULONG
          )

          @fn_evaluate = Fiddle::Function.new(
            @lib['jit_sim_evaluate'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_tick = Fiddle::Function.new(
            @lib['jit_sim_tick'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_tick_forced = Fiddle::Function.new(
            @lib['jit_sim_tick_forced'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_set_prev_clock = Fiddle::Function.new(
            @lib['jit_sim_set_prev_clock'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_VOID
          )

          @fn_get_clock_list_idx = Fiddle::Function.new(
            @lib['jit_sim_get_clock_list_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_run_ticks = Fiddle::Function.new(
            @lib['jit_sim_run_ticks'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_reset = Fiddle::Function.new(
            @lib['jit_sim_reset'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_signal_count = Fiddle::Function.new(
            @lib['jit_sim_signal_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_reg_count = Fiddle::Function.new(
            @lib['jit_sim_reg_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_input_names = Fiddle::Function.new(
            @lib['jit_sim_input_names'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_output_names = Fiddle::Function.new(
            @lib['jit_sim_output_names'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          # VCD trace functions
          @fn_trace_start = Fiddle::Function.new(
            @lib['jit_sim_trace_start'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_start_streaming = Fiddle::Function.new(
            @lib['jit_sim_trace_start_streaming'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_stop = Fiddle::Function.new(
            @lib['jit_sim_trace_stop'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_enabled = Fiddle::Function.new(
            @lib['jit_sim_trace_enabled'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_capture = Fiddle::Function.new(
            @lib['jit_sim_trace_capture'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_add_signal = Fiddle::Function.new(
            @lib['jit_sim_trace_add_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_add_signals_matching = Fiddle::Function.new(
            @lib['jit_sim_trace_add_signals_matching'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_all_signals = Fiddle::Function.new(
            @lib['jit_sim_trace_all_signals'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_clear_signals = Fiddle::Function.new(
            @lib['jit_sim_trace_clear_signals'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_to_vcd = Fiddle::Function.new(
            @lib['jit_sim_trace_to_vcd'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_trace_take_live_vcd = Fiddle::Function.new(
            @lib['jit_sim_trace_take_live_vcd'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_trace_save_vcd = Fiddle::Function.new(
            @lib['jit_sim_trace_save_vcd'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_clear = Fiddle::Function.new(
            @lib['jit_sim_trace_clear'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_change_count = Fiddle::Function.new(
            @lib['jit_sim_trace_change_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_LONG_LONG
          )

          @fn_trace_signal_count = Fiddle::Function.new(
            @lib['jit_sim_trace_signal_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_set_timescale = Fiddle::Function.new(
            @lib['jit_sim_trace_set_timescale'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_set_module_name = Fiddle::Function.new(
            @lib['jit_sim_trace_set_module_name'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          # MOS6502 extension functions
          @fn_is_mos6502_mode = Fiddle::Function.new(
            @lib['mos6502_jit_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_load_memory = Fiddle::Function.new(
            @lib['mos6502_jit_sim_load_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_set_reset_vector = Fiddle::Function.new(
            @lib['mos6502_jit_sim_set_reset_vector'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_run_cycles = Fiddle::Function.new(
            @lib['mos6502_jit_sim_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_read_memory = Fiddle::Function.new(
            @lib['mos6502_jit_sim_read_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_mos6502_write_memory = Fiddle::Function.new(
            @lib['mos6502_jit_sim_write_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_speaker_toggles = Fiddle::Function.new(
            @lib['mos6502_jit_sim_speaker_toggles'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_reset_speaker_toggles = Fiddle::Function.new(
            @lib['mos6502_jit_sim_reset_speaker_toggles'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_run_instructions_with_opcodes = Fiddle::Function.new(
            @lib['mos6502_jit_sim_run_instructions_with_opcodes'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          # Apple II extension functions
          @fn_is_apple2_mode = Fiddle::Function.new(
            @lib['apple2_jit_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_apple2_load_rom = Fiddle::Function.new(
            @lib['apple2_jit_sim_load_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_load_ram = Fiddle::Function.new(
            @lib['apple2_jit_sim_load_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_run_cpu_cycles = Fiddle::Function.new(
            @lib['apple2_jit_sim_run_cpu_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_read_ram = Fiddle::Function.new(
            @lib['apple2_jit_sim_read_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_SIZE_T
          )

          @fn_apple2_write_ram = Fiddle::Function.new(
            @lib['apple2_jit_sim_write_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          # Game Boy extension functions (optional - may not be built into library)
          begin
            @fn_is_gameboy_mode = Fiddle::Function.new(
              @lib['gameboy_jit_sim_is_mode'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_INT
            )

            @fn_gameboy_load_rom = Fiddle::Function.new(
              @lib['gameboy_jit_sim_load_rom'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
              Fiddle::TYPE_VOID
            )

            @fn_gameboy_load_boot_rom = Fiddle::Function.new(
              @lib['gameboy_jit_sim_load_boot_rom'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
              Fiddle::TYPE_VOID
            )

            @fn_gameboy_run_cycles = Fiddle::Function.new(
              @lib['gameboy_jit_sim_run_cycles'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
              Fiddle::TYPE_INT
            )

            @fn_gameboy_run_cycles_full = Fiddle::Function.new(
              @lib['gameboy_jit_sim_run_cycles_full'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOID
            )

            @fn_gameboy_read_vram = Fiddle::Function.new(
              @lib['gameboy_jit_sim_read_vram'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
              Fiddle::TYPE_CHAR
            )

            @fn_gameboy_write_vram = Fiddle::Function.new(
              @lib['gameboy_jit_sim_write_vram'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
              Fiddle::TYPE_VOID
            )

            @fn_gameboy_read_zpram = Fiddle::Function.new(
              @lib['gameboy_jit_sim_read_zpram'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
              Fiddle::TYPE_CHAR
            )

            @fn_gameboy_write_zpram = Fiddle::Function.new(
              @lib['gameboy_jit_sim_write_zpram'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
              Fiddle::TYPE_VOID
            )

            @fn_gameboy_framebuffer = Fiddle::Function.new(
              @lib['gameboy_jit_sim_framebuffer'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOIDP
            )

            @fn_gameboy_framebuffer_len = Fiddle::Function.new(
              @lib['gameboy_jit_sim_framebuffer_len'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_SIZE_T
            )

            @fn_gameboy_frame_count = Fiddle::Function.new(
              @lib['gameboy_jit_sim_frame_count'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_ULONG
            )

            @fn_gameboy_reset_lcd = Fiddle::Function.new(
              @lib['gameboy_jit_sim_reset_lcd'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOID
            )

            @fn_gameboy_get_v_cnt = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_v_cnt'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )

            @fn_gameboy_get_h_cnt = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_h_cnt'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )

            @fn_gameboy_get_vblank_irq = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_vblank_irq'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )

            @fn_gameboy_get_if_r = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_if_r'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )

            @fn_gameboy_get_signal = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_signal'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_LONG_LONG
            )

            @fn_gameboy_get_lcdc_on = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_lcdc_on'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )

            @fn_gameboy_get_h_div_cnt = Fiddle::Function.new(
              @lib['gameboy_jit_sim_get_h_div_cnt'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )

            @gameboy_available = true
          rescue Fiddle::DLError
            # Game Boy functions not available in this library build
            @gameboy_available = false
          end
        end

        def create_simulator
          error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          error_ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack('Q')  # Initialize to null

          @ctx = @fn_create.call(@ir_json, @ir_json.bytesize, @sub_cycles, error_ptr)

          if @ctx.null?
            error_str_ptr = error_ptr[0, Fiddle::SIZEOF_VOIDP].unpack1('Q')
            if error_str_ptr != 0
              error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
              @fn_free_error.call(error_str_ptr)
              raise RuntimeError, "Failed to create JIT simulator: #{error_msg}"
            end
            raise RuntimeError, "Failed to create JIT simulator"
          end

          # Set up destructor for cleanup
          @destructor = @fn_destroy
        end
      end  # class IrJitWrapper

      # Backwards compatibility alias
      RtlJitWrapper = IrJitWrapper
    end  # module IR
  end  # module Codegen
end  # module RHDL
