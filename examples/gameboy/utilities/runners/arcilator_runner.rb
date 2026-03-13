# frozen_string_literal: true

require 'digest'
require 'etc'
require 'fileutils'
require 'fiddle'
require 'json'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'rhdl/codegen'
require 'rhdl/sim/native/mlir/arcilator/runtime'
require_relative '../hdl_loader'
require_relative '../output/speaker'
require_relative '../renderers/lcd_renderer'
require_relative '../import/verilog_wrapper'

module RHDL
  module Examples
    module GameBoy
      # Arcilator-based runner for imported Game Boy cores.
      # This backend runs the imported `gb` MLIR directly instead of raising the
      # generated wrapper back through RHDL, so it is useful for benchmarking
      # the imported IR path on its own.
      class ArcilatorRunner
        include RHDL::Examples::GameBoy::Import::VerilogWrapper

        SCREEN_WIDTH = 160
        SCREEN_HEIGHT = 144
        BUILD_BASE = File.expand_path('../../.arcilator_build', __dir__)
        DEFAULT_IMPORT_DIR = File.expand_path('../../import', __dir__)
        DMG_BOOT_ROM_PATH = File.expand_path('../../software/roms/dmg_boot.bin', __dir__)
        OBSERVE_PORT_FLAGS = ['--observe-ports'].freeze

        CORE_SIGNAL_SPECS = {
          reset: { name: 'reset', preferred_type: 'input' },
          clk_sys: { name: 'clk_sys', preferred_type: 'input' },
          ce: { name: 'ce', preferred_type: 'input' },
          ce_n: { name: 'ce_n', preferred_type: 'input' },
          ce_2x: { name: 'ce_2x', preferred_type: 'input' },
          joystick: { name: 'joystick', preferred_type: 'input' },
          is_gbc: { name: 'isGBC', preferred_type: 'input' },
          real_cgb_boot: { name: 'real_cgb_boot', preferred_type: 'input' },
          is_sgb: { name: 'isSGB', preferred_type: 'input' },
          extra_spr_en: { name: 'extra_spr_en', preferred_type: 'input' },
          cart_do: { name: 'cart_do', preferred_type: 'input' },
          cart_oe: { name: 'cart_oe', preferred_type: 'input' },
          cgb_boot_download: { name: 'cgb_boot_download', preferred_type: 'input' },
          dmg_boot_download: { name: 'dmg_boot_download', preferred_type: 'input' },
          sgb_boot_download: { name: 'sgb_boot_download', preferred_type: 'input' },
          ioctl_wr: { name: 'ioctl_wr', preferred_type: 'input' },
          ioctl_addr: { name: 'ioctl_addr', preferred_type: 'input' },
          ioctl_dout: { name: 'ioctl_dout', preferred_type: 'input' },
          boot_gba_en: { name: 'boot_gba_en', preferred_type: 'input' },
          fast_boot_en: { name: 'fast_boot_en', preferred_type: 'input' },
          audio_no_pops: { name: 'audio_no_pops', preferred_type: 'input' },
          megaduck: { name: 'megaduck', preferred_type: 'input' },
          joy_din: { name: 'joy_din', preferred_type: 'input' },
          gg_reset: { name: 'gg_reset', preferred_type: 'input' },
          gg_en: { name: 'gg_en', preferred_type: 'input' },
          gg_code: { name: 'gg_code', preferred_type: 'input' },
          serial_clk_in: { name: 'serial_clk_in', preferred_type: 'input' },
          serial_data_in: { name: 'serial_data_in', preferred_type: 'input' },
          increase_ss_header_count: { name: 'increaseSSHeaderCount', preferred_type: 'input' },
          cart_ram_size: { name: 'cart_ram_size', preferred_type: 'input' },
          save_state: { name: 'save_state', preferred_type: 'input' },
          load_state: { name: 'load_state', preferred_type: 'input' },
          savestate_number: { name: 'savestate_number', preferred_type: 'input' },
          save_state_ext_dout: { name: 'SaveStateExt_Dout', preferred_type: 'input' },
          savestate_cram_read_data: { name: 'Savestate_CRAMReadData', preferred_type: 'input' },
          save_out_dout: { name: 'SAVE_out_Dout', preferred_type: 'input' },
          save_out_done: { name: 'SAVE_out_done', preferred_type: 'input' },
          rewind_on: { name: 'rewind_on', preferred_type: 'input' },
          rewind_active: { name: 'rewind_active', preferred_type: 'input' },
          ext_bus_addr: { name: 'ext_bus_addr', preferred_type: 'output' },
          ext_bus_a15: { name: 'ext_bus_a15', preferred_type: 'output' },
          cart_rd: { name: 'cart_rd', preferred_type: 'output' },
          cart_wr: { name: 'cart_wr', preferred_type: 'output' },
          cart_di: { name: 'cart_di', preferred_type: 'output' },
          lcd_clkena: { name: 'lcd_clkena', preferred_type: 'output' },
          lcd_data_gb: { name: 'lcd_data_gb', preferred_type: 'output' },
          lcd_vsync: { name: 'lcd_vsync', preferred_type: 'output' },
          lcd_on: { name: 'lcd_on', preferred_type: 'output' },
          joy_p54: { name: 'joy_p54', preferred_type: 'output' }
        }.freeze

        WRAPPER_SIGNAL_SPECS = {
          reset: { name: 'reset', preferred_type: 'input' },
          clk_sys: { name: 'clk_sys', preferred_type: 'input' },
          ce: { name: 'ce', preferred_type: 'input', required: false },
          ce_n: { name: 'ce_n', preferred_type: 'input', required: false },
          ce_2x: { name: 'ce_2x', preferred_type: 'input', required: false },
          joystick: { name: 'joystick', preferred_type: 'input' },
          is_gbc: { name: 'is_gbc', preferred_type: 'input' },
          is_sgb: { name: 'is_sgb', preferred_type: 'input' },
          cart_do: { name: 'cart_do', preferred_type: 'input' },
          boot_rom_do: { name: 'boot_rom_do', preferred_type: 'input' },
          ext_bus_addr: { name: 'ext_bus_addr', preferred_type: 'wire' },
          ext_bus_a15: { name: 'ext_bus_a15', preferred_type: 'wire' },
          cart_rd: { name: 'cart_rd', preferred_type: 'wire' },
          cart_wr: { name: 'cart_wr', preferred_type: 'wire' },
          cart_di: { name: 'cart_di', preferred_type: 'wire' },
          lcd_clkena: { name: 'lcd_clkena', preferred_type: 'wire' },
          lcd_data_gb: { name: 'lcd_data_gb', preferred_type: 'wire' },
          lcd_vsync: { name: 'lcd_vsync', preferred_type: 'wire' },
          lcd_on: { name: 'lcd_on', preferred_type: 'wire' },
          boot_rom_addr: { name: 'boot_rom_addr', preferred_type: 'wire' },
          gb_core_reset_r: { name: 'gb_core/rt_tmp_1_1', preferred_type: 'register', required: false },
          gb_core_boot_rom_enabled: { name: 'gb_core/rt_tmp_22_1', preferred_type: 'register', required: false },
          gb_core_boot_q: { name: 'gb_core/boot_rom/rt_tmp_1_8', preferred_type: 'register', required: false },
          gb_core_cpu_pc: { name: 'gb_core/cpu/u0/n1787', preferred_type: 'register', required: false },
          gb_core_cpu_ir: { name: 'gb_core/cpu/u0/n1796', preferred_type: 'register', required: false },
          gb_core_cpu_tstate: { name: 'gb_core/cpu/u0/n1799', preferred_type: 'register', required: false },
          gb_core_cpu_mcycle: { name: 'gb_core/cpu/u0/n1800', preferred_type: 'register', required: false },
          gb_core_cpu_addr: { name: 'gb_core/cpu/u0/n1836', preferred_type: 'register', required: false },
          gb_core_cpu_di: { name: 'gb_core/cpu/n166', preferred_type: 'register', required: false },
          gb_core_cpu_do: { name: 'gb_core/cpu/u0/n1837', preferred_type: 'register', required: false },
          gb_core_cpu_m1_n: { name: 'gb_core/cpu/u0/n1834', preferred_type: 'register', required: false },
          gb_core_cpu_mreq_n: { name: 'gb_core/cpu/n169', preferred_type: 'register', required: false },
          gb_core_cpu_iorq_n: { name: 'gb_core/cpu/n170', preferred_type: 'register', required: false },
          gb_core_cpu_rd_n: { name: 'gb_core/cpu/n171', preferred_type: 'register', required: false },
          gb_core_cpu_wr_n: { name: 'gb_core/cpu/n172', preferred_type: 'register', required: false },
          speed_ctrl_ce: { name: 'speed_ctrl/rt_tmp_1_1', preferred_type: 'register', required: false },
          speed_ctrl_ce_n: { name: 'speed_ctrl/rt_tmp_2_1', preferred_type: 'register', required: false },
          speed_ctrl_ce_2x: { name: 'speed_ctrl/rt_tmp_3_1', preferred_type: 'register', required: false },
          speed_ctrl_state: { name: 'speed_ctrl/rt_tmp_7_3', preferred_type: 'register', required: false },
          speed_ctrl_clkdiv: { name: 'speed_ctrl/rt_tmp_8_3', preferred_type: 'register', required: false },
          speed_ctrl_unpause_cnt: { name: 'speed_ctrl/rt_tmp_9_4', preferred_type: 'register', required: false },
          speed_ctrl_fastforward_cnt: { name: 'speed_ctrl/rt_tmp_10_4', preferred_type: 'register', required: false },
          video_h_cnt: { name: 'gb_core/video/rt_tmp_32_8', preferred_type: 'register', required: false },
          video_v_cnt: { name: 'gb_core/video/rt_tmp_36_8', preferred_type: 'register', required: false },
          video_scy: { name: 'gb_core/video/rt_tmp_15_8', preferred_type: 'register', required: false },
          video_scx: { name: 'gb_core/video/rt_tmp_16_8', preferred_type: 'register', required: false },
          video_bg_palette: { name: 'gb_core/video/rt_tmp_20_8', preferred_type: 'register', required: false },
          video_obj_palette0: { name: 'gb_core/video/rt_tmp_21_8', preferred_type: 'register', required: false },
          video_obj_palette1: { name: 'gb_core/video/rt_tmp_22_8', preferred_type: 'register', required: false },
          video_bg_shift_lo: { name: 'gb_core/video/rt_tmp_55_8', preferred_type: 'register', required: false },
          video_bg_shift_hi: { name: 'gb_core/video/rt_tmp_56_8', preferred_type: 'register', required: false },
          video_bg_attr: { name: 'gb_core/video/rt_tmp_57_8', preferred_type: 'register', required: false },
          video_obj_shift_lo: { name: 'gb_core/video/rt_tmp_58_8', preferred_type: 'register', required: false },
          video_obj_shift_hi: { name: 'gb_core/video/rt_tmp_59_8', preferred_type: 'register', required: false },
          video_obj_meta0: { name: 'gb_core/video/rt_tmp_60_8', preferred_type: 'register', required: false },
          video_obj_meta1: { name: 'gb_core/video/rt_tmp_61_8', preferred_type: 'register', required: false },
          video_fetch_phase: { name: 'gb_core/video/rt_tmp_46_3', preferred_type: 'register', required: false },
          video_fetch_slot: { name: 'gb_core/video/rt_tmp_48_3', preferred_type: 'register', required: false },
          video_fetch_hold0: { name: 'gb_core/video/rt_tmp_49_1', preferred_type: 'register', required: false },
          video_fetch_hold1: { name: 'gb_core/video/rt_tmp_50_1', preferred_type: 'register', required: false },
          video_fetch_data0: { name: 'gb_core/video/rt_tmp_51_8', preferred_type: 'register', required: false },
          video_fetch_data1: { name: 'gb_core/video/rt_tmp_52_8', preferred_type: 'register', required: false },
          video_tile_lo: { name: 'gb_core/video/rt_tmp_53_8', preferred_type: 'register', required: false },
          video_tile_hi: { name: 'gb_core/video/rt_tmp_54_8', preferred_type: 'register', required: false },
          video_input_vram_data: {
            name: 'gb_core/vram_data',
            names: ['gb_core/vram_data', 'vram_data'],
            preferred_type: 'wire',
            required: false
          },
          video_input_vram1_data: {
            name: 'gb_core/vram1_data',
            names: ['gb_core/vram1_data', 'vram1_data'],
            preferred_type: 'wire',
            required: false
          },
          vram0_q_a_reg: {
            name: 'gb_core/vram0/rt_tmp_1_8',
            names: [
              'gb_core/vram0/rt_tmp_1_8',
              'vram0/rt_tmp_1_8',
              'gb_core/vram0/altsyncram_component/rt_tmp_1_8',
              'vram0/altsyncram_component/rt_tmp_1_8'
            ],
            preferred_type: 'register',
            required: false
          },
          vram1_q_a_reg: {
            name: 'gb_core/vram1/rt_tmp_1_8',
            names: [
              'gb_core/vram1/rt_tmp_1_8',
              'vram1/rt_tmp_1_8',
              'gb_core/vram1/altsyncram_component/rt_tmp_1_8',
              'vram1/altsyncram_component/rt_tmp_1_8'
            ],
            preferred_type: 'register',
            required: false
          },
          vram0_r0_en: {
            name: 'gb_core/vram0/mem_ext/R0_en',
            names: ['gb_core/vram0/mem_ext/R0_en', 'gb_core/vram0/altsyncram_component/mem_ext/R0_en'],
            preferred_type: 'wire',
            required: false
          },
          vram0_r0_addr: {
            name: 'gb_core/vram0/mem_ext/R0_addr',
            names: ['gb_core/vram0/mem_ext/R0_addr', 'gb_core/vram0/altsyncram_component/mem_ext/R0_addr'],
            preferred_type: 'wire',
            required: false
          },
          vram0_r0_data: {
            name: 'gb_core/vram0/mem_ext/R0_data',
            names: ['gb_core/vram0/mem_ext/R0_data', 'gb_core/vram0/altsyncram_component/mem_ext/R0_data'],
            preferred_type: 'wire',
            required: false
          },
          vram1_r0_data: {
            name: 'gb_core/vram1/mem_ext/R0_data',
            names: ['gb_core/vram1/mem_ext/R0_data', 'gb_core/vram1/altsyncram_component/mem_ext/R0_data'],
            preferred_type: 'wire',
            required: false
          },
          vram0_w0_addr: {
            name: 'gb_core/vram0/mem_ext/W0_addr',
            names: ['gb_core/vram0/mem_ext/W0_addr', 'gb_core/vram0/altsyncram_component/mem_ext/W0_addr'],
            preferred_type: 'wire',
            required: false
          },
          vram0_w0_en: {
            name: 'gb_core/vram0/mem_ext/W0_en',
            names: ['gb_core/vram0/mem_ext/W0_en', 'gb_core/vram0/altsyncram_component/mem_ext/W0_en'],
            preferred_type: 'wire',
            required: false
          },
          vram0_w0_data: {
            name: 'gb_core/vram0/mem_ext/W0_data',
            names: ['gb_core/vram0/mem_ext/W0_data', 'gb_core/vram0/altsyncram_component/mem_ext/W0_data'],
            preferred_type: 'wire',
            required: false
          },
          vram1_w0_addr: {
            name: 'gb_core/vram1/mem_ext/W0_addr',
            names: ['gb_core/vram1/mem_ext/W0_addr', 'gb_core/vram1/altsyncram_component/mem_ext/W0_addr', 'gb_core/vram0/altsyncram_component/mem_ext/W1_addr'],
            preferred_type: 'wire',
            required: false
          },
          vram1_w0_en: {
            name: 'gb_core/vram1/mem_ext/W0_en',
            names: ['gb_core/vram1/mem_ext/W0_en', 'gb_core/vram1/altsyncram_component/mem_ext/W0_en', 'gb_core/vram0/altsyncram_component/mem_ext/W1_en'],
            preferred_type: 'wire',
            required: false
          },
          vram1_w0_data: {
            name: 'gb_core/vram1/mem_ext/W0_data',
            names: ['gb_core/vram1/mem_ext/W0_data', 'gb_core/vram1/altsyncram_component/mem_ext/W0_data', 'gb_core/vram0/altsyncram_component/mem_ext/W1_data'],
            preferred_type: 'wire',
            required: false
          },
          boot_upload_active: { name: 'boot_upload_active', preferred_type: 'register', required: false },
          boot_upload_phase: { name: 'boot_upload_phase', preferred_type: 'register', required: false },
          boot_upload_index: { name: 'boot_upload_index', preferred_type: 'register', required: false },
          boot_upload_low_byte: { name: 'boot_upload_low_byte', preferred_type: 'register', required: false }
        }.freeze

        CORE_STATIC_INPUT_VALUES = {
          is_gbc: 0,
          real_cgb_boot: 0,
          is_sgb: 0,
          extra_spr_en: 0,
          cart_oe: 1,
          cgb_boot_download: 0,
          dmg_boot_download: 0,
          sgb_boot_download: 0,
          ioctl_wr: 0,
          ioctl_addr: 0,
          ioctl_dout: 0,
          boot_gba_en: 0,
          fast_boot_en: 0,
          audio_no_pops: 0,
          megaduck: 0,
          gg_reset: 0,
          gg_en: 0,
          gg_code: 0,
          serial_clk_in: 0,
          serial_data_in: 1,
          increase_ss_header_count: 0,
          cart_ram_size: 0,
          save_state: 0,
          load_state: 0,
          savestate_number: 0,
          save_state_ext_dout: 0,
          savestate_cram_read_data: 0,
          save_out_dout: 0,
          save_out_done: 1,
          rewind_on: 0,
          rewind_active: 0
        }.freeze

        WRAPPER_STATIC_INPUT_VALUES = {
          is_gbc: 0,
          is_sgb: 0
        }.freeze

        attr_reader :import_root

        def runner_verbose?
          return true if ENV['RHDL_RUNNER_VERBOSE'] == '1'
          return false if ENV['RSPEC_QUIET_OUTPUT'] == '1'
          return false if defined?(RSpec)

          true
        end

        def log(message)
          puts(message) if runner_verbose?
        end

        def initialize(hdl_dir: nil, top: nil, use_staged_verilog: true, use_normalized_verilog: false, use_rhdl_source: false, jit: nil)
          @import_root = resolve_import_root(hdl_dir)
          @requested_top = top&.to_s
          @use_staged_verilog = !!use_staged_verilog
          @use_normalized_verilog = !!use_normalized_verilog
          @use_rhdl_source = !!use_rhdl_source
          @jit = jit.nil? ? env_truthy?('RHDL_GAMEBOY_ARC_JIT') : !!jit
          normalize_import_verilog_selection!
          @import_report = load_import_report_or_empty!(@import_root)
          validate_requested_top!

          check_tools_available!

          log 'Initializing Game Boy Arcilator simulation...'
          start_time = Time.now
          build_simulation
          jit_mode? ? start_jit_process : load_shared_library(@lib_path)
          elapsed = Time.now - start_time
          log "  Arcilator simulation built in #{elapsed.round(2)}s"

          @cycles = 0
          @halted = false
          @joystick_state = 0xFF
          @frame_count = 0
          @screen_dirty = false
          @speaker = Speaker.new

          load_boot_rom if File.exist?(DMG_BOOT_ROM_PATH)
        end

        def native?
          true
        end

        def sim
          @sim
        end

        def simulator_type
          :hdl_arcilator
        end

        def dry_run_info
          {
            mode: :circt,
            simulator_type: :hdl_arcilator,
            native: true,
            jit: jit_mode?
          }
        end

        def load_rom(bytes, base_addr: 0)
          bytes = bytes.bytes if bytes.is_a?(String)
          @rom = bytes.dup
          if jit_mode?
            send_jit_payload_command('LOAD_ROM', bytes)
          else
            @sim.runner_load_rom(bytes, base_addr)
          end
          log "Loaded #{bytes.size} bytes ROM"
        end

        def load_boot_rom(bytes = nil)
          if bytes.nil?
            return unless File.exist?(DMG_BOOT_ROM_PATH)

            bytes = File.binread(DMG_BOOT_ROM_PATH)
            log "Loading default DMG boot ROM from #{DMG_BOOT_ROM_PATH}"
          elsif bytes.is_a?(String) && File.exist?(bytes)
            bytes = File.binread(bytes)
          end

          bytes = bytes.bytes if bytes.is_a?(String)
          @boot_rom = bytes.dup
          if jit_mode?
            send_jit_payload_command('LOAD_BOOT_ROM', bytes)
          else
            @sim.runner_load_boot_rom(bytes, 0)
          end
          @boot_rom_loaded = true
          log "Loaded #{bytes.size} bytes boot ROM"
        end

        def boot_rom_loaded?
          @boot_rom_loaded || false
        end

        def reset
          if jit_mode?
            send_jit_command('RESET')
          else
            @sim.reset
          end
          @cycles = 0
          @frame_count = 0
          @halted = false
          @screen_dirty = false
          @joystick_state = 0xFF
          if jit_mode?
            send_jit_command("SET_JOYSTICK #{@joystick_state}")
          else
            @sim_set_joystick_fn&.call(@sim_ctx, @joystick_state)
          end
        end

        def run_steps(steps)
          if jit_mode?
            response = send_jit_command("RUN #{steps}")
            _, cycles_run, frames_completed, current_frame_count = response.split
            cycles_run = cycles_run.to_i
            frames_completed = frames_completed.to_i
            @frame_count = current_frame_count.to_i
          else
            result = @sim.runner_run_cycles(steps)
            cycles_run = result ? result[:cycles_run] : 0
            frames_completed = result ? result[:frames_completed] : 0
          end
          @cycles += cycles_run
          @frame_count += frames_completed unless jit_mode?
          @screen_dirty = true if frames_completed.positive?
        end

        def inject_key(button)
          @joystick_state &= ~(1 << button)
          if jit_mode?
            send_jit_command("SET_JOYSTICK #{@joystick_state}")
          else
            @sim_set_joystick_fn&.call(@sim_ctx, @joystick_state)
          end
        end

        def release_key(button)
          @joystick_state |= (1 << button)
          if jit_mode?
            send_jit_command("SET_JOYSTICK #{@joystick_state}")
          else
            @sim_set_joystick_fn&.call(@sim_ctx, @joystick_state)
          end
        end

        def read_framebuffer
          flat = if jit_mode?
                 parse_jit_framebuffer(send_jit_command('GET_FB'))
                else
                  @sim.runner_read_framebuffer(0, SCREEN_WIDTH * SCREEN_HEIGHT)
                 end
          Array.new(SCREEN_HEIGHT) do |y|
            Array.new(SCREEN_WIDTH) do |x|
              flat[(y * SCREEN_WIDTH) + x]
            end
          end
        end

        def cpu_state
          full_bus_addr, last_fetch_addr =
            if jit_mode?
              state = parse_jit_state(send_jit_command('GET_STATE'))
              [state.fetch(:ext_bus_addr), state.fetch(:last_fetch_addr)]
            else
              [
                @sim_get_ext_bus_full_addr_fn.call(@sim_ctx).to_i & 0xFFFF,
                @sim_get_last_fetch_addr_fn.call(@sim_ctx).to_i & 0xFFFF
              ]
            end
          pc = last_fetch_addr.zero? ? full_bus_addr : last_fetch_addr

          {
            pc: pc,
            a: 0,
            f: 0,
            b: 0,
            c: 0,
            d: 0,
            e: 0,
            h: 0,
            l: 0,
            sp: 0,
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

        def render_lcd_color(chars_wide: 80, invert: false)
          renderer = LcdRenderer.new(chars_wide: chars_wide, invert: invert)
          renderer.render_color(read_framebuffer)
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

        def debug_state
          return {} unless jit_mode?

          parse_jit_state(send_jit_command('GET_STATE'))
        end

        def debug_read_vram(addr)
          if jit_mode?
            response = send_jit_command("READ_VRAM #{addr}")
            _, value = response.split
            return value.to_i & 0xFF
          end

          return 0 unless @sim_read_vram_fn && @sim_ctx
          @sim.runner_read_vram(addr, 1).first.to_i & 0xFF
        end

        def debug_vram_write_count
          if jit_mode?
            response = send_jit_command('GET_VRAM_WRITES')
            _, value = response.split
            return value.to_i
          end

          return 0 unless @sim_get_vram_write_count_fn && @sim_ctx
          @sim_get_vram_write_count_fn.call(@sim_ctx).to_i
        end

        def debug_vram_fetch_state
          return nil unless jit_mode?

          _, en, addr, vram0_data, vram1_data = send_jit_command('GET_VRAM_FETCH').split
          {
            en: (en || 0).to_i & 0x1,
            addr: (addr || 0).to_i & 0x1FFF,
            vram0_data: (vram0_data || 0).to_i & 0xFF,
            vram1_data: (vram1_data || 0).to_i & 0xFF
          }
        end

        def close
          return close_jit_process if jit_mode?
          return false unless @sim_ctx

          @sim.close
          @sim = nil
          @sim_ctx = nil
          true
        end

        private

        def resolve_import_root(hdl_dir)
          File.expand_path(hdl_dir || DEFAULT_IMPORT_DIR)
        end

        def import_report_path
          File.join(@import_root, 'import_report.json')
        end

        def load_import_report!(root)
          report_path = File.join(root, 'import_report.json')
          return JSON.parse(File.read(report_path)) if File.file?(report_path)

          fallback_core_mlir = File.join(root, '.mixed_import', 'gb.core.mlir')
          raise ArgumentError, "Imported Game Boy report not found: #{report_path}" unless File.file?(fallback_core_mlir)

          {
            'artifacts' => {
              'core_mlir_path' => fallback_core_mlir
            },
            'mixed_import' => {
              'top_name' => 'gb',
              'core_mlir_path' => fallback_core_mlir
            }
          }
        end

        def load_import_report_or_empty!(root)
          load_import_report!(root)
        rescue ArgumentError
          raise unless @use_rhdl_source

          {}
        end

        def imported_core_top_name
          @imported_core_top_name ||= begin
            top = @import_report.dig('mixed_import', 'top_name').to_s
            top.empty? ? 'gb' : top
          end
        end

        def import_wrapper_info
          info = @import_report['import_wrapper']
          info.is_a?(Hash) ? info : {}
        end

        def wrapper_available?
          !wrapper_class_name.empty? && !wrapper_module_name.empty?
        end

        def wrapper_class_name
          @wrapper_class_name ||= import_wrapper_info.fetch('class_name', '').to_s
        end

        def wrapper_module_name
          @wrapper_module_name ||= import_wrapper_info.fetch('module_name', '').to_s
        end

        def wrapper_uses_imported_speedcontrol?
          @wrapper_uses_imported_speedcontrol ||= if import_wrapper_info['uses_imported_speedcontrol'] == true
                                                    true
                                                  else
                                                    source_path = first_existing_path(
                                                      selected_import_verilog_path,
                                                      @import_report.dig('artifacts', 'pure_verilog_entry_path'),
                                                      @import_report.dig('mixed_import', 'pure_verilog_entry_path'),
                                                      @import_report.dig('artifacts', 'workspace_pure_verilog_entry_path')
                                                    )
                                                    source = source_path && File.read(source_path)
                                                    import_support_modules.include?('speedcontrol') ||
                                                      source.to_s.match?(/\bmodule\s+speedcontrol\b/) ||
                                                      source.to_s.match?(/speedcontrol\.v\b/i)
                                                  end
        end

        def requested_top_name
          raw = @requested_top.to_s.strip
          return raw unless raw.empty?
          return wrapper_class_name if wrapper_available?

          imported_core_top_name
        end

        def using_import_wrapper?
          wrapper_available? && [wrapper_class_name.downcase, wrapper_module_name.downcase].include?(requested_top_name.downcase)
        end

        def state_top_name
          return rhdl_top_module_name if @use_rhdl_source

          using_import_wrapper? ? wrapper_module_name : imported_core_top_name
        end

        def validate_requested_top!
          return if @requested_top.nil? || @requested_top.empty?
          allowed = [imported_core_top_name, wrapper_class_name, wrapper_module_name, 'Gameboy', 'gameboy'].reject(&:empty?)
          return if allowed.include?(@requested_top)

          raise ArgumentError,
                "Game Boy ArcilatorRunner currently runs imported top #{requested_top_name.inspect}. "\
                "Requested top=#{@requested_top.inspect}"
        end

        def core_mlir_path
          path = @import_report.dig('artifacts', 'core_mlir_path') ||
                 @import_report.dig('mixed_import', 'core_mlir_path')
          raise ArgumentError, "Imported core MLIR path missing from #{import_report_path}" if path.to_s.empty?

          expanded = File.expand_path(path)
          raise ArgumentError, "Imported core MLIR not found: #{expanded}" unless File.file?(expanded)

          expanded
        end

        def normalize_import_verilog_selection!
          if @use_rhdl_source
            @use_staged_verilog = false
            @use_normalized_verilog = false
          elsif @use_normalized_verilog
            @use_staged_verilog = false
          elsif !@use_staged_verilog
            @use_staged_verilog = true
            @use_normalized_verilog = false
          end
        end

        def selected_import_verilog_path
          return nil if @use_rhdl_source

          @selected_import_verilog_path ||= begin
            candidates =
              if @use_staged_verilog
                [
                  @import_report.dig('artifacts', 'pure_verilog_entry_path'),
                  @import_report.dig('mixed_import', 'pure_verilog_entry_path'),
                  @import_report.dig('artifacts', 'workspace_pure_verilog_entry_path')
                ]
              else
                [
                  @import_report.dig('artifacts', 'normalized_verilog_path'),
                  @import_report.dig('mixed_import', 'normalized_verilog_path'),
                  @import_report.dig('artifacts', 'workspace_normalized_verilog_path')
                ]
              end

            Array(candidates).compact.map { |path| File.expand_path(path) }.find { |path| File.file?(path) }
          end
        end

        def rhdl_component_class
          @rhdl_component_class ||= resolve_component_class(hdl_dir: @import_root, top: requested_top_name)
        end

        def rhdl_top_module_name
          @rhdl_top_module_name ||= if rhdl_component_class.respond_to?(:verilog_module_name)
                                      rhdl_component_class.verilog_module_name.to_s
                                    else
                                      underscore_name(rhdl_component_class.name.to_s)
                                    end
        end

        def rhdl_source_dependency_paths
          @rhdl_source_dependency_paths ||= begin
            resolved_hdl_dir = HdlLoader.resolve_hdl_dir(hdl_dir: @import_root)
            Dir.glob(File.join(resolved_hdl_dir, '**', '*.rb'))
               .map { |path| File.expand_path(path) }
               .select { |path| File.file?(path) }
               .sort
          end
        end

        def rhdl_source_digest
          @rhdl_source_digest ||= Digest::SHA1.hexdigest(
            rhdl_source_dependency_paths.map { |path| "#{path}:#{File.mtime(path).to_i}:#{File.size(path)}" }.join('|')
          )[0, 12]
        end

        def import_support_paths_info
          @import_support_paths_info ||= begin
            mixed = @import_report['mixed_import'].is_a?(Hash) ? @import_report['mixed_import'] : {}
            components = Array(@import_report['components'])

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
        end

        def import_support_modules
          return [] if @use_staged_verilog

          import_support_paths_info.fetch(:modules)
        end

        def import_support_verilog_paths
          return [] if @use_staged_verilog
          return [] if selected_import_verilog_path.nil?
          return [] if File.read(selected_import_verilog_path).match?(/\bmodule\s+speedcontrol\b/)

          import_support_paths_info.fetch(:verilog_paths)
        end

        def wrapper_source_digest
          @wrapper_source_digest ||= selected_import_verilog_path && Digest::SHA1.file(selected_import_verilog_path).hexdigest[0, 12]
        end

        def build_artifact_stem
          @build_artifact_stem ||= begin
            source_path = if @use_rhdl_source
                            rhdl_source_dependency_paths.first || @import_root
                          else
                            selected_import_verilog_path || core_mlir_path
                          end
            seed = [
              @import_root,
              source_path,
              (@use_rhdl_source ? rhdl_source_digest : (wrapper_source_digest || core_mlir_digest)),
              requested_top_name,
              jit_mode? ? 'jit' : 'shared-lib',
              llvm_object_compiler,
              llvm_opt_level,
              llvm_threads.to_s,
              arcilator_split_funcs_threshold.to_s,
              (@use_rhdl_source ? 'rhdl' : (@use_staged_verilog ? 'staged' : 'normalized')),
              observe_flags.join(','),
              runner_source_digest
            ].join('|')
            Digest::SHA1.hexdigest(seed)[0, 12]
          end
        end

        def runner_source_digest
          @runner_source_digest ||= Digest::SHA1.file(__FILE__).hexdigest[0, 12]
        end

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, build_artifact_stem)
        end

        def shared_lib_path
          File.join(build_dir, 'libgameboy_arc_sim.so')
        end

        def runtime_bitcode_path
          File.join(build_dir, 'gameboy_arc_runtime.bc')
        end

        def llvm_object_path
          File.join(build_dir, 'gameboy_arc.o')
        end

        def linked_bitcode_path
          File.join(build_dir, 'gameboy_arc_jit.bc')
        end

        def core_mlir_digest
          @core_mlir_digest ||= Digest::SHA1.file(core_mlir_path).hexdigest[0, 12]
        end

        def check_tools_available!
          %w[arcilator firtool circt-opt].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end

          raise LoadError, 'circt-verilog not found in PATH' if selected_import_verilog_path && !command_available?('circt-verilog')

          if jit_mode?
            %w[lli llvm-link clang++].each do |tool|
              raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
            end
            return
          end

          raise LoadError, 'clang++ not found in PATH' unless command_available?('clang++')
          raise LoadError, 'llvm-link not found in PATH' unless command_available?('llvm-link')
          raise LoadError, 'Neither clang nor llc found in PATH' unless command_available?('clang') || command_available?('llc')
          return unless darwin_host?
          raise LoadError, 'clang++ not found in PATH' unless command_available?('clang++')
        end

        def command_available?(name)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            candidate = File.join(path, name)
            File.executable?(candidate) && !File.directory?(candidate)
          end
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)

          arc_dir = File.join(build_dir, 'arc')
          log_path = File.join(build_dir, 'arcilator.log')
          import_source_verilog_path = File.join(build_dir, 'gameboy_import_source.v')
          import_source_mlir_path = File.join(build_dir, 'gameboy_import_source.mlir')
          ll_path = File.join(build_dir, 'gameboy_arc.ll')
          state_path = File.join(build_dir, 'gameboy_state.json')
          wrapper_path = File.join(build_dir, 'arc_wrapper.cpp')
          wrapper_ll_path = File.join(build_dir, 'arc_wrapper.ll')
          lib_path = shared_lib_path
          jit_bc_path = linked_bitcode_path

          deps = [
            __FILE__,
            File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__),
            File.expand_path('../import/verilog_wrapper.rb', __dir__),
            import_report_path,
            (@use_rhdl_source ? nil : (selected_import_verilog_path || core_mlir_path)),
            *import_support_verilog_paths
          ].compact.select { |path| File.exist?(path) }
          deps.concat(rhdl_source_dependency_paths) if @use_rhdl_source

          needs_rebuild =
            !File.exist?(jit_mode? ? jit_bc_path : lib_path) ||
            !File.exist?(state_path) ||
            deps.any? { |path| File.mtime(path) > File.mtime(jit_mode? ? jit_bc_path : lib_path) }

          if needs_rebuild
            mlir_input_path =
              if @use_rhdl_source
                build_rhdl_mlir!(mlir_path: import_source_mlir_path)
              elsif selected_import_verilog_path
                build_source_mlir!(
                  verilog_path: import_source_verilog_path,
                  mlir_path: import_source_mlir_path,
                  top_name: state_top_name,
                  include_wrapper: using_import_wrapper?,
                  log_path: log_path
                )
              else
                core_mlir_path
              end
            prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
              mlir_path: mlir_input_path,
              work_dir: arc_dir,
              base_name: @use_rhdl_source ? rhdl_top_module_name : (using_import_wrapper? ? wrapper_module_name : imported_core_top_name),
              top: state_top_name
            )
            raise "ARC preparation failed:\n#{prepared.dig(:arc, :stderr)}" unless prepared[:success]
            RHDL::Codegen::CIRCT::Tooling.finalize_arc_mlir_for_arcilator!(
              arc_mlir_path: prepared.fetch(:arc_mlir_path),
              check_paths: [
                prepared[:normalized_llhd_mlir_path],
                prepared[:hwseq_mlir_path],
                prepared[:flattened_hwseq_mlir_path],
                prepared[:arc_mlir_path]
              ]
            )

            run_arcilator!(
              arc_mlir_path: prepared.fetch(:arc_mlir_path),
              state_path: state_path,
              ll_path: ll_path,
              log_path: log_path
            )
            state_info = parse_state_file!(state_path)
            cache_abi_signal_widths!(state_info)
            write_arcilator_wrapper(wrapper_path: wrapper_path, state_info: state_info)
            if jit_mode?
              compile_wrapper_llvm_ir!(wrapper_path: wrapper_path, wrapper_ll_path: wrapper_ll_path, log_path: log_path)
              link_jit_bitcode!(ll_path: ll_path, wrapper_ll_path: wrapper_ll_path, jit_bc_path: jit_bc_path, log_path: log_path)
            else
              build_runtime_library!(
                ll_path: ll_path,
                wrapper_path: wrapper_path,
                wrapper_ll_path: wrapper_ll_path,
                runtime_bitcode_path: runtime_bitcode_path,
                obj_path: llvm_object_path,
                lib_path: lib_path,
                log_path: log_path
              )
            end
          end

          cache_abi_signal_widths!(parse_state_file!(state_path)) unless @abi_signal_widths_by_name && @abi_signal_widths_by_idx

          @lib_path = lib_path
          @jit_bc_path = jit_bc_path
          @log_path = log_path
        end

        def build_source_mlir!(verilog_path:, mlir_path:, top_name:, include_wrapper:, log_path:)
          source_text = <<~VERILOG
            #{if include_wrapper
                gameboy_wrapper_source(
                  profile: gb_wrapper_profile(selected_import_verilog_path),
                  use_speedcontrol: wrapper_uses_imported_speedcontrol?
                ).strip
              end}

            #{File.read(selected_import_verilog_path)}
            #{import_support_verilog_paths.map { |path| File.read(path) }.join("\n\n")}
          VERILOG
          File.write(verilog_path, source_text)

          result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
            verilog_path: verilog_path,
            out_path: mlir_path,
            extra_args: ["--top=#{top_name}"]
          )
          existing_log = File.file?(log_path) ? File.read(log_path) : ''
          File.write(log_path, existing_log + result.fetch(:stdout, '') + result.fetch(:stderr, ''))
          return mlir_path if result[:success]

          raise "Imported Verilog -> MLIR conversion failed:\n#{result[:stdout]}\n#{result[:stderr]}"
        end

        def build_rhdl_mlir!(mlir_path:)
          File.write(mlir_path, rhdl_component_class.to_mlir_hierarchy(top_name: rhdl_top_module_name))
          mlir_path
        end

        def run_arcilator!(arc_mlir_path:, state_path:, ll_path:, log_path:)
          FileUtils.rm_f(state_path)
          FileUtils.rm_f(ll_path)
          extra_args = ['--async-resets-as-sync', *observe_flags]
          threshold = arcilator_split_funcs_threshold
          extra_args << "--split-funcs-threshold=#{threshold}" if threshold
          cmd = RHDL::Codegen::CIRCT::Tooling.arcilator_command(
            mlir_path: arc_mlir_path,
            state_file: state_path,
            out_path: ll_path,
            extra_args: extra_args
          )
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, "#{stdout}#{stderr}")
          return if status.success?

          raise "Arcilator compile failed:\n#{stdout}\n#{stderr}"
        end

        def parse_state_file!(path)
          state = JSON.parse(File.read(path))
          mod = state.find { |entry| entry['name'].to_s == state_top_name } || state.first
          raise "Arcilator state file missing module entries: #{path}" unless mod

          states = Array(mod['states'])
          specs = using_import_wrapper? ? WRAPPER_SIGNAL_SPECS : CORE_SIGNAL_SPECS
          signals = specs.each_with_object({}) do |(key, spec), acc|
            names = Array(spec[:names] || spec.fetch(:name))
            acc[key] = locate_signal(states, names, preferred_type: spec[:preferred_type])
          end

          missing = specs.filter_map do |key, spec|
            next if spec[:required] == false
            next if signals[key]

            key
          end
          unless missing.empty?
            raise "Arcilator state layout missing required Game Boy signals: #{missing.join(', ')}"
          end

          {
            module_name: mod.fetch('name'),
            state_size: mod.fetch('numStateBytes').to_i,
            signals: signals
          }
        end

        def cache_abi_signal_widths!(state_info)
          entries = abi_signal_entries(state_info)
          @abi_signal_widths_by_name = entries.each_with_object({}) do |(key, meta), widths|
            widths[key.to_s] = [meta.fetch(:bits).to_i, 1].max
          end
          @abi_signal_widths_by_idx = entries.map do |(key, _meta)|
            @abi_signal_widths_by_name.fetch(key.to_s, 32)
          end
        end

        def abi_signal_entries(state_info)
          signals = state_info.fetch(:signals)
          abi_entries = signals.compact.to_a.select { |_key, meta| meta.fetch(:bits).to_i <= 64 }
          input_entries = abi_entries.select { |_key, meta| meta.fetch(:type).to_s == 'input' }
          output_entries = abi_entries.reject { |_key, meta| meta.fetch(:type).to_s == 'input' }
          (input_entries + output_entries).uniq { |(key, _meta)| key }
        end

        def locate_signal(states, names, preferred_type:)
          names = Array(names).map(&:to_s)
          matches = states.select { |entry| names.include?(entry['name'].to_s) }
          return nil if matches.empty?

          match = matches.find { |entry| entry['type'].to_s == preferred_type.to_s } || matches.first
          {
            name: match.fetch('name'),
            offset: match.fetch('offset').to_i,
            bits: match.fetch('numBits').to_i,
            type: match['type'].to_s
          }
        end

        def manual_clock_enable_drive?(signals)
          return false if using_import_wrapper? && wrapper_uses_imported_speedcontrol?

          signals[:ce] && signals[:ce_n] && signals[:ce_2x]
        end

        def write_arcilator_wrapper(wrapper_path:, state_info:)
          return write_wrapper_top_arcilator_wrapper(wrapper_path: wrapper_path, state_info: state_info) if using_import_wrapper?

          module_name = state_info.fetch(:module_name)
          state_size = state_info.fetch(:state_size)
          signals = state_info.fetch(:signals)

          defines = signals.compact.map do |key, meta|
            macro = sanitize_macro(key)
            [
              "#define OFF_#{macro} #{meta.fetch(:offset)}",
              "#define BITS_#{macro} #{meta.fetch(:bits)}"
            ].join("\n")
          end.join("\n")

          static_tieoffs = CORE_STATIC_INPUT_VALUES.map do |key, value|
            macro = sanitize_macro(key)
            "  write_bits(ctx->state, OFF_#{macro}, BITS_#{macro}, #{format_c_integer(value)}ULL);"
          end.join("\n")

          abi_signal_entries = signals.compact.select { |_key, meta| meta.fetch(:bits).to_i <= 64 }
          abi_input_signal_entries = abi_signal_entries.select { |_key, meta| meta.fetch(:type).to_s == 'input' }
          abi_output_signal_entries = abi_signal_entries.reject { |_key, meta| meta.fetch(:type).to_s == 'input' }
          abi_input_names_csv = abi_input_signal_entries.map { |key, _| key.to_s }.join(',')
          abi_output_names_csv = abi_output_signal_entries.map { |key, _| key.to_s }.join(',')
          abi_signal_names_table = abi_signal_entries.map { |key, _| %("#{key}") }.join(",\n            ")
          abi_input_signal_names_table = abi_input_signal_entries.map { |key, _| %("#{key}") }.join(",\n            ")
          abi_output_signal_names_table = abi_output_signal_entries.map { |key, _| %("#{key}") }.join(",\n            ")
          abi_signal_index_lookup = abi_signal_entries.each_with_index.map do |(key, _meta), idx|
            %(if (strcmp(name, "#{key}") == 0) return #{idx};)
          end.join("\n              ")
          abi_signal_peek_cases = abi_signal_entries.each_with_index.map do |(key, _meta), idx|
            macro = sanitize_macro(key)
            %(case #{idx}: return static_cast<unsigned long>(read_bits(ctx->state, OFF_#{macro}, BITS_#{macro}));)
          end.join("\n                ")
          abi_signal_poke_cases = abi_input_signal_entries.each_with_index.map do |(key, _meta), idx|
            macro = sanitize_macro(key)
            %(case #{idx}: write_bits(ctx->state, OFF_#{macro}, BITS_#{macro}, value); return 1;)
          end.join("\n                ")

          wrapper = <<~CPP
            #include <stdint.h>
            #include <stdio.h>
            #include <stdlib.h>
            #include <string.h>

            extern "C" void #{module_name}_eval(void* state);

            #{defines}
            #define STATE_SIZE #{state_size}

            struct GbCycleResult {
              unsigned long cycles_run;
              unsigned int frames_completed;
            };

            struct SimContext {
              uint8_t state[STATE_SIZE];
              uint8_t rom[1024 * 1024];
              uint8_t boot_rom[256];
              uint8_t vram[8192];
              uint8_t framebuffer[160 * 144];
              unsigned int lcd_x;
              unsigned int lcd_y;
              uint8_t prev_lcd_clkena;
              uint8_t prev_lcd_vsync;
              unsigned long frame_count;
              unsigned long vram_write_count;
              unsigned int last_fetch_addr;
              unsigned int clk_counter;
              uint8_t joystick_state;
              uint8_t cart_type;
              uint8_t rom_size_code;
              uint8_t ram_size_code;
              uint16_t rom_bank_count;
              uint8_t mbc1_rom_bank_low5;
              uint8_t mbc1_bank_upper2;
              uint8_t mbc1_mode;
              uint8_t mbc1_ram_enabled;
            };

            struct RunnerCaps {
              int kind;
              unsigned int mem_spaces;
              unsigned int control_ops;
              unsigned int probe_ops;
            };

            struct RunnerRunResult {
              int text_dirty;
              int key_cleared;
              unsigned int cycles_run;
              unsigned int speaker_toggles;
              unsigned int frames_completed;
            };

            static inline size_t signal_num_bytes(unsigned int num_bits);
            static inline void write_bits(uint8_t* state, unsigned int offset, unsigned int num_bits, uint64_t value);
            static inline uint64_t read_bits(const uint8_t* state, unsigned int offset, unsigned int num_bits);

            static const char* k_input_signal_names[] = {
              #{abi_input_signal_names_table}
            };

            static const char* k_output_signal_names[] = {
              #{abi_output_signal_names_table}
            };

            static const char* k_signal_names[] = {
              #{abi_signal_names_table}
            };

            static const char k_input_names_csv[] = "#{abi_input_names_csv}";
            static const char k_output_names_csv[] = "#{abi_output_names_csv}";

            static const unsigned int k_signal_count = static_cast<unsigned int>(sizeof(k_signal_names) / sizeof(k_signal_names[0]));

            enum {
              SIM_CAP_SIGNAL_INDEX = 1u << 0,
              SIM_CAP_FORCED_CLOCK = 1u << 1,
              SIM_CAP_TRACE = 1u << 2,
              SIM_CAP_TRACE_STREAMING = 1u << 3,
              SIM_CAP_COMPILE = 1u << 4,
              SIM_CAP_GENERATED_CODE = 1u << 5,
              SIM_CAP_RUNNER = 1u << 6
            };

            enum {
              SIM_SIGNAL_HAS = 0u,
              SIM_SIGNAL_GET_INDEX = 1u,
              SIM_SIGNAL_PEEK = 2u,
              SIM_SIGNAL_POKE = 3u,
              SIM_SIGNAL_PEEK_INDEX = 4u,
              SIM_SIGNAL_POKE_INDEX = 5u
            };

            enum {
              SIM_EXEC_EVALUATE = 0u,
              SIM_EXEC_TICK = 1u,
              SIM_EXEC_TICK_FORCED = 2u,
              SIM_EXEC_SET_PREV_CLOCK = 3u,
              SIM_EXEC_GET_CLOCK_LIST_IDX = 4u,
              SIM_EXEC_RESET = 5u,
              SIM_EXEC_RUN_TICKS = 6u,
              SIM_EXEC_SIGNAL_COUNT = 7u,
              SIM_EXEC_REG_COUNT = 8u,
              SIM_EXEC_COMPILE = 9u,
              SIM_EXEC_IS_COMPILED = 10u
            };

            enum {
              SIM_TRACE_ENABLED = 3u
            };

            enum {
              SIM_BLOB_INPUT_NAMES = 0u,
              SIM_BLOB_OUTPUT_NAMES = 1u
            };

            enum {
              RUNNER_KIND_GAMEBOY = 3,
              RUNNER_MEM_OP_LOAD = 0u,
              RUNNER_MEM_OP_READ = 1u,
              RUNNER_MEM_OP_WRITE = 2u,
              RUNNER_MEM_SPACE_ROM = 1u,
              RUNNER_MEM_SPACE_BOOT_ROM = 2u,
              RUNNER_MEM_SPACE_FRAMEBUFFER = 6u,
              RUNNER_RUN_MODE_BASIC = 0u,
              RUNNER_CONTROL_RESET_LCD = 2u,
              RUNNER_PROBE_KIND = 0u,
              RUNNER_PROBE_IS_MODE = 1u,
              RUNNER_PROBE_FRAMEBUFFER_LEN = 3u,
              RUNNER_PROBE_FRAME_COUNT = 4u,
              RUNNER_PROBE_SIGNAL = 9u,
              RUNNER_PROBE_LCDC_ON = 10u,
              RUNNER_PROBE_LCD_X = 12u,
              RUNNER_PROBE_LCD_Y = 13u,
              RUNNER_PROBE_LCD_PREV_CLKENA = 14u,
              RUNNER_PROBE_LCD_PREV_VSYNC = 15u,
              RUNNER_PROBE_LCD_FRAME_COUNT = 16u
            };

            static inline void write_out_u32(unsigned int* out, unsigned int value) {
              if (out) *out = value;
            }

            static inline void write_out_ulong(unsigned long* out, unsigned long value) {
              if (out) *out = value;
            }

            static inline size_t copy_blob(unsigned char* out_ptr, size_t out_len, const char* text) {
              const size_t required = text ? strlen(text) : 0u;
              if (out_ptr && out_len && required) {
                size_t copy_len = required < out_len ? required : out_len;
                memcpy(out_ptr, text, copy_len);
              }
              return required;
            }

            static inline size_t signal_num_bytes(unsigned int num_bits);
            static inline void write_bits(uint8_t* state, unsigned int offset, unsigned int num_bits, uint64_t value);
            static inline uint64_t read_bits(const uint8_t* state, unsigned int offset, unsigned int num_bits);

            static inline int signal_index_from_name(const char* name) {
              if (!name) return -1;
              #{abi_signal_index_lookup}
              return -1;
            }

            static unsigned long signal_peek_by_index(SimContext* ctx, unsigned int idx) {
              switch (idx) {
                #{abi_signal_peek_cases}
                default: return 0ul;
              }
            }

            static int signal_poke_by_index(SimContext* ctx, unsigned int idx, unsigned long value) {
              switch (idx) {
                #{abi_signal_poke_cases}
                default: return 0;
              }
            }

            static inline size_t signal_num_bytes(unsigned int num_bits) {
              return (num_bits + 7u) / 8u;
            }

            static inline void write_bits(uint8_t* state, unsigned int offset, unsigned int num_bits, uint64_t value) {
              size_t num_bytes = signal_num_bytes(num_bits);
              memset(&state[offset], 0, num_bytes);
              size_t copy_bytes = num_bytes < sizeof(value) ? num_bytes : sizeof(value);
              memcpy(&state[offset], &value, copy_bytes);
              if (num_bits != 0u && (num_bits & 7u) != 0u) {
                uint8_t mask = static_cast<uint8_t>((1u << (num_bits & 7u)) - 1u);
                state[offset + num_bytes - 1u] &= mask;
              }
            }

            static inline uint64_t read_bits(const uint8_t* state, unsigned int offset, unsigned int num_bits) {
              uint64_t value = 0;
              size_t num_bytes = signal_num_bytes(num_bits);
              size_t copy_bytes = num_bytes < sizeof(value) ? num_bytes : sizeof(value);
              memcpy(&value, &state[offset], copy_bytes);
              if (num_bits < 64u && num_bits != 0u) {
                value &= ((uint64_t{1} << num_bits) - 1u);
              }
              return value;
            }

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
            }

            static unsigned char cart_read_byte(const SimContext* ctx, unsigned int full_addr) {
              unsigned int addr = full_addr & 0xFFFFu;
              if (!cart_is_mbc1(ctx)) {
                return (addr < sizeof(ctx->rom)) ? ctx->rom[addr] : 0xFFu;
              }
              if (addr > 0x7FFFu) return 0xFFu;

              unsigned int bank = 0u;
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

            static void cart_handle_write(SimContext* ctx, unsigned int full_addr, unsigned char value) {
              if (!cart_is_mbc1(ctx)) return;

              unsigned int addr = full_addr & 0x7FFFu;
              if (addr <= 0x1FFFu) {
                ctx->mbc1_ram_enabled = ((value & 0x0Fu) == 0x0Au) ? 1u : 0u;
              } else if (addr <= 0x3FFFu) {
                unsigned int bank = value & 0x1Fu;
                ctx->mbc1_rom_bank_low5 = (bank == 0u) ? 1u : bank;
              } else if (addr <= 0x5FFFu) {
                ctx->mbc1_bank_upper2 = value & 0x03u;
              } else if (addr <= 0x7FFFu) {
                ctx->mbc1_mode = value & 0x01u;
              }
            }

            static inline void eval_ctx(SimContext* ctx) {
              #{module_name}_eval(ctx->state);
            }

            static void apply_static_inputs(SimContext* ctx) {
          #{static_tieoffs}
              write_bits(ctx->state, OFF_JOYSTICK, BITS_JOYSTICK, ctx->joystick_state);
              write_bits(ctx->state, OFF_CART_DO, BITS_CART_DO, 0xFFu);
            }

            static void drive_clock_enable_inputs(SimContext* ctx) {
              unsigned int phase = ctx->clk_counter & 0x7u;
              write_bits(ctx->state, OFF_CE, BITS_CE, phase == 0u ? 1u : 0u);
              write_bits(ctx->state, OFF_CE_N, BITS_CE_N, phase == 4u ? 1u : 0u);
              write_bits(ctx->state, OFF_CE_2X, BITS_CE_2X, ((phase & 0x3u) == 0u) ? 1u : 0u);
            }

            static void drive_joypad_input(SimContext* ctx) {
              unsigned int joy = ctx->joystick_state & 0xFFu;
              unsigned int joy_p54 = static_cast<unsigned int>(read_bits(ctx->state, OFF_JOY_P54, BITS_JOY_P54)) & 0x3u;
              unsigned int p14 = joy_p54 & 0x1u;
              unsigned int p15 = (joy_p54 >> 1) & 0x1u;
              unsigned int joy_dir = joy & 0xFu;
              unsigned int joy_btn = (joy >> 4) & 0xFu;
              unsigned int joy_dir_masked = joy_dir | (p14 ? 0xFu : 0u);
              unsigned int joy_btn_masked = joy_btn | (p15 ? 0xFu : 0u);
              write_bits(ctx->state, OFF_JOYSTICK, BITS_JOYSTICK, joy);
              write_bits(ctx->state, OFF_JOY_DIN, BITS_JOY_DIN, joy_dir_masked & joy_btn_masked);
            }

            static unsigned int current_ext_bus_full_addr(const SimContext* ctx) {
              unsigned int addr = static_cast<unsigned int>(read_bits(ctx->state, OFF_EXT_BUS_ADDR, BITS_EXT_BUS_ADDR)) & 0x7FFFu;
              unsigned int a15 = static_cast<unsigned int>(read_bits(ctx->state, OFF_EXT_BUS_A15, BITS_EXT_BUS_A15)) & 0x1u;
              return (a15 << 15) | addr;
            }

            static void drive_cartridge_input(SimContext* ctx) {
              unsigned int full_addr = current_ext_bus_full_addr(ctx);
              unsigned int reset_active = static_cast<unsigned int>(read_bits(ctx->state, OFF_RESET, BITS_RESET)) & 0x1u;
              unsigned int cart_rd = static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_RD, BITS_CART_RD)) & 0x1u;
              unsigned int cart_wr = static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_WR, BITS_CART_WR)) & 0x1u;
              unsigned int cart_di = static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_DI, BITS_CART_DI)) & 0xFFu;

              if (!reset_active && cart_wr) {
                cart_handle_write(ctx, full_addr, static_cast<unsigned char>(cart_di));
              }

              unsigned int cart_do = cart_rd ? cart_read_byte(ctx, full_addr) : 0xFFu;
              write_bits(ctx->state, OFF_CART_DO, BITS_CART_DO, cart_do);

              if (cart_rd) {
                ctx->last_fetch_addr = full_addr;
              }
            }

            static void capture_lcd_output(SimContext* ctx, GbCycleResult* result) {
              unsigned int lcd_clkena = static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_CLKENA, BITS_LCD_CLKENA)) & 0x1u;
              unsigned int lcd_vsync = static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_VSYNC, BITS_LCD_VSYNC)) & 0x1u;
              unsigned int lcd_data = static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_DATA_GB, BITS_LCD_DATA_GB)) & 0x3u;
              unsigned int pixel_we = lcd_clkena;
          #{if signals[:speed_ctrl_ce]
                '    pixel_we &= static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_CE, BITS_SPEED_CTRL_CE)) & 0x1u;'
              elsif signals[:ce]
                '    pixel_we &= static_cast<unsigned int>(read_bits(ctx->state, OFF_CE, BITS_CE)) & 0x1u;'
              else
                ''
              end}

              if (lcd_vsync != 0u && ctx->prev_lcd_vsync == 0u) {
                ctx->lcd_x = 0u;
                ctx->lcd_y = 0u;
                ctx->frame_count++;
                if (result) result->frames_completed++;
              } else if (pixel_we != 0u) {
                if (ctx->lcd_x < 160u && ctx->lcd_y < 144u) {
                  ctx->framebuffer[(ctx->lcd_y * 160u) + ctx->lcd_x] = static_cast<uint8_t>(lcd_data);
                }
                ctx->lcd_x++;
                if (ctx->lcd_x >= 160u) {
                  ctx->lcd_x = 0u;
                  ctx->lcd_y++;
                }
              }

              ctx->prev_lcd_clkena = static_cast<uint8_t>(lcd_clkena);
              ctx->prev_lcd_vsync = static_cast<uint8_t>(lcd_vsync);
            }

            static void run_single_cycle(SimContext* ctx, GbCycleResult* result) {
              write_bits(ctx->state, OFF_CLK_SYS, BITS_CLK_SYS, 0u);
              drive_clock_enable_inputs(ctx);
              eval_ctx(ctx);
              drive_joypad_input(ctx);
              drive_cartridge_input(ctx);
              eval_ctx(ctx);

              write_bits(ctx->state, OFF_CLK_SYS, BITS_CLK_SYS, 1u);
              drive_clock_enable_inputs(ctx);
              eval_ctx(ctx);
              drive_joypad_input(ctx);
              drive_cartridge_input(ctx);
              eval_ctx(ctx);

              ctx->clk_counter++;
              if (result) result->cycles_run++;
              capture_lcd_output(ctx, result);
            }

            static void upload_boot_rom(SimContext* ctx) {
              write_bits(ctx->state, OFF_DMG_BOOT_DOWNLOAD, BITS_DMG_BOOT_DOWNLOAD, 1u);
              for (unsigned int index = 0; index < 128u; ++index) {
                unsigned int lo = ctx->boot_rom[index * 2u];
                unsigned int hi = ctx->boot_rom[(index * 2u) + 1u];
                write_bits(ctx->state, OFF_IOCTL_ADDR, BITS_IOCTL_ADDR, index * 2u);
                write_bits(ctx->state, OFF_IOCTL_DOUT, BITS_IOCTL_DOUT, (hi << 8u) | lo);
                write_bits(ctx->state, OFF_IOCTL_WR, BITS_IOCTL_WR, 1u);
                run_single_cycle(ctx, nullptr);
              }
              write_bits(ctx->state, OFF_IOCTL_WR, BITS_IOCTL_WR, 0u);
              write_bits(ctx->state, OFF_DMG_BOOT_DOWNLOAD, BITS_DMG_BOOT_DOWNLOAD, 0u);
            }

            extern "C" {

            void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** err_out) {
              (void)json;
              (void)json_len;
              (void)sub_cycles;
              if (err_out) *err_out = nullptr;
              SimContext* ctx = static_cast<SimContext*>(malloc(sizeof(SimContext)));
              if (!ctx) return nullptr;
              memset(ctx->state, 0, sizeof(ctx->state));
              memset(ctx->rom, 0, sizeof(ctx->rom));
              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0u;
              ctx->lcd_y = 0u;
              ctx->prev_lcd_clkena = 0u;
              ctx->prev_lcd_vsync = 0u;
              ctx->frame_count = 0u;
              ctx->last_fetch_addr = 0u;
              ctx->clk_counter = 0u;
              ctx->joystick_state = 0xFFu;
              ctx->cart_type = 0u;
              ctx->rom_size_code = 0u;
              ctx->ram_size_code = 0u;
              ctx->rom_bank_count = 2u;
              cart_reset_runtime_state(ctx);
              apply_static_inputs(ctx);
              eval_ctx(ctx);
              return ctx;
            }

            void sim_destroy(void* sim) {
              free(static_cast<SimContext*>(sim));
            }

            void sim_free_error(char* error) {
              if (error) free(error);
            }

            void sim_free_string(char* string) {
              if (string) free(string);
            }

            void* sim_wasm_alloc(size_t size) {
              return malloc(size);
            }

            void sim_wasm_dealloc(void* ptr, size_t size) {
              (void)size;
              free(ptr);
            }

            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0u;
              ctx->lcd_y = 0u;
              ctx->prev_lcd_clkena = 0u;
              ctx->prev_lcd_vsync = 0u;
              ctx->frame_count = 0u;
              ctx->last_fetch_addr = 0u;
              ctx->clk_counter = 0u;
              ctx->joystick_state = 0xFFu;
              cart_reset_runtime_state(ctx);
              apply_static_inputs(ctx);

              write_bits(ctx->state, OFF_RESET, BITS_RESET, 1u);
              for (int i = 0; i < 10; ++i) {
                run_single_cycle(ctx, nullptr);
              }

              upload_boot_rom(ctx);

              write_bits(ctx->state, OFF_RESET, BITS_RESET, 0u);
              for (int i = 0; i < 100; ++i) {
                run_single_cycle(ctx, nullptr);
              }

              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0u;
              ctx->lcd_y = 0u;
              ctx->prev_lcd_clkena = 0u;
              ctx->prev_lcd_vsync = 0u;
              ctx->frame_count = 0u;
              ctx->last_fetch_addr = 0u;
              ctx->clk_counter = 0u;
            }

            void sim_set_joystick(void* sim, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->joystick_state = static_cast<uint8_t>(value & 0xFFu);
              write_bits(ctx->state, OFF_JOYSTICK, BITS_JOYSTICK, ctx->joystick_state);
            }

            void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memset(ctx->rom, 0, sizeof(ctx->rom));
              for (unsigned int i = 0; i < len && i < sizeof(ctx->rom); ++i) {
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
              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
              for (unsigned int i = 0; i < len && i < sizeof(ctx->boot_rom); ++i) {
                ctx->boot_rom[i] = data[i];
              }
            }

            void sim_read_framebuffer(void* sim, unsigned char* out_buffer) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memcpy(out_buffer, ctx->framebuffer, sizeof(ctx->framebuffer));
            }

            unsigned int sim_get_last_fetch_addr(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->last_fetch_addr;
            }

            unsigned int sim_get_ext_bus_full_addr(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return current_ext_bus_full_addr(ctx);
            }

            unsigned int sim_get_lcd_on(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_ON, BITS_LCD_ON)) & 0x1u;
            }

            unsigned long sim_get_frame_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->frame_count;
            }

            int sim_get_caps(void* sim, unsigned int* caps_out) {
              (void)sim;
              write_out_u32(caps_out, SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER);
              return 1;
            }

            int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) {
                write_out_ulong(out_value, 0ul);
                return 0;
              }

              int resolved_idx = (name && name[0]) ? signal_index_from_name(name) : static_cast<int>(idx);
              switch (op) {
              case SIM_SIGNAL_HAS:
                write_out_ulong(out_value, resolved_idx >= 0 ? 1ul : 0ul);
                return resolved_idx >= 0 ? 1 : 0;
              case SIM_SIGNAL_GET_INDEX:
                if (resolved_idx < 0) {
                  write_out_ulong(out_value, 0ul);
                  return 0;
                }
                write_out_ulong(out_value, static_cast<unsigned long>(resolved_idx));
                return 1;
              case SIM_SIGNAL_PEEK:
              case SIM_SIGNAL_PEEK_INDEX:
                if (resolved_idx < 0) {
                  write_out_ulong(out_value, 0ul);
                  return 0;
                }
                write_out_ulong(out_value, signal_peek_by_index(ctx, static_cast<unsigned int>(resolved_idx)));
                return 1;
              case SIM_SIGNAL_POKE:
              case SIM_SIGNAL_POKE_INDEX:
                if (resolved_idx < 0) {
                  write_out_ulong(out_value, 0ul);
                  return 0;
                }
                {
                  int rc = signal_poke_by_index(ctx, static_cast<unsigned int>(resolved_idx), value);
                  write_out_ulong(out_value, rc != 0 ? 1ul : 0ul);
                  return rc;
                }
              default:
                write_out_ulong(out_value, 0ul);
                return 0;
              }
            }

            void sim_run_cycles(void* sim, unsigned int n_cycles, GbCycleResult* result) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              result->cycles_run = 0u;
              result->frames_completed = 0u;
              while (result->cycles_run < n_cycles) {
                run_single_cycle(ctx, result);
              }
            }

            int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, char** err_out) {
              (void)arg1;
              if (err_out) *err_out = nullptr;
              write_out_ulong(out_value, 0ul);

              switch (op) {
              case SIM_EXEC_EVALUATE:
                eval_ctx(static_cast<SimContext*>(sim));
                return 1;
              case SIM_EXEC_TICK: {
                GbCycleResult result = {0u, 0u};
                sim_run_cycles(sim, 1u, &result);
                write_out_ulong(out_value, result.cycles_run);
                return 1;
              }
              case SIM_EXEC_RESET:
                sim_reset(sim);
                return 1;
              case SIM_EXEC_RUN_TICKS: {
                GbCycleResult result = {0u, 0u};
                sim_run_cycles(sim, static_cast<unsigned int>(arg0), &result);
                write_out_ulong(out_value, result.cycles_run);
                return 1;
              }
              case SIM_EXEC_SIGNAL_COUNT:
                write_out_ulong(out_value, static_cast<unsigned long>(k_signal_count));
                return 1;
              case SIM_EXEC_REG_COUNT:
                return 1;
              default:
                return 0;
              }
            }

            int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
              (void)sim;
              (void)str_arg;
              if (op == SIM_TRACE_ENABLED) {
                write_out_ulong(out_value, 0ul);
                return 1;
              }
              write_out_ulong(out_value, 0ul);
              return 0;
            }

            size_t sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, size_t out_len) {
              (void)sim;
              switch (op) {
              case SIM_BLOB_INPUT_NAMES:
                return copy_blob(out_ptr, out_len, k_input_names_csv);
              case SIM_BLOB_OUTPUT_NAMES:
                return copy_blob(out_ptr, out_len, k_output_names_csv);
              default:
                return 0u;
              }
            }

            int runner_get_caps(void* sim, RunnerCaps* caps_out) {
              (void)sim;
              if (!caps_out) return 0;
              caps_out->kind = RUNNER_KIND_GAMEBOY;
              caps_out->mem_spaces =
                (1u << RUNNER_MEM_SPACE_ROM) |
                (1u << RUNNER_MEM_SPACE_BOOT_ROM) |
                (1u << RUNNER_MEM_SPACE_FRAMEBUFFER);
              caps_out->control_ops = (1u << RUNNER_CONTROL_RESET_LCD);
              caps_out->probe_ops =
                (1u << RUNNER_PROBE_KIND) |
                (1u << RUNNER_PROBE_IS_MODE) |
                (1u << RUNNER_PROBE_FRAMEBUFFER_LEN) |
                (1u << RUNNER_PROBE_FRAME_COUNT) |
                (1u << RUNNER_PROBE_SIGNAL) |
                (1u << RUNNER_PROBE_LCDC_ON) |
                (1u << RUNNER_PROBE_LCD_X) |
                (1u << RUNNER_PROBE_LCD_Y) |
                (1u << RUNNER_PROBE_LCD_PREV_CLKENA) |
                (1u << RUNNER_PROBE_LCD_PREV_VSYNC) |
                (1u << RUNNER_PROBE_LCD_FRAME_COUNT);
              return 1;
            }

            size_t runner_mem(void* sim, unsigned int op, unsigned int space, size_t offset, unsigned char* ptr, size_t len, unsigned int flags) {
              (void)flags;
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0u;

              if (op == RUNNER_MEM_OP_LOAD) {
                if (!ptr || len == 0u) return 0u;
                if (space == RUNNER_MEM_SPACE_ROM) {
                  sim_load_rom(sim, ptr, static_cast<unsigned int>(len));
                  return len;
                }
                if (space == RUNNER_MEM_SPACE_BOOT_ROM) {
                  sim_load_boot_rom(sim, ptr, static_cast<unsigned int>(len));
                  return len;
                }
                return 0u;
              }

              if (!ptr) return 0u;
              if (op == RUNNER_MEM_OP_READ) {
                if (space == RUNNER_MEM_SPACE_BOOT_ROM) {
                  size_t copied = 0u;
                  for (; copied < len && (offset + copied) < sizeof(ctx->boot_rom); ++copied) ptr[copied] = ctx->boot_rom[offset + copied];
                  return copied;
                }
                if (space == RUNNER_MEM_SPACE_FRAMEBUFFER) {
                  if (offset >= sizeof(ctx->framebuffer)) return 0u;
                  size_t available = sizeof(ctx->framebuffer) - offset;
                  size_t copy_len = available < len ? available : len;
                  memcpy(ptr, ctx->framebuffer + offset, copy_len);
                  return copy_len;
                }
                if (space == RUNNER_MEM_SPACE_ROM) {
                  if (offset >= sizeof(ctx->rom)) return 0u;
                  size_t available = sizeof(ctx->rom) - offset;
                  size_t copy_len = available < len ? available : len;
                  memcpy(ptr, ctx->rom + offset, copy_len);
                  return copy_len;
                }
                return 0u;
              }

              return 0u;
            }

            int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, RunnerRunResult* result_out) {
              (void)mode;
              if (key_ready) sim_set_joystick(sim, key_data);
              GbCycleResult result = {0u, 0u};
              sim_run_cycles(sim, cycles, &result);
              if (result_out) {
                result_out->text_dirty = result.frames_completed > 0 ? 1 : 0;
                result_out->key_cleared = key_ready ? 1 : 0;
                result_out->cycles_run = static_cast<unsigned int>(result.cycles_run);
                result_out->speaker_toggles = 0u;
                result_out->frames_completed = result.frames_completed;
              }
              return 1;
            }

            int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) {
              (void)arg0;
              (void)arg1;
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              if (op == RUNNER_CONTROL_RESET_LCD) {
                memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
                ctx->lcd_x = 0u;
                ctx->lcd_y = 0u;
                ctx->prev_lcd_clkena = 0u;
                ctx->prev_lcd_vsync = 0u;
                ctx->frame_count = 0u;
                return 1;
              }
              return 0;
            }

            unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0ull;
              switch (op) {
              case RUNNER_PROBE_KIND:
                return RUNNER_KIND_GAMEBOY;
              case RUNNER_PROBE_IS_MODE:
                return 0ull;
              case RUNNER_PROBE_FRAMEBUFFER_LEN:
                return sizeof(ctx->framebuffer);
              case RUNNER_PROBE_FRAME_COUNT:
              case RUNNER_PROBE_LCD_FRAME_COUNT:
                return ctx->frame_count;
              case RUNNER_PROBE_SIGNAL:
                return signal_peek_by_index(ctx, arg0);
              case RUNNER_PROBE_LCDC_ON:
                return sim_get_lcd_on(sim);
              case RUNNER_PROBE_LCD_X:
                return ctx->lcd_x;
              case RUNNER_PROBE_LCD_Y:
                return ctx->lcd_y;
              case RUNNER_PROBE_LCD_PREV_CLKENA:
                return ctx->prev_lcd_clkena;
              case RUNNER_PROBE_LCD_PREV_VSYNC:
                return ctx->prev_lcd_vsync;
              default:
                return 0ull;
              }
            }

            }  // extern "C"

            unsigned int sim_get_last_fetch_addr(void* sim);
            unsigned int sim_get_ext_bus_full_addr(void* sim);
            unsigned int sim_get_lcd_on(void* sim);
            unsigned long sim_get_frame_count(void* sim);
            unsigned int sim_get_boot_upload_active(void* sim);
            unsigned int sim_get_boot_upload_phase(void* sim);
            unsigned int sim_get_boot_upload_index(void* sim);
            unsigned int sim_get_boot_upload_low_byte(void* sim);
            unsigned int sim_get_gb_core_reset_r(void* sim);
            unsigned int sim_get_gb_core_boot_rom_enabled(void* sim);
            unsigned int sim_get_gb_core_boot_q(void* sim);
            unsigned int sim_get_ext_bus_a15(void* sim);
            unsigned int sim_get_cart_rd(void* sim);
            unsigned int sim_get_cart_wr(void* sim);
            unsigned int sim_get_cart_do(void* sim);
            unsigned int sim_get_lcd_clkena(void* sim);
            unsigned int sim_get_lcd_data_gb(void* sim);
            unsigned int sim_get_lcd_vsync(void* sim);
            unsigned int sim_get_gb_core_cpu_pc(void* sim);
            unsigned int sim_get_gb_core_cpu_ir(void* sim);
            unsigned int sim_get_gb_core_cpu_tstate(void* sim);
            unsigned int sim_get_gb_core_cpu_mcycle(void* sim);
            unsigned int sim_get_gb_core_cpu_addr(void* sim);
            unsigned int sim_get_gb_core_cpu_di(void* sim);
            unsigned int sim_get_gb_core_cpu_do(void* sim);
            unsigned int sim_get_gb_core_cpu_m1_n(void* sim);
            unsigned int sim_get_gb_core_cpu_mreq_n(void* sim);
            unsigned int sim_get_gb_core_cpu_iorq_n(void* sim);
            unsigned int sim_get_gb_core_cpu_rd_n(void* sim);
            unsigned int sim_get_gb_core_cpu_wr_n(void* sim);
            unsigned int sim_get_speed_ctrl_ce(void* sim);
            unsigned int sim_get_speed_ctrl_ce_n(void* sim);
            unsigned int sim_get_speed_ctrl_ce_2x(void* sim);
            unsigned int sim_get_speed_ctrl_state(void* sim);
            unsigned int sim_get_speed_ctrl_clkdiv(void* sim);
            unsigned int sim_get_speed_ctrl_unpause_cnt(void* sim);
            unsigned int sim_get_speed_ctrl_fastforward_cnt(void* sim);
            unsigned int sim_get_video_h_cnt(void* sim);
            unsigned int sim_get_video_v_cnt(void* sim);
            unsigned int sim_get_video_scy(void* sim);
            unsigned int sim_get_video_scx(void* sim);
            unsigned int sim_get_video_bg_palette(void* sim);
            unsigned int sim_get_video_obj_palette0(void* sim);
            unsigned int sim_get_video_obj_palette1(void* sim);
            unsigned int sim_get_video_bg_shift_lo(void* sim);
            unsigned int sim_get_video_bg_shift_hi(void* sim);
            unsigned int sim_get_video_bg_attr(void* sim);
            unsigned int sim_get_video_obj_shift_lo(void* sim);
            unsigned int sim_get_video_obj_shift_hi(void* sim);
            unsigned int sim_get_video_obj_meta0(void* sim);
            unsigned int sim_get_video_obj_meta1(void* sim);
            unsigned int sim_get_video_fetch_phase(void* sim);
            unsigned int sim_get_video_fetch_slot(void* sim);
            unsigned int sim_get_video_fetch_hold0(void* sim);
            unsigned int sim_get_video_fetch_hold1(void* sim);
            unsigned int sim_get_video_fetch_data0(void* sim);
            unsigned int sim_get_video_fetch_data1(void* sim);
            unsigned int sim_get_video_tile_lo(void* sim);
            unsigned int sim_get_video_tile_hi(void* sim);
            unsigned int sim_get_video_input_vram_data(void* sim);
            unsigned int sim_get_video_input_vram1_data(void* sim);
            unsigned int sim_get_vram0_q_a_reg(void* sim);
            unsigned int sim_get_vram1_q_a_reg(void* sim);
            unsigned long sim_get_vram_write_count(void* sim);

            #ifdef ARCI_JIT_MAIN
            static int hex_nibble(char ch) {
              if (ch >= '0' && ch <= '9') return ch - '0';
              if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
              if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
              return -1;
            }

            static bool decode_hex_payload(const char* hex, unsigned char* out, size_t out_cap, size_t* out_len) {
              size_t hex_len = strlen(hex);
              if ((hex_len & 1u) != 0u) return false;
              size_t byte_len = hex_len / 2u;
              if (byte_len > out_cap) return false;
              memset(out, 0, out_cap);
              for (size_t i = 0; i < byte_len; ++i) {
                int hi = hex_nibble(hex[i * 2u]);
                int lo = hex_nibble(hex[(i * 2u) + 1u]);
                if (hi < 0 || lo < 0) return false;
                out[i] = static_cast<unsigned char>((hi << 4) | lo);
              }
              if (out_len) *out_len = byte_len;
              return true;
            }

            static void write_hex_bytes(FILE* out, const unsigned char* bytes, size_t len) {
              static const char* digits = "0123456789abcdef";
              for (size_t i = 0; i < len; ++i) {
                unsigned int value = bytes[i];
                fputc(digits[(value >> 4) & 0xFu], out);
                fputc(digits[value & 0xFu], out);
              }
            }

            int main(int argc, char** argv) {
              (void)argc;
              (void)argv;
              SimContext* ctx = static_cast<SimContext*>(sim_create(nullptr, 0u, 0u, nullptr));
              if (!ctx) return 1;

              unsigned int sim_get_gb_core_boot_q(void* sim);
              unsigned int sim_get_gb_core_cpu_di(void* sim);
              unsigned int sim_get_gb_core_cpu_m1_n(void* sim);
              unsigned int sim_get_gb_core_cpu_mreq_n(void* sim);
              unsigned int sim_get_gb_core_cpu_iorq_n(void* sim);
              unsigned int sim_get_gb_core_cpu_rd_n(void* sim);
              unsigned int sim_get_gb_core_cpu_wr_n(void* sim);
              unsigned int sim_get_speed_ctrl_state(void* sim);
              unsigned int sim_get_speed_ctrl_clkdiv(void* sim);
              unsigned int sim_get_speed_ctrl_unpause_cnt(void* sim);
              unsigned int sim_get_speed_ctrl_fastforward_cnt(void* sim);
              unsigned int sim_get_video_scy(void* sim);
              unsigned int sim_get_video_scx(void* sim);
              unsigned int sim_get_video_bg_palette(void* sim);
              unsigned int sim_get_video_obj_palette0(void* sim);
              unsigned int sim_get_video_obj_palette1(void* sim);
              unsigned int sim_get_video_bg_shift_lo(void* sim);
              unsigned int sim_get_video_bg_shift_hi(void* sim);
              unsigned int sim_get_video_bg_attr(void* sim);
              unsigned int sim_get_video_obj_shift_lo(void* sim);
              unsigned int sim_get_video_obj_shift_hi(void* sim);
              unsigned int sim_get_video_obj_meta0(void* sim);
              unsigned int sim_get_video_obj_meta1(void* sim);
              unsigned int sim_get_video_fetch_phase(void* sim);
              unsigned int sim_get_video_fetch_slot(void* sim);
              unsigned int sim_get_video_fetch_hold0(void* sim);
              unsigned int sim_get_video_fetch_hold1(void* sim);
              unsigned int sim_get_video_fetch_data0(void* sim);
              unsigned int sim_get_video_fetch_data1(void* sim);
              unsigned int sim_get_video_tile_lo(void* sim);
              unsigned int sim_get_video_tile_hi(void* sim);
              unsigned int sim_get_video_input_vram_data(void* sim);
              unsigned int sim_get_video_input_vram1_data(void* sim);
              unsigned int sim_get_vram0_q_a_reg(void* sim);
              unsigned int sim_get_vram1_q_a_reg(void* sim);

              fprintf(stdout, "READY\\n");
              fflush(stdout);

              char* line = nullptr;
              size_t cap = 0;
              while (getline(&line, &cap, stdin) != -1) {
                size_t len = strlen(line);
                while (len > 0u && (line[len - 1u] == '\\n' || line[len - 1u] == '\\r')) {
                  line[--len] = '\\0';
                }

                if (strcmp(line, "RESET") == 0) {
                  sim_reset(ctx);
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "SET_JOYSTICK ", 13) == 0) {
                  unsigned long value = strtoul(line + 13, nullptr, 10);
                  sim_set_joystick(ctx, static_cast<unsigned int>(value));
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "LOAD_ROM ", 9) == 0) {
                  size_t payload_len = 0u;
                  if (!decode_hex_payload(line + 9, ctx->rom, sizeof(ctx->rom), &payload_len)) {
                    fprintf(stdout, "ERR LOAD_ROM\\n");
                    fflush(stdout);
                    continue;
                  }
                  ctx->cart_type = ctx->rom[0x147];
                  ctx->rom_size_code = ctx->rom[0x148];
                  ctx->ram_size_code = ctx->rom[0x149];
                  ctx->rom_bank_count = cart_rom_bank_count(ctx->rom_size_code);
                  cart_reset_runtime_state(ctx);
                  fprintf(stdout, "OK %zu\\n", payload_len);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "LOAD_BOOT_ROM ", 14) == 0) {
                  size_t payload_len = 0u;
                  if (!decode_hex_payload(line + 14, ctx->boot_rom, sizeof(ctx->boot_rom), &payload_len)) {
                    fprintf(stdout, "ERR LOAD_BOOT_ROM\\n");
                    fflush(stdout);
                    continue;
                  }
                  fprintf(stdout, "OK %zu\\n", payload_len);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "RUN ", 4) == 0) {
                  unsigned long requested = strtoul(line + 4, nullptr, 10);
                  GbCycleResult result;
                  sim_run_cycles(ctx, static_cast<unsigned int>(requested), &result);
                  fprintf(stdout, "RUN %lu %u %lu\\n", result.cycles_run, result.frames_completed, ctx->frame_count);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "GET_FB") == 0) {
                  fputs("FB ", stdout);
                  write_hex_bytes(stdout, ctx->framebuffer, sizeof(ctx->framebuffer));
                  fputc('\\n', stdout);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "GET_STATE") == 0) {
                  fprintf(
                    stdout,
                    "STATE %u %u %u %lu\\n",
                    sim_get_last_fetch_addr(ctx),
                    sim_get_ext_bus_full_addr(ctx),
                    sim_get_lcd_on(ctx),
                    sim_get_frame_count(ctx)
                  );
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "QUIT") == 0) {
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  break;
                }

                fprintf(stdout, "ERR UNKNOWN\\n");
                fflush(stdout);
              }

              free(line);
              sim_destroy(ctx);
              return 0;
            }
            #endif
          CPP

          File.write(wrapper_path, wrapper)
        end

        def write_wrapper_top_arcilator_wrapper(wrapper_path:, state_info:)
          module_name = state_info.fetch(:module_name)
          state_size = state_info.fetch(:state_size)
          signals = state_info.fetch(:signals)

          defines = signals.compact.map do |key, meta|
            macro = sanitize_macro(key)
            [
              "#define OFF_#{macro} #{meta.fetch(:offset)}",
              "#define BITS_#{macro} #{meta.fetch(:bits)}"
            ].join("\n")
          end.join("\n")

          static_tieoffs = WRAPPER_STATIC_INPUT_VALUES.filter_map do |key, value|
            meta = signals[key]
            next if meta.nil?

            macro = sanitize_macro(key)
            "  write_bits(ctx->state, OFF_#{macro}, BITS_#{macro}, #{format_c_integer(value)}ULL);"
          end.join("\n")

          clock_enable_lines =
            if manual_clock_enable_drive?(signals)
              <<~CPP.chomp
                unsigned int phase = ctx->clk_counter & 0x7u;
                write_bits(ctx->state, OFF_CE, BITS_CE, phase == 0u ? 1u : 0u);
                write_bits(ctx->state, OFF_CE_N, BITS_CE_N, phase == 4u ? 1u : 0u);
                write_bits(ctx->state, OFF_CE_2X, BITS_CE_2X, ((phase & 0x3u) == 0u) ? 1u : 0u);
              CPP
            else
              '(void)ctx;'
            end

          boot_upload_getters =
            if signals[:boot_upload_active] && signals[:boot_upload_phase] && signals[:boot_upload_index] && signals[:boot_upload_low_byte]
              <<~CPP.chomp
                unsigned int sim_get_boot_upload_active(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_BOOT_UPLOAD_ACTIVE, BITS_BOOT_UPLOAD_ACTIVE)) & 0x1u;
                }

                unsigned int sim_get_boot_upload_phase(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_BOOT_UPLOAD_PHASE, BITS_BOOT_UPLOAD_PHASE)) & 0x1u;
                }

                unsigned int sim_get_boot_upload_index(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_BOOT_UPLOAD_INDEX, BITS_BOOT_UPLOAD_INDEX)) & 0xFFu;
                }

                unsigned int sim_get_boot_upload_low_byte(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_BOOT_UPLOAD_LOW_BYTE, BITS_BOOT_UPLOAD_LOW_BYTE)) & 0xFFu;
                }

                unsigned int sim_get_ext_bus_a15(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_EXT_BUS_A15, BITS_EXT_BUS_A15)) & 0x1u;
                }

                unsigned int sim_get_cart_rd(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_RD, BITS_CART_RD)) & 0x1u;
                }

                unsigned int sim_get_cart_wr(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_WR, BITS_CART_WR)) & 0x1u;
                }

                unsigned int sim_get_cart_do(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_DO, BITS_CART_DO)) & 0xFFu;
                }

                unsigned int sim_get_lcd_clkena(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_CLKENA, BITS_LCD_CLKENA)) & 0x1u;
                }

                unsigned int sim_get_lcd_data_gb(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_DATA_GB, BITS_LCD_DATA_GB)) & 0x3u;
                }

                unsigned int sim_get_lcd_vsync(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_VSYNC, BITS_LCD_VSYNC)) & 0x1u;
                }

                #{if signals[:gb_core_cpu_pc]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_pc(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_PC, BITS_GB_CORE_CPU_PC)) & 0xFFFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_pc(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_ir]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_ir(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_IR, BITS_GB_CORE_CPU_IR)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_ir(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_tstate]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_tstate(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_TSTATE, BITS_GB_CORE_CPU_TSTATE)) & 0x7u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_tstate(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_mcycle]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_mcycle(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_MCYCLE, BITS_GB_CORE_CPU_MCYCLE)) & 0x7u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_mcycle(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_addr]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_addr(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_ADDR, BITS_GB_CORE_CPU_ADDR)) & 0xFFFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_addr(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_di]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_di(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_DI, BITS_GB_CORE_CPU_DI)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_di(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_do]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_do(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_DO, BITS_GB_CORE_CPU_DO)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_do(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_m1_n]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_m1_n(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_M1_N, BITS_GB_CORE_CPU_M1_N)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_m1_n(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_mreq_n]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_mreq_n(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_MREQ_N, BITS_GB_CORE_CPU_MREQ_N)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_mreq_n(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_iorq_n]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_iorq_n(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_IORQ_N, BITS_GB_CORE_CPU_IORQ_N)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_iorq_n(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_rd_n]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_rd_n(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_RD_N, BITS_GB_CORE_CPU_RD_N)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_rd_n(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_cpu_wr_n]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_wr_n(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_CPU_WR_N, BITS_GB_CORE_CPU_WR_N)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_cpu_wr_n(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_ce]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_ce(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_CE, BITS_SPEED_CTRL_CE)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_ce(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_ce_n]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_ce_n(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_CE_N, BITS_SPEED_CTRL_CE_N)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_ce_n(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_ce_2x]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_ce_2x(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_CE_2X, BITS_SPEED_CTRL_CE_2X)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_ce_2x(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_state]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_state(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_STATE, BITS_SPEED_CTRL_STATE)) & 0x7u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_state(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_clkdiv]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_clkdiv(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_CLKDIV, BITS_SPEED_CTRL_CLKDIV)) & 0x7u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_clkdiv(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_unpause_cnt]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_unpause_cnt(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_UNPAUSE_CNT, BITS_SPEED_CTRL_UNPAUSE_CNT)) & 0xFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_unpause_cnt(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:speed_ctrl_fastforward_cnt]
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_fastforward_cnt(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_FASTFORWARD_CNT, BITS_SPEED_CTRL_FASTFORWARD_CNT)) & 0xFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_speed_ctrl_fastforward_cnt(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_h_cnt]
                    <<~CPP.chomp
                      unsigned int sim_get_video_h_cnt(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_H_CNT, BITS_VIDEO_H_CNT)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_h_cnt(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_v_cnt]
                    <<~CPP.chomp
                      unsigned int sim_get_video_v_cnt(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_V_CNT, BITS_VIDEO_V_CNT)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_v_cnt(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_scy]
                    <<~CPP.chomp
                      unsigned int sim_get_video_scy(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_SCY, BITS_VIDEO_SCY)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_scy(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_scx]
                    <<~CPP.chomp
                      unsigned int sim_get_video_scx(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_SCX, BITS_VIDEO_SCX)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_scx(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_bg_palette]
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_palette(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_BG_PALETTE, BITS_VIDEO_BG_PALETTE)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_palette(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_obj_palette0]
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_palette0(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_OBJ_PALETTE0, BITS_VIDEO_OBJ_PALETTE0)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_palette0(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_obj_palette1]
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_palette1(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_OBJ_PALETTE1, BITS_VIDEO_OBJ_PALETTE1)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_palette1(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_bg_shift_lo]
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_shift_lo(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_BG_SHIFT_LO, BITS_VIDEO_BG_SHIFT_LO)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_shift_lo(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_bg_shift_hi]
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_shift_hi(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_BG_SHIFT_HI, BITS_VIDEO_BG_SHIFT_HI)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_shift_hi(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_bg_attr]
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_attr(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_BG_ATTR, BITS_VIDEO_BG_ATTR)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_bg_attr(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_obj_shift_lo]
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_shift_lo(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_OBJ_SHIFT_LO, BITS_VIDEO_OBJ_SHIFT_LO)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_shift_lo(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_obj_shift_hi]
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_shift_hi(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_OBJ_SHIFT_HI, BITS_VIDEO_OBJ_SHIFT_HI)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_shift_hi(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_obj_meta0]
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_meta0(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_OBJ_META0, BITS_VIDEO_OBJ_META0)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_meta0(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_obj_meta1]
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_meta1(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_OBJ_META1, BITS_VIDEO_OBJ_META1)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_obj_meta1(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_fetch_phase]
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_phase(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_FETCH_PHASE, BITS_VIDEO_FETCH_PHASE)) & 0x7u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_phase(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_fetch_slot]
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_slot(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_FETCH_SLOT, BITS_VIDEO_FETCH_SLOT)) & 0x7u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_slot(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_fetch_hold0]
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_hold0(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_FETCH_HOLD0, BITS_VIDEO_FETCH_HOLD0)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_hold0(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_fetch_hold1]
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_hold1(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_FETCH_HOLD1, BITS_VIDEO_FETCH_HOLD1)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_hold1(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_tile_lo]
                    <<~CPP.chomp
                      unsigned int sim_get_video_tile_lo(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_TILE_LO, BITS_VIDEO_TILE_LO)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_tile_lo(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_fetch_data0]
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_data0(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_FETCH_DATA0, BITS_VIDEO_FETCH_DATA0)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_data0(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_fetch_data1]
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_data1(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_FETCH_DATA1, BITS_VIDEO_FETCH_DATA1)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_fetch_data1(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_tile_hi]
                    <<~CPP.chomp
                      unsigned int sim_get_video_tile_hi(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_TILE_HI, BITS_VIDEO_TILE_HI)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_tile_hi(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_input_vram_data]
                    <<~CPP.chomp
                      unsigned int sim_get_video_input_vram_data(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_INPUT_VRAM_DATA, BITS_VIDEO_INPUT_VRAM_DATA)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_input_vram_data(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:video_input_vram1_data]
                    <<~CPP.chomp
                      unsigned int sim_get_video_input_vram1_data(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VIDEO_INPUT_VRAM1_DATA, BITS_VIDEO_INPUT_VRAM1_DATA)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_video_input_vram1_data(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:vram0_q_a_reg]
                    <<~CPP.chomp
                      unsigned int sim_get_vram0_q_a_reg(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM0_Q_A_REG, BITS_VRAM0_Q_A_REG)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_vram0_q_a_reg(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:vram1_q_a_reg]
                    <<~CPP.chomp
                      unsigned int sim_get_vram1_q_a_reg(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM1_Q_A_REG, BITS_VRAM1_Q_A_REG)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_vram1_q_a_reg(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_reset_r]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_reset_r(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_RESET_R, BITS_GB_CORE_RESET_R)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_reset_r(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_boot_rom_enabled]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_boot_rom_enabled(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_BOOT_ROM_ENABLED, BITS_GB_CORE_BOOT_ROM_ENABLED)) & 0x1u;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_boot_rom_enabled(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}

                #{if signals[:gb_core_boot_q]
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_boot_q(void* sim) {
                        SimContext* ctx = static_cast<SimContext*>(sim);
                        return static_cast<unsigned int>(read_bits(ctx->state, OFF_GB_CORE_BOOT_Q, BITS_GB_CORE_BOOT_Q)) & 0xFFu;
                      }
                    CPP
                  else
                    <<~CPP.chomp
                      unsigned int sim_get_gb_core_boot_q(void* sim) {
                        (void)sim;
                        return 0u;
                      }
                    CPP
                  end}
              CPP
            else
              <<~CPP.chomp
                unsigned int sim_get_boot_upload_active(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_boot_upload_phase(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_boot_upload_index(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_boot_upload_low_byte(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_ext_bus_a15(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_cart_rd(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_cart_wr(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_cart_do(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_lcd_clkena(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_lcd_data_gb(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_lcd_vsync(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_cpu_pc(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_cpu_ir(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_cpu_tstate(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_cpu_mcycle(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_cpu_addr(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_cpu_do(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_speed_ctrl_ce(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_speed_ctrl_ce_n(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_speed_ctrl_ce_2x(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_video_h_cnt(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_video_v_cnt(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_reset_r(void* sim) {
                  (void)sim;
                  return 0u;
                }

                unsigned int sim_get_gb_core_boot_rom_enabled(void* sim) {
                  (void)sim;
                  return 0u;
                }
              CPP
            end

          extra_debug_getter_specs = {
            gb_core_boot_q: { mask: '0xFFu' },
            gb_core_cpu_di: { mask: '0xFFu' },
            gb_core_cpu_m1_n: { mask: '0x1u' },
            gb_core_cpu_mreq_n: { mask: '0x1u' },
            gb_core_cpu_iorq_n: { mask: '0x1u' },
            gb_core_cpu_rd_n: { mask: '0x1u' },
            gb_core_cpu_wr_n: { mask: '0x1u' },
            speed_ctrl_state: { mask: '0x7u' },
            speed_ctrl_clkdiv: { mask: '0x7u' },
            speed_ctrl_unpause_cnt: { mask: '0xFu' },
            speed_ctrl_fastforward_cnt: { mask: '0xFu' },
            video_scy: { mask: '0xFFu' },
            video_scx: { mask: '0xFFu' },
            video_bg_palette: { mask: '0xFFu' },
            video_obj_palette0: { mask: '0xFFu' },
            video_obj_palette1: { mask: '0xFFu' },
            video_bg_shift_lo: { mask: '0xFFu' },
            video_bg_shift_hi: { mask: '0xFFu' },
            video_bg_attr: { mask: '0xFFu' },
            video_obj_shift_lo: { mask: '0xFFu' },
            video_obj_shift_hi: { mask: '0xFFu' },
            video_obj_meta0: { mask: '0xFFu' },
            video_obj_meta1: { mask: '0xFFu' },
            video_fetch_phase: { mask: '0x7u' },
            video_fetch_slot: { mask: '0x7u' },
            video_fetch_hold0: { mask: '0x1u' },
            video_fetch_hold1: { mask: '0x1u' },
            video_fetch_data0: { mask: '0xFFu' },
            video_fetch_data1: { mask: '0xFFu' },
            video_tile_lo: { mask: '0xFFu' },
            video_tile_hi: { mask: '0xFFu' },
            video_input_vram_data: { mask: '0xFFu' },
            video_input_vram1_data: { mask: '0xFFu' },
            vram0_q_a_reg: { mask: '0xFFu' },
            vram1_q_a_reg: { mask: '0xFFu' }
          }.freeze

          extra_debug_getters = extra_debug_getter_specs.map do |key, spec|
            func_name = "sim_get_#{key}"
            if signals[key]
              <<~CPP.chomp
                unsigned int #{func_name}(void* sim) {
                  SimContext* ctx = static_cast<SimContext*>(sim);
                  return static_cast<unsigned int>(read_bits(ctx->state, OFF_#{sanitize_macro(key)}, BITS_#{sanitize_macro(key)})) & #{spec.fetch(:mask)};
                }
              CPP
            else
              <<~CPP.chomp
                unsigned int #{func_name}(void* sim) {
                  (void)sim;
                  return 0u;
                }
              CPP
            end
          end.join("\n\n")

          abi_signal_entries = signals.compact.select { |_key, meta| meta.fetch(:bits).to_i <= 64 }
          abi_input_signal_entries = abi_signal_entries.select { |_key, meta| meta.fetch(:type).to_s == 'input' }
          abi_output_signal_entries = abi_signal_entries.reject { |_key, meta| meta.fetch(:type).to_s == 'input' }
          abi_input_names_csv = abi_input_signal_entries.map { |key, _| key.to_s }.join(',')
          abi_output_names_csv = abi_output_signal_entries.map { |key, _| key.to_s }.join(',')
          abi_signal_names_table = abi_signal_entries.map { |key, _| %("#{key}") }.join(",\n            ")
          abi_input_signal_names_table = abi_input_signal_entries.map { |key, _| %("#{key}") }.join(",\n            ")
          abi_output_signal_names_table = abi_output_signal_entries.map { |key, _| %("#{key}") }.join(",\n            ")
          abi_signal_index_lookup = abi_signal_entries.each_with_index.map do |(key, _meta), idx|
            %(if (strcmp(name, "#{key}") == 0) return #{idx};)
          end.join("\n              ")
          abi_signal_peek_cases = abi_signal_entries.each_with_index.map do |(key, _meta), idx|
            macro = sanitize_macro(key)
            %(case #{idx}: return static_cast<unsigned long>(read_bits(ctx->state, OFF_#{macro}, BITS_#{macro}));)
          end.join("\n                ")
          abi_signal_poke_cases = abi_input_signal_entries.each_with_index.map do |(key, _meta), idx|
            macro = sanitize_macro(key)
            %(case #{idx}: write_bits(ctx->state, OFF_#{macro}, BITS_#{macro}, value); return 1;)
          end.join("\n                ")

          wrapper = <<~CPP
            #include <stdint.h>
            #include <stdio.h>
            #include <stdlib.h>
            #include <string.h>

            extern "C" void #{module_name}_eval(void* state);

            #{defines}
            #define STATE_SIZE #{state_size}

            struct GbCycleResult {
              unsigned long cycles_run;
              unsigned int frames_completed;
            };

            struct SimContext {
              uint8_t state[STATE_SIZE];
              uint8_t rom[1024 * 1024];
              uint8_t boot_rom[256];
              uint8_t vram[8192];
              uint8_t framebuffer[160 * 144];
              unsigned int lcd_x;
              unsigned int lcd_y;
              uint8_t prev_lcd_clkena;
              uint8_t prev_lcd_vsync;
              unsigned long frame_count;
              unsigned long vram_write_count;
              unsigned int last_fetch_addr;
              unsigned int clk_counter;
              uint8_t joystick_state;
              uint8_t cart_type;
              uint8_t rom_size_code;
              uint8_t ram_size_code;
              uint16_t rom_bank_count;
              uint8_t mbc1_rom_bank_low5;
              uint8_t mbc1_bank_upper2;
              uint8_t mbc1_mode;
              uint8_t mbc1_ram_enabled;
            };

            struct RunnerCaps {
              int kind;
              unsigned int mem_spaces;
              unsigned int control_ops;
              unsigned int probe_ops;
            };

            struct RunnerRunResult {
              int text_dirty;
              int key_cleared;
              unsigned int cycles_run;
              unsigned int speaker_toggles;
              unsigned int frames_completed;
            };

            static const char* k_input_signal_names[] = {
              #{abi_input_signal_names_table}
            };

            static const char* k_output_signal_names[] = {
              #{abi_output_signal_names_table}
            };

            static const char* k_signal_names[] = {
              #{abi_signal_names_table}
            };

            static const char k_input_names_csv[] = "#{abi_input_names_csv}";
            static const char k_output_names_csv[] = "#{abi_output_names_csv}";

            static const unsigned int k_signal_count = static_cast<unsigned int>(sizeof(k_signal_names) / sizeof(k_signal_names[0]));

            enum {
              SIM_CAP_SIGNAL_INDEX = 1u << 0,
              SIM_CAP_FORCED_CLOCK = 1u << 1,
              SIM_CAP_TRACE = 1u << 2,
              SIM_CAP_TRACE_STREAMING = 1u << 3,
              SIM_CAP_COMPILE = 1u << 4,
              SIM_CAP_GENERATED_CODE = 1u << 5,
              SIM_CAP_RUNNER = 1u << 6
            };

            enum {
              SIM_SIGNAL_HAS = 0u,
              SIM_SIGNAL_GET_INDEX = 1u,
              SIM_SIGNAL_PEEK = 2u,
              SIM_SIGNAL_POKE = 3u,
              SIM_SIGNAL_PEEK_INDEX = 4u,
              SIM_SIGNAL_POKE_INDEX = 5u
            };

            enum {
              SIM_EXEC_EVALUATE = 0u,
              SIM_EXEC_TICK = 1u,
              SIM_EXEC_TICK_FORCED = 2u,
              SIM_EXEC_SET_PREV_CLOCK = 3u,
              SIM_EXEC_GET_CLOCK_LIST_IDX = 4u,
              SIM_EXEC_RESET = 5u,
              SIM_EXEC_RUN_TICKS = 6u,
              SIM_EXEC_SIGNAL_COUNT = 7u,
              SIM_EXEC_REG_COUNT = 8u,
              SIM_EXEC_COMPILE = 9u,
              SIM_EXEC_IS_COMPILED = 10u
            };

            enum {
              SIM_TRACE_ENABLED = 3u
            };

            enum {
              SIM_BLOB_INPUT_NAMES = 0u,
              SIM_BLOB_OUTPUT_NAMES = 1u
            };

            enum {
              RUNNER_KIND_GAMEBOY = 3,
              RUNNER_MEM_OP_LOAD = 0u,
              RUNNER_MEM_OP_READ = 1u,
              RUNNER_MEM_OP_WRITE = 2u,
              RUNNER_MEM_SPACE_ROM = 1u,
              RUNNER_MEM_SPACE_BOOT_ROM = 2u,
              RUNNER_MEM_SPACE_VRAM = 3u,
              RUNNER_MEM_SPACE_FRAMEBUFFER = 6u,
              RUNNER_RUN_MODE_BASIC = 0u,
              RUNNER_CONTROL_RESET_LCD = 2u,
              RUNNER_PROBE_KIND = 0u,
              RUNNER_PROBE_IS_MODE = 1u,
              RUNNER_PROBE_FRAMEBUFFER_LEN = 3u,
              RUNNER_PROBE_FRAME_COUNT = 4u,
              RUNNER_PROBE_SIGNAL = 9u,
              RUNNER_PROBE_LCDC_ON = 10u,
              RUNNER_PROBE_LCD_X = 12u,
              RUNNER_PROBE_LCD_Y = 13u,
              RUNNER_PROBE_LCD_PREV_CLKENA = 14u,
              RUNNER_PROBE_LCD_PREV_VSYNC = 15u,
              RUNNER_PROBE_LCD_FRAME_COUNT = 16u
            };

            static inline void write_out_u32(unsigned int* out, unsigned int value) {
              if (out) *out = value;
            }

            static inline void write_out_ulong(unsigned long* out, unsigned long value) {
              if (out) *out = value;
            }

            static inline size_t copy_blob(unsigned char* out_ptr, size_t out_len, const char* text) {
              const size_t required = text ? strlen(text) : 0u;
              if (out_ptr && out_len && required) {
                size_t copy_len = required < out_len ? required : out_len;
                memcpy(out_ptr, text, copy_len);
              }
              return required;
            }

            static inline size_t signal_num_bytes(unsigned int num_bits);
            static inline void write_bits(uint8_t* state, unsigned int offset, unsigned int num_bits, uint64_t value);
            static inline uint64_t read_bits(const uint8_t* state, unsigned int offset, unsigned int num_bits);

            static inline int signal_index_from_name(const char* name) {
              if (!name) return -1;
              #{abi_signal_index_lookup}
              return -1;
            }

            static unsigned long signal_peek_by_index(SimContext* ctx, unsigned int idx) {
              switch (idx) {
                #{abi_signal_peek_cases}
                default: return 0ul;
              }
            }

            static int signal_poke_by_index(SimContext* ctx, unsigned int idx, unsigned long value) {
              switch (idx) {
                #{abi_signal_poke_cases}
                default: return 0;
              }
            }

            static inline size_t signal_num_bytes(unsigned int num_bits) {
              return (num_bits + 7u) / 8u;
            }

            static inline void write_bits(uint8_t* state, unsigned int offset, unsigned int num_bits, uint64_t value) {
              size_t num_bytes = signal_num_bytes(num_bits);
              memset(&state[offset], 0, num_bytes);
              size_t copy_bytes = num_bytes < sizeof(value) ? num_bytes : sizeof(value);
              memcpy(&state[offset], &value, copy_bytes);
              if (num_bits != 0u && (num_bits & 7u) != 0u) {
                uint8_t mask = static_cast<uint8_t>((1u << (num_bits & 7u)) - 1u);
                state[offset + num_bytes - 1u] &= mask;
              }
            }

            static inline uint64_t read_bits(const uint8_t* state, unsigned int offset, unsigned int num_bits) {
              uint64_t value = 0;
              size_t num_bytes = signal_num_bytes(num_bits);
              size_t copy_bytes = num_bytes < sizeof(value) ? num_bytes : sizeof(value);
              memcpy(&value, &state[offset], copy_bytes);
              if (num_bits < 64u && num_bits != 0u) {
                value &= ((uint64_t{1} << num_bits) - 1u);
              }
              return value;
            }

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
            }

            static unsigned char cart_read_byte(const SimContext* ctx, unsigned int full_addr) {
              unsigned int addr = full_addr & 0xFFFFu;
              if (!cart_is_mbc1(ctx)) {
                return (addr < sizeof(ctx->rom)) ? ctx->rom[addr] : 0xFFu;
              }
              if (addr > 0x7FFFu) return 0xFFu;

              unsigned int bank = 0u;
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

            static void cart_handle_write(SimContext* ctx, unsigned int full_addr, unsigned char value) {
              if (!cart_is_mbc1(ctx)) return;

              unsigned int addr = full_addr & 0x7FFFu;
              if (addr <= 0x1FFFu) {
                ctx->mbc1_ram_enabled = ((value & 0x0Fu) == 0x0Au) ? 1u : 0u;
              } else if (addr <= 0x3FFFu) {
                unsigned int bank = value & 0x1Fu;
                ctx->mbc1_rom_bank_low5 = (bank == 0u) ? 1u : bank;
              } else if (addr <= 0x5FFFu) {
                ctx->mbc1_bank_upper2 = value & 0x03u;
              } else if (addr <= 0x7FFFu) {
                ctx->mbc1_mode = value & 0x01u;
              }
            }

            static inline void eval_ctx(SimContext* ctx) {
              #{module_name}_eval(ctx->state);
            }

            static void apply_static_inputs(SimContext* ctx) {
          #{static_tieoffs}
              write_bits(ctx->state, OFF_JOYSTICK, BITS_JOYSTICK, ctx->joystick_state);
              write_bits(ctx->state, OFF_CART_DO, BITS_CART_DO, 0xFFu);
              write_bits(ctx->state, OFF_BOOT_ROM_DO, BITS_BOOT_ROM_DO, 0u);
            }

            static void drive_clock_enable_inputs(SimContext* ctx) {
          #{clock_enable_lines}
            }

            static void drive_boot_rom_input(SimContext* ctx) {
              unsigned int boot_addr = static_cast<unsigned int>(read_bits(ctx->state, OFF_BOOT_ROM_ADDR, BITS_BOOT_ROM_ADDR)) & 0xFFu;
              write_bits(ctx->state, OFF_BOOT_ROM_DO, BITS_BOOT_ROM_DO, ctx->boot_rom[boot_addr]);
            }

            static unsigned int current_ext_bus_full_addr(const SimContext* ctx) {
              unsigned int addr = static_cast<unsigned int>(read_bits(ctx->state, OFF_EXT_BUS_ADDR, BITS_EXT_BUS_ADDR)) & 0x7FFFu;
              unsigned int a15 = static_cast<unsigned int>(read_bits(ctx->state, OFF_EXT_BUS_A15, BITS_EXT_BUS_A15)) & 0x1u;
              return (a15 << 15) | addr;
            }

            static void drive_cartridge_input(SimContext* ctx) {
              unsigned int full_addr = current_ext_bus_full_addr(ctx);
              unsigned int cart_rd = static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_RD, BITS_CART_RD)) & 0x1u;
              unsigned int cart_wr = static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_WR, BITS_CART_WR)) & 0x1u;
              unsigned int cart_di = static_cast<unsigned int>(read_bits(ctx->state, OFF_CART_DI, BITS_CART_DI)) & 0xFFu;

              if (cart_wr) {
                cart_handle_write(ctx, full_addr, static_cast<unsigned char>(cart_di));
              }

              unsigned int cart_do = cart_rd ? cart_read_byte(ctx, full_addr) : 0xFFu;
              write_bits(ctx->state, OFF_CART_DO, BITS_CART_DO, cart_do);

              if (cart_rd) {
                ctx->last_fetch_addr = full_addr;
              }
            }

            static void capture_lcd_output(SimContext* ctx, GbCycleResult* result) {
              unsigned int lcd_clkena = static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_CLKENA, BITS_LCD_CLKENA)) & 0x1u;
              unsigned int lcd_vsync = static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_VSYNC, BITS_LCD_VSYNC)) & 0x1u;
              unsigned int lcd_data = static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_DATA_GB, BITS_LCD_DATA_GB)) & 0x3u;
              unsigned int pixel_we = lcd_clkena;
          #{if signals[:speed_ctrl_ce]
                '    pixel_we &= static_cast<unsigned int>(read_bits(ctx->state, OFF_SPEED_CTRL_CE, BITS_SPEED_CTRL_CE)) & 0x1u;'
              elsif signals[:ce]
                '    pixel_we &= static_cast<unsigned int>(read_bits(ctx->state, OFF_CE, BITS_CE)) & 0x1u;'
              else
                ''
              end}

              if (lcd_vsync != 0u && ctx->prev_lcd_vsync == 0u) {
                ctx->lcd_x = 0u;
                ctx->lcd_y = 0u;
                ctx->frame_count++;
                if (result) result->frames_completed++;
              } else if (pixel_we != 0u) {
                if (ctx->lcd_x < 160u && ctx->lcd_y < 144u) {
                  ctx->framebuffer[(ctx->lcd_y * 160u) + ctx->lcd_x] = static_cast<uint8_t>(lcd_data);
                }
                ctx->lcd_x++;
                if (ctx->lcd_x >= 160u) {
                  ctx->lcd_x = 0u;
                  ctx->lcd_y++;
                }
              }

              ctx->prev_lcd_clkena = static_cast<uint8_t>(lcd_clkena);
              ctx->prev_lcd_vsync = static_cast<uint8_t>(lcd_vsync);
            }

            static void capture_vram_writes(SimContext* ctx) {
              #{if signals[:vram0_w0_addr] && signals[:vram0_w0_en] && signals[:vram0_w0_data]
                  <<~CPP.chomp
                    if ((static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM0_W0_EN, BITS_VRAM0_W0_EN)) & 0x1u) != 0u) {
                      unsigned int addr = static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM0_W0_ADDR, BITS_VRAM0_W0_ADDR)) & 0x1FFFu;
                      if (addr < sizeof(ctx->vram)) {
                        ctx->vram[addr] = static_cast<uint8_t>(read_bits(ctx->state, OFF_VRAM0_W0_DATA, BITS_VRAM0_W0_DATA)) & 0xFFu;
                        ctx->vram_write_count++;
                      }
                    }
                  CPP
                else
                  ''
                end}
              #{if signals[:vram1_w0_addr] && signals[:vram1_w0_en] && signals[:vram1_w0_data]
                  <<~CPP.chomp
                    if ((static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM1_W0_EN, BITS_VRAM1_W0_EN)) & 0x1u) != 0u) {
                      unsigned int addr = static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM1_W0_ADDR, BITS_VRAM1_W0_ADDR)) & 0x1FFFu;
                      if (addr < sizeof(ctx->vram)) {
                        ctx->vram[addr] = static_cast<uint8_t>(read_bits(ctx->state, OFF_VRAM1_W0_DATA, BITS_VRAM1_W0_DATA)) & 0xFFu;
                        ctx->vram_write_count++;
                      }
                    }
                  CPP
                else
                  ''
                end}
            }

            static void run_single_cycle(SimContext* ctx, GbCycleResult* result) {
              write_bits(ctx->state, OFF_CLK_SYS, BITS_CLK_SYS, 0u);
              drive_clock_enable_inputs(ctx);
              eval_ctx(ctx);
              capture_vram_writes(ctx);
              capture_lcd_output(ctx, result);
              drive_boot_rom_input(ctx);
              drive_cartridge_input(ctx);
              eval_ctx(ctx);
              capture_vram_writes(ctx);
              capture_lcd_output(ctx, result);

              write_bits(ctx->state, OFF_CLK_SYS, BITS_CLK_SYS, 1u);
              drive_clock_enable_inputs(ctx);
              eval_ctx(ctx);
              capture_vram_writes(ctx);
              capture_lcd_output(ctx, result);
              drive_boot_rom_input(ctx);
              drive_cartridge_input(ctx);
              eval_ctx(ctx);
              capture_vram_writes(ctx);
              capture_lcd_output(ctx, result);

              ctx->clk_counter++;
              if (result) result->cycles_run++;
            }

            extern "C" {

            void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** err_out) {
              (void)json;
              (void)json_len;
              (void)sub_cycles;
              if (err_out) *err_out = nullptr;
              SimContext* ctx = static_cast<SimContext*>(malloc(sizeof(SimContext)));
              if (!ctx) return nullptr;
              memset(ctx->state, 0, sizeof(ctx->state));
              memset(ctx->rom, 0, sizeof(ctx->rom));
              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
              memset(ctx->vram, 0, sizeof(ctx->vram));
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0u;
              ctx->lcd_y = 0u;
              ctx->prev_lcd_clkena = 0u;
              ctx->prev_lcd_vsync = 0u;
              ctx->frame_count = 0u;
              ctx->vram_write_count = 0u;
              ctx->last_fetch_addr = 0u;
              ctx->clk_counter = 0u;
              ctx->joystick_state = 0xFFu;
              ctx->cart_type = 0u;
              ctx->rom_size_code = 0u;
              ctx->ram_size_code = 0u;
              ctx->rom_bank_count = 2u;
              cart_reset_runtime_state(ctx);
              apply_static_inputs(ctx);
              drive_boot_rom_input(ctx);
              eval_ctx(ctx);
              return ctx;
            }

            void sim_destroy(void* sim) {
              free(static_cast<SimContext*>(sim));
            }

            void sim_free_error(char* error) {
              if (error) free(error);
            }

            void sim_free_string(char* string) {
              if (string) free(string);
            }

            void* sim_wasm_alloc(size_t size) {
              return malloc(size);
            }

            void sim_wasm_dealloc(void* ptr, size_t size) {
              (void)size;
              free(ptr);
            }

            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              memset(ctx->vram, 0, sizeof(ctx->vram));
              ctx->lcd_x = 0u;
              ctx->lcd_y = 0u;
              ctx->prev_lcd_clkena = 0u;
              ctx->prev_lcd_vsync = 0u;
              ctx->frame_count = 0u;
              ctx->vram_write_count = 0u;
              ctx->last_fetch_addr = 0u;
              ctx->clk_counter = 0u;
              ctx->joystick_state = 0xFFu;
              cart_reset_runtime_state(ctx);
              apply_static_inputs(ctx);

              write_bits(ctx->state, OFF_RESET, BITS_RESET, 1u);
              for (int i = 0; i < 10; ++i) {
                run_single_cycle(ctx, nullptr);
              }

              write_bits(ctx->state, OFF_RESET, BITS_RESET, 0u);
              for (int i = 0; i < 100; ++i) {
                run_single_cycle(ctx, nullptr);
              }

              memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
              ctx->lcd_x = 0u;
              ctx->lcd_y = 0u;
              ctx->prev_lcd_clkena = 0u;
              ctx->prev_lcd_vsync = 0u;
              ctx->frame_count = 0u;
              ctx->last_fetch_addr = 0u;
              ctx->clk_counter = 0u;
            }

            void sim_set_joystick(void* sim, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->joystick_state = static_cast<uint8_t>(value & 0xFFu);
              write_bits(ctx->state, OFF_JOYSTICK, BITS_JOYSTICK, ctx->joystick_state);
            }

            void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memset(ctx->rom, 0, sizeof(ctx->rom));
              for (unsigned int i = 0; i < len && i < sizeof(ctx->rom); ++i) {
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
              memset(ctx->boot_rom, 0, sizeof(ctx->boot_rom));
              for (unsigned int i = 0; i < len && i < sizeof(ctx->boot_rom); ++i) {
                ctx->boot_rom[i] = data[i];
              }
            }

            void sim_read_framebuffer(void* sim, unsigned char* out_buffer) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              memcpy(out_buffer, ctx->framebuffer, sizeof(ctx->framebuffer));
            }

            unsigned int sim_get_last_fetch_addr(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->last_fetch_addr;
            }

            unsigned int sim_get_ext_bus_full_addr(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return current_ext_bus_full_addr(ctx);
            }

            unsigned int sim_get_lcd_on(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return static_cast<unsigned int>(read_bits(ctx->state, OFF_LCD_ON, BITS_LCD_ON)) & 0x1u;
            }

            unsigned long sim_get_frame_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->frame_count;
            }

            unsigned char sim_read_vram(void* sim, unsigned int addr) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (addr < sizeof(ctx->vram)) return ctx->vram[addr];
              return 0u;
            }

            unsigned long sim_get_vram_write_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return ctx->vram_write_count;
            }

          #{boot_upload_getters}

          #{extra_debug_getters}

            int sim_get_caps(void* sim, unsigned int* caps_out) {
              (void)sim;
              write_out_u32(caps_out, SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER);
              return 1;
            }

            int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) {
                write_out_ulong(out_value, 0ul);
                return 0;
              }

              int resolved_idx = (name && name[0]) ? signal_index_from_name(name) : static_cast<int>(idx);
              switch (op) {
              case SIM_SIGNAL_HAS:
                write_out_ulong(out_value, resolved_idx >= 0 ? 1ul : 0ul);
                return resolved_idx >= 0 ? 1 : 0;
              case SIM_SIGNAL_GET_INDEX:
                if (resolved_idx < 0) {
                  write_out_ulong(out_value, 0ul);
                  return 0;
                }
                write_out_ulong(out_value, static_cast<unsigned long>(resolved_idx));
                return 1;
              case SIM_SIGNAL_PEEK:
              case SIM_SIGNAL_PEEK_INDEX:
                if (resolved_idx < 0) {
                  write_out_ulong(out_value, 0ul);
                  return 0;
                }
                write_out_ulong(out_value, signal_peek_by_index(ctx, static_cast<unsigned int>(resolved_idx)));
                return 1;
              case SIM_SIGNAL_POKE:
              case SIM_SIGNAL_POKE_INDEX:
                if (resolved_idx < 0) {
                  write_out_ulong(out_value, 0ul);
                  return 0;
                }
                {
                  int rc = signal_poke_by_index(ctx, static_cast<unsigned int>(resolved_idx), value);
                  write_out_ulong(out_value, rc != 0 ? 1ul : 0ul);
                  return rc;
                }
              default:
                write_out_ulong(out_value, 0ul);
                return 0;
              }
            }

            void sim_run_cycles(void* sim, unsigned int n_cycles, GbCycleResult* result) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              result->cycles_run = 0u;
              result->frames_completed = 0u;
              while (result->cycles_run < n_cycles) {
                run_single_cycle(ctx, result);
              }
            }

            int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, char** err_out) {
              (void)arg1;
              if (err_out) *err_out = nullptr;
              write_out_ulong(out_value, 0ul);

              switch (op) {
              case SIM_EXEC_EVALUATE:
                eval_ctx(static_cast<SimContext*>(sim));
                return 1;
              case SIM_EXEC_TICK: {
                GbCycleResult result = {0u, 0u};
                sim_run_cycles(sim, 1u, &result);
                write_out_ulong(out_value, result.cycles_run);
                return 1;
              }
              case SIM_EXEC_RESET:
                sim_reset(sim);
                return 1;
              case SIM_EXEC_RUN_TICKS: {
                GbCycleResult result = {0u, 0u};
                sim_run_cycles(sim, static_cast<unsigned int>(arg0), &result);
                write_out_ulong(out_value, result.cycles_run);
                return 1;
              }
              case SIM_EXEC_SIGNAL_COUNT:
                write_out_ulong(out_value, static_cast<unsigned long>(k_signal_count));
                return 1;
              case SIM_EXEC_REG_COUNT:
                return 1;
              default:
                return 0;
              }
            }

            int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
              (void)sim;
              (void)str_arg;
              if (op == SIM_TRACE_ENABLED) {
                write_out_ulong(out_value, 0ul);
                return 1;
              }
              write_out_ulong(out_value, 0ul);
              return 0;
            }

            size_t sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, size_t out_len) {
              (void)sim;
              switch (op) {
              case SIM_BLOB_INPUT_NAMES:
                return copy_blob(out_ptr, out_len, k_input_names_csv);
              case SIM_BLOB_OUTPUT_NAMES:
                return copy_blob(out_ptr, out_len, k_output_names_csv);
              default:
                return 0u;
              }
            }

            int runner_get_caps(void* sim, RunnerCaps* caps_out) {
              (void)sim;
              if (!caps_out) return 0;
              caps_out->kind = RUNNER_KIND_GAMEBOY;
              caps_out->mem_spaces =
                (1u << RUNNER_MEM_SPACE_ROM) |
                (1u << RUNNER_MEM_SPACE_BOOT_ROM) |
                (1u << RUNNER_MEM_SPACE_VRAM) |
                (1u << RUNNER_MEM_SPACE_FRAMEBUFFER);
              caps_out->control_ops = (1u << RUNNER_CONTROL_RESET_LCD);
              caps_out->probe_ops =
                (1u << RUNNER_PROBE_KIND) |
                (1u << RUNNER_PROBE_IS_MODE) |
                (1u << RUNNER_PROBE_FRAMEBUFFER_LEN) |
                (1u << RUNNER_PROBE_FRAME_COUNT) |
                (1u << RUNNER_PROBE_SIGNAL) |
                (1u << RUNNER_PROBE_LCDC_ON) |
                (1u << RUNNER_PROBE_LCD_X) |
                (1u << RUNNER_PROBE_LCD_Y) |
                (1u << RUNNER_PROBE_LCD_PREV_CLKENA) |
                (1u << RUNNER_PROBE_LCD_PREV_VSYNC) |
                (1u << RUNNER_PROBE_LCD_FRAME_COUNT);
              return 1;
            }

            size_t runner_mem(void* sim, unsigned int op, unsigned int space, size_t offset, unsigned char* ptr, size_t len, unsigned int flags) {
              (void)flags;
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0u;

              if (op == RUNNER_MEM_OP_LOAD) {
                if (!ptr || len == 0u) return 0u;
                if (space == RUNNER_MEM_SPACE_ROM) {
                  sim_load_rom(sim, ptr, static_cast<unsigned int>(len));
                  return len;
                }
                if (space == RUNNER_MEM_SPACE_BOOT_ROM) {
                  sim_load_boot_rom(sim, ptr, static_cast<unsigned int>(len));
                  return len;
                }
                if (space == RUNNER_MEM_SPACE_VRAM) {
                  size_t copied = 0u;
                  for (; copied < len && (offset + copied) < sizeof(ctx->vram); ++copied) ctx->vram[offset + copied] = ptr[copied];
                  return copied;
                }
                return 0u;
              }

              if (!ptr) return 0u;
              if (op == RUNNER_MEM_OP_READ) {
                if (space == RUNNER_MEM_SPACE_BOOT_ROM) {
                  size_t copied = 0u;
                  for (; copied < len && (offset + copied) < sizeof(ctx->boot_rom); ++copied) ptr[copied] = ctx->boot_rom[offset + copied];
                  return copied;
                }
                if (space == RUNNER_MEM_SPACE_VRAM) {
                  size_t copied = 0u;
                  for (; copied < len && (offset + copied) < sizeof(ctx->vram); ++copied) ptr[copied] = ctx->vram[offset + copied];
                  return copied;
                }
                if (space == RUNNER_MEM_SPACE_FRAMEBUFFER) {
                  if (offset >= sizeof(ctx->framebuffer)) return 0u;
                  size_t available = sizeof(ctx->framebuffer) - offset;
                  size_t copy_len = available < len ? available : len;
                  memcpy(ptr, ctx->framebuffer + offset, copy_len);
                  return copy_len;
                }
                if (space == RUNNER_MEM_SPACE_ROM) {
                  if (offset >= sizeof(ctx->rom)) return 0u;
                  size_t available = sizeof(ctx->rom) - offset;
                  size_t copy_len = available < len ? available : len;
                  memcpy(ptr, ctx->rom + offset, copy_len);
                  return copy_len;
                }
                return 0u;
              }

              if (op == RUNNER_MEM_OP_WRITE && space == RUNNER_MEM_SPACE_VRAM) {
                size_t copied = 0u;
                for (; copied < len && (offset + copied) < sizeof(ctx->vram); ++copied) ctx->vram[offset + copied] = ptr[copied];
                return copied;
              }

              return 0u;
            }

            int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, RunnerRunResult* result_out) {
              (void)mode;
              if (key_ready) sim_set_joystick(sim, key_data);
              GbCycleResult result = {0u, 0u};
              sim_run_cycles(sim, cycles, &result);
              if (result_out) {
                result_out->text_dirty = result.frames_completed > 0 ? 1 : 0;
                result_out->key_cleared = key_ready ? 1 : 0;
                result_out->cycles_run = static_cast<unsigned int>(result.cycles_run);
                result_out->speaker_toggles = 0u;
                result_out->frames_completed = result.frames_completed;
              }
              return 1;
            }

            int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) {
              (void)arg0;
              (void)arg1;
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              if (op == RUNNER_CONTROL_RESET_LCD) {
                memset(ctx->framebuffer, 0, sizeof(ctx->framebuffer));
                ctx->lcd_x = 0u;
                ctx->lcd_y = 0u;
                ctx->prev_lcd_clkena = 0u;
                ctx->prev_lcd_vsync = 0u;
                ctx->frame_count = 0u;
                return 1;
              }
              return 0;
            }

            unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0ull;
              switch (op) {
              case RUNNER_PROBE_KIND:
                return RUNNER_KIND_GAMEBOY;
              case RUNNER_PROBE_IS_MODE:
                return 0ull;
              case RUNNER_PROBE_FRAMEBUFFER_LEN:
                return sizeof(ctx->framebuffer);
              case RUNNER_PROBE_FRAME_COUNT:
              case RUNNER_PROBE_LCD_FRAME_COUNT:
                return ctx->frame_count;
              case RUNNER_PROBE_SIGNAL:
                return signal_peek_by_index(ctx, arg0);
              case RUNNER_PROBE_LCDC_ON:
                return sim_get_lcd_on(sim);
              case RUNNER_PROBE_LCD_X:
                return ctx->lcd_x;
              case RUNNER_PROBE_LCD_Y:
                return ctx->lcd_y;
              case RUNNER_PROBE_LCD_PREV_CLKENA:
                return ctx->prev_lcd_clkena;
              case RUNNER_PROBE_LCD_PREV_VSYNC:
                return ctx->prev_lcd_vsync;
              default:
                return 0ull;
              }
            }

            }  // extern "C"

            #ifdef ARCI_JIT_MAIN
            static int hex_nibble(char ch) {
              if (ch >= '0' && ch <= '9') return ch - '0';
              if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
              if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
              return -1;
            }

            static bool decode_hex_payload(const char* hex, unsigned char* out, size_t out_cap, size_t* out_len) {
              size_t hex_len = strlen(hex);
              if ((hex_len & 1u) != 0u) return false;
              size_t byte_len = hex_len / 2u;
              if (byte_len > out_cap) return false;
              memset(out, 0, out_cap);
              for (size_t i = 0; i < byte_len; ++i) {
                int hi = hex_nibble(hex[i * 2u]);
                int lo = hex_nibble(hex[(i * 2u) + 1u]);
                if (hi < 0 || lo < 0) return false;
                out[i] = static_cast<unsigned char>((hi << 4) | lo);
              }
              if (out_len) *out_len = byte_len;
              return true;
            }

            static void write_hex_bytes(FILE* out, const unsigned char* bytes, size_t len) {
              static const char* digits = "0123456789abcdef";
              for (size_t i = 0; i < len; ++i) {
                unsigned int value = bytes[i];
                fputc(digits[(value >> 4) & 0xFu], out);
                fputc(digits[value & 0xFu], out);
              }
            }

            int main(int argc, char** argv) {
              (void)argc;
              (void)argv;
              SimContext* ctx = static_cast<SimContext*>(sim_create(nullptr, 0u, 0u, nullptr));
              if (!ctx) return 1;

              unsigned int sim_get_gb_core_boot_q(void* sim);
              unsigned int sim_get_gb_core_cpu_di(void* sim);
              unsigned int sim_get_gb_core_cpu_m1_n(void* sim);
              unsigned int sim_get_gb_core_cpu_mreq_n(void* sim);
              unsigned int sim_get_gb_core_cpu_iorq_n(void* sim);
              unsigned int sim_get_gb_core_cpu_rd_n(void* sim);
              unsigned int sim_get_gb_core_cpu_wr_n(void* sim);
              unsigned int sim_get_speed_ctrl_state(void* sim);
              unsigned int sim_get_speed_ctrl_clkdiv(void* sim);
              unsigned int sim_get_speed_ctrl_unpause_cnt(void* sim);
              unsigned int sim_get_speed_ctrl_fastforward_cnt(void* sim);
              unsigned int sim_get_video_scy(void* sim);
              unsigned int sim_get_video_scx(void* sim);
              unsigned int sim_get_video_bg_palette(void* sim);
              unsigned int sim_get_video_obj_palette0(void* sim);
              unsigned int sim_get_video_obj_palette1(void* sim);
              unsigned int sim_get_video_bg_shift_lo(void* sim);
              unsigned int sim_get_video_bg_shift_hi(void* sim);
              unsigned int sim_get_video_bg_attr(void* sim);
              unsigned int sim_get_video_obj_shift_lo(void* sim);
              unsigned int sim_get_video_obj_shift_hi(void* sim);
              unsigned int sim_get_video_obj_meta0(void* sim);
              unsigned int sim_get_video_obj_meta1(void* sim);
              unsigned int sim_get_video_fetch_phase(void* sim);
              unsigned int sim_get_video_fetch_slot(void* sim);
              unsigned int sim_get_video_fetch_hold0(void* sim);
              unsigned int sim_get_video_fetch_hold1(void* sim);
              unsigned int sim_get_video_fetch_data0(void* sim);
              unsigned int sim_get_video_fetch_data1(void* sim);
              unsigned int sim_get_video_tile_lo(void* sim);
              unsigned int sim_get_video_tile_hi(void* sim);
              unsigned int sim_get_video_input_vram_data(void* sim);
              unsigned int sim_get_video_input_vram1_data(void* sim);
              unsigned int sim_get_vram0_q_a_reg(void* sim);
              unsigned int sim_get_vram1_q_a_reg(void* sim);

              fprintf(stdout, "READY\\n");
              fflush(stdout);

              char* line = nullptr;
              size_t cap = 0;
              while (getline(&line, &cap, stdin) != -1) {
                size_t len = strlen(line);
                while (len > 0u && (line[len - 1u] == '\\n' || line[len - 1u] == '\\r')) {
                  line[--len] = '\\0';
                }

                if (strcmp(line, "RESET") == 0) {
                  sim_reset(ctx);
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "SET_JOYSTICK ", 13) == 0) {
                  unsigned long value = strtoul(line + 13, nullptr, 10);
                  sim_set_joystick(ctx, static_cast<unsigned int>(value));
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "LOAD_ROM ", 9) == 0) {
                  size_t payload_len = 0u;
                  if (!decode_hex_payload(line + 9, ctx->rom, sizeof(ctx->rom), &payload_len)) {
                    fprintf(stdout, "ERR LOAD_ROM\\n");
                    fflush(stdout);
                    continue;
                  }
                  ctx->cart_type = ctx->rom[0x147];
                  ctx->rom_size_code = ctx->rom[0x148];
                  ctx->ram_size_code = ctx->rom[0x149];
                  ctx->rom_bank_count = cart_rom_bank_count(ctx->rom_size_code);
                  cart_reset_runtime_state(ctx);
                  fprintf(stdout, "OK %zu\\n", payload_len);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "LOAD_BOOT_ROM ", 14) == 0) {
                  size_t payload_len = 0u;
                  if (!decode_hex_payload(line + 14, ctx->boot_rom, sizeof(ctx->boot_rom), &payload_len)) {
                    fprintf(stdout, "ERR LOAD_BOOT_ROM\\n");
                    fflush(stdout);
                    continue;
                  }
                  fprintf(stdout, "OK %zu\\n", payload_len);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "RUN ", 4) == 0) {
                  unsigned long requested = strtoul(line + 4, nullptr, 10);
                  GbCycleResult result;
                  sim_run_cycles(ctx, static_cast<unsigned int>(requested), &result);
                  fprintf(stdout, "RUN %lu %u %lu\\n", result.cycles_run, result.frames_completed, ctx->frame_count);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "GET_FB") == 0) {
                  fputs("FB ", stdout);
                  write_hex_bytes(stdout, ctx->framebuffer, sizeof(ctx->framebuffer));
                  fputc('\\n', stdout);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "GET_STATE") == 0) {
                  fprintf(
                    stdout,
                    "STATE %u %u %u %lu %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u\\n",
                    sim_get_last_fetch_addr(ctx),
                    sim_get_ext_bus_full_addr(ctx),
                    sim_get_lcd_on(ctx),
                    sim_get_frame_count(ctx),
                    sim_get_boot_upload_active(ctx),
                    sim_get_boot_upload_phase(ctx),
                    sim_get_boot_upload_index(ctx),
                    static_cast<unsigned int>(read_bits(ctx->state, OFF_BOOT_ROM_ADDR, BITS_BOOT_ROM_ADDR)) & 0xFFu,
                    sim_get_boot_upload_low_byte(ctx),
                    sim_get_gb_core_reset_r(ctx),
                    sim_get_gb_core_boot_rom_enabled(ctx),
                    sim_get_gb_core_boot_q(ctx),
                    sim_get_ext_bus_a15(ctx),
                    sim_get_cart_rd(ctx),
                    sim_get_cart_wr(ctx),
                    sim_get_cart_do(ctx),
                    sim_get_lcd_clkena(ctx),
                    sim_get_lcd_data_gb(ctx),
                    sim_get_lcd_vsync(ctx),
                    sim_get_gb_core_cpu_pc(ctx),
                    sim_get_gb_core_cpu_ir(ctx),
                    sim_get_gb_core_cpu_tstate(ctx),
                    sim_get_gb_core_cpu_mcycle(ctx),
                    sim_get_gb_core_cpu_addr(ctx),
                    sim_get_gb_core_cpu_di(ctx),
                    sim_get_gb_core_cpu_do(ctx),
                    sim_get_gb_core_cpu_m1_n(ctx),
                    sim_get_gb_core_cpu_mreq_n(ctx),
                    sim_get_gb_core_cpu_iorq_n(ctx),
                    sim_get_gb_core_cpu_rd_n(ctx),
                    sim_get_gb_core_cpu_wr_n(ctx),
                    sim_get_speed_ctrl_ce(ctx),
                    sim_get_speed_ctrl_ce_n(ctx),
                    sim_get_speed_ctrl_ce_2x(ctx),
                    sim_get_speed_ctrl_state(ctx),
                    sim_get_speed_ctrl_clkdiv(ctx),
                    sim_get_speed_ctrl_unpause_cnt(ctx),
                    sim_get_speed_ctrl_fastforward_cnt(ctx),
                    sim_get_video_h_cnt(ctx),
                    sim_get_video_v_cnt(ctx),
                    sim_get_video_scy(ctx),
                    sim_get_video_scx(ctx),
                    sim_get_video_bg_palette(ctx),
                    sim_get_video_obj_palette0(ctx),
                    sim_get_video_obj_palette1(ctx),
                    sim_get_video_bg_shift_lo(ctx),
                    sim_get_video_bg_shift_hi(ctx),
                    sim_get_video_bg_attr(ctx),
                    sim_get_video_obj_shift_lo(ctx),
                    sim_get_video_obj_shift_hi(ctx),
                    sim_get_video_obj_meta0(ctx),
                    sim_get_video_obj_meta1(ctx),
                    sim_get_video_fetch_phase(ctx),
                    sim_get_video_fetch_slot(ctx),
                    sim_get_video_fetch_hold0(ctx),
                    sim_get_video_fetch_hold1(ctx),
                    sim_get_video_fetch_data0(ctx),
                    sim_get_video_fetch_data1(ctx),
                    sim_get_video_tile_lo(ctx),
                    sim_get_video_tile_hi(ctx),
                    sim_get_video_input_vram_data(ctx),
                    sim_get_video_input_vram1_data(ctx),
                    sim_get_vram0_q_a_reg(ctx),
                    sim_get_vram1_q_a_reg(ctx)
                  );
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "GET_VRAM_WRITES") == 0) {
                  fprintf(stdout, "VRAM_WRITES %lu\\n", sim_get_vram_write_count(ctx));
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "GET_VRAM_FETCH") == 0) {
                  fprintf(
                    stdout,
                    "VFETCH %u %u %u %u\\n",
                    #{if signals[:vram0_r0_en]
                        'static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM0_R0_EN, BITS_VRAM0_R0_EN)) & 0x1u'
                      else
                        '0u'
                      end},
                    #{if signals[:vram0_r0_addr]
                        'static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM0_R0_ADDR, BITS_VRAM0_R0_ADDR)) & 0x1FFFu'
                      else
                        '0u'
                      end},
                    #{if signals[:vram0_r0_data]
                        'static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM0_R0_DATA, BITS_VRAM0_R0_DATA)) & 0xFFu'
                      else
                        '0u'
                      end},
                    #{if signals[:vram1_r0_data]
                        'static_cast<unsigned int>(read_bits(ctx->state, OFF_VRAM1_R0_DATA, BITS_VRAM1_R0_DATA)) & 0xFFu'
                      else
                        '0u'
                      end}
                  );
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "READ_VRAM ", 10) == 0) {
                  unsigned long addr = strtoul(line + 10, nullptr, 10);
                  fprintf(stdout, "VRAM %u\\n", static_cast<unsigned int>(sim_read_vram(ctx, static_cast<unsigned int>(addr))) & 0xFFu);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "QUIT") == 0) {
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  break;
                }

                fprintf(stdout, "ERR UNKNOWN\\n");
                fflush(stdout);
              }

              free(line);
              sim_destroy(ctx);
              return 0;
            }
            #endif
          CPP

          File.write(wrapper_path, wrapper)
        end

        def sanitize_macro(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')
        end

        def format_c_integer(value)
          integer = value.to_i
          integer.negative? ? "(0x#{(integer & 0xFFFF_FFFF_FFFF_FFFF).to_s(16)})" : integer.to_s
        end

        def compile_wrapper_llvm_ir!(wrapper_path:, wrapper_ll_path:, log_path:)
          cmd = ['clang++', '-std=c++17', '-O0', '-S', '-emit-llvm', '-DARCI_JIT_MAIN', wrapper_path, '-o', wrapper_ll_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, File.read(log_path).to_s + stdout + stderr)
          return if status.success?

          raise "Wrapper LLVM IR compilation failed:\n#{stdout}\n#{stderr}"
        end

        def link_jit_bitcode!(ll_path:, wrapper_ll_path:, jit_bc_path:, log_path:)
          cmd = ['llvm-link', ll_path, wrapper_ll_path, '-o', jit_bc_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, File.read(log_path).to_s + stdout + stderr)
          return if status.success?

          raise "JIT bitcode link failed:\n#{stdout}\n#{stderr}"
        end

        def compile_object!(ll_path:, obj_path:, log_path:)
          cmd = if command_available?('clang')
                  ['clang', '-c', '-O0', '-fPIC', ll_path, '-o', obj_path]
                else
                  ['llc', '-filetype=obj', '-O0', '-relocation-model=pic', ll_path, '-o', obj_path]
                end
          stdout, stderr, status = Open3.capture3(*cmd)

          File.write(log_path, File.read(log_path).to_s + stdout + stderr)
          return if status.success?

          raise "Object compilation failed:\n#{stdout}\n#{stderr}"
        end

        def build_runtime_library!(ll_path:, wrapper_path:, wrapper_ll_path:, runtime_bitcode_path:, obj_path:, lib_path:, log_path:)
          FileUtils.rm_f(wrapper_ll_path)
          FileUtils.rm_f(runtime_bitcode_path)
          FileUtils.rm_f(obj_path)
          compile_wrapper_llvm_ir!(wrapper_path: wrapper_path, wrapper_ll_path: wrapper_ll_path, log_path: log_path)
          link_jit_bitcode!(ll_path: ll_path, wrapper_ll_path: wrapper_ll_path, jit_bc_path: runtime_bitcode_path, log_path: log_path)
          compile_object!(ll_path: runtime_bitcode_path, obj_path: obj_path, log_path: log_path)
          link_shared_library!(obj_path: obj_path, lib_path: lib_path, log_path: log_path)
        end

        def link_shared_library!(obj_path:, lib_path:, log_path:)
          cxx = if darwin_host? && command_available?('clang++')
                  'clang++'
                elsif command_available?('g++')
                  'g++'
                else
                  'c++'
                end

          cmd = [cxx, '-shared', '-fPIC', '-O2']
          cmd += ['-arch', build_target_arch] if build_target_arch
          cmd += ['-o', lib_path, obj_path]

          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, File.read(log_path).to_s + stdout + stderr)
          return if status.success?

          raise "Shared library link failed:\n#{stdout}\n#{stderr}"
        end

        def start_jit_process
          raise "Linked JIT bitcode not found: #{@jit_bc_path}" unless @jit_bc_path && File.file?(@jit_bc_path)

          cmd = ['lli', '--jit-kind=orc-lazy', "--compile-threads=#{jit_compile_threads}", '-O0', @jit_bc_path]
          @jit_stdin, @jit_stdout, @jit_stderr, @jit_wait_thr = Open3.popen3(*cmd)
          @jit_stdin.sync = true
          @jit_stdout.sync = true
          @jit_stderr.sync = true
          @jit_log_thread = Thread.new do
            begin
              File.open(@log_path, 'a') do |file|
                @jit_stderr.each_line do |line|
                  file.write(line)
                  file.flush
                end
              end
            rescue IOError
              nil
            end
          end

          ready = @jit_stdout.gets
          return if ready&.strip == 'READY'

          close_jit_process
          raise "JIT runner failed to start#{ready ? ": #{ready.strip}" : ''}"
        end

        def send_jit_command(command)
          raise 'JIT runner process is not active' unless @jit_stdin && @jit_stdout

          @jit_stdin.puts(command)
          response = @jit_stdout.gets
          raise 'JIT runner exited unexpectedly' unless response

          response = response.strip
          raise "JIT runner command failed: #{response}" if response.start_with?('ERR')

          response
        end

        def send_jit_payload_command(prefix, bytes)
          payload = Array(bytes).pack('C*').unpack1('H*')
          send_jit_command("#{prefix} #{payload}")
        end

        def parse_jit_framebuffer(response)
          _, hex = response.split(' ', 2)
          (hex || '').scan(/../).map { |byte| byte.to_i(16) }
        end

        def parse_jit_state(response)
          _, last_fetch_addr, ext_bus_addr, lcd_on, frame_count, boot_upload_active, boot_upload_phase, boot_upload_index, boot_rom_addr, boot_upload_low_byte, gb_core_reset_r, gb_core_boot_rom_enabled, gb_core_boot_q, ext_bus_a15, cart_rd, cart_wr, cart_do, lcd_clkena, lcd_data_gb, lcd_vsync, gb_core_cpu_pc, gb_core_cpu_ir, gb_core_cpu_tstate, gb_core_cpu_mcycle, gb_core_cpu_addr, gb_core_cpu_di, gb_core_cpu_do, gb_core_cpu_m1_n, gb_core_cpu_mreq_n, gb_core_cpu_iorq_n, gb_core_cpu_rd_n, gb_core_cpu_wr_n, speed_ctrl_ce, speed_ctrl_ce_n, speed_ctrl_ce_2x, speed_ctrl_state, speed_ctrl_clkdiv, speed_ctrl_unpause_cnt, speed_ctrl_fastforward_cnt, video_h_cnt, video_v_cnt, video_scy, video_scx, video_bg_palette, video_obj_palette0, video_obj_palette1, video_bg_shift_lo, video_bg_shift_hi, video_bg_attr, video_obj_shift_lo, video_obj_shift_hi, video_obj_meta0, video_obj_meta1, video_fetch_phase, video_fetch_slot, video_fetch_hold0, video_fetch_hold1, video_fetch_data0, video_fetch_data1, video_tile_lo, video_tile_hi, video_input_vram_data, video_input_vram1_data, vram0_q_a_reg, vram1_q_a_reg = response.split
          {
            last_fetch_addr: last_fetch_addr.to_i & 0xFFFF,
            ext_bus_addr: ext_bus_addr.to_i & 0xFFFF,
            lcd_on: lcd_on.to_i & 0x1,
            frame_count: frame_count.to_i,
            boot_upload_active: (boot_upload_active || 0).to_i & 0x1,
            boot_upload_phase: (boot_upload_phase || 0).to_i & 0x1,
            boot_upload_index: (boot_upload_index || 0).to_i & 0xFF,
            boot_rom_addr: (boot_rom_addr || 0).to_i & 0xFF,
            boot_upload_low_byte: (boot_upload_low_byte || 0).to_i & 0xFF,
            gb_core_reset_r: (gb_core_reset_r || 0).to_i & 0x1,
            gb_core_boot_rom_enabled: (gb_core_boot_rom_enabled || 0).to_i & 0x1,
            gb_core_boot_q: (gb_core_boot_q || 0).to_i & 0xFF,
            ext_bus_a15: (ext_bus_a15 || 0).to_i & 0x1,
            cart_rd: (cart_rd || 0).to_i & 0x1,
            cart_wr: (cart_wr || 0).to_i & 0x1,
            cart_do: (cart_do || 0).to_i & 0xFF,
            lcd_clkena: (lcd_clkena || 0).to_i & 0x1,
            lcd_data_gb: (lcd_data_gb || 0).to_i & 0x3,
            lcd_vsync: (lcd_vsync || 0).to_i & 0x1,
            gb_core_cpu_pc: (gb_core_cpu_pc || 0).to_i & 0xFFFF,
            gb_core_cpu_ir: (gb_core_cpu_ir || 0).to_i & 0xFF,
            gb_core_cpu_tstate: (gb_core_cpu_tstate || 0).to_i & 0x7,
            gb_core_cpu_mcycle: (gb_core_cpu_mcycle || 0).to_i & 0x7,
            gb_core_cpu_addr: (gb_core_cpu_addr || 0).to_i & 0xFFFF,
            gb_core_cpu_di: (gb_core_cpu_di || 0).to_i & 0xFF,
            gb_core_cpu_do: (gb_core_cpu_do || 0).to_i & 0xFF,
            gb_core_cpu_m1_n: (gb_core_cpu_m1_n || 0).to_i & 0x1,
            gb_core_cpu_mreq_n: (gb_core_cpu_mreq_n || 0).to_i & 0x1,
            gb_core_cpu_iorq_n: (gb_core_cpu_iorq_n || 0).to_i & 0x1,
            gb_core_cpu_rd_n: (gb_core_cpu_rd_n || 0).to_i & 0x1,
            gb_core_cpu_wr_n: (gb_core_cpu_wr_n || 0).to_i & 0x1,
            speed_ctrl_ce: (speed_ctrl_ce || 0).to_i & 0x1,
            speed_ctrl_ce_n: (speed_ctrl_ce_n || 0).to_i & 0x1,
            speed_ctrl_ce_2x: (speed_ctrl_ce_2x || 0).to_i & 0x1,
            speed_ctrl_state: (speed_ctrl_state || 0).to_i & 0x7,
            speed_ctrl_clkdiv: (speed_ctrl_clkdiv || 0).to_i & 0x7,
            speed_ctrl_unpause_cnt: (speed_ctrl_unpause_cnt || 0).to_i & 0xF,
            speed_ctrl_fastforward_cnt: (speed_ctrl_fastforward_cnt || 0).to_i & 0xF,
            video_h_cnt: (video_h_cnt || 0).to_i & 0xFF,
            video_v_cnt: (video_v_cnt || 0).to_i & 0xFF,
            video_scy: (video_scy || 0).to_i & 0xFF,
            video_scx: (video_scx || 0).to_i & 0xFF,
            video_bg_palette: (video_bg_palette || 0).to_i & 0xFF,
            video_obj_palette0: (video_obj_palette0 || 0).to_i & 0xFF,
            video_obj_palette1: (video_obj_palette1 || 0).to_i & 0xFF,
            video_bg_shift_lo: (video_bg_shift_lo || 0).to_i & 0xFF,
            video_bg_shift_hi: (video_bg_shift_hi || 0).to_i & 0xFF,
            video_bg_attr: (video_bg_attr || 0).to_i & 0xFF,
            video_obj_shift_lo: (video_obj_shift_lo || 0).to_i & 0xFF,
            video_obj_shift_hi: (video_obj_shift_hi || 0).to_i & 0xFF,
            video_obj_meta0: (video_obj_meta0 || 0).to_i & 0xFF,
            video_obj_meta1: (video_obj_meta1 || 0).to_i & 0xFF,
            video_fetch_phase: (video_fetch_phase || 0).to_i & 0x7,
            video_fetch_slot: (video_fetch_slot || 0).to_i & 0x7,
            video_fetch_hold0: (video_fetch_hold0 || 0).to_i & 0x1,
            video_fetch_hold1: (video_fetch_hold1 || 0).to_i & 0x1,
            video_fetch_data0: (video_fetch_data0 || 0).to_i & 0xFF,
            video_fetch_data1: (video_fetch_data1 || 0).to_i & 0xFF,
            video_tile_lo: (video_tile_lo || 0).to_i & 0xFF,
            video_tile_hi: (video_tile_hi || 0).to_i & 0xFF,
            video_input_vram_data: (video_input_vram_data || 0).to_i & 0xFF,
            video_input_vram1_data: (video_input_vram1_data || 0).to_i & 0xFF,
            vram0_q_a_reg: (vram0_q_a_reg || 0).to_i & 0xFF,
            vram1_q_a_reg: (vram1_q_a_reg || 0).to_i & 0xFF
          }
        end

        def close_jit_process
          return false unless @jit_wait_thr

          begin
            send_jit_command('QUIT') if @jit_stdin && !@jit_stdin.closed?
          rescue StandardError
            nil
          end

          @jit_stdin&.close unless @jit_stdin&.closed?
          @jit_stdout&.close unless @jit_stdout&.closed?
          @jit_stderr&.close unless @jit_stderr&.closed?
          @jit_wait_thr.value
          @jit_log_thread&.join(1)
          @jit_stdin = nil
          @jit_stdout = nil
          @jit_stderr = nil
          @jit_wait_thr = nil
          @jit_log_thread = nil
          true
        end

        def darwin_host?(host_os: RbConfig::CONFIG['host_os'])
          host_os.to_s.downcase.include?('darwin')
        end

        def build_target_arch(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          return nil unless darwin_host?(host_os: host_os)

          cpu = host_cpu.to_s.downcase
          return 'arm64' if cpu.include?('arm64') || cpu.include?('aarch64')
          return 'x86_64' if cpu.include?('x86_64') || cpu.include?('amd64')

          nil
        end

        def target_triple(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          arch = build_target_arch(host_os: host_os, host_cpu: host_cpu)
          return nil unless arch

          "#{arch}-apple-macosx"
        end

        def llvm_opt_level
          raw = ENV.fetch('RHDL_GAMEBOY_ARC_LLVM_OPT_LEVEL', '0').to_s.strip
          level = raw.match?(/\A[0-3sz]\z/i) ? raw.downcase : '0'
          "-O#{level}"
        end

        def llvm_object_compiler
          requested = ENV.fetch('RHDL_GAMEBOY_ARC_OBJECT_COMPILER', '').to_s.strip.downcase
          return 'clang' if requested == 'clang'
          return 'llc' if requested == 'llc'

          command_available?('llc') ? 'llc' : 'clang'
        end

        def llvm_threads
          raw = ENV.fetch('RHDL_GAMEBOY_ARC_LLVM_THREADS', '8').to_s.strip
          value = Integer(raw, exception: false)
          value && value.positive? ? value : 8
        end

        def observe_flags
          []
        end

        def jit_compile_threads
          [Etc.nprocessors, 8].compact.min
        end

        def jit_mode?
          @jit
        end

        def resolve_component_class(hdl_dir:, top: nil)
          resolved_hdl_dir = HdlLoader.resolve_hdl_dir(hdl_dir: hdl_dir)
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
            candidate.is_a?(Class) && candidate.respond_to?(:to_mlir_hierarchy)
          end
          return component_class if component_class

          raise NameError,
                "Unable to resolve imported Game Boy top component '#{top_name}' "\
                "(expected class '#{class_name}') in #{resolved_hdl_dir}"
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
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .tr('-', '_')
            .downcase
        end

        def first_existing_path(*candidates)
          Array(candidates).flatten.compact.map { |path| File.expand_path(path) }.find { |path| File.file?(path) }
        end

        def env_truthy?(name)
          value = ENV[name].to_s.strip.downcase
          %w[1 true yes on].include?(value)
        end

        def arcilator_split_funcs_threshold
          raw = ENV['RHDL_GAMEBOY_ARC_SPLIT_FUNCS_THRESHOLD'].to_s.strip
          return nil if raw.empty?

          value = Integer(raw, exception: false)
          value && value.positive? ? value : nil
        end

        def load_shared_library(lib_path)
          @sim = RHDL::Sim::Native::MLIR::Arcilator::Runtime.open(
            lib_path: lib_path,
            signal_widths_by_name: @abi_signal_widths_by_name || {},
            signal_widths_by_idx: @abi_signal_widths_by_idx,
            backend_label: 'Game Boy Arcilator'
          )

          ensure_runner_abi!(@sim, expected_kind: :gameboy, backend_label: 'Game Boy Arcilator')

          @sim_ctx = @sim.raw_context
          @sim_destroy = @sim.bind_optional_function('sim_destroy', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_set_joystick_fn = @sim.bind_optional_function('sim_set_joystick', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
          @sim_get_last_fetch_addr_fn = @sim.bind_optional_function('sim_get_last_fetch_addr', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @sim_get_ext_bus_full_addr_fn = @sim.bind_optional_function('sim_get_ext_bus_full_addr', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @sim_get_lcd_on_fn = @sim.bind_optional_function('sim_get_lcd_on', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @sim_get_frame_count_fn = @sim.bind_optional_function('sim_get_frame_count', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
          @sim_read_vram_fn = @sim.bind_optional_function('sim_read_vram', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_CHAR)
          @sim_get_vram_write_count_fn = @sim.bind_optional_function('sim_get_vram_write_count', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
          @sim_set_joystick_fn&.call(@sim_ctx, @joystick_state || 0xFF)
        end

        def ensure_runner_abi!(sim, expected_kind:, backend_label:)
          unless sim.runner_supported?
            sim.close
            @sim = nil
            raise RuntimeError, "#{backend_label} shared library does not expose runner ABI"
          end

          actual_kind = sim.runner_kind
          return if actual_kind == expected_kind

          sim.close
          @sim = nil
          raise RuntimeError, "#{backend_label} shared library exposes runner kind #{actual_kind.inspect}, expected #{expected_kind.inspect}"
        end
      end
    end
  end
end
