# frozen_string_literal: true

# Game Boy IR Simulator Runner
# High-performance IR-level simulation using batched Rust execution
#
# Usage:
#   runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :interpret)
#   runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :jit)
#   runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
#   runner.reset
#   runner.run_steps(100)

require_relative '../hdl_loader'
require_relative '../output/speaker'
require_relative '../renderers/lcd_renderer'
require_relative '../clock_enable_waveform'

module RHDL
  module Examples
    module GameBoy
      # Utility module for exporting Gameboy component to IR
      module GameBoyIr
      class << self
        # Get the CIRCT node graph for the Gameboy component (shallow module view)
        def behavior_ir(component_class: ::RHDL::Examples::GameBoy::Gameboy)
          component_class.to_circt_nodes
        end

        # Get the flattened Behavior IR (includes all subcomponent logic)
        def flat_ir(component_class: ::RHDL::Examples::GameBoy::Gameboy)
          component_class.to_flat_circt_nodes
        end

        # Convert to JSON format for the simulator
        def ir_json(component_class: ::RHDL::Examples::GameBoy::Gameboy, backend: :interpreter)
          ir = flat_ir(component_class: component_class)
          RHDL::Sim::Native::IR.sim_json(ir, backend: backend)
        end

        # Get stats about the IR
        def stats(component_class: ::RHDL::Examples::GameBoy::Gameboy)
          ir = behavior_ir(component_class: component_class)
          {
            port_count: ir.ports.length,
            net_count: ir.nets.length,
            reg_count: ir.regs.length,
            assign_count: ir.assigns.length,
            process_count: ir.processes.length,
            inputs: ir.ports.select { |p| p.direction == :in }.map(&:name),
            outputs: ir.ports.select { |p| p.direction == :out }.map(&:name)
          }
        end
      end
    end

    # High-performance IR-level runner
    class IrRunner
      attr_reader :sim, :ir_json

      # Screen dimensions
      SCREEN_WIDTH = 160
      SCREEN_HEIGHT = 144

      # Memory map constants
      ROM_BANK_0_END = 0x3FFF
      ROM_BANK_N_END = 0x7FFF
      VRAM_START = 0x8000
      VRAM_END = 0x9FFF
      WRAM_START = 0xC000
      WRAM_END = 0xDFFF

      # Boot ROM paths (relative to the gameboy directory)
      DMG_BOOT_ROM_PATH = File.expand_path('../../software/roms/dmg_boot.bin', __dir__)

      def runner_verbose?
        return true if ENV['RHDL_RUNNER_VERBOSE'] == '1'
        return false if ENV['RSPEC_QUIET_OUTPUT'] == '1'
        return false if defined?(RSpec)

        true
      end

      def log(message)
        puts(message) if runner_verbose?
      end

      # Initialize the Game Boy IR runner
      # @param backend [Symbol] :interpret, :jit, or :compile
      # @param hdl_dir [String, nil] Optional HDL directory override.
      # @param top [String, nil] Imported top component/module override for imported HDL trees.
      def initialize(backend: :interpret, hdl_dir: nil, top: nil)
        require 'rhdl/codegen'
        require 'rhdl/sim/native/ir/simulator'
        @component_class = resolve_component_class(hdl_dir: hdl_dir, top: top&.to_s)

        backend_names = { interpret: "Interpreter", jit: "JIT", compile: "Compiler" }
        log "Initializing Game Boy IR simulation [#{backend_names[backend]}]..."
        start_time = Time.now

        # Generate IR JSON
        @ir_json = GameBoyIr.ir_json(component_class: @component_class, backend: backend)
        @backend = backend

        @sim = RHDL::Sim::Native::IR::Simulator.new(
          @ir_json,
          backend: backend
        )

        elapsed = Time.now - start_time
        log "  IR loaded in #{elapsed.round(2)}s"
        log "  Native backend: Rust (optimized)"
        log "  Signals: #{@sim.signal_count}, Registers: #{@sim.reg_count}"

        @cycles = 0
        @halted = false
        @screen_dirty = false

        # Memory
        @rom = []
        @ram = Array.new(64 * 1024, 0)

        # Speaker audio simulation
        @speaker = Speaker.new
        @prev_audio = 0

        @use_batched = @sim.native? && @sim.runner_mode?
        if @use_batched && requires_manual_clock_enable_drive? && !@sim.gameboy_mode?
          @use_batched = false
          log "  Batched execution: disabled (manual CE drive required for imported top)"
        end

        if @use_batched
          log "  Batched execution: enabled"
        end

        # Check for Game Boy mode specifically
        if @sim.gameboy_mode?
          log "  Game Boy mode: enabled"
        end

        @sim.reset
        @clock_enable_phase = 0
        initialize_inputs

        # Load boot ROM if available
        load_boot_rom if File.exist?(DMG_BOOT_ROM_PATH)
      end

      def native?
        @sim.native?
      end

      def simulator_type
        @sim.simulator_type
      end

      def initialize_inputs
        @clock_enable_phase = 0
        poke_if_available('reset', 0)
        poke_if_available('clk_sys', 0)
        drive_clock_enable_inputs(falling_edge: false)
        poke_if_available('joystick', 0xFF)
        @joystick_state = 0xFF
        poke_if_available('joy_din', 0xF)
        poke_if_available('is_gbc', 0)
        poke_if_available('isGBC', 0)
        poke_if_available('is_sgb', 0)
        poke_if_available('isSGB', 0)
        poke_if_available('cart_oe', 1)
        poke_if_available('real_cgb_boot', 0)
        poke_if_available('cgb_boot_download', 0)
        poke_if_available('dmg_boot_download', 0)
        poke_if_available('sgb_boot_download', 0)
        poke_if_available('ioctl_wr', 0)
        poke_if_available('ioctl_addr', 0)
        poke_if_available('ioctl_dout', 0)
        poke_if_available('boot_gba_en', 0)
        poke_if_available('fast_boot_en', 0)
        poke_if_available('audio_no_pops', 0)
        poke_if_available('extra_spr_en', 0)
        poke_if_available('megaduck', 0)
        poke_if_available('gg_reset', 0)
        poke_if_available('gg_en', 0)
        poke_if_available('gg_code', 0)
        poke_if_available('serial_clk_in', 0)
        poke_if_available('serial_data_in', 1)
        poke_if_available('increaseSSHeaderCount', 0)
        poke_if_available('cart_ram_size', 0)
        poke_if_available('save_state', 0)
        poke_if_available('load_state', 0)
        poke_if_available('savestate_number', 0)
        poke_if_available('SaveStateExt_Dout', 0)
        poke_if_available('Savestate_CRAMReadData', 0)
        poke_if_available('SAVE_out_Dout', 0)
        poke_if_available('SAVE_out_done', 1)
        poke_if_available('rewind_on', 0)
        poke_if_available('rewind_active', 0)
        @sim.evaluate unless @use_batched
        update_joypad_input
      end

      def poke_input(name, value)
        @sim.poke(name, value)
      end

      def peek_output(name)
        @sim.peek(name)
      end

      def load_rom(bytes, base_addr: 0)
        bytes = bytes.bytes if bytes.is_a?(String)
        @rom = bytes.dup

        if @use_batched
          @sim.load_rom(bytes)
        end

        log "Loaded #{@rom.length} bytes ROM"
      end

      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)

        if @use_batched
          @sim.runner_load_memory(bytes, base_addr, false)
        else
          bytes.each_with_index do |byte, i|
            addr = base_addr + i
            @ram[addr] = byte if addr < @ram.size
          end
        end
      end

      # Load the DMG boot ROM (256 bytes)
      # @param bytes [String, Array<Integer>] boot ROM data or path to file
      def load_boot_rom(bytes = nil)
        # Default to DMG boot ROM if no data provided
        if bytes.nil?
          if File.exist?(DMG_BOOT_ROM_PATH)
            bytes = File.binread(DMG_BOOT_ROM_PATH)
            log "Loading default DMG boot ROM from #{DMG_BOOT_ROM_PATH}"
          else
            log "Warning: DMG boot ROM not found at #{DMG_BOOT_ROM_PATH}"
            return
          end
        elsif bytes.is_a?(String) && File.exist?(bytes)
          # If it's a path, read the file
          bytes = File.binread(bytes)
        end

        bytes = bytes.bytes if bytes.is_a?(String)

        if @use_batched && @sim.respond_to?(:load_boot_rom)
          @sim.load_boot_rom(bytes)
          log "Loaded #{bytes.length} bytes boot ROM"
          @boot_rom_loaded = true
        else
          @boot_rom = bytes.dup
          log "Loaded #{bytes.length} bytes boot ROM (software-driven)"
          @boot_rom_loaded = true
        end
      end

      def boot_rom_loaded?
        @boot_rom_loaded || false
      end

      def reset
        @clock_enable_phase = 0
        if @use_batched && @sim.gameboy_mode?
          # Keep reset deterministic for tests: assert reset for one cycle, then release.
          poke_input('reset', 1)
          @sim.run_gb_cycles(1)
          poke_input('reset', 0)
          @sim.reset_lcd_state if @sim.respond_to?(:reset_lcd_state)
        elsif @use_batched
          poke_input('reset', 1)
          @sim.runner_run_cycles(1, 0, false)
          poke_input('reset', 0)
          @sim.runner_run_cycles(10, 0, false)
        else
          poke_input('reset', 1)
          run_cycles(10)
          poke_input('reset', 0)
          run_cycles(100)
        end

        # Initialize joystick to all buttons released (active low, 0xFF = no buttons)
        poke_input('joystick', 0xFF)
        @joystick_state = 0xFF
        update_joypad_input

        @cycles = 0
        @halted = false
      end

      # Run N machine cycles
      def run_steps(steps)
        if @use_batched
          run_steps_batched(steps)
        else
          steps.times { run_machine_cycle }
        end
      end

      # Batched execution
      def run_steps_batched(steps)
        # Use Game Boy specific cycles if available (with framebuffer capture)
        if @sim.respond_to?(:run_gb_cycles) && @sim.gameboy_mode?
          result = @sim.run_gb_cycles(steps)
          @cycles += result[:cycles_run]
          @screen_dirty = true if result[:frames_completed] > 0
        else
          result = @sim.runner_run_cycles(steps, 0, false)
          @cycles += result[:cycles_run]
          @screen_dirty = true if result[:screen_dirty]
        end
      end

      def run_machine_cycle
        4.times { run_clock_cycle }
        @cycles += 1
      end

      def run_clock_cycle
        poke_if_available('clk_sys', 0)
        drive_clock_enable_inputs(falling_edge: false)
        @sim.evaluate
        update_joypad_input

        # Handle memory access
        handle_memory_access

        # Keep CE asserted through the rising edge so imported tops that gate
        # state updates on CE/CE_N actually advance.
        drive_clock_enable_inputs(falling_edge: false)
        poke_if_available('clk_sys', 1)
        @sim.tick
        @clock_enable_phase = ClockEnableWaveform.advance_phase(@clock_enable_phase)
      end

      def run_cycles(n)
        n.times { run_clock_cycle }
      end

      def handle_memory_access
        if @boot_rom_loaded && @boot_rom && signal_available?('sel_boot_rom') && safe_peek('sel_boot_rom') == 1
          boot_addr = safe_peek('boot_rom_addr') & 0xFF
          poke_if_available('boot_rom_do', @boot_rom[boot_addr] || 0)
        end

        addr = safe_peek('ext_bus_addr')
        a15 = safe_peek('ext_bus_a15')
        full_addr = (a15 << 15) | addr

        cart_rd = safe_peek('cart_rd')

        if cart_rd == 1
          data = read(full_addr)
          poke_input('cart_do', data)
        end
      end

      def read(addr)
        addr &= 0xFFFF

        if addr <= ROM_BANK_N_END
          @rom[addr] || 0
        elsif @use_batched
          data = @sim.runner_read_memory(addr, 1)
          data[0] || 0
        else
          @ram[addr] || 0
        end
      end

      def write(addr, value)
        addr &= 0xFFFF

        if @use_batched
          @sim.runner_write_memory(addr, [value & 0xFF])
        else
          @ram[addr] = value & 0xFF if addr < @ram.size
        end
      end

      def inject_key(button)
        current = @joystick_state || safe_peek('joystick') || 0xFF
        @joystick_state = current & ~(1 << button)
        poke_input('joystick', @joystick_state)
        update_joypad_input
      end

      def release_key(button)
        current = @joystick_state || safe_peek('joystick') || 0xFF
        @joystick_state = current | (1 << button)
        poke_input('joystick', @joystick_state)
        update_joypad_input
      end

      def read_framebuffer
        # Use native framebuffer capture if available
        if @use_batched && @sim.respond_to?(:read_framebuffer) && @sim.gameboy_mode?
          # Get flat 1D array from native code and reshape to 2D
          flat = @sim.read_framebuffer
          Array.new(SCREEN_HEIGHT) do |y|
            Array.new(SCREEN_WIDTH) do |x|
              flat[y * SCREEN_WIDTH + x] || 0
            end
          end
        else
          # Placeholder when native capture not available
          Array.new(SCREEN_HEIGHT) { Array.new(SCREEN_WIDTH, 0) }
        end
      end

      def read_screen
        ly = (@cycles / 456) % 154
        ["Game Boy LCD (IR)", "LY: #{ly}", "Cycles: #{@cycles}"]
      end

      def screen_dirty?
        @screen_dirty
      end

      def clear_screen_dirty
        @screen_dirty = false
      end

      def render_lcd_braille(chars_wide: 80, invert: false)
        renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
        renderer.render_braille(read_framebuffer)
      end

      def render_lcd_color(chars_wide: 80, invert: false)
        renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
        renderer.render_color(read_framebuffer)
      end

      def safe_peek(name)
        peek_output(name)
      rescue StandardError
        0
      end

      def poke_if_available(name, value)
        poke_input(name, value) if signal_available?(name)
      rescue StandardError
        nil
      end

      def drive_clock_enable_inputs(falling_edge:)
        values = ClockEnableWaveform.values_for_phase(@clock_enable_phase)
        poke_if_available('ce', values[:ce])
        poke_if_available('ce_n', values[:ce_n])
        poke_if_available('ce_2x', values[:ce_2x])
      end

      def update_joypad_input
        return unless signal_available?('joy_din')
        return unless signal_available?('joy_p54')

        joy = (@joystick_state || safe_peek('joystick') || 0xFF) & 0xFF
        joy_p54 = safe_peek('joy_p54') & 0x3
        p14 = joy_p54 & 0x1
        p15 = (joy_p54 >> 1) & 0x1
        joy_dir = joy & 0xF
        joy_btn = (joy >> 4) & 0xF
        joy_dir_masked = joy_dir | (p14.zero? ? 0x0 : 0xF)
        joy_btn_masked = joy_btn | (p15.zero? ? 0x0 : 0xF)
        poke_input('joy_din', joy_dir_masked & joy_btn_masked)
      end

      def signal_available?(name)
        @signal_presence ||= {}
        return @signal_presence[name] if @signal_presence.key?(name)

        @sim.peek(name)
        @signal_presence[name] = true
      rescue StandardError
        @signal_presence[name] = false
      end

      def requires_manual_clock_enable_drive?
        return false unless @component_class.respond_to?(:_ports)

        input_names = @component_class._ports
          .select { |port| port.direction == :in }
          .map { |port| port.name.to_s }
        input_names.include?('ce_n') || input_names.include?('ce_2x')
      rescue StandardError
        false
      end

      def cpu_state
        debug_pc =
          if signal_available?('gb_core__cpu__debug_pc')
            safe_peek('gb_core__cpu__debug_pc')
          elsif signal_available?('debug_pc')
            safe_peek('debug_pc')
          end
        bus_pc =
          if signal_available?('ext_bus_addr')
            ((safe_peek('ext_bus_a15') & 0x1) << 15) | (safe_peek('ext_bus_addr') & 0x7FFF)
          end
        pc =
          if debug_pc.nil?
            bus_pc || 0
          elsif debug_pc.to_i.zero? && bus_pc.to_i.nonzero?
            bus_pc
          else
            debug_pc
          end

        {
          pc: pc,
          a: safe_peek('gb_core__cpu__debug_acc'),
          f: safe_peek('gb_core__cpu__debug_f'),
          b: safe_peek('gb_core__cpu__debug_b'),
          c: safe_peek('gb_core__cpu__debug_c'),
          d: safe_peek('gb_core__cpu__debug_d'),
          e: safe_peek('gb_core__cpu__debug_e'),
          h: safe_peek('gb_core__cpu__debug_h'),
          l: safe_peek('gb_core__cpu__debug_l'),
          sp: safe_peek('gb_core__cpu__debug_sp'),
          cycles: @cycles,
          halted: @halted,
          simulator_type: simulator_type
        }
      end

      def halted?
        @halted
      end

      def cycle_count
        @cycles
      end

      def speaker
        @speaker
      end

      def start_audio
        @speaker.start
      end

      def stop_audio
        @speaker.stop
      end

      private

      def resolve_component_class(hdl_dir:, top: nil)
        resolved_hdl_dir = HdlLoader.resolve_hdl_dir(hdl_dir: hdl_dir)
        if resolved_hdl_dir == HdlLoader::DEFAULT_HDL_DIR
          HdlLoader.configure!(hdl_dir: resolved_hdl_dir)
          require_relative '../../gameboy'
          return ::RHDL::Examples::GameBoy::Gameboy
        end

        HdlLoader.load_component_tree!(hdl_dir: resolved_hdl_dir)
        candidates = []
        if top
          top_name = top
          class_name = camelize_name(top_name.to_s)
          candidates << Object.const_get(class_name, false) if Object.const_defined?(class_name, false)
          if defined?(::RHDL::Examples::GameBoy) && ::RHDL::Examples::GameBoy.const_defined?(class_name, false)
            candidates << ::RHDL::Examples::GameBoy.const_get(class_name, false)
          end
        else
          %w[GB Gb].each do |class_name|
            candidates << Object.const_get(class_name, false) if Object.const_defined?(class_name, false)
            if defined?(::RHDL::Examples::GameBoy) && ::RHDL::Examples::GameBoy.const_defined?(class_name, false)
              candidates << ::RHDL::Examples::GameBoy.const_get(class_name, false)
            end
          end
        end

        component_class = candidates.find do |candidate|
          candidate.is_a?(Class) && candidate.respond_to?(:to_flat_circt_nodes)
        end

        return component_class if component_class

        unless top
          require_relative '../../gameboy'
          return ::RHDL::Examples::GameBoy::Gameboy
        end

        top_name = top
        class_name = camelize_name(top_name.to_s)
        raise NameError,
              "Unable to resolve imported Game Boy top component '#{top_name}' "\
              "(expected class '#{class_name}') in #{resolved_hdl_dir}"
      end

      def camelize_name(value)
        tokens = value.to_s
                      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                      .tr('-', '_')
                      .split('_')
                      .reject(&:empty?)
        tokens.map(&:capitalize).join
      end
      end
    end
  end
end
