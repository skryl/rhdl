# frozen_string_literal: true

# Game Boy IR Simulator Runner
# High-performance IR-level simulation using batched Rust execution
#
# Usage:
#   runner = RHDL::GameBoy::IrRunner.new(backend: :interpret)
#   runner = RHDL::GameBoy::IrRunner.new(backend: :jit)
#   runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
#   runner.reset
#   runner.run_steps(100)

require_relative '../gameboy'
require_relative 'speaker'
require_relative 'lcd_renderer'

module RHDL
  module GameBoy
    # Utility module for exporting Gameboy component to IR
    module GameBoyIr
      class << self
        # Get the Behavior IR for the Gameboy component (shallow, for Verilog export)
        def behavior_ir
          ::GameBoy::Gameboy.to_ir
        end

        # Get the flattened Behavior IR (includes all subcomponent logic)
        def flat_ir
          ::GameBoy::Gameboy.to_flat_ir
        end

        # Convert to JSON format for the simulator
        def ir_json
          ir = flat_ir
          RHDL::Codegen::IR::IRToJson.convert(ir)
        end

        # Get stats about the IR
        def stats
          ir = behavior_ir
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
      DMG_BOOT_ROM_PATH = File.expand_path('../software/roms/dmg_boot.bin', __dir__)

      # Initialize the Game Boy IR runner
      # @param backend [Symbol] :interpret, :jit, or :compile
      def initialize(backend: :interpret)
        require 'rhdl/codegen'
        require 'rhdl/codegen/ir/sim/ir_interpreter'

        backend_names = { interpret: "Interpreter", jit: "JIT", compile: "Compiler" }
        puts "Initializing Game Boy IR simulation [#{backend_names[backend]}]..."
        start_time = Time.now

        # Generate IR JSON
        @ir_json = GameBoyIr.ir_json
        @backend = backend

        # Create the simulator based on backend choice
        @sim = case backend
               when :interpret
                 RHDL::Codegen::IR::IrInterpreterWrapper.new(@ir_json, allow_fallback: false)
               when :jit
                 require 'rhdl/codegen/ir/sim/ir_jit'
                 RHDL::Codegen::IR::IrJitWrapper.new(@ir_json, allow_fallback: false)
               when :compile
                 require 'rhdl/codegen/ir/sim/ir_compiler'
                 RHDL::Codegen::IR::IrCompilerWrapper.new(@ir_json)
               else
                 raise ArgumentError, "Unknown backend: #{backend}. Use :interpret, :jit, or :compile"
               end

        elapsed = Time.now - start_time
        puts "  IR loaded in #{elapsed.round(2)}s"
        puts "  Native backend: #{@sim.native? ? 'Rust (optimized)' : 'Ruby (fallback)'}"
        puts "  Signals: #{@sim.signal_count}, Registers: #{@sim.reg_count}"

        @cycles = 0
        @halted = false
        @screen_dirty = false

        # Memory
        @rom = []
        @ram = Array.new(64 * 1024, 0)

        # Speaker audio simulation
        @speaker = Speaker.new
        @prev_audio = 0

        # Check for either Game Boy batched cycles or Apple II batched cycles
        @use_batched = @sim.native? && (@sim.respond_to?(:run_gb_cycles) || @sim.respond_to?(:run_cpu_cycles))

        if @use_batched
          puts "  Batched execution: enabled"
        end

        # Check for Game Boy mode specifically
        if @sim.respond_to?(:gameboy_mode?) && @sim.gameboy_mode?
          puts "  Game Boy mode: enabled"
        end

        @sim.reset
        initialize_inputs unless @use_batched

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
        return if @use_batched
        poke_input('reset', 0)
        poke_input('clk_sys', 0)
        poke_input('ce', 0)
        poke_input('joystick', 0xFF)
        poke_input('is_gbc', 0)
        @sim.evaluate
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

        puts "Loaded #{@rom.length} bytes ROM"
      end

      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)

        if @use_batched
          @sim.load_ram(bytes, base_addr)
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
            puts "Loading default DMG boot ROM from #{DMG_BOOT_ROM_PATH}"
          else
            puts "Warning: DMG boot ROM not found at #{DMG_BOOT_ROM_PATH}"
            return
          end
        elsif bytes.is_a?(String) && File.exist?(bytes)
          # If it's a path, read the file
          bytes = File.binread(bytes)
        end

        bytes = bytes.bytes if bytes.is_a?(String)

        if @use_batched && @sim.respond_to?(:load_boot_rom)
          @sim.load_boot_rom(bytes)
          puts "Loaded #{bytes.length} bytes boot ROM"
          @boot_rom_loaded = true
        else
          puts "Warning: Boot ROM not supported in non-batched mode"
          @boot_rom_loaded = false
        end
      end

      def boot_rom_loaded?
        @boot_rom_loaded || false
      end

      def reset
        if @use_batched && @sim.respond_to?(:gameboy_mode?) && @sim.gameboy_mode?
          # Use run_gb_cycles for Game Boy - run_cpu_cycles corrupts signals[0] (reset)
          poke_input('reset', 1)
          @sim.run_gb_cycles(10)
          poke_input('reset', 0)
          @sim.run_gb_cycles(100)
          @sim.reset_lcd_state if @sim.respond_to?(:reset_lcd_state)
        elsif @use_batched
          poke_input('reset', 1)
          @sim.run_cpu_cycles(1, 0, false)
          poke_input('reset', 0)
          @sim.run_cpu_cycles(10, 0, false)
        else
          poke_input('reset', 1)
          run_cycles(10)
          poke_input('reset', 0)
          run_cycles(100)
        end
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
        if @sim.respond_to?(:run_gb_cycles) && @sim.respond_to?(:gameboy_mode?) && @sim.gameboy_mode?
          result = @sim.run_gb_cycles(steps)
          @cycles += result[:cycles_run]
          @screen_dirty = true if result[:frames_completed] > 0
        else
          result = @sim.run_cpu_cycles(steps, 0, false)
          @cycles += result[:cycles_run]
          @screen_dirty = true if result[:screen_dirty]
        end
      end

      def run_machine_cycle
        4.times { run_clock_cycle }
        @cycles += 1
      end

      def run_clock_cycle
        poke_input('ce', 1)
        @sim.evaluate

        # Handle memory access
        handle_memory_access

        poke_input('ce', 0)
        @sim.tick
      end

      def run_cycles(n)
        n.times { run_clock_cycle }
      end

      def handle_memory_access
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
          data = @sim.read_ram(addr, 1)
          data[0] || 0
        else
          @ram[addr] || 0
        end
      end

      def write(addr, value)
        addr &= 0xFFFF

        if @use_batched
          @sim.write_ram(addr, [value & 0xFF])
        else
          @ram[addr] = value & 0xFF if addr < @ram.size
        end
      end

      def inject_key(button)
        current = safe_peek('joystick') || 0xFF
        poke_input('joystick', current & ~(1 << button))
      end

      def release_key(button)
        current = safe_peek('joystick') || 0xFF
        poke_input('joystick', current | (1 << button))
      end

      def read_framebuffer
        # Use native framebuffer capture if available
        if @use_batched && @sim.respond_to?(:read_framebuffer) && @sim.respond_to?(:gameboy_mode?) && @sim.gameboy_mode?
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

      def safe_peek(name)
        peek_output(name)
      rescue StandardError
        0
      end

      def cpu_state
        {
          pc: safe_peek('gb_core__cpu__debug_pc'),
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

      def dry_run_info
        {
          mode: :hdl,
          simulator_type: simulator_type,
          native: native?,
          backend: @backend,
          cpu_state: cpu_state,
          rom_size: @rom.length
        }
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
    end
  end
end
