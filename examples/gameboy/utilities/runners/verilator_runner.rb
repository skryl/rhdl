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
require_relative '../output/speaker'
require_relative '../renderers/lcd_renderer'
require_relative '../clock_enable_waveform'
require 'rhdl/codegen'
require 'fileutils'
require 'set'
require 'json'
require 'fiddle'
require 'fiddle/import'

module RHDL
  module Examples
    module GameBoy
      # Verilator-based runner for Game Boy simulation
    # Compiles RHDL Verilog export to native code via Verilator
    class VerilogRunner
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
      # @param top [String, nil] Imported top component/module override for imported HDL trees.
      # @param use_staged_verilog [Boolean] Use the staged imported Verilog artifact when available.
      def initialize(hdl_dir: nil, top: nil, use_staged_verilog: false)
        @import_top_name = top&.to_s
        @use_staged_verilog = !!use_staged_verilog
        @component_class = resolve_component_class(hdl_dir: hdl_dir, top: @import_top_name)
        @component_input_ports = Set.new
        @component_output_ports = Set.new
        @component_port_widths = {}
        if @component_class.respond_to?(:_ports)
          @component_class._ports.each do |port|
            name = port.name.to_s
            @component_port_widths[name] = port.width.to_i
            if port.direction == :in
              @component_input_ports << name
            else
              @component_output_ports << name
            end
          end
        end
        @component_ports = (@component_input_ports + @component_output_ports).to_set
        @top_module_name = resolve_top_module_name(@component_class)
        @verilator_prefix = "V#{@top_module_name}"
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
        drive_clock_enable_inputs(falling_edge: true)
        drive_cartridge_input

        # Falling edge
        verilator_poke('clk_sys', 0)
        update_joypad_input
        verilator_eval

        # Handle ROM read
        drive_cartridge_input
        verilator_eval

        # Rising edge
        verilator_poke('clk_sys', 1)
        drive_clock_enable_inputs(falling_edge: false)
        drive_cartridge_input
        verilator_eval
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

      def resolve_component_class(hdl_dir:, top: nil)
        resolved_hdl_dir = HdlLoader.resolve_hdl_dir(hdl_dir: hdl_dir)
        @resolved_hdl_dir = resolved_hdl_dir
        if resolved_hdl_dir == HdlLoader::DEFAULT_HDL_DIR
          HdlLoader.configure!(hdl_dir: resolved_hdl_dir)
          require_relative '../../gameboy'
          return ::RHDL::Examples::GameBoy::Gameboy
        end

        HdlLoader.load_component_tree!(hdl_dir: resolved_hdl_dir)
        unless top
          require_relative '../../gameboy'
          return ::RHDL::Examples::GameBoy::Gameboy
        end

        top_name = top
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
        if @top_module_name == 'gb'
          lines << "#{keyword} (strcmp(name, \"cpu_pc_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_A;"
          lines << "else if (strcmp(name, \"boot_rom_enabled_internal\") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_22_1;"
          lines << "else if (strcmp(name, \"boot_rom_addr_internal\") == 0) return ctx->dut->rootp->gb__DOT__boot_rom__DOT__address_a;"
          lines << "else if (strcmp(name, \"boot_rom_q_internal\") == 0) return ctx->dut->rootp->gb__DOT___boot_rom_q_a;"
          lines << "else if (strcmp(name, \"cpu_di_internal\") == 0) return ctx->dut->rootp->gb__DOT___GEN_178;"
          lines << "else if (strcmp(name, \"cpu_do_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_DO;"
          lines << "else if (strcmp(name, \"cpu_rd_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_RD_n;"
          lines << "else if (strcmp(name, \"cpu_wr_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_WR_n;"
          lines << "else if (strcmp(name, \"cpu_m1_n_internal\") == 0) return ctx->dut->rootp->gb__DOT___cpu_M1_n;"
          lines << "else if (strcmp(name, \"savestate_reset_out_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_reset_out;"
          lines << "else if (strcmp(name, \"savestate_sleep_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_sleep_savestate;"
          lines << "else if (strcmp(name, \"request_loadstate_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_loadstate;"
          lines << "else if (strcmp(name, \"request_savestate_internal\") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_savestate;"
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
          "#{indent}unsigned int boot_addr = ctx->dut->#{boot_addr_port} & 0xFF;",
          "#{indent}ctx->dut->#{boot_data_port} = ctx->boot_rom[boot_addr];"
        ].join("\n")
      end

      def c_cart_feed_lines(indent:)
        cart_addr_port = resolve_port_name('ext_bus_addr')
        cart_a15_port = resolve_port_name('ext_bus_a15')
        cart_do_port = resolve_port_name('cart_do')
        return '' unless cart_addr_port && cart_a15_port && cart_do_port

        [
          "#{indent}{",
          "#{indent}    unsigned int addr = ctx->dut->#{cart_addr_port};",
          "#{indent}    unsigned int a15 = ctx->dut->#{cart_a15_port};",
          "#{indent}    unsigned int full_addr = (a15 << 15) | addr;",
          "#{indent}    if (full_addr < sizeof(ctx->rom)) {",
          "#{indent}        ctx->dut->#{cart_do_port} = ctx->rom[full_addr];",
          "#{indent}    } else {",
          "#{indent}        ctx->dut->#{cart_do_port} = 0;",
          "#{indent}    }",
          "#{indent}}"
        ].join("\n")
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

      def runtime_staged_verilog_entry
        return nil unless @resolved_hdl_dir
        return nil unless @use_staged_verilog

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
          library_basename: "gameboy_sim_#{sanitize_identifier(@top_module_name)}",
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

        stem = sanitize_identifier(@top_module_name)
        verilog_file = runtime_staged_verilog_entry
        if verilog_file
          log "  Using staged mixed-source Verilog: #{verilog_file}"
        else
          verilog_file = File.join(VERILOG_DIR, "gameboy_#{stem}.v")
          verilog_codegen = File.expand_path('../../../../lib/rhdl/dsl/codegen.rb', __dir__)
          circt_codegen = File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__)
          export_deps = [__FILE__, verilog_codegen, circt_codegen].select { |p| File.exist?(p) }
          needs_export = !File.exist?(verilog_file) ||
                         export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

          if needs_export
            log "  Exporting #{@component_class} to Verilog..."
            export_verilog(verilog_file)
          end
        end

        # Create C++ wrapper
        wrapper_file = File.join(VERILOG_DIR, "sim_wrapper_#{stem}.cpp")
        header_file = File.join(VERILOG_DIR, "sim_wrapper_#{stem}.h")
        create_cpp_wrapper(wrapper_file, header_file)

        # Check if we need to rebuild
        lib_file = shared_lib_path
        simulator_codegen = File.expand_path('../../../../lib/rhdl/codegen/verilog/sim/verilog_simulator.rb', __dir__)
        build_deps = [verilog_file, wrapper_file, __FILE__, simulator_codegen].select { |path| File.exist?(path) }
        needs_build = !File.exist?(lib_file) ||
                      build_deps.any? { |path| File.mtime(path) > File.mtime(lib_file) }

        if needs_build
          log "  Compiling with Verilator..."
          compile_verilator(verilog_file, wrapper_file)
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
          };

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
      #{constant_tieoffs}
              // Hold reset high and clock a few times to properly reset sequential logic
              ctx->dut->reset = 1;
              for (int i = 0; i < 10; i++) {
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                  ctx->dut->eval();
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
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                      ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                      ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                      ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                      ctx->dut->eval();
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
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}

                  ctx->dut->clk_sys = 1;
          #{ce_feed_high}
                  ctx->dut->eval();
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
              for (unsigned int i = 0; i < len && i < sizeof(ctx->rom); i++) {
                  ctx->rom[i] = data[i];
              }
          }

          void sim_load_boot_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len && i < sizeof(ctx->boot_rom); i++) {
                  ctx->boot_rom[i] = data[i];
              }
          }

          unsigned char sim_read_boot_rom(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              unsigned int byte_addr = addr & 0xFFFu;
              unsigned int word_addr = (byte_addr >> 1) & 0x7FFu;
              unsigned int word = ctx->dut->rootp->gb__DOT__boot_rom__DOT__mem[word_addr];
              return (byte_addr & 0x1u) ? ((word >> 8) & 0xFFu) : (word & 0xFFu);
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
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  ctx->dut->clk_sys = 0;
          #{ce_feed_low}
                  ctx->dut->eval();
          #{joypad_feed}
          #{boot_feed}
          #{cart_feed}
                  if (ctx->dut->cart_rd) {
                      unsigned int addr = ctx->dut->ext_bus_addr & 0x7FFF;
                      unsigned int a15 = ctx->dut->ext_bus_a15 & 0x1;
                      ctx->last_fetch_addr = (a15 << 15) | addr;
                  }
                  ctx->dut->eval();

                  // Rising edge
                  ctx->dut->clk_sys = 1;
          #{ce_feed_high}
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

      def compile_verilator(verilog_file, wrapper_file)
        verilog_simulator.compile_backend(verilog_file: verilog_file, wrapper_file: wrapper_file)
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
        ext_bus_addr_port = @output_port_aliases['ext_bus_addr']
        ext_bus_a15_port = @output_port_aliases['ext_bus_a15']
        cart_do_port = @input_port_aliases['cart_do']
        return if cart_rd_port.nil? || ext_bus_addr_port.nil? || ext_bus_a15_port.nil? || cart_do_port.nil?

        addr = verilator_peek(ext_bus_addr_port)
        a15 = verilator_peek(ext_bus_a15_port)
        full_addr = (a15 << 15) | addr
        @last_fetch_addr = full_addr if verilator_peek(cart_rd_port) == 1
        verilator_poke(cart_do_port, @rom[full_addr] || 0)
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
      end
    end
  end
end
