# frozen_string_literal: true

# Game Boy Verilator Simulator Runner
# High-performance RTL simulation using Verilator
#
# This runner exports the Gameboy HDL to Verilog, compiles it with Verilator,
# and provides a native simulation interface similar to the Rust IR runners.
#
# Usage:
#   runner = RHDL::ExamplesRHDL::Examples::GameBoy::VerilogRunner.new
#   runner.load_rom(File.binread('game.gb'))
#   runner.reset
#   runner.run_steps(100)

require_relative '../hdl_loader'
require_relative '../import/verilog_wrapper'
require_relative '../output/speaker'
require_relative '../renderers/lcd_renderer'
require_relative '../clock_enable_waveform'
require 'rhdl/codegen'
require 'fileutils'
require 'set'
require 'json'
require 'digest'
require 'fiddle'
require 'fiddle/import'

module RHDL
  module Examples
    module GameBoy
      # Verilator-based runner for Game Boy simulation
    # Compiles RHDL Verilog export to native code via Verilator
    class VerilogRunner
      include RHDL::Examples::GameBoy::Import::VerilogWrapper

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
      HRAM_START = 0xFF80
      HRAM_END = 0xFFFE
      CART_TYPE_ROM_ONLY = 0x00
      MBC1_CART_TYPES = [0x01, 0x02, 0x03].freeze
      ROM_BANK_COUNTS_BY_SIZE_CODE = {
        0x00 => 2,
        0x01 => 4,
        0x02 => 8,
        0x03 => 16,
        0x04 => 32,
        0x05 => 64,
        0x06 => 128,
        0x07 => 256,
        0x08 => 512,
        0x52 => 72,
        0x53 => 80,
        0x54 => 96
      }.freeze

      # Build directory for Verilator output
      BUILD_DIR = File.expand_path('../../.verilator_build', __dir__)
      VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
      OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')
      VERILATOR_WARN_FLAGS = %w[
        -Wno-fatal
        -Wno-ASCRANGE
        -Wno-MULTIDRIVEN
        -Wno-PINMISSING
        -Wno-WIDTHEXPAND
        -Wno-WIDTHTRUNC
        -Wno-UNOPTFLAT
        -Wno-CASEINCOMPLETE
      ].freeze

      # Boot ROM path
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

      # Initialize the Game Boy Verilator runner
      # @param hdl_dir [String, nil] Optional HDL directory override.
      # @param verilog_dir [String, nil] Optional direct Verilog directory/file override.
      # @param top [String, nil] Imported top component/module override for imported HDL trees.
      # @param use_staged_verilog [Boolean] Use the staged imported Verilog artifact when available.
      def initialize(hdl_dir: nil, verilog_dir: nil, top: nil, use_staged_verilog: false)
        if hdl_dir && verilog_dir
          raise ArgumentError, 'Pass either hdl_dir or verilog_dir, not both'
        end

        @import_top_name = top&.to_s
        @use_staged_verilog = !!use_staged_verilog
        if verilog_dir
          configure_direct_verilog!(verilog_dir: verilog_dir, top: @import_top_name)
        else
          configure_component_mode!(hdl_dir: hdl_dir, top: @import_top_name)
        end
        @input_port_aliases = build_input_port_aliases
        @output_port_aliases = build_output_port_aliases

        check_verilator_available!

        log "Initializing Game Boy Verilator simulation..."
        start_time = Time.now

        # Build and load the Verilator simulation
        build_verilator_simulation

        elapsed = Time.now - start_time
        log "  Verilator simulation built in #{elapsed.round(2)}s"

        @cycles = 0
        @halted = false
        @screen_dirty = false

        # Memory arrays
        @rom = Array.new(1024 * 1024, 0)  # 1MB max ROM
        @vram = Array.new(8192, 0)         # 8KB VRAM
        @wram = Array.new(8192, 0)         # 8KB WRAM
        @hram = Array.new(127, 0)          # 127 bytes HRAM
        @boot_rom = Array.new(256, 0)      # 256 bytes DMG boot ROM
        @cartridge = default_cartridge_state

        # Framebuffer (160x144 pixels, 2-bit grayscale)
        @framebuffer = Array.new(SCREEN_HEIGHT) { Array.new(SCREEN_WIDTH, 0) }

        # LCD state tracking
        @lcd_x = 0
        @lcd_y = 0
        @prev_lcd_clkena = 0
        @prev_lcd_vsync = 0
        @frame_count = 0
        @last_fetch_addr = 0
        @joystick_state = 0xFF
        @clock_enable_phase = 0

        # Speaker audio simulation
        @speaker = Speaker.new

        # Only auto-load a boot ROM when the top exposes a real boot-ROM feed path.
        load_boot_rom if auto_load_boot_rom?
      end

      def native?
        true
      end

      def simulator_type
        :hdl_verilator
      end

      def dry_run_info
        {
          mode: :verilog,
          simulator_type: :hdl_verilator,
          native: true
        }
      end

      # Load ROM data
      def load_rom(bytes, base_addr: 0)
        bytes = bytes.bytes if bytes.is_a?(String)
        @rom = bytes.dup
        @rom.concat(Array.new(1024 * 1024 - @rom.size, 0)) if @rom.size < 1024 * 1024
        @cartridge = cartridge_state_for_rom(bytes)

        # Bulk load into C++ side
        if @sim_load_rom_fn && @sim_ctx
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
        end

        log "Loaded #{bytes.size} bytes ROM"
      end

      # Load boot ROM data
      def load_boot_rom(bytes = nil)
        if bytes.nil?
          if File.exist?(DMG_BOOT_ROM_PATH)
            bytes = File.binread(DMG_BOOT_ROM_PATH)
            log "Loading default DMG boot ROM from #{DMG_BOOT_ROM_PATH}"
          else
            log "Warning: DMG boot ROM not found at #{DMG_BOOT_ROM_PATH}"
            return
          end
        elsif bytes.is_a?(String) && File.exist?(bytes)
          bytes = File.binread(bytes)
        end

        bytes = bytes.bytes if bytes.is_a?(String)
        @boot_rom = bytes.dup
        @boot_rom.concat(Array.new(256 - @boot_rom.size, 0)) if @boot_rom.size < 256

        # Bulk load into C++ side
        if @sim_load_boot_rom_fn && @sim_ctx
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_boot_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
        end

        log "Loaded #{bytes.size} bytes boot ROM"
        @boot_rom_loaded = true
      end

      def boot_rom_loaded?
        @boot_rom_loaded || false
      end

      def auto_load_boot_rom?
        return false unless File.exist?(DMG_BOOT_ROM_PATH)
        return true if @top_module_name == 'gb'

        !resolve_port_name('boot_rom_addr').nil? && !resolve_port_name('boot_rom_do').nil?
      end

      def reset
        reset_simulation
        @cycles = 0
        @halted = false
        @screen_dirty = false
        @lcd_x = 0
        @lcd_y = 0
        @frame_count = 0
        @last_fetch_addr = 0
        @joystick_state = 0xFF
        @clock_enable_phase = 0
        reset_cartridge_runtime_state!
      end

      # Main entry point for running cycles
      def run_steps(steps)
        if @sim_run_cycles_fn
          # Use batch execution - run all cycles in C++
          result_ptr = Fiddle::Pointer.malloc(16)  # GbCycleResult struct
          @sim_run_cycles_fn.call(@sim_ctx, steps, result_ptr)
          # Unpack result: cycles_run (usize) + frames_completed (u32)
          values = result_ptr.to_s(16).unpack('QL')
          cycles_run = values[0]
          frames_completed = values[1]
          @cycles += cycles_run
          @screen_dirty = true if frames_completed > 0
          @frame_count += frames_completed
        else
          # Fallback to per-cycle Ruby execution
          steps.times { run_clock_cycle }
        end
      end

      # Run a single clock cycle
      def run_clock_cycle
        # Falling edge
        verilator_poke('clk_sys', 0)
        drive_clock_enable_inputs(falling_edge: true)
        verilator_eval
        update_joypad_input
        drive_cartridge_input
        verilator_eval

        # Rising edge
        verilator_poke('clk_sys', 1)
        drive_clock_enable_inputs(falling_edge: false)
        verilator_eval
        update_joypad_input
        drive_cartridge_input
        verilator_eval
        advance_cartridge_read_pipeline!
        @clock_enable_phase = ClockEnableWaveform.advance_phase(@clock_enable_phase)

        # Capture LCD output
        lcd_clkena = verilator_peek('lcd_clkena')
        lcd_vsync = verilator_peek('lcd_vsync')
        lcd_data = verilator_peek('lcd_data_gb') & 0x3

        # Rising edge of lcd_clkena: capture pixel
        if lcd_clkena == 1 && @prev_lcd_clkena == 0
          if @lcd_x < SCREEN_WIDTH && @lcd_y < SCREEN_HEIGHT
            @framebuffer[@lcd_y][@lcd_x] = lcd_data
            @screen_dirty = true
          end
          @lcd_x += 1
          if @lcd_x >= SCREEN_WIDTH
            @lcd_x = 0
            @lcd_y += 1
          end
        end

        # Rising edge of lcd_vsync: end of frame
        if lcd_vsync == 1 && @prev_lcd_vsync == 0
          @lcd_x = 0
          @lcd_y = 0
          @frame_count += 1
        end

        @prev_lcd_clkena = lcd_clkena
        @prev_lcd_vsync = lcd_vsync
        @cycles += 1
      end

      # Inject a joypad button press
      def inject_key(button)
        current = @joystick_state || (verilator_peek('joystick') || 0xFF)
        @joystick_state = current & ~(1 << button)
        verilator_poke('joystick', @joystick_state)
        update_joypad_input
      end

      def release_key(button)
        current = @joystick_state || (verilator_peek('joystick') || 0xFF)
        @joystick_state = current | (1 << button)
        verilator_poke('joystick', @joystick_state)
        update_joypad_input
      end

      def read_framebuffer
        # Read framebuffer from C++ side
        if @sim_read_framebuffer_fn && @sim_ctx
          buffer = Fiddle::Pointer.malloc(160 * 144)
          @sim_read_framebuffer_fn.call(@sim_ctx, buffer)
          flat = buffer.to_s(160 * 144).bytes
          # Reshape to 2D array
          Array.new(SCREEN_HEIGHT) do |y|
            Array.new(SCREEN_WIDTH) do |x|
              flat[y * SCREEN_WIDTH + x]
            end
          end
        else
          @framebuffer
        end
      end

      def read_screen
        ly = (@cycles / 456) % 154
        ["Game Boy LCD (Verilator)", "LY: #{ly}", "Cycles: #{@cycles}"]
      end

      def screen_dirty?
        @screen_dirty
      end

      def clear_screen_dirty
        @screen_dirty = false
      end

      def render_lcd_braille(chars_wide: 40, invert: false)
        renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
        renderer.render_braille(read_framebuffer)
      end

      def render_lcd_color(chars_wide: 80)
        renderer = LcdRenderer.new(chars_wide: chars_wide)
        renderer.render_color(read_framebuffer)
      end

      def cpu_state
        debug_pc = verilator_peek('debug_pc')
        bus_pc = ((verilator_peek('ext_bus_a15') & 0x1) << 15) | (verilator_peek('ext_bus_addr') & 0x7FFF)
        internal_pc = begin
          verilator_peek('cpu_pc_internal')
        rescue StandardError
          @last_fetch_addr || 0
        end
        internal_acc = begin
          verilator_peek('debug_acc_internal')
        rescue StandardError
          0
        end
        internal_f = begin
          verilator_peek('debug_f_internal')
        rescue StandardError
          0
        end
        internal_sp = begin
          verilator_peek('debug_sp_internal')
        rescue StandardError
          0
        end
        pc = if debug_port_available?('debug_pc')
               if debug_pc.to_i.zero?
                 next_pc = bus_pc.to_i.zero? ? internal_pc : bus_pc
                 next_pc
               else
                 debug_pc
               end
             else
               bus_pc.to_i.zero? ? internal_pc : bus_pc
             end
        acc = begin
          value = verilator_peek('debug_acc')
          value.to_i.zero? && internal_acc.to_i != 0 ? internal_acc : value
        rescue StandardError
          internal_acc
        end
        f_reg = begin
          value = verilator_peek('debug_f')
          value.to_i.zero? && internal_f.to_i != 0 ? internal_f : value
        rescue StandardError
          internal_f
        end
        sp_reg = begin
          value = verilator_peek('debug_sp')
          value.to_i.zero? && internal_sp.to_i != 0 ? internal_sp : value
        rescue StandardError
          internal_sp
        end

        {
          pc: pc || 0,
          a: acc || 0,
          f: f_reg || 0,
          b: verilator_peek('debug_b') || 0,
          c: verilator_peek('debug_c') || 0,
          d: verilator_peek('debug_d') || 0,
          e: verilator_peek('debug_e') || 0,
          h: verilator_peek('debug_h') || 0,
          l: verilator_peek('debug_l') || 0,
          sp: sp_reg || 0,
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

      def frame_count
        @frame_count
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

      def read(addr)
        addr &= 0xFFFF

        if addr <= ROM_BANK_N_END
          @rom[addr] || 0
        elsif addr >= VRAM_START && addr <= VRAM_END
          @vram[addr - VRAM_START] || 0
        elsif addr >= WRAM_START && addr <= WRAM_END
          @wram[addr - WRAM_START] || 0
        elsif addr >= HRAM_START && addr <= HRAM_END
          @hram[addr - HRAM_START] || 0
        else
          0xFF
        end
      end

      def write(addr, value)
        addr &= 0xFFFF

        if addr >= VRAM_START && addr <= VRAM_END
          @vram[addr - VRAM_START] = value & 0xFF
          verilator_write_vram(addr - VRAM_START, value & 0xFF)
        elsif addr >= WRAM_START && addr <= WRAM_END
          @wram[addr - WRAM_START] = value & 0xFF
        elsif addr >= HRAM_START && addr <= HRAM_END
          @hram[addr - HRAM_START] = value & 0xFF
        end
      end

      private

      def configure_component_mode!(hdl_dir:, top:)
        @direct_verilog_source_plan = nil
        @resolved_verilog_dir = nil
        @component_class = resolve_component_class(hdl_dir: hdl_dir, top: top)
        install_component_ports!(@component_class)
        @top_module_name = resolve_top_module_name(@component_class)
        @verilator_prefix = "V#{@top_module_name}"
      end

      def configure_direct_verilog!(verilog_dir:, top:)
        @component_class = nil
        @direct_verilog_source_plan = resolve_direct_verilog_source_plan(
          verilog_dir: verilog_dir,
          top: top,
          use_staged_verilog: @use_staged_verilog
        )
        @resolved_verilog_dir = @direct_verilog_source_plan.fetch(:resolved_root)
        @resolved_hdl_dir = nil
        install_port_declarations!(@direct_verilog_source_plan.fetch(:port_declarations))
        @top_module_name = @direct_verilog_source_plan.fetch(:top_module_name)
        @verilator_prefix = "V#{@top_module_name}"
      end

      def install_component_ports!(component_class)
        reset_component_port_metadata!
        return unless component_class.respond_to?(:_ports)

        component_class._ports.each do |port|
          install_port_metadata_entry!(
            name: port.name.to_s,
            direction: (port.direction == :in ? :in : :out),
            width: port.width.to_i
          )
        end
      end

      def install_port_declarations!(declarations)
        reset_component_port_metadata!
        Array(declarations).each do |entry|
          install_port_metadata_entry!(
            name: entry.fetch(:name).to_s,
            direction: entry.fetch(:direction).to_sym,
            width: entry.fetch(:width).to_i
          )
        end
      end

      def reset_component_port_metadata!
        @component_input_ports = Set.new
        @component_output_ports = Set.new
        @component_port_widths = {}
        @component_ports = Set.new
      end

      def install_port_metadata_entry!(name:, direction:, width:)
        @component_port_widths[name] = width
        if direction == :in
          @component_input_ports << name
        else
          @component_output_ports << name
        end
        @component_ports << name
      end

      def resolve_component_class(hdl_dir:, top: nil)
        resolved_hdl_dir = HdlLoader.resolve_hdl_dir(hdl_dir: hdl_dir)
        @resolved_hdl_dir = resolved_hdl_dir
        if resolved_hdl_dir == HdlLoader::DEFAULT_HDL_DIR
          HdlLoader.configure!(hdl_dir: resolved_hdl_dir)
          require_relative '../../hdl/gameboy'
          return ::RHDL::Examples::GameBoy::Gameboy
        end

        HdlLoader.load_component_tree!(hdl_dir: resolved_hdl_dir)
        top_name = top || default_import_top_name(resolved_hdl_dir: resolved_hdl_dir)
        if top_name.nil? || top_name.to_s.empty?
          raise ArgumentError,
                "Imported Game Boy HDL at #{resolved_hdl_dir} does not define a wrapper top. "\
                "Re-run the importer or pass --top explicitly."
        end

        class_name = camelize_name(top_name.to_s)

        candidates = []
        candidates << Object.const_get(class_name, false) if Object.const_defined?(class_name, false)
        if defined?(::RHDL::Examples::GameBoy) && ::RHDL::Examples::GameBoy.const_defined?(class_name, false)
          candidates << ::RHDL::Examples::GameBoy.const_get(class_name, false)
        end

        component_class = candidates.find do |candidate|
          candidate.is_a?(Class) && candidate.respond_to?(:to_verilog)
        end
        return component_class if component_class

        raise NameError,
              "Unable to resolve imported Game Boy top component '#{top_name}' "\
              "(expected class '#{class_name}') in #{resolved_hdl_dir}"
      end

      def resolve_direct_verilog_source_plan(verilog_dir:, top:, use_staged_verilog:)
        requested_top = top.to_s.strip
        raise ArgumentError, 'Direct Verilog runs require --top' if requested_top.empty?

        artifact = resolve_direct_verilog_artifact(
          verilog_dir: verilog_dir,
          top: requested_top,
          use_staged_verilog: use_staged_verilog
        )
        top_module_name = normalize_direct_verilog_top_name(requested_top)
        wrapper_source = nil
        port_source_text = nil
        if top_module_name == gameboy_wrapper_top_module
          profile = gb_wrapper_profile(artifact.fetch(:core_verilog_path))
          wrapper_source = gameboy_wrapper_source(
            profile: profile,
            use_speedcontrol: artifact.fetch(:support_modules).include?('speedcontrol')
          )
          port_source_text = wrapper_source
        else
          port_source_text = File.read(artifact.fetch(:core_verilog_path))
        end

        {
          resolved_root: artifact.fetch(:resolved_root),
          report_path: artifact[:report_path],
          source_verilog_path: artifact.fetch(:source_verilog_path),
          core_verilog_path: artifact.fetch(:core_verilog_path),
          top_module_name: top_module_name,
          wrapper_source: wrapper_source,
          wrapper_module_name: (wrapper_source ? gameboy_wrapper_top_module : nil),
          port_declarations: extract_module_port_declarations(
            text: port_source_text,
            module_name: top_module_name
          ),
          dependency_paths: artifact.fetch(:dependency_paths),
          support_verilog_paths: artifact.fetch(:support_verilog_paths),
          support_modules: artifact.fetch(:support_modules)
        }
      end

      def resolve_direct_verilog_artifact(verilog_dir:, top:, use_staged_verilog:)
        resolved = File.expand_path(verilog_dir)
        if File.file?(resolved)
          return {
            resolved_root: File.dirname(resolved),
            source_verilog_path: resolved,
            core_verilog_path: resolved,
            dependency_paths: [resolved],
            support_verilog_paths: [],
            support_modules: []
          }
        end

        raise ArgumentError, "Direct Verilog path not found: #{resolved}" unless Dir.exist?(resolved)

        report_path = locate_direct_verilog_report(resolved)
        if report_path && File.file?(report_path)
          report = JSON.parse(File.read(report_path))
          mixed = report['mixed_import'].is_a?(Hash) ? report['mixed_import'] : {}
          artifacts = report['artifacts'].is_a?(Hash) ? report['artifacts'] : {}
          selected_source = if use_staged_verilog
                              first_existing_path(
                                mixed['pure_verilog_entry_path'],
                                artifacts['pure_verilog_entry_path'],
                                artifacts['workspace_pure_verilog_entry_path']
                              )
                            else
                              first_existing_path(
                                mixed['normalized_verilog_path'],
                                artifacts['normalized_verilog_path'],
                                artifacts['workspace_normalized_verilog_path']
                              )
                            end
          core_verilog_path = if use_staged_verilog
                                first_existing_path(mixed['top_file'])
                              else
                                selected_source
                              end
          dependency_paths = []
          dependency_paths << report_path
          dependency_paths << selected_source if selected_source
          dependency_paths << core_verilog_path if core_verilog_path
          dependency_paths.concat(Dir.glob(File.join(mixed['pure_verilog_root'], '**', '*.v'))) if use_staged_verilog && mixed['pure_verilog_root']
          support = direct_verilog_wrapper_support(report: report)
          support_verilog_paths = use_staged_verilog ? [] : support.fetch(:verilog_paths)
          dependency_paths.concat(support_verilog_paths)

          if selected_source && core_verilog_path
            return {
              resolved_root: resolved,
              report_path: report_path,
              source_verilog_path: selected_source,
              core_verilog_path: core_verilog_path,
              dependency_paths: dependency_paths.uniq,
              support_verilog_paths: support_verilog_paths,
              support_modules: support.fetch(:modules)
            }
          end
        end

        raw_tree_artifact = resolve_raw_direct_verilog_artifact(
          resolved: resolved,
          top: top,
          use_staged_verilog: use_staged_verilog
        )
        return raw_tree_artifact if raw_tree_artifact

        fallback_source = resolve_direct_verilog_fallback_source(
          resolved,
          use_staged_verilog: use_staged_verilog
        )
        {
          resolved_root: resolved,
          source_verilog_path: fallback_source,
          core_verilog_path: fallback_source,
          dependency_paths: [fallback_source],
          support_verilog_paths: [],
          support_modules: []
        }
      end

      def direct_verilog_wrapper_support(report:)
        mixed = report['mixed_import'].is_a?(Hash) ? report['mixed_import'] : {}
        components = Array(report['components'])

        speedcontrol_path =
          components.find do |entry|
            entry['verilog_module_name'].to_s == 'speedcontrol' || entry['module_name'].to_s == 'speedcontrol'
          end&.yield_self { |entry| first_existing_path(entry['staged_verilog_path']) }

        if speedcontrol_path.nil?
          synth_entry = Array(mixed['vhdl_synth_outputs']).find do |entry|
            entry['module_name'].to_s == 'speedcontrol' || entry['entity'].to_s == 'speedcontrol'
          end
          speedcontrol_path = first_existing_path(synth_entry && synth_entry['output_path'])
        end

        modules = []
        verilog_paths = []
        if speedcontrol_path
          modules << 'speedcontrol'
          verilog_paths << speedcontrol_path
        end

        {
          modules: modules.uniq,
          verilog_paths: verilog_paths.uniq
        }
      end

      def locate_direct_verilog_report(resolved)
        candidates = [
          File.join(resolved, 'import_report.json'),
          File.join(resolved, '.mixed_import', 'import_report.json'),
          File.join(resolved, '..', 'import_report.json')
        ]
        candidates.find { |path| File.file?(File.expand_path(path)) }.then do |path|
          path && File.expand_path(path)
        end
      end

      def resolve_direct_verilog_fallback_source(resolved, use_staged_verilog:)
        candidates =
          if use_staged_verilog
            [
              File.join(resolved, '.mixed_import', 'pure_verilog_entry.v'),
              *Dir.glob(File.join(resolved, '*.pure_entry.v')).sort,
              *Dir.glob(File.join(resolved, '**', 'pure_verilog_entry.v')).sort
            ]
          else
            [
              File.join(resolved, '.mixed_import', 'gb.normalized.v'),
              *Dir.glob(File.join(resolved, '*.normalized.v')).sort,
              *Dir.glob(File.join(resolved, '**', '*.normalized.v')).sort
            ]
          end

        source = first_existing_path(*candidates)
        return source if source

        raise ArgumentError,
              "Unable to resolve #{use_staged_verilog ? 'staged' : 'normalized'} imported Verilog from #{resolved}"
      end

      def resolve_raw_direct_verilog_artifact(resolved:, top:, use_staged_verilog:)
        return nil if use_staged_verilog

        top_module_name = normalize_direct_verilog_top_name(top)
        core_module_name = top_module_name == gameboy_wrapper_top_module ? 'gb' : top_module_name
        verilog_files = raw_direct_verilog_files(resolved)
        return nil if verilog_files.empty?

        top_file = raw_direct_verilog_top_file(verilog_files: verilog_files, top_module_name: core_module_name)
        return nil unless top_file

        {
          resolved_root: resolved,
          source_verilog_path: top_file,
          core_verilog_path: top_file,
          dependency_paths: verilog_files,
          support_verilog_paths: verilog_files.reject { |path| path == top_file },
          support_modules: []
        }
      end

      def raw_direct_verilog_files(resolved)
        patterns = ['**/*.v', '**/*.sv']
        patterns.flat_map { |pattern| Dir.glob(File.join(resolved, pattern)) }
                .map { |path| File.expand_path(path) }
                .select { |path| File.file?(path) }
                .uniq
                .sort
      end

      def raw_direct_verilog_top_file(verilog_files:, top_module_name:)
        exact_name = "#{top_module_name}.v"
        exact_sv_name = "#{top_module_name}.sv"
        named_match = verilog_files.find do |path|
          base = File.basename(path)
          base == exact_name || base == exact_sv_name
        end
        return named_match if named_match && file_declares_module?(named_match, top_module_name)

        verilog_files.find { |path| file_declares_module?(path, top_module_name) }
      end

      def file_declares_module?(path, module_name)
        text = File.read(path)
        !!text.match(/\bmodule\s+#{Regexp.escape(module_name)}\b/)
      rescue Errno::ENOENT
        false
      end

      def first_existing_path(*candidates)
        Array(candidates).flatten.compact.map { |path| File.expand_path(path) }.find { |path| File.file?(path) }
      end

      def normalize_direct_verilog_top_name(value)
        text = value.to_s.strip
        return text if text.match?(/\A[a-z][a-z0-9_]*\z/)

        underscore_name(text)
      end

      def extract_module_port_declarations(text:, module_name:)
        header_match = text.match(
          /module\s+#{Regexp.escape(module_name)}\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;/m
        )
        raise "Unable to locate module #{module_name} in direct Verilog source" unless header_match

        declarations = []
        header_match[1].scan(
          /\b(input|output)\b\s+(?:wire\s+|reg\s+|logic\s+)?(?:signed\s+)?(\[[^\]]+\])?\s*([A-Za-z_][A-Za-z0-9_$]*)/m
        ) do |direction, range, name|
          declarations << {
            direction: direction == 'input' ? :in : :out,
            name: name,
            width: verilog_port_width(range)
          }
        end
        raise "Unable to parse ports for module #{module_name}" if declarations.empty?

        declarations
      end

      def verilog_port_width(range)
        return 1 if range.nil? || range.empty?

        match = range.match(/\[(\d+)\s*:\s*(\d+)\]/)
        return 1 unless match

        (match[1].to_i - match[2].to_i).abs + 1
      end

      def default_import_top_name(resolved_hdl_dir:)
        report_path = File.expand_path(File.join(resolved_hdl_dir, 'import_report.json'))
        if File.file?(report_path)
          begin
            report = JSON.parse(File.read(report_path))
            wrapper_name = report.dig('import_wrapper', 'class_name')
            return wrapper_name unless wrapper_name.to_s.empty?
          rescue JSON::ParserError
            # Fall through to static path probes.
          end
        end

        wrapper_path = File.join(resolved_hdl_dir, 'gameboy.rb')
        return 'Gameboy' if File.file?(wrapper_path)

        nil
      end

      def resolve_top_module_name(component_class)
        if component_class.respond_to?(:verilog_module_name)
          raw = component_class.verilog_module_name.to_s
          return raw unless raw.empty?
        end

        underscore_name(component_class.name.to_s)
      end

      def build_input_port_aliases
        aliases = {}
        @component_input_ports.each do |name|
          aliases[name] = name if port_width_for(name) <= 32
        end
        aliases['clk_sys'] = resolve_port_name('clk_sys')
        aliases['reset'] = resolve_port_name('reset')
        aliases['joystick'] = resolve_port_name('joystick')
        aliases['is_gbc'] = resolve_port_name('is_gbc', 'isGBC')
        aliases['is_sgb'] = resolve_port_name('is_sgb', 'isSGB')
        aliases['cart_do'] = resolve_port_name('cart_do')
        aliases.compact
      end

      def build_output_port_aliases
        aliases = {}
        @component_output_ports.each do |name|
          aliases[name] = name if port_width_for(name) <= 32
        end

        aliases.merge!(
          {
          'ext_bus_addr' => resolve_port_name('ext_bus_addr'),
          'ext_bus_a15' => resolve_port_name('ext_bus_a15'),
          'cart_rd' => resolve_port_name('cart_rd'),
          'cart_wr' => resolve_port_name('cart_wr'),
          'cart_di' => resolve_port_name('cart_di'),
          'lcd_clkena' => resolve_port_name('lcd_clkena'),
          'lcd_data_gb' => resolve_port_name('lcd_data_gb'),
          'lcd_vsync' => resolve_port_name('lcd_vsync'),
          'lcd_on' => resolve_port_name('lcd_on'),
          'joystick' => resolve_port_name('joystick'),
          'debug_pc' => resolve_port_name('debug_pc', 'debug_cpu_pc'),
          'debug_acc' => resolve_port_name('debug_acc', 'debug_cpu_acc'),
          'debug_f' => resolve_port_name('debug_f'),
          'debug_b' => resolve_port_name('debug_b'),
          'debug_c' => resolve_port_name('debug_c'),
          'debug_d' => resolve_port_name('debug_d'),
          'debug_e' => resolve_port_name('debug_e'),
          'debug_h' => resolve_port_name('debug_h'),
          'debug_l' => resolve_port_name('debug_l'),
          'debug_sp' => resolve_port_name('debug_sp'),
          'debug_ir' => resolve_port_name('debug_ir'),
          'debug_save_alu' => resolve_port_name('debug_save_alu'),
          'debug_t_state' => resolve_port_name('debug_t_state'),
          'debug_m_cycle' => resolve_port_name('debug_m_cycle'),
          'debug_alu_flags' => resolve_port_name('debug_alu_flags'),
          'debug_clken' => resolve_port_name('debug_clken'),
          'debug_alu_op' => resolve_port_name('debug_alu_op'),
          'debug_bus_a' => resolve_port_name('debug_bus_a'),
          'debug_bus_b' => resolve_port_name('debug_bus_b'),
          'debug_alu_result' => resolve_port_name('debug_alu_result'),
          'debug_z_flag' => resolve_port_name('debug_z_flag'),
          'debug_bus_a_zero' => resolve_port_name('debug_bus_a_zero'),
          'debug_const_one' => resolve_port_name('debug_const_one')
        }
        )
        aliases.compact
      end

      def c_poke_dispatch_lines
        lines = []
        @input_port_aliases.each_with_index do |(api_name, port_name), idx|
          keyword = idx.zero? ? 'if' : 'else if'
          lines << "#{keyword} (strcmp(name, \"#{api_name}\") == 0) ctx->dut->#{port_name} = value;"
        end
        lines << '(void)name; (void)value;' if lines.empty?
        lines.map { |line| "      #{line}" }.join("\n")
      end

      def c_peek_dispatch_lines
        lines = []
        @output_port_aliases.each_with_index do |(api_name, port_name), idx|
          keyword = idx.zero? ? 'if' : 'else if'
          lines << "#{keyword} (strcmp(name, \"#{api_name}\") == 0) return ctx->dut->#{port_name};"
        end
        keyword = lines.empty? ? 'if' : 'else if'
        if @top_module_name == 'gb' && !direct_verilog_mode?
          lines << "#{keyword} (strcmp(name, \"cpu_pc_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_A;"
          lines << "else if (strcmp(name, \"cpu_addr_raw_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_A;"
          lines << "else if (strcmp(name, \"boot_rom_enabled_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_22_1;"
          lines << "else if (strcmp(name, \"boot_rom_addr_internal\") == 0) return ctx->dut->rootp->gb__DOT__boot_rom__DOT__address_a;"
          lines << "else if (strcmp(name, \"boot_rom_q_internal\") == 0) return ctx->dut->rootp->gb__DOT___boot_rom_q_a;"
          lines << "else if (strcmp(name, \"cart_do_internal\") == 0) return ctx->dut->rootp->gb__DOT__cart_do;"
          lines << "else if (strcmp(name, \"cart_oe_internal\") == 0) return ctx->dut->rootp->gb__DOT__cart_oe;"
          lines << "else if (strcmp(name, \"cpu_di_internal\") == 0) return ctx->dut->rootp->gb__DOT___GEN_178;"
          lines << "else if (strcmp(name, \"cpu_do_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_DO;"
          lines << "else if (strcmp(name, \"cpu_rd_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_RD_n;"
          lines << "else if (strcmp(name, \"cpu_wr_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_WR_n;"
          lines << "else if (strcmp(name, \"cpu_m1_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_M1_n;"
          lines << "else if (strcmp(name, \"cpu_clken_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__clken;"
          lines << "else if (strcmp(name, \"cpu_regdih_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regdih;"
          lines << "else if (strcmp(name, \"cpu_regdil_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regdil;"
          lines << "else if (strcmp(name, \"cpu_regweh_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regweh;"
          lines << "else if (strcmp(name, \"cpu_regwel_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regwel;"
          lines << "else if (strcmp(name, \"cpu_regaddra_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regaddra;"
          lines << "else if (strcmp(name, \"cpu_regbusa_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regbusa;"
          lines << "else if (strcmp(name, \"cpu_tmpaddr_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__tmpaddr;"
          lines << "else if (strcmp(name, \"cpu_id16_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__id16;"
          lines << "else if (strcmp(name, \"savestate_reset_out_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_reset_out;"
          lines << "else if (strcmp(name, \"savestate_sleep_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_sleep_savestate;"
          lines << "else if (strcmp(name, \"request_loadstate_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_loadstate;"
          lines << "else if (strcmp(name, \"request_savestate_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_savestate;"
        elsif normalized_direct_verilog_gb?
          lines << "#{keyword} (strcmp(name, \"cpu_pc_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__pc;"
          lines << "else if (strcmp(name, \"cpu_addr_internal\") == 0) return ctx->dut->rootp->gb__DOT___md_swizz_a_out;"
          lines << "else if (strcmp(name, \"cpu_addr_raw_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_A;"
          lines << "else if (strcmp(name, \"cpu_di_reg_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__di_reg;"
          lines << "else if (strcmp(name, \"cpu_t80_di_reg_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__di_reg;"
          lines << "else if (strcmp(name, \"cpu_set_addr_to_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__set_addr_to;"
          lines << "else if (strcmp(name, \"cpu_iorq_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__iorq_i;"
          lines << "else if (strcmp(name, \"cpu_mcycle_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__mcycle;"
          lines << "else if (strcmp(name, \"cpu_tstate_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__tstate;"
          lines << "else if (strcmp(name, \"cpu_save_mux_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__save_mux;"
          lines << "else if (strcmp(name, \"cpu_save_alu_r_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__save_alu_r;"
          lines << "else if (strcmp(name, \"cpu_clken_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__clken;"
          lines << "else if (strcmp(name, \"cpu_regdih_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regdih;"
          lines << "else if (strcmp(name, \"cpu_regdil_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regdil;"
          lines << "else if (strcmp(name, \"cpu_regweh_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regweh;"
          lines << "else if (strcmp(name, \"cpu_regwel_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regwel;"
          lines << "else if (strcmp(name, \"cpu_regaddra_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regaddra;"
          lines << "else if (strcmp(name, \"cpu_regbusa_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regbusa;"
          lines << "else if (strcmp(name, \"cpu_regbusc_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regbusc;"
          lines << "else if (strcmp(name, \"cpu_tmpaddr_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__tmpaddr;"
          lines << "else if (strcmp(name, \"cpu_id16_internal\") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__id16;"
          lines << "else if (strcmp(name, \"boot_rom_enabled_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_22_1;"
          lines << "else if (strcmp(name, \"boot_rom_addr_internal\") == 0) return ctx->dut->rootp->gb__DOT__boot_rom__DOT__address_a;"
          lines << "else if (strcmp(name, \"boot_rom_q_internal\") == 0) return ctx->dut->rootp->gb__DOT___boot_rom_q_a;"
          lines << "else if (strcmp(name, \"cart_do_internal\") == 0) return ctx->dut->rootp->gb__DOT__cart_do;"
          lines << "else if (strcmp(name, \"cart_oe_internal\") == 0) return ctx->dut->rootp->gb__DOT__cart_oe;"
          lines << "else if (strcmp(name, \"cpu_di_internal\") == 0) return ctx->dut->rootp->gb__DOT___GEN_178;"
          lines << "else if (strcmp(name, \"cpu_do_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_DO;"
          lines << "else if (strcmp(name, \"cpu_rd_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_RD_n;"
          lines << "else if (strcmp(name, \"cpu_wr_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_WR_n;"
          lines << "else if (strcmp(name, \"cpu_m1_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_M1_n;"
          lines << "else if (strcmp(name, \"interrupt_flags_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_11_8;"
          lines << "else if (strcmp(name, \"interrupt_enable_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_12_5;"
          lines << "else if (strcmp(name, \"old_vblank_irq_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_13_1;"
          lines << "else if (strcmp(name, \"old_video_irq_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_14_1;"
          lines << "else if (strcmp(name, \"old_timer_irq_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_15_1;"
          lines << "else if (strcmp(name, \"old_serial_irq_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_16_1;"
          lines << "else if (strcmp(name, \"old_ack_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_17_1;"
          lines << "else if (strcmp(name, \"irq_ack_internal\") == 0) return (~ctx->dut->rootp->gb__DOT___cpu_IORQ_n & ~ctx->dut->rootp->gb__DOT___cpu_M1_n) ? 1u : 0u;"
          lines << "else if (strcmp(name, \"video_irq_internal\") == 0) return ctx->dut->rootp->gb__DOT___video_irq;"
          lines << "else if (strcmp(name, \"video_vblank_irq_internal\") == 0) return ctx->dut->rootp->gb__DOT___video_vblank_irq;"
          lines << "else if (strcmp(name, \"sel_ff50_internal\") == 0) return ctx->dut->rootp->gb__DOT___md_swizz_a_out == 0xFF50u ? 1u : 0u;"
          lines << "else if (strcmp(name, \"savestate_reset_out_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_reset_out;"
          lines << "else if (strcmp(name, \"savestate_sleep_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_sleep_savestate;"
          lines << "else if (strcmp(name, \"request_loadstate_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_loadstate;"
          lines << "else if (strcmp(name, \"request_savestate_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_savestate;"
          lines << "else if (strcmp(name, \"video_lcd_on_internal\") == 0) return ctx->dut->rootp->gb__DOT__video__DOT__lcd_on;"
          lines << "else if (strcmp(name, \"video_lcd_clkena_internal\") == 0) return ctx->dut->rootp->gb__DOT__video__DOT__lcd_clkena;"
          lines << "else if (strcmp(name, \"video_lcd_vsync_internal\") == 0) return ctx->dut->rootp->gb__DOT__video__DOT__lcd_vsync;"
          lines << "else if (strcmp(name, \"video_mode_internal\") == 0) return ctx->dut->rootp->gb__DOT___video_mode;"
        elsif direct_verilog_import_wrapper_gameboy?
          lines << "#{keyword} (strcmp(name, \"cpu_pc_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__pc;"
          lines << "else if (strcmp(name, \"cpu_addr_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___md_swizz_a_out;"
          lines << "else if (strcmp(name, \"cpu_addr_raw_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_A;"
          lines << "else if (strcmp(name, \"cpu_di_reg_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__di_reg;"
          lines << "else if (strcmp(name, \"cpu_t80_di_reg_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__di_reg;"
          lines << "else if (strcmp(name, \"cpu_set_addr_to_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__set_addr_to;"
          lines << "else if (strcmp(name, \"cpu_iorq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__iorq_i;"
          lines << "else if (strcmp(name, \"cpu_mcycle_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__mcycle;"
          lines << "else if (strcmp(name, \"cpu_tstate_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__tstate;"
          lines << "else if (strcmp(name, \"cpu_save_mux_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__save_mux;"
          lines << "else if (strcmp(name, \"cpu_save_alu_r_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__save_alu_r;"
          lines << "else if (strcmp(name, \"cpu_clken_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__clken;"
          lines << "else if (strcmp(name, \"cpu_regdih_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regdih;"
          lines << "else if (strcmp(name, \"cpu_regdil_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regdil;"
          lines << "else if (strcmp(name, \"cpu_regweh_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regweh;"
          lines << "else if (strcmp(name, \"cpu_regwel_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regwel;"
          lines << "else if (strcmp(name, \"cpu_regaddra_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regaddra;"
          lines << "else if (strcmp(name, \"cpu_regbusa_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regbusa;"
          lines << "else if (strcmp(name, \"cpu_regbusc_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regbusc;"
          lines << "else if (strcmp(name, \"cpu_tmpaddr_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__tmpaddr;"
          lines << "else if (strcmp(name, \"cpu_id16_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__id16;"
          lines << "else if (strcmp(name, \"boot_rom_enabled_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_22_1;"
          lines << "else if (strcmp(name, \"boot_rom_q_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___boot_rom_q_a;"
          lines << "else if (strcmp(name, \"cpu_di_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___GEN_178;"
          lines << "else if (strcmp(name, \"cpu_rd_n_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_RD_n;"
          lines << "else if (strcmp(name, \"cpu_wr_n_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_WR_n;"
          lines << "else if (strcmp(name, \"cpu_m1_n_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_M1_n;"
          lines << "else if (strcmp(name, \"interrupt_flags_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_11_8;"
          lines << "else if (strcmp(name, \"interrupt_enable_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_12_5;"
          lines << "else if (strcmp(name, \"old_vblank_irq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_13_1;"
          lines << "else if (strcmp(name, \"old_video_irq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_14_1;"
          lines << "else if (strcmp(name, \"old_timer_irq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_15_1;"
          lines << "else if (strcmp(name, \"old_serial_irq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_16_1;"
          lines << "else if (strcmp(name, \"old_ack_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_17_1;"
          lines << "else if (strcmp(name, \"irq_ack_internal\") == 0) return (~ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_IORQ_n & ~ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_M1_n) ? 1u : 0u;"
          lines << "else if (strcmp(name, \"video_irq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___video_irq;"
          lines << "else if (strcmp(name, \"video_vblank_irq_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___video_vblank_irq;"
          lines << "else if (strcmp(name, \"sel_ff50_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___md_swizz_a_out == 0xFF50u ? 1u : 0u;"
          lines << "else if (strcmp(name, \"savestate_reset_out_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___gb_savestates_reset_out;"
          lines << "else if (strcmp(name, \"savestate_sleep_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___gb_savestates_sleep_savestate;"
          lines << "else if (strcmp(name, \"request_loadstate_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___gb_statemanager_request_loadstate;"
          lines << "else if (strcmp(name, \"request_savestate_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___gb_statemanager_request_savestate;"
          lines << "else if (strcmp(name, \"video_lcd_on_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__video__DOT__lcd_on;"
          lines << "else if (strcmp(name, \"video_lcd_clkena_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__video__DOT__lcd_clkena;"
          lines << "else if (strcmp(name, \"video_lcd_vsync_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__video__DOT__lcd_vsync;"
          lines << "else if (strcmp(name, \"video_mode_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___video_mode;"
          lines << "else if (strcmp(name, \"ce_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__ce;"
          lines << "else if (strcmp(name, \"ce_n_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__ce_n;"
          lines << "else if (strcmp(name, \"ce_2x_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__ce_2x;"
          lines << "else if (strcmp(name, \"boot_upload_active_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__boot_upload_active;"
          lines << "else if (strcmp(name, \"boot_upload_phase_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__boot_upload_phase;"
          lines << "else if (strcmp(name, \"boot_upload_index_internal\") == 0) return ctx->dut->rootp->gameboy__DOT__boot_upload_index;"
        elsif @top_module_name == 'gameboy'
          lines << "#{keyword} (strcmp(name, \"cpu_pc_internal\") == 0) return ctx->last_fetch_addr;"
          lines << "else if (strcmp(name, \"boot_rom_enabled_internal\") == 0) return 0;"
          lines << "else if (strcmp(name, \"boot_rom_q_internal\") == 0) return 0;"
          lines << "else if (strcmp(name, \"sel_ff50_internal\") == 0) return 0;"
        else
          lines << "#{keyword} (strcmp(name, \"cpu_pc_internal\") == 0) return ctx->last_fetch_addr;"
        end
        lines.map { |line| "      #{line}" }.join("\n")
      end

      def c_boot_rom_feed_lines(indent:)
        boot_addr_port = resolve_port_name('boot_rom_addr')
        boot_data_port = resolve_port_name('boot_rom_do')
        return '' unless boot_addr_port && boot_data_port

        [
          "#{indent}ctx->dut->#{boot_data_port} = ctx->boot_rom[ctx->dut->#{boot_addr_port} & 0xFFu];"
        ].join("\n")
      end

      def c_cart_feed_lines(indent:)
        cart_addr_port = resolve_port_name('ext_bus_addr')
        cart_a15_port = resolve_port_name('ext_bus_a15')
        cart_do_port = resolve_port_name('cart_do')
        cart_oe_port = resolve_port_name('cart_oe')
        cart_wr_port = resolve_port_name('cart_wr')
        cart_di_port = resolve_port_name('cart_di')
        cart_rd_port = resolve_port_name('cart_rd')
        return '' unless cart_addr_port && cart_a15_port && cart_do_port

        lines = [
          "#{indent}{",
          "#{indent}    unsigned int addr = ctx->dut->#{cart_addr_port};",
          "#{indent}    unsigned int a15 = ctx->dut->#{cart_a15_port} & 0x1u;",
          "#{indent}    unsigned int full_addr = (a15 << 15) | addr;",
          "#{indent}    ctx->cart_last_full_addr = full_addr;"
        ]
        if cart_wr_port && cart_di_port
          lines << "#{indent}    if (!ctx->dut->reset && ctx->dut->#{cart_wr_port}) cart_handle_write(ctx, full_addr, ctx->dut->#{cart_di_port} & 0xFFu);"
        end
        if immediate_cartridge_response?
          read_active_expr = cart_rd_port ? "ctx->dut->#{cart_rd_port} ? 1u : 0u" : '0u'
          lines << "#{indent}    unsigned int read_active = #{read_active_expr};"
          lines << "#{indent}    ctx->dut->#{cart_oe_port} = 1u;" if cart_oe_port
          lines << "#{indent}    ctx->dut->#{cart_do_port} = read_active ? cart_read_byte(ctx, full_addr) : 0xFFu;"
          lines << "#{indent}    if (read_active) ctx->last_fetch_addr = full_addr;"
          lines << "#{indent}    ctx->cart_last_rd = static_cast<unsigned char>(read_active);"
        else
          lines << "#{indent}    ctx->dut->#{cart_oe_port} = 1u;" if cart_oe_port
          lines << "#{indent}    ctx->dut->#{cart_do_port} = ctx->cart_do_latched;"
          if cart_rd_port
            lines << "#{indent}    if (ctx->dut->#{cart_rd_port}) ctx->last_fetch_addr = full_addr;"
            lines << "#{indent}    ctx->cart_last_rd = ctx->dut->#{cart_rd_port} ? 1u : 0u;"
          else
            lines << "#{indent}    ctx->cart_last_rd = 0u;"
          end
        end
        lines << "#{indent}}"
        lines.join("\n")
      end

      def c_joypad_drive_lines(indent:)
        joystick_port = resolve_port_name('joystick')
        joy_din_port = resolve_port_name('joy_din')
        joy_p54_port = resolve_port_name('joy_p54')
        return '' unless joystick_port && joy_din_port && joy_p54_port

        [
          "#{indent}{",
          "#{indent}unsigned int joy = ctx->dut->#{joystick_port} & 0xFF;",
          "#{indent}unsigned int joy_p54 = ctx->dut->#{joy_p54_port} & 0x3;",
          "#{indent}unsigned int p14 = joy_p54 & 0x1;",
          "#{indent}unsigned int p15 = (joy_p54 >> 1) & 0x1;",
          "#{indent}unsigned int joy_dir = joy & 0xF;",
          "#{indent}unsigned int joy_btn = (joy >> 4) & 0xF;",
          "#{indent}unsigned int joy_dir_masked = joy_dir | (p14 ? 0xF : 0x0);",
          "#{indent}unsigned int joy_btn_masked = joy_btn | (p15 ? 0xF : 0x0);",
          "#{indent}ctx->dut->#{joy_din_port} = joy_dir_masked & joy_btn_masked;",
          "#{indent}}"
        ].join("\n")
      end

      def c_ce_drive_lines(indent:)
        ce_port = resolve_port_name('ce')
        ce_n_port = resolve_port_name('ce_n')
        ce_2x_port = resolve_port_name('ce_2x')
        return '' unless ce_port || ce_n_port || ce_2x_port

        lines = []
        lines << "#{indent}{"
        lines << "#{indent}unsigned int ce_phase = ctx->clk_counter & 0x7u;"
        lines << "#{indent}ctx->dut->#{ce_port} = (ce_phase == 0u) ? 1u : 0u;" if ce_port
        lines << "#{indent}ctx->dut->#{ce_n_port} = (ce_phase == 4u) ? 1u : 0u;" if ce_n_port
        lines << "#{indent}ctx->dut->#{ce_2x_port} = ((ce_phase & 0x3u) == 0u) ? 1u : 0u;" if ce_2x_port
        lines << "#{indent}}"
        lines.join("\n")
      end

      def c_constant_tieoff_lines(indent:)
        lines = []

        if resolve_port_name('gg_code') && @top_module_name == 'gb'
          lines << "#{indent}for (int i = 0; i < 5; ++i) ctx->dut->gg_code[i] = 0u;"
        end

        save_state_ext_dout_port = resolve_port_name('SaveStateExt_Dout')
        lines << "#{indent}ctx->dut->#{save_state_ext_dout_port} = 0ULL;" if save_state_ext_dout_port

        save_out_dout_port = resolve_port_name('SAVE_out_Dout')
        lines << "#{indent}ctx->dut->#{save_out_dout_port} = 0ULL;" if save_out_dout_port

        lines.join("\n")
      end

      def resolve_port_name(*candidates)
        candidates.map(&:to_s).find { |name| @component_ports.include?(name) }
      end

      def port_width_for(name)
        @component_port_widths.fetch(name.to_s, 1)
      end

      def sanitize_identifier(value)
        value.to_s.gsub(/[^A-Za-z0-9_]/, '_')
      end

      def build_artifact_stem
        @build_artifact_stem ||= "#{sanitize_identifier(@top_module_name)}_#{build_cache_suffix}"
      end

      def build_cache_suffix
        @build_cache_suffix ||= begin
          native_wrapper_signature =
            if @component_ports
              [
                c_cart_feed_lines(indent: 'cache'),
                c_peek_dispatch_lines,
                c_constant_tieoff_lines(indent: 'cache')
              ].join('|')
            else
              'ports_uninitialized'
            end
          cache_parts = [
            @top_module_name.to_s,
            @resolved_hdl_dir.to_s,
            @resolved_verilog_dir.to_s,
            @import_top_name.to_s,
            direct_verilog_mode? ? 'direct_verilog' : (@use_staged_verilog ? 'staged' : 'generated'),
            selected_verilog_source_path.to_s,
            native_wrapper_signature
          ]
          if direct_verilog_mode? && @direct_verilog_source_plan[:wrapper_source]
            cache_parts << Digest::SHA1.hexdigest(@direct_verilog_source_plan[:wrapper_source])
          end
          Digest::SHA1.hexdigest(cache_parts.join('|'))[0, 12]
        end
      end

      def source_dependency_paths
        return direct_verilog_dependency_paths if direct_verilog_mode?

        hdl_source_dependency_paths
      end

      def hdl_source_dependency_paths
        paths = []
        wrapper_path = File.expand_path('../../hdl/gameboy.rb', __dir__)
        loader_path = File.expand_path('../hdl_loader.rb', __dir__)
        speedcontrol_path = File.expand_path('../../hdl/speedcontrol.rb', __dir__)
        paths << wrapper_path if File.file?(wrapper_path)
        paths << loader_path if File.file?(loader_path)
        paths << speedcontrol_path if File.file?(speedcontrol_path)

        if @resolved_hdl_dir && Dir.exist?(@resolved_hdl_dir)
          paths.concat(Dir.glob(File.join(@resolved_hdl_dir, '**', '*.rb')))
        end

        staged_verilog = runtime_staged_verilog_entry
        paths << staged_verilog if staged_verilog && File.file?(staged_verilog)
        paths.uniq
      end

      def direct_verilog_dependency_paths
        Array(@direct_verilog_source_plan && @direct_verilog_source_plan[:dependency_paths]).select { |path| File.file?(path) }.uniq
      end

      def direct_verilog_mode?
        !@direct_verilog_source_plan.nil?
      end

      def normalized_direct_verilog_gb?
        return false unless direct_verilog_mode?
        return false unless @top_module_name == 'gb'

        source_path = @direct_verilog_source_plan[:source_verilog_path].to_s
        File.basename(source_path).end_with?('.normalized.v')
      end

      def direct_verilog_import_wrapper_gameboy?
        return false unless direct_verilog_mode?
        return false unless @top_module_name == 'gameboy'

        source_path = @direct_verilog_source_plan[:source_verilog_path].to_s
        File.basename(source_path).end_with?('.normalized.v')
      end

      def immediate_cartridge_response?
        direct_verilog_mode?
      end

      def selected_verilog_source_path
        return @direct_verilog_source_plan[:source_verilog_path] if direct_verilog_mode?

        runtime_staged_verilog_entry
      end

      def runtime_staged_verilog_entry
        return nil unless @resolved_hdl_dir
        return nil unless @use_staged_verilog
        return nil unless staged_verilog_supported_for_selected_top?

        report_path = File.expand_path(File.join(@resolved_hdl_dir, 'import_report.json'))
        if File.file?(report_path)
          begin
            report = JSON.parse(File.read(report_path))
            artifacts = report['artifacts']
            mixed = report['mixed_import']
            if mixed.is_a?(Hash) || artifacts.is_a?(Hash)
              candidates = [
                artifacts.is_a?(Hash) ? artifacts['normalized_verilog_path'] : nil,
                mixed.is_a?(Hash) ? mixed['normalized_verilog_path'] : nil,
                artifacts.is_a?(Hash) ? artifacts['pure_verilog_entry_path'] : nil,
                mixed.is_a?(Hash) ? mixed['pure_verilog_entry_path'] : nil
              ].compact
              candidate = candidates.find { |path| File.file?(path) }
              return File.expand_path(candidate) if candidate
            end
          rescue JSON::ParserError
            # Fall back to static path probes below.
          end
        end

        runtime_candidate = File.expand_path(File.join(@resolved_hdl_dir, '.mixed_import', 'gb.normalized.v'))
        return runtime_candidate if File.file?(runtime_candidate)

        staged_candidate = File.expand_path(File.join(@resolved_hdl_dir, '.mixed_import', 'pure_verilog_entry.v'))
        return staged_candidate if File.file?(staged_candidate)

        nil
      end

      def staged_verilog_supported_for_selected_top?
        selected_top = (@import_top_name || @top_module_name).to_s
        selected_top == 'gb'
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

      def underscore_name(name)
        name
          .to_s
          .gsub('::', '_')
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      def verilog_simulator
        @verilog_simulator ||= RHDL::Codegen::Verilog::VerilogSimulator.new(
          backend: :verilator,
          build_dir: BUILD_DIR,
          library_basename: "gameboy_sim_#{build_artifact_stem}",
          top_module: @top_module_name,
          verilator_prefix: @verilator_prefix,
          extra_verilator_flags: ['--public-flat-rw', *VERILATOR_WARN_FLAGS]
        )
      end

      def check_verilator_available!
        verilog_simulator.ensure_backend_available!
      end

      def build_verilator_simulation
        verilog_simulator.prepare_build_dirs!

        stem = build_artifact_stem
        verilog_files = nil
        verilog_file = nil
        if direct_verilog_mode?
          verilog_files = direct_verilog_compile_files(stem: stem)
          log "  Using direct Verilog sources: #{verilog_files.join(', ')}"
        else
          verilog_file = runtime_staged_verilog_entry
          if verilog_file
            log "  Using staged mixed-source Verilog: #{verilog_file}"
          else
            verilog_file = File.join(VERILOG_DIR, "gameboy_#{stem}.v")
            verilog_codegen = File.expand_path('../../../../lib/rhdl/dsl/codegen.rb', __dir__)
            circt_codegen = File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__)
            export_deps = [__FILE__, verilog_codegen, circt_codegen, *hdl_source_dependency_paths].select { |p| File.exist?(p) }
            needs_export = !File.exist?(verilog_file) ||
                           export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

            if needs_export
              log "  Exporting #{@component_class} to Verilog..."
              export_verilog(verilog_file)
            end
          end
        end

        # Create C++ wrapper
        wrapper_file = File.join(VERILOG_DIR, "sim_wrapper_#{stem}.cpp")
        header_file = File.join(VERILOG_DIR, "sim_wrapper_#{stem}.h")
        create_cpp_wrapper(wrapper_file, header_file)

        # Check if we need to rebuild
        lib_file = shared_lib_path
        simulator_codegen = File.expand_path('../../../../lib/rhdl/codegen/verilog/sim/verilog_simulator.rb', __dir__)
        build_inputs = verilog_files || [verilog_file]
        build_deps = [*build_inputs, wrapper_file, header_file, __FILE__, simulator_codegen, *source_dependency_paths].select do |path|
          File.exist?(path)
        end
        needs_build = !File.exist?(lib_file) ||
                      build_deps.any? { |path| File.mtime(path) > File.mtime(lib_file) }

        if needs_build
          log "  Compiling with Verilator..."
          compile_verilator(verilog_files || verilog_file, wrapper_file)
        end

        # Load the shared library
        log "  Loading Verilator simulation..."
        load_shared_library(lib_file)
      end

      def export_verilog(output_file)
        # Export selected top via CIRCT-backed DSL codegen.
        all_verilog = @component_class.to_verilog

        # Post-process for Verilator compatibility
        all_verilog = make_verilator_compatible(all_verilog)

        File.write(output_file, all_verilog)
      end

      def make_verilator_compatible(verilog)
        # Add Verilator lint pragmas at the top
        pragmas = <<~PRAGMAS
          /* verilator lint_off IMPLICIT */
          /* verilator lint_off UNUSED */
          /* verilator lint_off UNDRIVEN */
          /* verilator lint_off PINMISSING */

        PRAGMAS

        verilog = pragmas + verilog

        # Replace true/false with 1'b1/1'b0
        verilog = verilog.gsub(/\(true\)/, "(1'b1)")
        verilog = verilog.gsub(/\(false\)/, "(1'b0)")
        verilog = verilog.gsub(/= true\b/, "= 1'b1")
        verilog = verilog.gsub(/= false\b/, "= 1'b0")

        # Remove default values from input declarations
        # Pattern: input name = value -> input name
        verilog = verilog.gsub(/^(\s*input\s+(?:\[[^\]]+\]\s+)?(\w+))\s*=\s*[^,;\n]+([,;])/) do
          "#{$1}#{$3}"
        end

        # Replace reduce_or(expr) with |expr
        verilog = verilog.gsub(/reduce_or\(([^)]+)\)/, '|\1')

        # Replace reduce_and(expr) with &expr
        verilog = verilog.gsub(/reduce_and\(([^)]+)\)/, '&\1')

        # Replace reduce_xor(expr) with ^expr
        verilog = verilog.gsub(/reduce_xor\(([^)]+)\)/, '^\1')

        # Remove parameter overrides that don't exist in module definitions
        # Pattern: game_boy_dpram #(.addr_width(N)) name -> game_boy_dpram name
        verilog = verilog.gsub(/game_boy_dpram\s+#\(\s*\.addr_width\(\d+\)\s*\)\s+(\w+)/, 'game_boy_dpram \1')
        verilog = verilog.gsub(/game_boy_spram\s+#\(\s*\.addr_width\(\d+\)\s*\)\s+(\w+)/, 'game_boy_spram \1')
        verilog = verilog.gsub(/game_boy_channel_square\s+#\(\s*\.has_sweep\([^)]+\)\s*\)\s+(\w+)/, 'game_boy_channel_square \1')

        # Fix unsized constants in concatenations: {0'd0, -> {1'b0,
        verilog = verilog.gsub(/\{0'd0,/, "{1'b0,")

        # Fix DPRAM outputs - they should be reg not wire since assigned in always blocks
        # Pattern: output [7:0] q_a, -> output reg [7:0] q_a,
        verilog = verilog.gsub(/output\s+(\[\d+:\d+\]\s+)(q_a|q_b)/, 'output reg \1\2')
        verilog = verilog.gsub(/output\s+(q_a|q_b)/, 'output reg \1')

        # Fix SPRAM outputs - data_out should be reg since assigned in always block
        verilog = verilog.gsub(/output\s+(\[\d+:\d+\]\s+)(data_out)(\s*[;)])/, 'output reg \1\2\3')
        verilog = verilog.gsub(/output\s+(data_out)(\s*[;)])/, 'output reg \1\2')

        verilog
      end

      def direct_verilog_compile_files(stem:)
        files = [
          @direct_verilog_source_plan.fetch(:source_verilog_path),
          *Array(@direct_verilog_source_plan[:support_verilog_paths])
        ].uniq
        wrapper_source = @direct_verilog_source_plan[:wrapper_source]
        return files unless wrapper_source

        wrapper_path = File.join(VERILOG_DIR, "gameboy_direct_wrapper_#{stem}.v")
        write_file_if_changed(wrapper_path, wrapper_source)
        files << wrapper_path
        files
      end

      def create_cpp_wrapper(cpp_file, header_file)
        header_content = <<~HEADER
          #ifndef SIM_WRAPPER_H
          #define SIM_WRAPPER_H

          #ifdef __cplusplus
          extern "C" {
          #endif

          // Lifecycle
          void* sim_create(void);
          void sim_destroy(void* sim);
          void sim_reset(void* sim);
          void sim_eval(void* sim);

          // Signal access
          void sim_poke(void* sim, const char* name, unsigned int value);
          unsigned int sim_peek(void* sim, const char* name);

          // Memory access
          void sim_load_rom(void* sim, const unsigned char* data, unsigned int len);
          void sim_load_boot_rom(void* sim, const unsigned char* data, unsigned int len);
          unsigned char sim_read_boot_rom(void* sim, unsigned int addr);
          void sim_write_vram(void* sim, unsigned int addr, unsigned char value);
          unsigned char sim_read_vram(void* sim, unsigned int addr);

          // Framebuffer access
          void sim_read_framebuffer(void* sim, unsigned char* out_buffer);
          unsigned long sim_get_frame_count(void* sim);

          // Cycle result struct
          struct GbCycleResult {
              unsigned long cycles_run;
              unsigned int frames_completed;
          };

          // Batch execution
          void sim_run_cycles(void* sim, unsigned int n_cycles, struct GbCycleResult* result);

          #ifdef __cplusplus
          }
          #endif

          #endif // SIM_WRAPPER_H
        HEADER

        poke_dispatch = c_poke_dispatch_lines
        peek_dispatch = c_peek_dispatch_lines
        boot_feed = c_boot_rom_feed_lines(indent: '        ')
        cart_feed = c_cart_feed_lines(indent: '        ')
        joypad_feed = c_joypad_drive_lines(indent: '        ')
        ce_feed_low = c_ce_drive_lines(indent: '        ')
        ce_feed_high = c_ce_drive_lines(indent: '        ')
        reset_cycle_advance = '              ctx->clk_counter++;'
        constant_tieoffs = c_constant_tieoff_lines(indent: '        ')

        cpp_content = <<~CPP
          #include "#{@verilator_prefix}.h"
          #include "#{@verilator_prefix}___024root.h"  // For internal signal access
          #include "verilated.h"
          #include "sim_wrapper.h"
          #include <cstring>

          // Verilator runtime expects this symbol when linking libverilated.
          // Our simulation doesn't use SystemC time, so return 0.
          double sc_time_stamp() { return 0; }

          struct SimContext {
              #{@verilator_prefix}* dut;
              unsigned char rom[1048576];     // 1MB ROM
              unsigned char boot_rom[256];    // 256 byte DMG boot ROM
              unsigned char vram[8192];       // 8KB VRAM
              unsigned char framebuffer[160 * 144];  // Framebuffer
              unsigned int lcd_x;
              unsigned int lcd_y;
              unsigned char prev_lcd_clkena;
              unsigned char prev_lcd_vsync;
              unsigned long frame_count;
              unsigned int last_fetch_addr;
              unsigned int clk_counter;       // System clock counter for CPU cycle estimation
              unsigned char cart_type;
              unsigned char rom_size_code;
              unsigned char ram_size_code;
              unsigned short rom_bank_count;
              unsigned char mbc1_rom_bank_low5;
              unsigned char mbc1_bank_upper2;
              unsigned char mbc1_mode;
              unsigned char mbc1_ram_enabled;
              unsigned char cart_do_latched;
              unsigned char cart_oe_latched;
              unsigned int cart_read_pipeline[6];
              unsigned char cart_read_valid[6];
              unsigned int cart_last_full_addr;
              unsigned char cart_last_rd;
          };

          static unsigned short cart_rom_bank_count(unsigned char rom_size_code) {
              switch (rom_size_code) {
                  case 0x00: return 2;
                  case 0x01: return 4;
                  case 0x02: return 8;
                  case 0x03: return 16;
                  case 0x04: return 32;
                  case 0x05: return 64;
                  case 0x06: return 128;
                  case 0x07: return 256;
                  case 0x08: return 512;
                  case 0x52: return 72;
                  case 0x53: return 80;
                  case 0x54: return 96;
                  default: return 2;
              }
          }

          static bool cart_is_mbc1(const SimContext* ctx) {
              return ctx->cart_type == 0x01 || ctx->cart_type == 0x02 || ctx->cart_type == 0x03;
          }

          static void cart_reset_runtime_state(SimContext* ctx) {
              ctx->mbc1_rom_bank_low5 = 1;
              ctx->mbc1_bank_upper2 = 0;
              ctx->mbc1_mode = 0;
              ctx->mbc1_ram_enabled = 0;
              ctx->cart_do_latched = 0xFFu;
              ctx->cart_oe_latched = 0u;
              memset(ctx->cart_read_pipeline, 0, sizeof(ctx->cart_read_pipeline));
              memset(ctx->cart_read_valid, 0, sizeof(ctx->cart_read_valid));
              ctx->cart_last_full_addr = 0u;
              ctx->cart_last_rd = 0u;
          }

          static unsigned char cart_read_byte(const SimContext* ctx, unsigned int full_addr) {
              unsigned int addr = full_addr & 0xFFFFu;
              if (!cart_is_mbc1(ctx)) {
                  return (addr < sizeof(ctx->rom)) ? ctx->rom[addr] : 0xFFu;
              }
              if (addr > 0x7FFFu) return 0xFFu;

              unsigned int bank = 0;
              if (addr <= 0x3FFFu) {
                  bank = ctx->mbc1_mode ? ((ctx->mbc1_bank_upper2 & 0x3u) << 5) : 0u;
              } else {
                  unsigned int low = ctx->mbc1_rom_bank_low5 & 0x1Fu;
                  if (low == 0u) low = 1u;
                  bank = ((ctx->mbc1_bank_upper2 & 0x3u) << 5) | low;
              }
              unsigned int bank_count = ctx->rom_bank_count ? ctx->rom_bank_count : 1u;
              bank %= bank_count;
              unsigned int index = bank * 0x4000u + (addr & 0x3FFFu);
              return (index < sizeof(ctx->rom)) ? ctx->rom[index] : 0xFFu;
          }

          static unsigned char cart_output_enable(const SimContext* ctx, unsigned int full_addr) {
              unsigned int addr = full_addr & 0xFFFFu;
              if (addr <= 0x7FFFu) return 1u;
              if (cart_is_mbc1(ctx) && addr >= 0xA000u && addr <= 0xBFFFu) return ctx->mbc1_ram_enabled ? 1u : 0u;
              return 0u;
          }

          static void cart_handle_write(SimContext* ctx, unsigned int full_addr, unsigned char value) {
              if (!cart_is_mbc1(ctx)) return;

              unsigned int addr = full_addr & 0x7FFFu;
              if (addr <= 0x1FFFu) {
                  ctx->mbc1_ram_enabled = ((value & 0x0Fu) == 0x0Au) ? 1u : 0u;
              } else if (addr <= 0x3FFFu) {
                  unsigned int bank = value & 0x1Fu;
                  ctx->mbc1_rom_bank_low5 = bank == 0u ? 1u : bank;
              } else if (addr <= 0x5FFFu) {
                  ctx->mbc1_bank_upper2 = value & 0x03u;
              } else if (addr <= 0x7FFFu) {
                  ctx->mbc1_mode = value & 0x01u;
              }
          }

          static void cart_advance_read_pipeline(SimContext* ctx) {
      #{if immediate_cartridge_response?
          <<~CPP.chomp
              (void)ctx;
          CPP
        else
          <<~CPP.chomp
              for (int i = 5; i > 0; --i) {
                  ctx->cart_read_pipeline[i] = ctx->cart_read_pipeline[i - 1];
                  ctx->cart_read_valid[i] = ctx->cart_read_valid[i - 1];
              }
              ctx->cart_read_pipeline[0] = ctx->cart_last_full_addr;
              ctx->cart_read_valid[0] = ctx->cart_last_rd;
              if (ctx->cart_read_valid[5]) {
                  ctx->cart_do_latched = cart_read_byte(ctx, ctx->cart_read_pipeline[5]);
                  ctx->cart_oe_latched = cart_output_enable(ctx, ctx->cart_read_pipeline[5]);
              } else {
                  ctx->cart_oe_latched = 0u;
              }
          CPP
        end}
          }

          extern "C" {

          void* sim_create(void) {
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);
              SimContext* ctx = new SimContext();
              ctx->dut = new #{@verilator_prefix}();
              memset(ctx->rom, 0, sizeof(ctx->rom));
              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
              memset(ctx->vram, 0, sizeof(ctx->vram));
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0;
              ctx->lcd_y = 0;
              ctx->prev_lcd_clkena = 0;
              ctx->prev_lcd_vsync = 0;
              ctx->frame_count = 0;
              ctx->last_fetch_addr = 0;
              ctx->clk_counter = 0;
              ctx->cart_type = 0;
              ctx->rom_size_code = 0;
              ctx->ram_size_code = 0;
              ctx->rom_bank_count = 2;
              cart_reset_runtime_state(ctx);
      #{constant_tieoffs}
              return ctx;
          }

          void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
          }

          void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              cart_reset_runtime_state(ctx);
              ctx->clk_counter = 0;
      #{constant_tieoffs}
              // Hold reset high and clock a few times to properly reset sequential logic
              ctx->dut->reset = 1;
              for (int i = 0; i < 10; i++) {
                  ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->eval();
                  ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                  ctx->dut->eval();
                  #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->eval();
                  cart_advance_read_pipeline(ctx);
      #{reset_cycle_advance}
              }
        #{if @top_module_name == 'gb'
            <<~CPP.chomp
                  ctx->dut->dmg_boot_download = 1;
                  for (unsigned int i = 0; i < 128; ++i) {
                      unsigned int lo = ctx->boot_rom[i * 2];
                      unsigned int hi = ctx->boot_rom[(i * 2) + 1];
                  ctx->dut->ioctl_addr = i * 2;
                  ctx->dut->ioctl_dout = (hi << 8) | lo;
                  ctx->dut->ioctl_wr = 1;
                      ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                      ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                      ctx->dut->eval();
                      ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                      ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                      ctx->dut->eval();
                      cart_advance_read_pipeline(ctx);
      #{reset_cycle_advance}
                  }
                  ctx->dut->ioctl_wr = 0;
                  ctx->dut->dmg_boot_download = 0;
            CPP
          else
            ''
          end}
              // Release reset and clock to let the system initialize
              ctx->dut->reset = 0;
              for (int i = 0; i < 100; i++) {
                  ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->eval();
                  ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->eval();
                  cart_advance_read_pipeline(ctx);
      #{reset_cycle_advance}
              }

              ctx->lcd_x = 0;
              ctx->lcd_y = 0;
              ctx->frame_count = 0;
              ctx->last_fetch_addr = 0;
              ctx->clk_counter = 0;  // Reset clock counter / external SpeedControl phase
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
          }

          void sim_eval(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->dut->eval();
          }

          void sim_poke(void* sim, const char* name, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
          #{poke_dispatch}
          }

          unsigned int sim_peek(void* sim, const char* name) {
              SimContext* ctx = static_cast<SimContext*>(sim);
          #{peek_dispatch}
              // Internal signals not accessible - return estimated values
              else if (strcmp(name, "_clkdiv") == 0) return ctx->clk_counter & 7;  // Estimate clkdiv
              // Other internal signals not accessible
              return 0;
          }

          void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memset(ctx->rom, 0, sizeof(ctx->rom));
              for (unsigned int i = 0; i < len && i < sizeof(ctx->rom); i++) {
                  ctx->rom[i] = data[i];
              }
              ctx->cart_type = ctx->rom[0x147];
              ctx->rom_size_code = ctx->rom[0x148];
              ctx->ram_size_code = ctx->rom[0x149];
              ctx->rom_bank_count = cart_rom_bank_count(ctx->rom_size_code);
              cart_reset_runtime_state(ctx);
          }

          void sim_load_boot_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len && i < sizeof(ctx->boot_rom); i++) {
                  ctx->boot_rom[i] = data[i];
              }
          }

          unsigned char sim_read_boot_rom(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
      #{if resolve_port_name('boot_rom_addr') && resolve_port_name('boot_rom_do') && @top_module_name != 'gb'
          <<~CPP.chomp
              return ctx->boot_rom[addr & 0xFFu];
          CPP
        else
          ''
        end}
      #{if @top_module_name == 'gb'
          <<~CPP.chomp
              unsigned int byte_addr = addr & 0xFFFu;
              unsigned int word_addr = (byte_addr >> 1) & 0x7FFu;
              unsigned int word = ctx->dut->rootp->gb__DOT__boot_rom__DOT__mem[word_addr];
              return (byte_addr & 0x1u) ? ((word >> 8) & 0xFFu) : (word & 0xFFu);
          CPP
        else
          <<~CPP.chomp
              return 0;
          CPP
        end}
          }

          void sim_write_vram(void* sim, unsigned int addr, unsigned char value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->vram)) {
                  ctx->vram[addr] = value;
              }
          }

          unsigned char sim_read_vram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->vram)) {
                  return ctx->vram[addr];
              }
              return 0;
          }

          void sim_read_framebuffer(void* sim, unsigned char* out_buffer) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memcpy(out_buffer, ctx->framebuffer, 160 * 144);
          }

          unsigned long sim_get_frame_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->frame_count;
          }

          // Batch cycle execution - runs until n_cycles CPU cycles completed
          // CPU cycles occur every 8 system clocks (SpeedControl divider)
          // This aligns with IR Compiler which counts effective CPU cycles
          void sim_run_cycles(void* sim, unsigned int n_cycles, struct GbCycleResult* result) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              result->cycles_run = 0;
              result->frames_completed = 0;

              while (result->cycles_run < n_cycles) {
                  // Falling edge
                  ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->eval();

                  // Rising edge
                  ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->eval();

                  // Count every system clock as a CPU cycle
                  ctx->clk_counter++;
                  result->cycles_run++;

                  // Capture LCD output
                  unsigned char lcd_clkena = ctx->dut->lcd_clkena;
                  unsigned char lcd_vsync = ctx->dut->lcd_vsync;
                  unsigned char lcd_data = ctx->dut->lcd_data_gb & 0x3;

                  // Rising edge of lcd_clkena: capture pixel
                  if (lcd_clkena && !ctx->prev_lcd_clkena) {
                      if (ctx->lcd_x < 160 && ctx->lcd_y < 144) {
                          ctx->framebuffer[ctx->lcd_y * 160 + ctx->lcd_x] = lcd_data;
                      }
                      ctx->lcd_x++;
                      if (ctx->lcd_x >= 160) {
                          ctx->lcd_x = 0;
                          ctx->lcd_y++;
                      }
                  }

                  // Rising edge of lcd_vsync: end of frame
                  if (lcd_vsync && !ctx->prev_lcd_vsync) {
                      ctx->lcd_x = 0;
                      ctx->lcd_y = 0;
                      ctx->frame_count++;
                      result->frames_completed++;
                  }

                  ctx->prev_lcd_clkena = lcd_clkena;
                  ctx->prev_lcd_vsync = lcd_vsync;
                  cart_advance_read_pipeline(ctx);
              }
          }

          } // extern "C"
        CPP

        write_file_if_changed(header_file, header_content)
        write_file_if_changed(cpp_file, cpp_content)
      end

      def write_file_if_changed(path, content)
        verilog_simulator.write_file_if_changed(path, content)
      end

      def compile_verilator(verilog_file_or_files, wrapper_file)
        if verilog_file_or_files.is_a?(Array)
          verilog_simulator.compile_backend(verilog_files: verilog_file_or_files, wrapper_file: wrapper_file)
        else
          verilog_simulator.compile_backend(verilog_file: verilog_file_or_files, wrapper_file: wrapper_file)
        end
      end

      def build_shared_library(_wrapper_file = nil)
        verilog_simulator.build_shared_library
      end

      def shared_lib_path
        verilog_simulator.shared_library_path
      end

      def load_shared_library(lib_path)
        @lib = verilog_simulator.load_library!(lib_path)

        # Bind FFI functions
        @sim_create = Fiddle::Function.new(
          @lib['sim_create'],
          [],
          Fiddle::TYPE_VOIDP
        )

        @sim_destroy = Fiddle::Function.new(
          @lib['sim_destroy'],
          [Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        @sim_reset = Fiddle::Function.new(
          @lib['sim_reset'],
          [Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        @sim_eval = Fiddle::Function.new(
          @lib['sim_eval'],
          [Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        @sim_poke = Fiddle::Function.new(
          @lib['sim_poke'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_VOID
        )

        @sim_peek = Fiddle::Function.new(
          @lib['sim_peek'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @sim_load_rom_fn = Fiddle::Function.new(
          @lib['sim_load_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_VOID
        )

        @sim_load_boot_rom_fn = Fiddle::Function.new(
          @lib['sim_load_boot_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_VOID
        )

        @sim_read_boot_rom_fn = Fiddle::Function.new(
          @lib['sim_read_boot_rom'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_CHAR
        )

        @sim_write_vram_fn = Fiddle::Function.new(
          @lib['sim_write_vram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR],
          Fiddle::TYPE_VOID
        )

        @sim_read_vram_fn = Fiddle::Function.new(
          @lib['sim_read_vram'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_CHAR
        )

        @sim_read_framebuffer_fn = Fiddle::Function.new(
          @lib['sim_read_framebuffer'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        @sim_get_frame_count_fn = Fiddle::Function.new(
          @lib['sim_get_frame_count'],
          [Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_LONG
        )

        @sim_run_cycles_fn = Fiddle::Function.new(
          @lib['sim_run_cycles'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID
        )

        # Create simulation context
        @sim_ctx = @sim_create.call
      end

      def reset_simulation
        initialize_inputs
        @sim_reset&.call(@sim_ctx) if @sim_ctx
        initialize_inputs
      end

      def initialize_inputs
        return unless @sim_ctx

        @clock_enable_phase = 0
        verilator_poke('clk_sys', 0)
        verilator_poke('reset', 0)
        drive_clock_enable_inputs(falling_edge: false)
        poke_if_available('joystick', 0xFF)  # All buttons released
        @joystick_state = 0xFF
        poke_if_available('joy_din', 0xF)
        poke_if_available('is_gbc', 0)       # DMG mode
        poke_if_available('is_sgb', 0)       # Not SGB
        poke_if_available('cart_do', 0)
        poke_if_available('cart_oe', 1)

        # Tie-offs used by imported gb top.
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
        poke_if_available('cart_ram_size', (@cartridge[:ram_size_code] || 0))
        poke_if_available('save_state', 0)
        poke_if_available('load_state', 0)
        poke_if_available('savestate_number', 0)
        poke_if_available('SaveStateExt_Dout', 0)
        poke_if_available('Savestate_CRAMReadData', 0)
        poke_if_available('SAVE_out_Dout', 0)
        poke_if_available('SAVE_out_done', 1)
        poke_if_available('rewind_on', 0)
        poke_if_available('rewind_active', 0)
        verilator_eval
        update_joypad_input
      end

      def drive_clock_enable_inputs(falling_edge:)
        values = ClockEnableWaveform.values_for_phase(@clock_enable_phase)
        poke_if_available('ce', values[:ce])
        poke_if_available('ce_n', values[:ce_n])
        poke_if_available('ce_2x', values[:ce_2x])
      end

      def drive_cartridge_input
        cart_rd_port = @output_port_aliases['cart_rd']
        cart_wr_port = @output_port_aliases['cart_wr']
        cart_di_port = @output_port_aliases['cart_di']
        ext_bus_addr_port = @output_port_aliases['ext_bus_addr']
        ext_bus_a15_port = @output_port_aliases['ext_bus_a15']
        cart_do_port = @input_port_aliases['cart_do']
        return if cart_rd_port.nil? || ext_bus_addr_port.nil? || ext_bus_a15_port.nil? || cart_do_port.nil?

        addr = verilator_peek(ext_bus_addr_port)
        a15 = verilator_peek(ext_bus_a15_port)
        full_addr = (a15 << 15) | addr
        if cart_wr_port && cart_di_port && verilator_peek(cart_wr_port) == 1
          handle_cartridge_write(full_addr, verilator_peek(cart_di_port) & 0xFF)
        end
        read_active = verilator_peek(cart_rd_port) == 1
        @cartridge[:last_full_addr] = full_addr
        @cartridge[:last_rd] = read_active
        @last_fetch_addr = full_addr if read_active
        if (cart_oe_port = @input_port_aliases['cart_oe'])
          verilator_poke(cart_oe_port, 1)
        end
        if immediate_cartridge_response?
          verilator_poke(cart_do_port, read_active ? cartridge_read_byte(full_addr) : 0xFF)
        else
          verilator_poke(cart_do_port, @cartridge[:cart_do_latched])
        end
      end

      def update_joypad_input
        joy_din_port = @input_port_aliases['joy_din']
        joy_p54_port = @output_port_aliases['joy_p54']
        return if joy_din_port.nil? || joy_p54_port.nil?

        joy = (@joystick_state || verilator_peek('joystick') || 0xFF) & 0xFF
        joy_p54 = verilator_peek(joy_p54_port) & 0x3
        p14 = joy_p54 & 0x1
        p15 = (joy_p54 >> 1) & 0x1
        joy_dir = joy & 0xF
        joy_btn = (joy >> 4) & 0xF
        joy_dir_masked = joy_dir | (p14.zero? ? 0x0 : 0xF)
        joy_btn_masked = joy_btn | (p15.zero? ? 0x0 : 0xF)
        verilator_poke(joy_din_port, joy_dir_masked & joy_btn_masked)
      end

      def poke_if_available(name, value)
        port_name = @input_port_aliases[name.to_s]
        return if port_name.nil?

        verilator_poke(port_name, value)
      end

      def debug_port_available?(name)
        @output_port_aliases.key?(name.to_s)
      end

      def verilator_poke(name, value)
        return unless @sim_ctx
        @sim_poke.call(@sim_ctx, name, value.to_i)
      end

      def verilator_peek(name)
        return 0 unless @sim_ctx
        @sim_peek.call(@sim_ctx, name)
      end

      def verilator_eval
        return unless @sim_ctx
        @sim_eval.call(@sim_ctx)
      end

      def verilator_write_vram(addr, value)
        return unless @sim_ctx
        @sim_write_vram_fn.call(@sim_ctx, addr, value)
      end

      def verilator_read_vram(addr)
        return 0 unless @sim_ctx
        @sim_read_vram_fn.call(@sim_ctx, addr) & 0xFF
      end

      def verilator_read_boot_rom(addr)
        return 0 unless @sim_ctx
        @sim_read_boot_rom_fn.call(@sim_ctx, addr) & 0xFF
      end

      def default_cartridge_state
        {
          cart_type: CART_TYPE_ROM_ONLY,
          rom_size_code: 0x00,
          ram_size_code: 0x00,
          rom_bank_count: 2,
          mbc1_rom_bank_low5: 1,
          mbc1_bank_upper2: 0,
          mbc1_mode: 0,
          ram_enabled: false,
          cart_do_latched: 0xFF,
          cart_oe_latched: 0,
          read_pipeline: Array.new(6),
          last_full_addr: 0,
          last_rd: false
        }
      end

      def cartridge_state_for_rom(bytes)
        bytes = Array(bytes)
        state = default_cartridge_state
        state[:cart_type] = bytes[0x147].to_i & 0xFF
        state[:rom_size_code] = bytes[0x148].to_i & 0xFF
        state[:ram_size_code] = bytes[0x149].to_i & 0xFF
        state[:rom_bank_count] = cartridge_rom_bank_count(bytes, state[:rom_size_code])
        state
      end

      def cartridge_rom_bank_count(bytes, rom_size_code)
        from_header = ROM_BANK_COUNTS_BY_SIZE_CODE[rom_size_code]
        from_length = [(Array(bytes).length.to_f / 0x4000).ceil, 1].max
        [from_header || from_length, from_length].max
      end

      def mbc1_cartridge?
        MBC1_CART_TYPES.include?((@cartridge || default_cartridge_state)[:cart_type])
      end

      def reset_cartridge_runtime_state!
        @cartridge ||= default_cartridge_state
        @cartridge[:mbc1_rom_bank_low5] = 1
        @cartridge[:mbc1_bank_upper2] = 0
        @cartridge[:mbc1_mode] = 0
        @cartridge[:ram_enabled] = false
        @cartridge[:cart_do_latched] = 0xFF
        @cartridge[:cart_oe_latched] = 0
        @cartridge[:read_pipeline] = Array.new(6)
        @cartridge[:last_full_addr] = 0
        @cartridge[:last_rd] = false
      end

      def cartridge_read_byte(full_addr)
        addr = full_addr & 0xFFFF
        if mbc1_cartridge?
          return 0xFF unless addr <= 0x7FFF

          bank = if addr <= ROM_BANK_0_END
                   @cartridge[:mbc1_mode].to_i == 1 ? ((@cartridge[:mbc1_bank_upper2].to_i & 0x3) << 5) : 0
                 else
                   low = @cartridge[:mbc1_rom_bank_low5].to_i & 0x1F
                   low = 1 if low.zero?
                   ((@cartridge[:mbc1_bank_upper2].to_i & 0x3) << 5) | low
                 end
          bank_count = [@cartridge[:rom_bank_count].to_i, 1].max
          bank %= bank_count
          index = bank * 0x4000 + (addr & 0x3FFF)
          @rom[index] || 0xFF
        else
          @rom[addr] || 0xFF
        end
      end

      def cartridge_output_enabled?(full_addr)
        addr = full_addr & 0xFFFF
        return true if addr <= 0x7FFF
        return @cartridge[:ram_enabled] if mbc1_cartridge? && addr >= 0xA000 && addr <= 0xBFFF

        false
      end

      def advance_cartridge_read_pipeline!
        return if immediate_cartridge_response?

        @cartridge ||= default_cartridge_state
        pipeline = Array(@cartridge[:read_pipeline])
        pipeline.unshift(@cartridge[:last_rd] ? true : false)
        completed_read = pipeline.pop
        @cartridge[:read_pipeline] = pipeline
        if completed_read
          completed_addr = @cartridge[:last_full_addr]
          @cartridge[:cart_do_latched] = cartridge_read_byte(completed_addr)
          @cartridge[:cart_oe_latched] = cartridge_output_enabled?(completed_addr) ? 1 : 0
        else
          @cartridge[:cart_oe_latched] = 0
        end
      end

      def handle_cartridge_write(full_addr, value)
        return unless mbc1_cartridge?

        addr = full_addr & 0x7FFF
        case addr
        when 0x0000..0x1FFF
          @cartridge[:ram_enabled] = (value & 0x0F) == 0x0A
        when 0x2000..0x3FFF
          bank = value & 0x1F
          @cartridge[:mbc1_rom_bank_low5] = bank.zero? ? 1 : bank
        when 0x4000..0x5FFF
          @cartridge[:mbc1_bank_upper2] = value & 0x03
        when 0x6000..0x7FFF
          @cartridge[:mbc1_mode] = value & 0x01
        end
      end
      end
    end
  end
end
