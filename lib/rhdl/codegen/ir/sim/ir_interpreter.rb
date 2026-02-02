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
      # Determine library path based on platform
      IR_INTERPRETER_EXT_DIR = File.expand_path('ir_interpreter/lib', __dir__)
      IR_INTERPRETER_LIB_NAME = case RbConfig::CONFIG['host_os']
      when /darwin/ then 'ir_interpreter.dylib'
      when /mswin|mingw/ then 'ir_interpreter.dll'
      else 'ir_interpreter.so'
      end
      IR_INTERPRETER_LIB_PATH = File.join(IR_INTERPRETER_EXT_DIR, IR_INTERPRETER_LIB_NAME)

      # Check if interpreter extension is available and functional
      # We need to verify the library can be loaded and has required symbols
      IR_INTERPRETER_AVAILABLE = begin
        if File.exist?(IR_INTERPRETER_LIB_PATH)
          # Try to load the library and check for required symbols
          _test_lib = Fiddle.dlopen(IR_INTERPRETER_LIB_PATH)
          # Check for core symbols to verify the library is valid and up-to-date
          _test_lib['ir_sim_create']
          _test_lib['ir_sim_poke_by_idx']
          _test_lib['ir_sim_peek_by_idx']
          true
        else
          false
        end
      rescue Fiddle::DLError
        false
      end

      # Backwards compatibility alias
      RTL_INTERPRETER_AVAILABLE = IR_INTERPRETER_AVAILABLE

      # Wrapper class that uses Fiddle to call Rust interpreter
      class IrInterpreterWrapper
        attr_reader :ir_json, :sub_cycles

        # @param ir_json [String] JSON representation of the IR
        # @param allow_fallback [Boolean] Allow fallback to Ruby implementation
        # @param sub_cycles [Integer] Number of sub-cycles per CPU cycle (default: 14)
        def initialize(ir_json, allow_fallback: true, sub_cycles: 14)
          @ir_json = ir_json
          @sub_cycles = sub_cycles.clamp(1, 14)

          if IR_INTERPRETER_AVAILABLE
            load_library
            create_simulator
            @backend = :interpret
          elsif allow_fallback
            @sim = RubyIrSim.new(ir_json)
            @backend = :ruby
            @fallback = true
          else
            raise LoadError, "IR interpreter extension not found at: #{IR_INTERPRETER_LIB_PATH}\nRun 'rake native:build' to build it."
          end
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          IR_INTERPRETER_AVAILABLE && @backend == :interpret
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
          return @sim.respond_to?(:has_signal?) && @sim.has_signal?(name) if @fallback
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
          return @sim.respond_to?(:run_ticks) ? @sim.run_ticks(n) : n.times { @sim.tick } if @fallback
          @fn_run_ticks.call(@ctx, n)
        end

        # Get signal index by name (for caching)
        def get_signal_idx(name)
          return @sim.respond_to?(:get_signal_idx) ? @sim.get_signal_idx(name) : nil if @fallback
          idx = @fn_get_signal_idx.call(@ctx, name)
          idx >= 0 ? idx : nil
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
          return false if @fallback
          @fn_is_mos6502_mode.call(@ctx) != 0
        end

        def mos6502_load_memory(data, offset, is_rom = false)
          return @sim.mos6502_load_memory(data, offset, is_rom) if @fallback && @sim.respond_to?(:mos6502_load_memory)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          @fn_mos6502_load_memory.call(@ctx, data, data.bytesize, offset, is_rom ? 1 : 0)
        end

        def mos6502_set_reset_vector(addr)
          return @sim.mos6502_set_reset_vector(addr) if @fallback && @sim.respond_to?(:mos6502_set_reset_vector)
          return if @fallback
          @fn_mos6502_set_reset_vector.call(@ctx, addr)
        end

        def mos6502_run_cycles(n)
          return @sim.mos6502_run_cycles(n) if @fallback && @sim.respond_to?(:mos6502_run_cycles)
          return 0 if @fallback
          @fn_mos6502_run_cycles.call(@ctx, n)
        end

        def mos6502_read_memory(addr)
          return @sim.mos6502_read_memory(addr) if @fallback && @sim.respond_to?(:mos6502_read_memory)
          return 0 if @fallback
          @fn_mos6502_read_memory.call(@ctx, addr) & 0xFF
        end

        def mos6502_write_memory(addr, data)
          return @sim.mos6502_write_memory(addr, data) if @fallback && @sim.respond_to?(:mos6502_write_memory)
          return if @fallback
          @fn_mos6502_write_memory.call(@ctx, addr, data)
        end

        def mos6502_speaker_toggles
          return @sim.mos6502_speaker_toggles if @fallback && @sim.respond_to?(:mos6502_speaker_toggles)
          return 0 if @fallback
          @fn_mos6502_speaker_toggles.call(@ctx)
        end

        def mos6502_reset_speaker_toggles
          return @sim.mos6502_reset_speaker_toggles if @fallback && @sim.respond_to?(:mos6502_reset_speaker_toggles)
          return if @fallback
          @fn_mos6502_reset_speaker_toggles.call(@ctx)
        end

        def mos6502_run_instructions_with_opcodes(n)
          if @fallback && @sim.respond_to?(:mos6502_run_instructions_with_opcodes)
            return @sim.mos6502_run_instructions_with_opcodes(n)
          end
          return [] if @fallback

          buf = Fiddle::Pointer.malloc(n * 8)
          count = @fn_mos6502_run_instructions_with_opcodes.call(@ctx, n, buf, n)

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
          return false if @fallback
          @fn_is_apple2_mode.call(@ctx) != 0
        end

        def apple2_load_rom(data)
          return @sim.apple2_load_rom(data) if @fallback && @sim.respond_to?(:apple2_load_rom)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          @fn_apple2_load_rom.call(@ctx, data, data.bytesize)
        end

        def apple2_load_ram(data, offset)
          return @sim.apple2_load_ram(data, offset) if @fallback && @sim.respond_to?(:apple2_load_ram)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          @fn_apple2_load_ram.call(@ctx, data, data.bytesize, offset)
        end

        def apple2_run_cpu_cycles(n, key_data, key_ready)
          if @fallback && @sim.respond_to?(:apple2_run_cpu_cycles)
            return @sim.apple2_run_cpu_cycles(n, key_data, key_ready)
          end
          return { text_dirty: false, key_cleared: false, cycles_run: 0, speaker_toggles: 0 } if @fallback

          result_buf = Fiddle::Pointer.malloc(16)
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
          return Array.new(length, 0) if @fallback
          buf = Fiddle::Pointer.malloc(length)
          actual_len = @fn_apple2_read_ram.call(@ctx, offset, buf, length)
          buf[0, actual_len].unpack('C*')
        end

        def apple2_write_ram(offset, data)
          return @sim.apple2_write_ram(offset, data) if @fallback && @sim.respond_to?(:apple2_write_ram)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          @fn_apple2_write_ram.call(@ctx, offset, data, data.bytesize)
        end

        # ====================================================================
        # Game Boy Extension Methods
        # ====================================================================

        def gameboy_mode?
          return @sim.gameboy_mode? if @fallback && @sim.respond_to?(:gameboy_mode?)
          return false if @fallback
          @fn_is_gameboy_mode.call(@ctx) != 0
        end

        def load_rom(data)
          return @sim.load_rom(data) if @fallback && @sim.respond_to?(:load_rom)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          @fn_gameboy_load_rom.call(@ctx, data, data.bytesize)
        end

        def load_boot_rom(data)
          return @sim.load_boot_rom(data) if @fallback && @sim.respond_to?(:load_boot_rom)
          return if @fallback
          data = data.pack('C*') if data.is_a?(Array)
          @fn_gameboy_load_boot_rom.call(@ctx, data, data.bytesize)
        end

        def run_gb_cycles(n)
          return @sim.run_gb_cycles(n) if @fallback && @sim.respond_to?(:run_gb_cycles)
          return { cycles_run: 0, frames_completed: 0 } if @fallback

          result_buf = Fiddle::Pointer.malloc(16)
          @fn_gameboy_run_cycles_full.call(@ctx, n, result_buf)

          values = result_buf[0, 16].unpack('QL')
          {
            cycles_run: values[0],
            frames_completed: values[1]
          }
        end

        def read_vram(addr)
          return @sim.read_vram(addr) if @fallback && @sim.respond_to?(:read_vram)
          return 0 if @fallback
          @fn_gameboy_read_vram.call(@ctx, addr) & 0xFF
        end

        def write_vram(addr, data)
          return @sim.write_vram(addr, data) if @fallback && @sim.respond_to?(:write_vram)
          return if @fallback
          @fn_gameboy_write_vram.call(@ctx, addr, data)
        end

        def read_zpram(addr)
          return @sim.read_zpram(addr) if @fallback && @sim.respond_to?(:read_zpram)
          return 0 if @fallback
          @fn_gameboy_read_zpram.call(@ctx, addr) & 0xFF
        end

        def write_zpram(addr, data)
          return @sim.write_zpram(addr, data) if @fallback && @sim.respond_to?(:write_zpram)
          return if @fallback
          @fn_gameboy_write_zpram.call(@ctx, addr, data)
        end

        def read_framebuffer
          return @sim.read_framebuffer if @fallback && @sim.respond_to?(:read_framebuffer)
          return [] if @fallback

          len = @fn_gameboy_framebuffer_len.call(@ctx)
          return [] if len == 0

          ptr = @fn_gameboy_framebuffer.call(@ctx)
          return [] if ptr.null?

          Fiddle::Pointer.new(ptr)[0, len].unpack('C*')
        end

        def frame_count
          return @sim.frame_count if @fallback && @sim.respond_to?(:frame_count)
          return 0 if @fallback
          @fn_gameboy_frame_count.call(@ctx)
        end

        def reset_lcd_state
          return @sim.reset_lcd_state if @fallback && @sim.respond_to?(:reset_lcd_state)
          return if @fallback
          @fn_gameboy_reset_lcd.call(@ctx)
        end

        def get_v_cnt
          return @sim.get_v_cnt if @fallback && @sim.respond_to?(:get_v_cnt)
          return 0 if @fallback
          @fn_gameboy_get_v_cnt.call(@ctx)
        end

        def get_h_cnt
          return @sim.get_h_cnt if @fallback && @sim.respond_to?(:get_h_cnt)
          return 0 if @fallback
          @fn_gameboy_get_h_cnt.call(@ctx)
        end

        def get_vblank_irq
          return @sim.get_vblank_irq if @fallback && @sim.respond_to?(:get_vblank_irq)
          return 0 if @fallback
          @fn_gameboy_get_vblank_irq.call(@ctx)
        end

        def get_if_r
          return @sim.get_if_r if @fallback && @sim.respond_to?(:get_if_r)
          return 0 if @fallback
          @fn_gameboy_get_if_r.call(@ctx)
        end

        def get_signal(idx)
          return @sim.get_signal(idx) if @fallback && @sim.respond_to?(:get_signal)
          return 0 if @fallback
          @fn_gameboy_get_signal.call(@ctx, idx)
        end

        def get_lcdc_on
          return @sim.get_lcdc_on if @fallback && @sim.respond_to?(:get_lcdc_on)
          return 0 if @fallback
          @fn_gameboy_get_lcdc_on.call(@ctx)
        end

        def get_h_div_cnt
          return @sim.get_h_div_cnt if @fallback && @sim.respond_to?(:get_h_div_cnt)
          return 0 if @fallback
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
          @lib = Fiddle.dlopen(IR_INTERPRETER_LIB_PATH)

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

          @fn_get_signal_idx = Fiddle::Function.new(
            @lib['ir_sim_get_signal_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_poke_by_idx = Fiddle::Function.new(
            @lib['ir_sim_poke_by_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_VOID
          )

          @fn_peek_by_idx = Fiddle::Function.new(
            @lib['ir_sim_peek_by_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_ULONG
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

          @fn_tick_forced = Fiddle::Function.new(
            @lib['ir_sim_tick_forced'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_set_prev_clock = Fiddle::Function.new(
            @lib['ir_sim_set_prev_clock'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_VOID
          )

          @fn_get_clock_list_idx = Fiddle::Function.new(
            @lib['ir_sim_get_clock_list_idx'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_run_ticks = Fiddle::Function.new(
            @lib['ir_sim_run_ticks'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
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
            @lib['mos6502_interp_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_load_memory = Fiddle::Function.new(
            @lib['mos6502_interp_sim_load_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_set_reset_vector = Fiddle::Function.new(
            @lib['mos6502_interp_sim_set_reset_vector'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_run_cycles = Fiddle::Function.new(
            @lib['mos6502_interp_sim_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_read_memory = Fiddle::Function.new(
            @lib['mos6502_interp_sim_read_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_mos6502_write_memory = Fiddle::Function.new(
            @lib['mos6502_interp_sim_write_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_speaker_toggles = Fiddle::Function.new(
            @lib['mos6502_interp_sim_speaker_toggles'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_mos6502_reset_speaker_toggles = Fiddle::Function.new(
            @lib['mos6502_interp_sim_reset_speaker_toggles'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_mos6502_run_instructions_with_opcodes = Fiddle::Function.new(
            @lib['mos6502_interp_sim_run_instructions_with_opcodes'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          # Apple II extension functions
          @fn_is_apple2_mode = Fiddle::Function.new(
            @lib['apple2_interp_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_apple2_load_rom = Fiddle::Function.new(
            @lib['apple2_interp_sim_load_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_load_ram = Fiddle::Function.new(
            @lib['apple2_interp_sim_load_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_run_cpu_cycles = Fiddle::Function.new(
            @lib['apple2_interp_sim_run_cpu_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_apple2_read_ram = Fiddle::Function.new(
            @lib['apple2_interp_sim_read_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_SIZE_T
          )

          @fn_apple2_write_ram = Fiddle::Function.new(
            @lib['apple2_interp_sim_write_ram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          # Game Boy extension functions
          @fn_is_gameboy_mode = Fiddle::Function.new(
            @lib['gameboy_interp_sim_is_mode'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @fn_gameboy_load_rom = Fiddle::Function.new(
            @lib['gameboy_interp_sim_load_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_load_boot_rom = Fiddle::Function.new(
            @lib['gameboy_interp_sim_load_boot_rom'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_run_cycles = Fiddle::Function.new(
            @lib['gameboy_interp_sim_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )

          @fn_gameboy_run_cycles_full = Fiddle::Function.new(
            @lib['gameboy_interp_sim_run_cycles_full'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_read_vram = Fiddle::Function.new(
            @lib['gameboy_interp_sim_read_vram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_gameboy_write_vram = Fiddle::Function.new(
            @lib['gameboy_interp_sim_write_vram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_read_zpram = Fiddle::Function.new(
            @lib['gameboy_interp_sim_read_zpram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_CHAR
          )

          @fn_gameboy_write_zpram = Fiddle::Function.new(
            @lib['gameboy_interp_sim_write_zpram'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_framebuffer = Fiddle::Function.new(
            @lib['gameboy_interp_sim_framebuffer'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )

          @fn_gameboy_framebuffer_len = Fiddle::Function.new(
            @lib['gameboy_interp_sim_framebuffer_len'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_SIZE_T
          )

          @fn_gameboy_frame_count = Fiddle::Function.new(
            @lib['gameboy_interp_sim_frame_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_ULONG
          )

          @fn_gameboy_reset_lcd = Fiddle::Function.new(
            @lib['gameboy_interp_sim_reset_lcd'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )

          @fn_gameboy_get_v_cnt = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_v_cnt'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_h_cnt = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_h_cnt'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_vblank_irq = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_vblank_irq'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_if_r = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_if_r'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_signal = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_signal'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_LONG_LONG
          )

          @fn_gameboy_get_lcdc_on = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_lcdc_on'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )

          @fn_gameboy_get_h_div_cnt = Fiddle::Function.new(
            @lib['gameboy_interp_sim_get_h_div_cnt'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
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
              raise RuntimeError, "Failed to create interpreter simulator: #{error_msg}"
            end
            raise RuntimeError, "Failed to create interpreter simulator"
          end

          @destructor = @fn_destroy
        end
      end

      # Backwards compatibility alias
      RtlInterpreterWrapper = IrInterpreterWrapper

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
