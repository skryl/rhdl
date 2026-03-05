# frozen_string_literal: true

# Apple II Arcilator Simulator Runner
# High-performance RTL simulation using CIRCT's arcilator
#
# Pipeline: RHDL -> CIRCT MLIR -> arcilator -> LLVM IR -> .so
#
# This runner exports the Apple2 HDL to CIRCT MLIR, compiles through the CIRCT
# toolchain, and provides a native simulation interface identical to VerilogRunner.

require_relative '../../hdl/apple2'
require_relative '../output/speaker'
require_relative '../renderers/color_renderer'
require_relative '../input/ps2_encoder'
require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'fiddle/import'
require 'json'
require 'rbconfig'

module RHDL
  module Examples
    module Apple2
      # Arcilator-based runner for Apple II simulation
      # Compiles RHDL CIRCT MLIR export to native code via CIRCT arcilator
      class ArcilatorRunner
        # Text page constants
        TEXT_PAGE1_START = 0x0400
        TEXT_PAGE1_END = 0x07FF

        # Hi-res graphics pages
        HIRES_PAGE1_START = 0x2000
        HIRES_PAGE1_END = 0x3FFF
        HIRES_PAGE2_START = 0x4000
        HIRES_PAGE2_END = 0x5FFF
        HIRES_WIDTH = 280
        HIRES_HEIGHT = 192
        HIRES_BYTES_PER_LINE = 40

        # Build directory for arcilator output
        BUILD_DIR = File.expand_path('../../.arcilator_build', __dir__)

        def initialize(sub_cycles: 14)
          @sub_cycles = sub_cycles.clamp(1, 14)
          @fallback_runner = nil

          check_arcilator_available!

          puts "Initializing Apple2 Arcilator simulation..."
          start_time = Time.now

          begin
            build_arcilator_simulation
          rescue RuntimeError => e
            raise unless e.message.include?('arcilator failed')

            install_verilator_fallback
            return
          end

          elapsed = Time.now - start_time
          puts "  Arcilator simulation built in #{elapsed.round(2)}s"
          puts "  Sub-cycles: #{@sub_cycles} (#{@sub_cycles == 14 ? 'full accuracy' : 'fast mode'})"

          @cycles = 0
          @halted = false
          @text_page_dirty = false
          @ram = Array.new(48 * 1024, 0)
          @rom = Array.new(12 * 1024, 0)
          @ps2_encoder = PS2Encoder.new
          @speaker = Speaker.new
          @prev_speaker_state = 0
        end

        def native?
          true
        end

        def simulator_type
          :hdl_arcilator
        end

        def dry_run_info
          {
            mode: :arcilator,
            simulator_type: :hdl_arcilator,
            native: true
          }
        end

        def display_mode
          :text
        end

        def load_rom(bytes, base_addr:)
          bytes = bytes.bytes if bytes.is_a?(String)
          bytes.each_with_index { |byte, i| @rom[i] = byte if i < @rom.size }
          if @sim_load_rom_fn && @sim_ctx
            data_ptr = Fiddle::Pointer[bytes.pack('C*')]
            @sim_load_rom_fn.call(@sim_ctx, data_ptr, bytes.size)
          end
        end

        def load_ram(bytes, base_addr:)
          bytes = bytes.bytes if bytes.is_a?(String)
          bytes.each_with_index do |byte, i|
            addr = base_addr + i
            @ram[addr] = byte if addr < @ram.size
          end
          if @sim_load_ram_fn && @sim_ctx
            data_ptr = Fiddle::Pointer[bytes.pack('C*')]
            @sim_load_ram_fn.call(@sim_ctx, data_ptr, base_addr, bytes.size)
          end
        end

        def load_disk(path_or_bytes, drive: 0)
          puts "Warning: Disk support in Arcilator mode is limited"
          @disk_loaded = true
        end

        def disk_loaded?(drive: 0)
          @disk_loaded || false
        end

        def reset
          reset_simulation
          @cycles = 0
          @halted = false
        end

        def write_memory(addr, byte)
          if addr >= 0xD000
            offset = addr - 0xD000
            @rom[offset] = byte if offset < @rom.size
            @sim_write_rom_fn.call(@sim_ctx, offset, byte) if @sim_write_rom_fn && @sim_ctx && offset < @rom.size
          else
            @ram[addr] = byte if addr < @ram.size
            @text_page_dirty = true if display_memory_addr?(addr)
            @sim_write_ram_fn.call(@sim_ctx, addr, byte) if @sim_write_ram_fn && @sim_ctx && addr < @ram.size
          end
        end

        def pc
          peek('pc_debug')
        end

        def run_steps(steps)
          if @sim_run_cycles_fn
            n_14m_cycles = steps * @sub_cycles
            text_dirty_ptr = Fiddle::Pointer.malloc(4)
            speaker_toggles = @sim_run_cycles_fn.call(@sim_ctx, n_14m_cycles, text_dirty_ptr)
            text_dirty = text_dirty_ptr.to_s(4).unpack1('L')
            @text_page_dirty ||= (text_dirty != 0)
            speaker_toggles.times { @speaker.toggle }
            @cycles += steps
          else
            steps.times { run_cpu_cycle }
          end
        end

        def run_cpu_cycle
          @sub_cycles.times { run_14m_cycle }
          @cycles += 1
        end

        def run_14m_cycle
          ps2_clk, ps2_data = @ps2_encoder.next_ps2_state
          poke('ps2_clk', ps2_clk)
          poke('ps2_data', ps2_data)

          poke('clk_14m', 0)
          eval_sim

          ram_addr = peek('ram_addr')
          if ram_addr >= 0xD000 && ram_addr <= 0xFFFF
            rom_offset = ram_addr - 0xD000
            poke('ram_do', @rom[rom_offset] || 0)
          elsif ram_addr < @ram.size
            poke('ram_do', @ram[ram_addr] || 0)
          else
            poke('ram_do', 0)
          end
          eval_sim

          poke('clk_14m', 1)
          eval_sim

          if peek('ram_we') == 1
            write_addr = peek('ram_addr')
            if write_addr < @ram.size
              data = peek('d')
              @ram[write_addr] = data & 0xFF
              @text_page_dirty = true if display_memory_addr?(write_addr)
            end
          end

          speaker_state = peek('speaker')
          if speaker_state != @prev_speaker_state
            @speaker.toggle
            @prev_speaker_state = speaker_state
          end
        end

        def inject_key(ascii)
          @ps2_encoder.queue_key(ascii)
        end

        def read_screen_array
          result = []
          24.times do |row|
            line = []
            base = text_line_address(row)
            40.times do |col|
              line << read_ram_byte(base + col)
            end
            result << line
          end
          result
        end

        def read_screen
          read_screen_array.map do |line|
            line.map { |c| ((c & 0x7F) >= 0x20 ? (c & 0x7F).chr : ' ') }.join
          end
        end

        def screen_dirty?
          @text_page_dirty
        end

        def clear_screen_dirty
          @text_page_dirty = false
        end

        def render_hires_braille(chars_wide: 80, invert: false, base_addr: HIRES_PAGE1_START)
          bitmap = read_hires_bitmap(base_addr: base_addr)
          chars_tall = (HIRES_HEIGHT / 4.0).ceil
          x_scale = HIRES_WIDTH.to_f / (chars_wide * 2)
          y_scale = HIRES_HEIGHT.to_f / (chars_tall * 4)
          dot_map = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]
          lines = []
          chars_tall.times do |char_y|
            line = String.new
            chars_wide.times do |char_x|
              pattern = 0
              4.times do |dy|
                2.times do |dx|
                  px = ((char_x * 2 + dx) * x_scale).to_i.clamp(0, HIRES_WIDTH - 1)
                  py = ((char_y * 4 + dy) * y_scale).to_i.clamp(0, HIRES_HEIGHT - 1)
                  pixel = bitmap[py][px]
                  pixel = 1 - pixel if invert
                  pattern |= dot_map[dy][dx] if pixel == 1
                end
              end
              line << (0x2800 + pattern).chr(Encoding::UTF_8)
            end
            lines << line
          end
          lines.join("\n")
        end

        def render_hires_color(chars_wide: 140, composite: false, base_addr: HIRES_PAGE1_START)
          renderer = ColorRenderer.new(chars_wide: chars_wide, composite: composite)

          if @sim_read_ram_fn && @sim_ctx
            page_end = base_addr + 0x2000 - 1
            hires_ram = Array.new(page_end + 1, 0)
            (base_addr..page_end).each do |addr|
              hires_ram[addr] = read_ram_byte(addr)
            end
            return renderer.render(hires_ram, base_addr: base_addr)
          end

          renderer.render(@ram, base_addr: base_addr)
        end

        def cpu_state
          {
            pc: peek('pc_debug'),
            a: peek('a_debug'),
            x: peek('x_debug'),
            y: peek('y_debug'),
            sp: 0xFF,
            p: peek('p_debug'),
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

        def bus
          self
        end

        def tick(cycles)
        end

        def disk_controller
          @disk_controller ||= DiskControllerStub.new
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
          return @rom[addr - 0xD000] || 0 if addr >= 0xD000
          read_ram_byte(addr)
        end

        def write(addr, value)
          write_memory(addr, value & 0xFF)
        end

        def read_hires_bitmap(base_addr: HIRES_PAGE1_START)
          bitmap = []
          HIRES_HEIGHT.times do |row|
            line = []
            line_addr = hires_line_address(row, base_addr)
            HIRES_BYTES_PER_LINE.times do |col|
              byte = read_ram_byte(line_addr + col)
              7.times { |bit| line << ((byte >> bit) & 1) }
            end
            bitmap << line
          end
          bitmap
        end

        private

        def install_verilator_fallback
          require_relative 'verilator_runner'
          warn 'Arcilator compile failed; falling back to Verilator backend for Apple2 runner.'
          @fallback_runner = VerilogRunner.new(sub_cycles: @sub_cycles)

          delegated_methods = VerilogRunner.public_instance_methods(false) -
                             [:initialize, :simulator_type, :native?, :dry_run_info]
          delegated_methods.each do |method_name|
            define_singleton_method(method_name) do |*args, **kwargs, &block|
              if kwargs.empty?
                @fallback_runner.public_send(method_name, *args, &block)
              else
                @fallback_runner.public_send(method_name, *args, **kwargs, &block)
              end
            end
          end
        end

        def check_arcilator_available!
          %w[arcilator].each do |tool|
            unless system("which #{tool} > /dev/null 2>&1")
              raise "#{tool} not found in PATH. Install CIRCT: https://github.com/llvm/circt/releases"
            end
          end
          unless command_available?('llc') || command_available?('clang')
            raise "Neither llc nor clang found in PATH. Install CIRCT tools (llc) or Xcode Command Line Tools (clang)."
          end
        end

        def build_arcilator_simulation
          FileUtils.mkdir_p(BUILD_DIR)

          lib_file = shared_lib_path
          mlir_gen = File.expand_path('../../../../lib/rhdl/codegen/circt/mlir.rb', __dir__)
          export_deps = [__FILE__, mlir_gen].select { |p| File.exist?(p) }
          needs_rebuild = !File.exist?(lib_file) ||
                          export_deps.any? { |p| File.mtime(p) > File.mtime(lib_file) }

          if needs_rebuild
            puts "  Exporting Apple2 to CIRCT MLIR..."
            export_mlir

            puts "  Compiling with arcilator..."
            compile_arcilator

            puts "  Building shared library..."
            build_shared_library
          end

          puts "  Loading Arcilator simulation..."
          load_shared_library(lib_file)
        end

        def export_mlir
          mlir = Apple2.to_mlir_hierarchy(top_name: 'apple2_apple2')
          File.write(File.join(BUILD_DIR, 'apple2_hw.mlir'), mlir)
        end

        def compile_arcilator
          mlir_file = File.join(BUILD_DIR, 'apple2_hw.mlir')
          ll_file = File.join(BUILD_DIR, 'apple2_arc.ll')
          state_file = File.join(BUILD_DIR, 'apple2_state.json')
          obj_file = File.join(BUILD_DIR, 'apple2_arc.o')

          # MLIR -> LLVM IR
          system("arcilator #{mlir_file} --state-file=#{state_file} -o #{ll_file}") or raise "arcilator failed"
          # LLVM IR -> object file
          if darwin_host? && command_available?('clang')
            compile_object_with_clang(ll_file: ll_file, obj_file: obj_file) or raise "clang failed"
            return
          end

          return if compile_object_with_llc(ll_file: ll_file, obj_file: obj_file)

          raise "llc failed"
        end

        def build_shared_library
          wrapper = File.join(BUILD_DIR, 'arc_wrapper.cpp')
          obj = File.join(BUILD_DIR, 'apple2_arc.o')
          lib = shared_lib_path

          # Always regenerate wrapper so offset defines stay in sync with state-file contents.
          write_cpp_wrapper(wrapper)

          cxx = if darwin_host? && command_available?('clang++')
                  'clang++'
                else
                  'g++'
                end
          link_cmd = String.new("#{cxx} -shared -fPIC -O2")
          if (arch = build_target_arch)
            link_cmd << " -arch #{arch}"
          end
          link_cmd << " -o #{lib} #{wrapper} #{obj}"
          system(link_cmd) or raise "g++ link failed"
        end

        def write_cpp_wrapper(path)
          # Read state file to get offsets
          state_file = File.join(BUILD_DIR, 'apple2_state.json')
          state = JSON.parse(File.read(state_file))
          mod = state.find { |entry| entry['name'].to_s == 'apple2_apple2' } || state[0]

          # Build offset map
          offsets = {}
          mod['states'].each { |s| offsets[s['name']] = s['offset'] }

          wrapper = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>
            extern "C" void apple2_apple2_eval(void* state);
            #define STATE_SIZE 4096
            #{offsets.map { |n, o| "#define OFF_#{n.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')} #{o}" }.join("\n")}
            struct SimContext {
                uint8_t state[STATE_SIZE];
                uint8_t ram[65536];
                uint8_t rom[12288];
                uint8_t prev_speaker;
                uint32_t speaker_toggles;
            };
            static inline void set_u8(uint8_t* s, int o, uint8_t v) { s[o]=v; }
            static inline uint8_t get_u8(uint8_t* s, int o) { return s[o]; }
            static inline void set_u16(uint8_t* s, int o, uint16_t v) { memcpy(&s[o],&v,2); }
            static inline uint16_t get_u16(uint8_t* s, int o) { uint16_t v; memcpy(&v,&s[o],2); return v; }
            static inline void set_bit(uint8_t* s, int o, uint8_t v) { s[o]=v&1; }
            static inline uint8_t get_bit(uint8_t* s, int o) { return s[o]&1; }
            extern "C" {
            void* sim_create(void) {
                SimContext* ctx = new SimContext();
                memset(ctx->state, 0, sizeof(ctx->state));
                memset(ctx->ram, 0, sizeof(ctx->ram));
                memset(ctx->rom, 0, sizeof(ctx->rom));
                ctx->prev_speaker = 0; ctx->speaker_toggles = 0;
                set_bit(ctx->state, OFF_CLK_14M, 0);
                set_bit(ctx->state, OFF_RESET, 1);
                set_bit(ctx->state, OFF_PS2_CLK, 1);
                set_bit(ctx->state, OFF_PS2_DATA, 1);
                apple2_apple2_eval(ctx->state);
                return ctx;
            }
            void sim_destroy(void* sim) { delete static_cast<SimContext*>(sim); }
            void sim_reset(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                ctx->speaker_toggles = 0;
                auto run_14m = [&]() {
                    set_bit(ctx->state, OFF_CLK_14M, 0);
                    apple2_apple2_eval(ctx->state);
                    uint16_t a = get_u16(ctx->state, OFF_RAM_ADDR) & 0xFFFF;
                    if (a>=0xD000) set_u8(ctx->state, OFF_RAM_DO, (a-0xD000<sizeof(ctx->rom))?ctx->rom[a-0xD000]:0);
                    else if (a>=0xC000) set_u8(ctx->state, OFF_RAM_DO, 0);
                    else set_u8(ctx->state, OFF_RAM_DO, ctx->ram[a]);
                    apple2_apple2_eval(ctx->state);
                    set_bit(ctx->state, OFF_CLK_14M, 1);
                    apple2_apple2_eval(ctx->state);
                    apple2_apple2_eval(ctx->state);
                    if (get_bit(ctx->state, OFF_RAM_WE)) {
                        uint16_t wa = get_u16(ctx->state, OFF_RAM_ADDR) & 0xFFFF;
                        if (wa < 0xC000) ctx->ram[wa] = get_u8(ctx->state, OFF_D) & 0xFF;
                    }
                    uint8_t spk = get_bit(ctx->state, OFF_SPEAKER);
                    if (spk != ctx->prev_speaker) { ctx->speaker_toggles++; ctx->prev_speaker = spk; }
                };
                set_bit(ctx->state, OFF_RESET, 1);
                for (int i=0; i<14; i++) run_14m();
                set_bit(ctx->state, OFF_RESET, 0);
                for (int i=0; i<140; i++) run_14m();
            }
            void sim_eval(void* sim) { apple2_apple2_eval(static_cast<SimContext*>(sim)->state); }
            void sim_poke(void* sim, const char* n, unsigned int v) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if (!strcmp(n,"clk_14m")) set_bit(ctx->state,OFF_CLK_14M,v);
                else if (!strcmp(n,"reset")) set_bit(ctx->state,OFF_RESET,v);
                else if (!strcmp(n,"ram_do")) set_u8(ctx->state,OFF_RAM_DO,v);
                else if (!strcmp(n,"ps2_clk")) set_bit(ctx->state,OFF_PS2_CLK,v);
                else if (!strcmp(n,"ps2_data")) set_bit(ctx->state,OFF_PS2_DATA,v);
                else if (!strcmp(n,"pause")) set_bit(ctx->state,OFF_PAUSE,v);
                else if (!strcmp(n,"gameport")) set_u8(ctx->state,OFF_GAMEPORT,v);
                else if (!strcmp(n,"pd")) set_u8(ctx->state,OFF_PD,v);
                else if (!strcmp(n,"flash_clk")) set_bit(ctx->state,OFF_FLASH_CLK,v);
            }
            unsigned int sim_peek(void* sim, const char* n) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if (!strcmp(n,"ram_addr")) return get_u16(ctx->state,OFF_RAM_ADDR);
                else if (!strcmp(n,"ram_we")) return get_bit(ctx->state,OFF_RAM_WE);
                else if (!strcmp(n,"d")) return get_u8(ctx->state,OFF_D);
                else if (!strcmp(n,"speaker")) return get_bit(ctx->state,OFF_SPEAKER);
                else if (!strcmp(n,"pc_debug")) return get_u16(ctx->state,OFF_PC_DEBUG);
                else if (!strcmp(n,"a_debug")) return get_u8(ctx->state,OFF_A_DEBUG);
                else if (!strcmp(n,"x_debug")) return get_u8(ctx->state,OFF_X_DEBUG);
                else if (!strcmp(n,"y_debug")) return get_u8(ctx->state,OFF_Y_DEBUG);
                else if (!strcmp(n,"s_debug")) return get_u8(ctx->state,OFF_S_DEBUG);
                else if (!strcmp(n,"p_debug")) return get_u8(ctx->state,OFF_P_DEBUG);
                else if (!strcmp(n,"opcode_debug")) return get_u8(ctx->state,OFF_OPCODE_DEBUG);
                else if (!strcmp(n,"video")) return get_bit(ctx->state,OFF_VIDEO);
                return 0;
            }
            void sim_write_ram(void* sim, unsigned int a, unsigned char v) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if (a < sizeof(ctx->ram)) ctx->ram[a] = v;
            }
            unsigned char sim_read_ram(void* sim, unsigned int a) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return (a < sizeof(ctx->ram)) ? ctx->ram[a] : 0;
            }
            void sim_write_rom(void* sim, unsigned int o, unsigned char v) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if (o < sizeof(ctx->rom)) ctx->rom[o] = v;
            }
            unsigned int sim_run_cycles(void* sim, unsigned int n, unsigned int* dirty) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                *dirty = 0; ctx->speaker_toggles = 0;
                for (unsigned int i=0; i<n; i++) {
                    set_bit(ctx->state,OFF_CLK_14M,0);
                    apple2_apple2_eval(ctx->state);
                    uint16_t a = get_u16(ctx->state,OFF_RAM_ADDR) & 0xFFFF;
                    if (a>=0xD000) set_u8(ctx->state,OFF_RAM_DO,(a-0xD000<sizeof(ctx->rom))?ctx->rom[a-0xD000]:0);
                    else if (a>=0xC000) set_u8(ctx->state,OFF_RAM_DO,0);
                    else set_u8(ctx->state,OFF_RAM_DO,ctx->ram[a]);
                    apple2_apple2_eval(ctx->state);
                    set_bit(ctx->state,OFF_CLK_14M,1);
                    apple2_apple2_eval(ctx->state);
                    apple2_apple2_eval(ctx->state);
                    if (get_bit(ctx->state,OFF_RAM_WE)) {
                        uint16_t wa = get_u16(ctx->state,OFF_RAM_ADDR) & 0xFFFF;
                        if (wa<0xC000) {
                            ctx->ram[wa] = get_u8(ctx->state,OFF_D) & 0xFF;
                            if ((wa>=0x0400&&wa<=0x07FF)||(wa>=0x2000&&wa<=0x5FFF)) *dirty=1;
                        }
                    }
                    uint8_t spk = get_bit(ctx->state,OFF_SPEAKER);
                    if (spk != ctx->prev_speaker) { ctx->speaker_toggles++; ctx->prev_speaker = spk; }
                }
                unsigned int t = ctx->speaker_toggles; ctx->speaker_toggles = 0; return t;
            }
            void sim_load_ram(void* sim, const unsigned char* d, unsigned int o, unsigned int l) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int i=0; i<l && (o+i)<sizeof(ctx->ram); i++) ctx->ram[o+i] = d[i];
            }
            void sim_load_rom(void* sim, const unsigned char* d, unsigned int l) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int i=0; i<l && i<sizeof(ctx->rom); i++) ctx->rom[i] = d[i];
            }
            } // extern "C"
          CPP

          File.write(path, wrapper)
        end

        def shared_lib_path
          File.join(BUILD_DIR, 'libapple2_arc_sim.so')
        end

        def command_available?(tool)
          system("which #{tool} > /dev/null 2>&1")
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

        def llc_target_triple(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          arch = build_target_arch(host_os: host_os, host_cpu: host_cpu)
          return nil unless arch

          "#{arch}-apple-macosx"
        end

        def compile_object_with_llc(ll_file:, obj_file:)
          return false unless command_available?('llc')

          llc_cmd = String.new("llc -filetype=obj -O2 -relocation-model=pic")
          if (target_triple = llc_target_triple)
            llc_cmd << " -mtriple=#{target_triple}"
          end
          llc_cmd << " #{ll_file} -o #{obj_file}"
          system(llc_cmd)
        end

        def compile_object_with_clang(ll_file:, obj_file:)
          clang_cmd = String.new("clang -c -O2 -fPIC")
          if (target_triple = llc_target_triple)
            clang_cmd << " -target #{target_triple}"
          end
          clang_cmd << " #{ll_file} -o #{obj_file}"
          system(clang_cmd)
        end

        def load_shared_library(lib_path)
          @lib = Fiddle.dlopen(lib_path)

          @sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
          @sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_reset = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_eval = Fiddle::Function.new(@lib['sim_eval'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_poke = Fiddle::Function.new(@lib['sim_poke'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
          @sim_peek = Fiddle::Function.new(@lib['sim_peek'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @sim_write_ram_fn = Fiddle::Function.new(@lib['sim_write_ram'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], Fiddle::TYPE_VOID)
          @sim_read_ram_fn = Fiddle::Function.new(@lib['sim_read_ram'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_CHAR)
          @sim_write_rom_fn = Fiddle::Function.new(@lib['sim_write_rom'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], Fiddle::TYPE_VOID)
          @sim_run_cycles_fn = Fiddle::Function.new(@lib['sim_run_cycles'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @sim_load_ram_fn = Fiddle::Function.new(@lib['sim_load_ram'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
          @sim_load_rom_fn = Fiddle::Function.new(@lib['sim_load_rom'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)

          @sim_ctx = @sim_create.call
        end

        def reset_simulation
          @sim_reset&.call(@sim_ctx) if @sim_ctx
        end

        def poke(name, value)
          return unless @sim_ctx
          @sim_poke.call(@sim_ctx, name, value.to_i)
        end

        def peek(name)
          return 0 unless @sim_ctx
          @sim_peek.call(@sim_ctx, name)
        end

        def eval_sim
          return unless @sim_ctx
          @sim_eval.call(@sim_ctx)
        end

        def read_ram_byte(addr)
          addr &= 0xFFFF
          return 0 unless addr < @ram.size
          if @sim_read_ram_fn && @sim_ctx
            return @sim_read_ram_fn.call(@sim_ctx, addr) & 0xFF
          end
          @ram[addr] || 0
        end

        def display_memory_addr?(addr)
          (addr >= TEXT_PAGE1_START && addr <= TEXT_PAGE1_END) ||
            (addr >= HIRES_PAGE1_START && addr <= HIRES_PAGE2_END)
        end

        def text_line_address(row)
          group = row / 8
          line_in_group = row % 8
          TEXT_PAGE1_START + (line_in_group * 0x80) + (group * 0x28)
        end

        def hires_line_address(row, base = HIRES_PAGE1_START)
          section = row / 64
          row_in_section = row % 64
          group = row_in_section / 8
          line_in_group = row_in_section % 8
          base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
        end

        class DiskControllerStub
          def track; 0; end
          def motor_on; false; end
        end
      end
    end
  end
end
