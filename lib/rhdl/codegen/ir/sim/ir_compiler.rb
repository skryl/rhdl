# frozen_string_literal: true

# IR Compiler with Rust backend (Fiddle-based)
#
# This simulator generates specialized Rust code for the circuit and compiles
# it at runtime for maximum simulation performance. Unlike the interpreter,
# this approach eliminates all interpretation overhead.
#
# Uses Fiddle (Ruby's built-in FFI) to call the Rust library directly,
# similar to the Verilator runners.

require 'json'
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'
require_relative 'ir_interpreter'  # For IRToJson module

module RHDL
  module Codegen
    module IR
        # Determine library path based on platform
        COMPILER_EXT_DIR = File.expand_path('ir_compiler/lib', __dir__)
        COMPILER_LIB_NAME = case RbConfig::CONFIG['host_os']
        when /darwin/ then 'ir_compiler.dylib'
        when /mswin|mingw/ then 'ir_compiler.dll'
        else 'ir_compiler.so'
        end
        COMPILER_LIB_PATH = File.join(COMPILER_EXT_DIR, COMPILER_LIB_NAME)

        # Check if compiler extension is available and functional
        COMPILER_AVAILABLE = begin
          if File.exist?(COMPILER_LIB_PATH)
            # Try to load the library and check for required symbols
            _test_lib = Fiddle.dlopen(COMPILER_LIB_PATH)
            _test_lib['ir_sim_create']
            _test_lib['ir_sim_compile']
            true
          else
            false
          end
        rescue Fiddle::DLError
          false
        end

        # Backwards compatibility alias
        IR_COMPILER_AVAILABLE = COMPILER_AVAILABLE

        # Wrapper class that uses Fiddle to call Rust IR Compiler
        class IrCompilerWrapper
        attr_reader :ir_json, :sub_cycles

        # @param ir_json [String] JSON representation of the IR
        # @param allow_fallback [Boolean] Allow fallback to interpreter if compiler unavailable
        # @param sub_cycles [Integer] Number of sub-cycles per CPU cycle (default: 14)
        def initialize(ir_json, allow_fallback: true, sub_cycles: 14)
          @ir_json = ir_json
          @sub_cycles = sub_cycles.clamp(1, 14)

          if COMPILER_AVAILABLE
            load_library
            create_simulator
            # Auto-compile for performance
            compile
            @backend = :compile
          elsif allow_fallback
            require_relative 'ir_interpreter'
            @sim = IrInterpreterWrapper.new(ir_json, allow_fallback: true, sub_cycles: @sub_cycles)
            @backend = @sim.native? ? :interpret : :ruby
            @fallback = true
          else
            raise LoadError, "IR Compiler library not found at: #{COMPILER_LIB_PATH}\nRun 'rake native:build' to build it."
          end
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          COMPILER_AVAILABLE && @backend == :compile
        end

        def backend
          @backend
        end

        def compiled?
          return false if @fallback
          @fn_is_compiled.call(@ctx) != 0
        end

        def compile
          return true if @fallback  # No-op for fallback
          error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          result = @fn_compile.call(@ctx, error_ptr)
          if result < 0
            error_str_ptr = error_ptr[0, Fiddle::SIZEOF_VOIDP].unpack1('Q')
            if error_str_ptr != 0
              error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
              @fn_free_error.call(error_str_ptr)
              raise RuntimeError, "Compilation failed: #{error_msg}"
            end
            raise RuntimeError, "Compilation failed"
          end
          result == 1  # true if cached
        end

        def generated_code
          return "" if @fallback
          ptr = @fn_generated_code.call(@ctx)
          return "" if ptr.null?
          code = ptr.to_s
          @fn_free_string.call(ptr)
          code
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

        def stats
          return @sim.stats if @fallback
          {
            signals: signal_count,
            regs: reg_count,
            compiled: compiled?,
            apple2_mode: apple2_mode?,
            mos6502_mode: mos6502_mode?,
            gameboy_mode: gameboy_mode?
          }
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
          return false unless @gameboy_available
          @fn_is_gameboy_mode.call(@ctx) != 0
        end

        def load_rom(data)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_gameboy_load_rom.call(@ctx, data, data.bytesize)
        end

        def load_boot_rom(data)
          data = data.pack('C*') if data.is_a?(Array)
          @fn_gameboy_load_boot_rom.call(@ctx, data, data.bytesize)
        end

        def run_gb_cycles(n)
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
          @fn_gameboy_read_vram.call(@ctx, addr) & 0xFF
        end

        def write_vram(addr, data)
          @fn_gameboy_write_vram.call(@ctx, addr, data)
        end

        def read_zpram(addr)
          @fn_gameboy_read_zpram.call(@ctx, addr) & 0xFF
        end

        def write_zpram(addr, data)
          @fn_gameboy_write_zpram.call(@ctx, addr, data)
        end

        def read_wram(addr)
          @fn_gameboy_read_wram.call(@ctx, addr) & 0xFF
        end

        def write_wram(addr, data)
          @fn_gameboy_write_wram.call(@ctx, addr, data)
        end

        def read_framebuffer
          len = @fn_gameboy_framebuffer_len.call(@ctx)
          return [] if len == 0

          ptr = @fn_gameboy_framebuffer.call(@ctx)
          return [] if ptr.null?

          # Read the framebuffer data
          Fiddle::Pointer.new(ptr)[0, len].unpack('C*')
        end

        def frame_count
          @fn_gameboy_frame_count.call(@ctx)
        end

        def reset_lcd_state
          @fn_gameboy_reset_lcd.call(@ctx)
        end

        # Debug methods for PPU/interrupt signals
        def get_v_cnt
          @fn_gameboy_get_v_cnt.call(@ctx)
        end

        def get_h_cnt
          @fn_gameboy_get_h_cnt.call(@ctx)
        end

        def get_vblank_irq
          @fn_gameboy_get_vblank_irq.call(@ctx)
        end

        def get_if_r
          @fn_gameboy_get_if_r.call(@ctx)
        end

        def get_signal(idx)
          @fn_gameboy_get_signal.call(@ctx, idx)
        end

        def get_lcdc_on
          @fn_gameboy_get_lcdc_on.call(@ctx)
        end

        def get_h_div_cnt
          @fn_gameboy_get_h_div_cnt.call(@ctx)
        end

        # ====================================================================
        # VCD Tracing Methods
        # ====================================================================

        # Start VCD tracing in buffer mode (accumulate in memory)
        # @return [Boolean] true on success
        def trace_start
          return false if @fallback
          @fn_trace_start.call(@ctx) == 0
        end

        # Start VCD tracing in streaming mode (write directly to file)
        # @param path [String] Path to the VCD file
        # @return [Boolean] true on success
        def trace_start_streaming(path)
          return false if @fallback
          @fn_trace_start_streaming.call(@ctx, path) == 0
        end

        # Stop VCD tracing
        def trace_stop
          return if @fallback
          @fn_trace_stop.call(@ctx)
        end

        # Check if tracing is enabled
        # @return [Boolean]
        def trace_enabled?
          return false if @fallback
          @fn_trace_enabled.call(@ctx) != 0
        end

        # Capture current signal values (call each simulation step)
        def trace_capture
          return if @fallback
          @fn_trace_capture.call(@ctx)
        end

        # Add a signal to trace by name
        # @param name [String] Signal name
        # @return [Boolean] true if signal found and added
        def trace_add_signal(name)
          return false if @fallback
          @fn_trace_add_signal.call(@ctx, name) == 0
        end

        # Add signals matching a pattern (substring match)
        # @param pattern [String] Pattern to match
        # @return [Integer] Number of signals added
        def trace_add_signals_matching(pattern)
          return 0 if @fallback
          @fn_trace_add_signals_matching.call(@ctx, pattern)
        end

        # Trace all signals
        def trace_all_signals
          return if @fallback
          @fn_trace_all_signals.call(@ctx)
        end

        # Clear the set of traced signals
        def trace_clear_signals
          return if @fallback
          @fn_trace_clear_signals.call(@ctx)
        end

        # Get VCD output as string
        # @return [String] VCD formatted output
        def trace_to_vcd
          return "" if @fallback
          ptr = @fn_trace_to_vcd.call(@ctx)
          return "" if ptr.null?
          vcd = ptr.to_s
          @fn_free_string.call(ptr)
          vcd
        end

        # Save VCD output to a file
        # @param path [String] Path to save the VCD file
        # @return [Boolean] true on success
        def trace_save_vcd(path)
          return false if @fallback
          @fn_trace_save_vcd.call(@ctx, path) == 0
        end

        # Clear all buffered trace data
        def trace_clear
          return if @fallback
          @fn_trace_clear.call(@ctx)
        end

        # Get the number of recorded changes
        # @return [Integer]
        def trace_change_count
          return 0 if @fallback
          @fn_trace_change_count.call(@ctx)
        end

        # Get the number of traced signals
        # @return [Integer]
        def trace_signal_count
          return 0 if @fallback
          @fn_trace_signal_count.call(@ctx)
        end

        # Set the VCD timescale (e.g., "1ns", "1ps")
        # @param timescale [String]
        # @return [Boolean] true on success
        def trace_set_timescale(timescale)
          return false if @fallback
          @fn_trace_set_timescale.call(@ctx, timescale) == 0
        end

        # Set the VCD module name
        # @param name [String]
        # @return [Boolean] true on success
        def trace_set_module_name(name)
          return false if @fallback
          @fn_trace_set_module_name.call(@ctx, name) == 0
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
          @lib = Fiddle.dlopen(COMPILER_LIB_PATH)

          # Core functions
          @fn_create = Fiddle::Function.new(
            @lib['ir_sim_create'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_destroy = Fiddle::Function.new(
            @lib['ir_sim_destroy'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_free_error = Fiddle::Function.new(
            @lib['ir_sim_free_error'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_compile = Fiddle::Function.new(
            @lib['ir_sim_compile'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_is_compiled = Fiddle::Function.new(
            @lib['ir_sim_is_compiled'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_generated_code = Fiddle::Function.new(
            @lib['ir_sim_generated_code'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_free_string = Fiddle::Function.new(
            @lib['ir_sim_free_string'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_poke = Fiddle::Function.new(
            @lib['ir_sim_poke'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_INT
          )

          @fn_peek = Fiddle::Function.new(
            @lib['ir_sim_peek'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_ULONG
          )

          @fn_has_signal = Fiddle::Function.new(
            @lib['ir_sim_has_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_evaluate = Fiddle::Function.new(
            @lib['ir_sim_evaluate'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_tick = Fiddle::Function.new(
            @lib['ir_sim_tick'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_reset = Fiddle::Function.new(
            @lib['ir_sim_reset'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_signal_count = Fiddle::Function.new(
            @lib['ir_sim_signal_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_reg_count = Fiddle::Function.new(
            @lib['ir_sim_reg_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_input_names = Fiddle::Function.new(
            @lib['ir_sim_input_names'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_output_names = Fiddle::Function.new(
            @lib['ir_sim_output_names'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          # MOS6502 extension functions
          @fn_is_mos6502_mode = Fiddle::Function.new(
            @lib['mos6502_ir_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_load_memory = Fiddle::Function.new(
            @lib['mos6502_ir_sim_load_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_set_reset_vector = Fiddle::Function.new(
            @lib['mos6502_ir_sim_set_reset_vector'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_run_cycles = Fiddle::Function.new(
            @lib['mos6502_ir_sim_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_read_memory = Fiddle::Function.new(
            @lib['mos6502_ir_sim_read_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_mos6502_write_memory = Fiddle::Function.new(
            @lib['mos6502_ir_sim_write_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_speaker_toggles = Fiddle::Function.new(
            @lib['mos6502_ir_sim_speaker_toggles'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_reset_speaker_toggles = Fiddle::Function.new(
            @lib['mos6502_ir_sim_reset_speaker_toggles'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_run_instructions_with_opcodes = Fiddle::Function.new(
            @lib['mos6502_ir_sim_run_instructions_with_opcodes'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          # Apple II extension functions
          @fn_is_apple2_mode = Fiddle::Function.new(
            @lib['apple2_ir_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_apple2_load_rom = Fiddle::Function.new(
            @lib['apple2_ir_sim_load_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_load_ram = Fiddle::Function.new(
            @lib['apple2_ir_sim_load_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_run_cpu_cycles = Fiddle::Function.new(
            @lib['apple2_ir_sim_run_cpu_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_read_ram = Fiddle::Function.new(
            @lib['apple2_ir_sim_read_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_SIZE_T
          )

          @fn_apple2_write_ram = Fiddle::Function.new(
            @lib['apple2_ir_sim_write_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          # Game Boy extension functions (optional - may not be built into library)
          begin
            @fn_is_gameboy_mode = Fiddle::Function.new(
              @lib['gameboy_ir_sim_is_mode'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_INT
            )

          @fn_gameboy_load_rom = Fiddle::Function.new(
            @lib['gameboy_ir_sim_load_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_load_boot_rom = Fiddle::Function.new(
            @lib['gameboy_ir_sim_load_boot_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_run_cycles = Fiddle::Function.new(
            @lib['gameboy_ir_sim_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_gameboy_run_cycles_full = Fiddle::Function.new(
            @lib['gameboy_ir_sim_run_cycles_full'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_read_vram = Fiddle::Function.new(
            @lib['gameboy_ir_sim_read_vram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_gameboy_write_vram = Fiddle::Function.new(
            @lib['gameboy_ir_sim_write_vram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_read_zpram = Fiddle::Function.new(
            @lib['gameboy_ir_sim_read_zpram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_gameboy_write_zpram = Fiddle::Function.new(
            @lib['gameboy_ir_sim_write_zpram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_read_wram = Fiddle::Function.new(
            @lib['gameboy_ir_sim_read_wram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_gameboy_write_wram = Fiddle::Function.new(
            @lib['gameboy_ir_sim_write_wram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_framebuffer = Fiddle::Function.new(
            @lib['gameboy_ir_sim_framebuffer'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_gameboy_framebuffer_len = Fiddle::Function.new(
            @lib['gameboy_ir_sim_framebuffer_len'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_SIZE_T
          )

          @fn_gameboy_frame_count = Fiddle::Function.new(
            @lib['gameboy_ir_sim_frame_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_ULONG
          )

          @fn_gameboy_reset_lcd = Fiddle::Function.new(
            @lib['gameboy_ir_sim_reset_lcd'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_get_v_cnt = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_v_cnt'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_h_cnt = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_h_cnt'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_vblank_irq = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_vblank_irq'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_if_r = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_if_r'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_signal = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_LONG_LONG
          )

          @fn_gameboy_get_lcdc_on = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_lcdc_on'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_h_div_cnt = Fiddle::Function.new(
            @lib['gameboy_ir_sim_get_h_div_cnt'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

            @gameboy_available = true
          rescue Fiddle::DLError
            # Game Boy functions not available in this library build
            @gameboy_available = false
          end

          # VCD Tracing functions
          @fn_trace_start = Fiddle::Function.new(
            @lib['ir_sim_trace_start'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_start_streaming = Fiddle::Function.new(
            @lib['ir_sim_trace_start_streaming'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_stop = Fiddle::Function.new(
            @lib['ir_sim_trace_stop'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_enabled = Fiddle::Function.new(
            @lib['ir_sim_trace_enabled'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_capture = Fiddle::Function.new(
            @lib['ir_sim_trace_capture'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_add_signal = Fiddle::Function.new(
            @lib['ir_sim_trace_add_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_add_signals_matching = Fiddle::Function.new(
            @lib['ir_sim_trace_add_signals_matching'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_all_signals = Fiddle::Function.new(
            @lib['ir_sim_trace_all_signals'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_clear_signals = Fiddle::Function.new(
            @lib['ir_sim_trace_clear_signals'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_to_vcd = Fiddle::Function.new(
            @lib['ir_sim_trace_to_vcd'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_trace_save_vcd = Fiddle::Function.new(
            @lib['ir_sim_trace_save_vcd'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_clear = Fiddle::Function.new(
            @lib['ir_sim_trace_clear'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_trace_change_count = Fiddle::Function.new(
            @lib['ir_sim_trace_change_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_ULONG
          )

          @fn_trace_signal_count = Fiddle::Function.new(
            @lib['ir_sim_trace_signal_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_set_timescale = Fiddle::Function.new(
            @lib['ir_sim_trace_set_timescale'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_trace_set_module_name = Fiddle::Function.new(
            @lib['ir_sim_trace_set_module_name'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
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
              raise RuntimeError, "Failed to create IR simulator: #{error_msg}"
            end
            raise RuntimeError, "Failed to create IR simulator"
          end

          # Set up destructor for cleanup (called explicitly or on GC)
          @destructor = @fn_destroy
        end
      end  # class IrCompilerWrapper

      # Backwards compatibility alias
      RtlCompilerWrapper = IrCompilerWrapper
    end  # module IR
  end  # module Codegen
end  # module RHDL
