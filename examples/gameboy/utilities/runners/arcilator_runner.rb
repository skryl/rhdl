# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'fiddle'
require 'json'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'rhdl/codegen'

module RHDL
  module Examples
    module GameBoy
      # Arcilator-based runner for imported Game Boy cores.
      # This backend runs the imported `gb` MLIR directly instead of raising the
      # generated wrapper back through RHDL, so it is useful for benchmarking
      # the imported IR path on its own.
      class ArcilatorRunner
        SCREEN_WIDTH = 160
        SCREEN_HEIGHT = 144
        BUILD_BASE = File.expand_path('../../.arcilator_build', __dir__)
        DEFAULT_IMPORT_DIR = File.expand_path('../../import', __dir__)
        DMG_BOOT_ROM_PATH = File.expand_path('../../software/roms/dmg_boot.bin', __dir__)
        OBSERVE_FLAGS = ['--observe-ports'].freeze

        SIGNAL_SPECS = {
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

        STATIC_INPUT_VALUES = {
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

        def initialize(hdl_dir: nil, top: nil)
          @import_root = resolve_import_root(hdl_dir)
          @requested_top = top&.to_s
          @import_report = load_import_report!(@import_root)
          validate_requested_top!

          check_tools_available!

          log 'Initializing Game Boy Arcilator simulation...'
          start_time = Time.now
          build_simulation
          load_shared_library(@lib_path)
          elapsed = Time.now - start_time
          log "  Arcilator simulation built in #{elapsed.round(2)}s"

          @cycles = 0
          @halted = false
          @joystick_state = 0xFF
          @frame_count = 0

          load_boot_rom if File.exist?(DMG_BOOT_ROM_PATH)
        end

        def native?
          true
        end

        def simulator_type
          :hdl_arcilator
        end

        def dry_run_info
          {
            mode: :circt,
            simulator_type: :hdl_arcilator,
            native: true
          }
        end

        def load_rom(bytes, base_addr: 0)
          bytes = bytes.bytes if bytes.is_a?(String)
          @rom = bytes.dup
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
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
          data_ptr = Fiddle::Pointer[bytes.pack('C*')]
          @sim_load_boot_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
          @boot_rom_loaded = true
          log "Loaded #{bytes.size} bytes boot ROM"
        end

        def boot_rom_loaded?
          @boot_rom_loaded || false
        end

        def reset
          @sim_reset.call(@sim_ctx)
          @cycles = 0
          @frame_count = 0
          @halted = false
          @joystick_state = 0xFF
          @sim_set_joystick_fn.call(@sim_ctx, @joystick_state)
        end

        def run_steps(steps)
          result_ptr = Fiddle::Pointer.malloc(16)
          @sim_run_cycles_fn.call(@sim_ctx, steps, result_ptr)
          cycles_run, frames_completed = result_ptr.to_s(16).unpack('QL')
          @cycles += cycles_run
          @frame_count += frames_completed
        end

        def inject_key(button)
          @joystick_state &= ~(1 << button)
          @sim_set_joystick_fn.call(@sim_ctx, @joystick_state)
        end

        def release_key(button)
          @joystick_state |= (1 << button)
          @sim_set_joystick_fn.call(@sim_ctx, @joystick_state)
        end

        def read_framebuffer
          buffer = Fiddle::Pointer.malloc(SCREEN_WIDTH * SCREEN_HEIGHT)
          @sim_read_framebuffer_fn.call(@sim_ctx, buffer)
          flat = buffer.to_s(SCREEN_WIDTH * SCREEN_HEIGHT).bytes
          Array.new(SCREEN_HEIGHT) do |y|
            Array.new(SCREEN_WIDTH) do |x|
              flat[(y * SCREEN_WIDTH) + x]
            end
          end
        end

        def cpu_state
          full_bus_addr = @sim_get_ext_bus_full_addr_fn.call(@sim_ctx).to_i & 0xFFFF
          last_fetch_addr = @sim_get_last_fetch_addr_fn.call(@sim_ctx).to_i & 0xFFFF
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

        def close
          return false unless @sim_ctx

          @sim_destroy.call(@sim_ctx)
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
          raise ArgumentError, "Imported Game Boy report not found: #{report_path}" unless File.file?(report_path)

          JSON.parse(File.read(report_path))
        end

        def imported_core_top_name
          @imported_core_top_name ||= begin
            top = @import_report.dig('mixed_import', 'top_name').to_s
            top.empty? ? 'gb' : top
          end
        end

        def validate_requested_top!
          return if @requested_top.nil? || @requested_top.empty?
          return if [imported_core_top_name, 'Gameboy'].include?(@requested_top)

          raise ArgumentError,
                "Game Boy ArcilatorRunner currently runs the imported core top '#{imported_core_top_name}'. "\
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

        def build_artifact_stem
          @build_artifact_stem ||= begin
            seed = [
              @import_root,
              core_mlir_path,
              imported_core_top_name,
              llvm_opt_level,
              arcilator_split_funcs_threshold.to_s,
              OBSERVE_FLAGS.join(','),
              __FILE__
            ].join('|')
            Digest::SHA1.hexdigest(seed)[0, 12]
          end
        end

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, build_artifact_stem)
        end

        def shared_lib_path
          File.join(build_dir, 'libgameboy_arc_sim.so')
        end

        def check_tools_available!
          %w[arcilator firtool circt-opt].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end

          return if darwin_host? && command_available?('clang') && command_available?('clang++')
          raise LoadError, 'llc not found in PATH' unless command_available?('llc')
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
          ll_path = File.join(build_dir, 'gameboy_arc.ll')
          state_path = File.join(build_dir, 'gameboy_state.json')
          obj_path = File.join(build_dir, 'gameboy_arc.o')
          wrapper_path = File.join(build_dir, 'arc_wrapper.cpp')
          lib_path = shared_lib_path

          deps = [
            __FILE__,
            File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__),
            core_mlir_path,
            import_report_path
          ].select { |path| File.exist?(path) }

          needs_rebuild =
            !File.exist?(lib_path) ||
            !File.exist?(state_path) ||
            deps.any? { |path| File.mtime(path) > File.mtime(lib_path) }

          if needs_rebuild
            prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
              mlir_path: core_mlir_path,
              work_dir: arc_dir,
              base_name: 'gb',
              top: imported_core_top_name
            )
            raise "ARC preparation failed:\n#{prepared.dig(:arc, :stderr)}" unless prepared[:success]

            run_arcilator!(
              arc_mlir_path: prepared.fetch(:arc_mlir_path),
              state_path: state_path,
              ll_path: ll_path,
              log_path: log_path
            )
            state_info = parse_state_file!(state_path)
            write_arcilator_wrapper(wrapper_path: wrapper_path, state_info: state_info)
            compile_object!(ll_path: ll_path, obj_path: obj_path, log_path: log_path)
            link_shared_library!(wrapper_path: wrapper_path, obj_path: obj_path, lib_path: lib_path, log_path: log_path)
          end

          @lib_path = lib_path
        end

        def run_arcilator!(arc_mlir_path:, state_path:, ll_path:, log_path:)
          FileUtils.rm_f(state_path)
          FileUtils.rm_f(ll_path)
          cmd = ['arcilator', arc_mlir_path, *OBSERVE_FLAGS]
          threshold = arcilator_split_funcs_threshold
          cmd << "--split-funcs-threshold=#{threshold}" if threshold
          cmd += ["--state-file=#{state_path}", '-o', ll_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, "#{stdout}#{stderr}")
          return if status.success?

          raise "Arcilator compile failed:\n#{stdout}\n#{stderr}"
        end

        def parse_state_file!(path)
          state = JSON.parse(File.read(path))
          mod = state.find { |entry| entry['name'].to_s == imported_core_top_name } || state.first
          raise "Arcilator state file missing module entries: #{path}" unless mod

          states = Array(mod['states'])
          signals = SIGNAL_SPECS.each_with_object({}) do |(key, spec), acc|
            acc[key] = locate_signal(states, spec.fetch(:name), preferred_type: spec[:preferred_type])
          end

          missing = signals.select { |_key, meta| meta.nil? }.keys
          unless missing.empty?
            raise "Arcilator state layout missing required Game Boy signals: #{missing.join(', ')}"
          end

          {
            module_name: mod.fetch('name'),
            state_size: mod.fetch('numStateBytes').to_i,
            signals: signals
          }
        end

        def locate_signal(states, name, preferred_type:)
          matches = states.select { |entry| entry['name'].to_s == name.to_s }
          return nil if matches.empty?

          match = matches.find { |entry| entry['type'].to_s == preferred_type.to_s } || matches.first
          {
            name: match.fetch('name'),
            offset: match.fetch('offset').to_i,
            bits: match.fetch('numBits').to_i,
            type: match['type'].to_s
          }
        end

        def write_arcilator_wrapper(wrapper_path:, state_info:)
          module_name = state_info.fetch(:module_name)
          state_size = state_info.fetch(:state_size)
          signals = state_info.fetch(:signals)

          defines = signals.map do |key, meta|
            macro = sanitize_macro(key)
            [
              "#define OFF_#{macro} #{meta.fetch(:offset)}",
              "#define BITS_#{macro} #{meta.fetch(:bits)}"
            ].join("\n")
          end.join("\n")

          static_tieoffs = STATIC_INPUT_VALUES.map do |key, value|
            macro = sanitize_macro(key)
            "  write_bits(ctx->state, OFF_#{macro}, BITS_#{macro}, #{format_c_integer(value)}ULL);"
          end.join("\n")

          wrapper = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>

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
              uint8_t framebuffer[160 * 144];
              unsigned int lcd_x;
              unsigned int lcd_y;
              uint8_t prev_lcd_clkena;
              uint8_t prev_lcd_vsync;
              unsigned long frame_count;
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

              if (lcd_clkena != 0u && ctx->prev_lcd_clkena == 0u) {
                if (ctx->lcd_x < 160u && ctx->lcd_y < 144u) {
                  ctx->framebuffer[(ctx->lcd_y * 160u) + ctx->lcd_x] = static_cast<uint8_t>(lcd_data);
                }
                ctx->lcd_x++;
                if (ctx->lcd_x >= 160u) {
                  ctx->lcd_x = 0u;
                  ctx->lcd_y++;
                }
              }

              if (lcd_vsync != 0u && ctx->prev_lcd_vsync == 0u) {
                ctx->lcd_x = 0u;
                ctx->lcd_y = 0u;
                ctx->frame_count++;
                if (result) result->frames_completed++;
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

            void* sim_create(void) {
              SimContext* ctx = new SimContext();
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
              delete static_cast<SimContext*>(sim);
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

            void sim_run_cycles(void* sim, unsigned int n_cycles, GbCycleResult* result) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              result->cycles_run = 0u;
              result->frames_completed = 0u;
              while (result->cycles_run < n_cycles) {
                run_single_cycle(ctx, result);
              }
            }

            }  // extern "C"
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

        def compile_object!(ll_path:, obj_path:, log_path:)
          stdout = +''
          stderr = +''
          status = nil

          # The imported Game Boy ARC IR is large enough that compiling the raw
          # LLVM IR with clang on macOS uses excessive memory. Prefer llc when
          # available and keep clang only as a fallback.
          if command_available?('llc')
            cmd = ['llc', '-filetype=obj', llvm_opt_level, '-relocation-model=pic']
            cmd += ["-mtriple=#{target_triple}"] if target_triple
            cmd += [ll_path, '-o', obj_path]
            stdout, stderr, status = Open3.capture3(*cmd)
          else
            cmd = ['clang', '-c', llvm_opt_level, '-fPIC']
            if (target = target_triple)
              cmd += ['-target', target]
            end
            cmd += [ll_path, '-o', obj_path]
            stdout, stderr, status = Open3.capture3(*cmd)
          end

          File.write(log_path, File.read(log_path).to_s + stdout + stderr)
          return if status.success?

          raise "Object compilation failed:\n#{stdout}\n#{stderr}"
        end

        def link_shared_library!(wrapper_path:, obj_path:, lib_path:, log_path:)
          cxx = if darwin_host? && command_available?('clang++')
                  'clang++'
                elsif command_available?('g++')
                  'g++'
                else
                  'c++'
                end

          cmd = [cxx, '-shared', '-fPIC', '-O2']
          cmd += ['-arch', build_target_arch] if build_target_arch
          cmd += ['-o', lib_path, wrapper_path, obj_path]

          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, File.read(log_path).to_s + stdout + stderr)
          return if status.success?

          raise "Shared library link failed:\n#{stdout}\n#{stderr}"
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

        def arcilator_split_funcs_threshold
          raw = ENV.fetch('RHDL_GAMEBOY_ARC_SPLIT_FUNCS_THRESHOLD', '1000').to_s.strip
          return nil if raw.empty?

          value = Integer(raw, exception: false)
          value && value.positive? ? value : nil
        end

        def load_shared_library(lib_path)
          @lib = Fiddle.dlopen(lib_path)

          @sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
          @sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_reset = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_set_joystick_fn = Fiddle::Function.new(
            @lib['sim_set_joystick'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
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
          @sim_read_framebuffer_fn = Fiddle::Function.new(
            @lib['sim_read_framebuffer'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )
          @sim_get_last_fetch_addr_fn = Fiddle::Function.new(
            @lib['sim_get_last_fetch_addr'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_get_ext_bus_full_addr_fn = Fiddle::Function.new(
            @lib['sim_get_ext_bus_full_addr'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_get_lcd_on_fn = Fiddle::Function.new(
            @lib['sim_get_lcd_on'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
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

          @sim_ctx = @sim_create.call
          @sim_set_joystick_fn.call(@sim_ctx, @joystick_state || 0xFF)
        end
      end
    end
  end
end
