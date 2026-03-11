# frozen_string_literal: true

require 'fileutils'
require 'fiddle'
require 'json'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'rhdl/codegen'
require_relative '../../hdl/cpu/cpu'

module RHDL
  module Examples
    module CPU8Bit
      # Native runner for 8-bit CPU using arcilator ArcToGPU lowering.
      #
      # Pipeline:
      #   RHDL CPU -> FIRRTL -> firtool (HW MLIR) -> arcilator (ArcToGPU LLVM IR)
      #   -> clang/llc object -> C++ shim .so/.dylib -> Fiddle
      class ArcilatorGpuRunner
        BUILD_DIR = File.expand_path('../../.arcilator_gpu_build', __dir__)
        MAX_INSTANCE_COUNT = 1024

        REQUIRED_TOOLS = %w[firtool arcilator mlir-opt spirv-cross].freeze
        GPU_OPTION_PATTERNS = [
          '--arc-to-gpu',
          '--lowering=arc-to-gpu',
          '--arc-lowering=to-gpu',
          '--lower-arc-to-gpu'
        ].freeze

        REQUIRED_SIGNAL_NAMES = %w[
          clk
          rst
          mem_addr
          mem_data_in
          mem_data_out
          mem_write_en
          halted
          pc_out
          acc_out
          sp_out
          state_out
          zero_flag_out
        ].freeze

        attr_reader :backend, :instance_count

        def self.status
          missing_tools = REQUIRED_TOOLS.reject { |tool| command_available?(tool) }
          missing_tools << 'llc/clang' unless command_available?('llc') || command_available?('clang')
          missing_tools << 'c++/clang++/g++' unless command_available?('c++') || command_available?('clang++') || command_available?('g++')

          arcilator_help = command_output(%w[arcilator --help])
          gpu_option_tokens = detect_gpu_option_tokens(arcilator_help)
          missing_capabilities = []

          if macos_host?
            missing_tools << 'xcrun' unless command_available?('xcrun')
            missing_tools << 'metal' unless command_success?(%w[xcrun -f metal])
            missing_tools << 'metallib' unless command_success?(%w[xcrun -f metallib])
          end

          {
            ready: missing_tools.empty?,
            missing_tools: missing_tools.uniq,
            missing_capabilities: missing_capabilities,
            gpu_option_tokens: gpu_option_tokens
          }
        end

        def self.ensure_available!
          info = status
          return info if info[:ready]

          details = []
          details << "missing tools: #{info[:missing_tools].join(', ')}" unless info[:missing_tools].empty?
          details << "missing capabilities: #{info[:missing_capabilities].join(', ')}" unless info[:missing_capabilities].empty?

          raise ArgumentError,
            "arcilator_gpu backend unavailable (#{details.join('; ')}). " \
            "Install required arcilator/firtool and Metal/SPIR-V toolchain tools."
        end

        def self.detect_gpu_option_tokens(help_text)
          env_value = ENV['RHDL_ARCILATOR_GPU_OPTION'].to_s.strip
          return Shellwords.split(env_value) unless env_value.empty?

          text = help_text.to_s
          return [] if text.empty?

          GPU_OPTION_PATTERNS.each do |opt|
            return [opt] if text.include?(opt)
          end

          text.each_line do |line|
            next unless line.match?(/arc/i) && line.match?(/gpu/i)

            token = line[/--[A-Za-z0-9][A-Za-z0-9\-_=]*/]
            return [token] if token
          end

          []
        end

        def initialize(instances: nil)
          @backend = :arcilator_gpu
          @instance_count = normalize_instance_count(instances)
          @gpu_info = self.class.ensure_available!
          @gpu_option_tokens = @gpu_info[:gpu_option_tokens]
          build_simulation
          load_library
          reset
        end

        def native?
          true
        end

        def runner_mode?
          true
        end

        def runner_kind
          :cpu8bit
        end

        def runner_parallel_instances
          @instance_count
        end

        def evaluate
          @fn_sim_eval.call(@ctx)
          nil
        end

        def reset
          @fn_sim_reset.call(@ctx)
          nil
        end

        def poke(name, value)
          @fn_sim_poke.call(@ctx, name.to_s, value.to_i & 0xFFFF_FFFF)
          true
        end

        def peek(name)
          @fn_sim_peek.call(@ctx, name.to_s) & 0xFFFF_FFFF
        end

        def runner_load_memory(data, offset = 0, _is_rom = false)
          payload = normalize_payload(data)
          return false if payload.empty?

          ptr = Fiddle::Pointer[payload]
          loaded = @fn_runner_load_memory.call(@ctx, ptr, payload.bytesize, offset.to_i & 0xFFFF)
          loaded.to_i.positive?
        end

        def runner_read_memory(offset, length, mapped: true)
          _ = mapped
          len = [length.to_i, 0].max
          return [] if len.zero?

          out = Fiddle::Pointer.malloc(len)
          read_len = @fn_runner_read_memory.call(@ctx, offset.to_i & 0xFFFF, len, out).to_i
          return [] if read_len <= 0

          out[0, read_len].unpack('C*')
        end

        def runner_write_memory(offset, data, mapped: true)
          _ = mapped
          payload = normalize_payload(data)
          return 0 if payload.empty?

          ptr = Fiddle::Pointer[payload]
          @fn_runner_write_memory.call(@ctx, offset.to_i & 0xFFFF, ptr, payload.bytesize).to_i
        end

        def runner_run_cycles(n, _key_data = 0, _key_ready = false)
          cycles = @fn_runner_run_cycles.call(@ctx, [n.to_i, 0].max).to_i
          {
            text_dirty: false,
            key_cleared: false,
            cycles_run: cycles,
            speaker_toggles: 0
          }
        end

        private

        def self.command_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, tool))
          end
        end

        def self.command_output(cmd)
          out, _status = Open3.capture2e(*cmd)
          out
        rescue StandardError
          ''
        end

        def self.command_success?(cmd)
          _out, status = Open3.capture2e(*cmd)
          status.success?
        rescue StandardError
          false
        end

        def self.macos_host?
          RUBY_PLATFORM.include?('darwin')
        end

        def command_available?(tool)
          self.class.command_available?(tool)
        end

        def normalize_instance_count(instances)
          raw = instances || ENV['RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES'] || ENV['RHDL_BENCH_ARCILATOR_GPU_INSTANCES']
          value = raw.to_i
          value = 1 if value <= 0
          [value, MAX_INSTANCE_COUNT].min
        end

        def build_simulation
          FileUtils.mkdir_p(BUILD_DIR)

          fir_file = File.join(BUILD_DIR, 'cpu8bit.fir')
          mlir_file = File.join(BUILD_DIR, 'cpu8bit_hw.mlir')
          ll_file = File.join(BUILD_DIR, 'cpu8bit_arcgpu.ll')
          state_file = File.join(BUILD_DIR, 'cpu8bit_state.json')
          obj_file = File.join(BUILD_DIR, 'cpu8bit_arcgpu.o')
          wrapper_file = File.join(BUILD_DIR, 'cpu8bit_arcgpu_wrapper.cpp')
          runner_file = __FILE__

          firrtl_changed = write_file_if_changed(
            fir_file,
            RHDL::Codegen::CIRCT::FIRRTL.generate(RHDL::HDL::CPU::CPU.to_flat_ir(top_name: 'cpu8bit'))
          )

          codegen_needed = firrtl_changed
          codegen_needed ||= !File.exist?(mlir_file) || !File.exist?(ll_file) || !File.exist?(state_file) || !File.exist?(obj_file)
          codegen_needed ||= File.exist?(obj_file) && File.mtime(runner_file) > File.mtime(obj_file)

          if codegen_needed
            compile_with_arcilator(fir_file, mlir_file, ll_file, state_file, obj_file)
          end

          wrapper_changed = write_wrapper(wrapper_file, state_file)

          needs_link = !File.exist?(shared_lib_path)
          needs_link ||= codegen_needed || wrapper_changed
          needs_link ||= File.mtime(obj_file) > File.mtime(shared_lib_path) if File.exist?(shared_lib_path)
          needs_link ||= File.mtime(wrapper_file) > File.mtime(shared_lib_path) if File.exist?(shared_lib_path)
          needs_link ||= File.mtime(runner_file) > File.mtime(shared_lib_path) if File.exist?(shared_lib_path)

          link_shared_library(wrapper_file, obj_file, shared_lib_path) if needs_link
        end

        def export_firrtl(path)
          ir = RHDL::HDL::CPU::CPU.to_flat_ir(top_name: 'cpu8bit')
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate(ir)
          File.write(path, firrtl)
        end

        def compile_with_arcilator(fir_file, mlir_file, ll_file, state_file, obj_file)
          log_file = File.join(BUILD_DIR, 'cpu8bit_arcilator_gpu.log')
          File.delete(log_file) if File.exist?(log_file)

          run_or_raise(%W[firtool #{fir_file} --ir-hw -o #{mlir_file}], 'firtool HW lowering', log_file)

          arcilator_cmd = ['arcilator', mlir_file] + @gpu_option_tokens + ["--state-file=#{state_file}", '-o', ll_file]
          run_or_raise(arcilator_cmd, 'arcilator ArcToGPU lowering', log_file)

          if command_available?('clang')
            compile_object_with_clang(ll_file: ll_file, obj_file: obj_file, log_file: log_file)
            return
          end

          compile_object_with_llc(ll_file: ll_file, obj_file: obj_file, log_file: log_file)
        end

        def run_or_raise(cmd, step_name, log_file)
          out, status = Open3.capture2e(*cmd)
          File.write(log_file, out, mode: 'a')
          return if status.success?

          raise LoadError, "#{step_name} failed: #{last_log_lines(log_file)}"
        end

        def compile_object_with_clang(ll_file:, obj_file:, log_file:)
          cmd = ['clang', '-c', '-O2', '-fPIC']
          if (target = llc_target_triple)
            cmd += ['-target', target]
          end
          cmd += [ll_file, '-o', obj_file]
          run_or_raise(cmd, 'clang compile', log_file)
        end

        def compile_object_with_llc(ll_file:, obj_file:, log_file:)
          cmd = ['llc', '-filetype=obj', '-O2', '-relocation-model=pic']
          if (triple = llc_target_triple)
            cmd << "-mtriple=#{triple}"
          end
          cmd += [ll_file, '-o', obj_file]
          run_or_raise(cmd, 'llc compile', log_file)
        end

        def llc_target_triple(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          return nil unless host_os.to_s.downcase.include?('darwin')

          cpu = host_cpu.to_s.downcase
          arch = if cpu.include?('arm64') || cpu.include?('aarch64')
            'arm64'
          elsif cpu.include?('x86_64') || cpu.include?('amd64')
            'x86_64'
          end
          return nil unless arch

          "#{arch}-apple-macosx"
        end

        def link_shared_library(wrapper_file, obj_file, output_file)
          cxx = if command_available?('clang++')
            'clang++'
          elsif command_available?('g++')
            'g++'
          else
            'c++'
          end

          cmd = [cxx, '-shared', '-fPIC', '-O2', '-o', output_file, wrapper_file, obj_file]
          run_or_raise(cmd, 'C++ link', File.join(BUILD_DIR, 'cpu8bit_arcilator_gpu.log'))
        end

        def write_wrapper(path, state_path)
          state = JSON.parse(File.read(state_path))
          mod = state[0]
          states = mod.fetch('states', [])

          offsets = {}
          widths = {}
          states.each do |entry|
            name = entry.fetch('name')
            offsets[name] = entry.fetch('offset')
            widths[name] = entry.fetch('numBits', 32).to_i
          end

          missing = REQUIRED_SIGNAL_NAMES.reject { |name| offsets.key?(name) }
          raise LoadError, "Missing required CPU8bit signals in arcilator state: #{missing.join(', ')}" unless missing.empty?

          defines = []
          defines << "#define MAX_INSTANCE_COUNT #{MAX_INSTANCE_COUNT}"
          defines << "#define STATE_SIZE #{mod.fetch('numStateBytes')}"
          defines << '#define MEMORY_SIZE 65536'
          offsets.each do |name, offset|
            defines << "#define #{offset_define(name)} #{offset}"
          end

          poke_cases = []
          %w[clk rst mem_data_in pc_reg__q].each do |name|
            next unless offsets.key?(name)

            poke_cases << "if (!strcmp(name, \"#{name}\")) { #{setter_expr(offset_define(name), widths[name], 'value')}; return; }"
          end

          peek_cases = []
          %w[mem_addr mem_data_out mem_write_en halted pc_out acc_out sp_out state_out zero_flag_out].each do |name|
            peek_cases << "if (!strcmp(name, \"#{name}\")) return #{getter_expr(offset_define(name), widths[name])};"
          end

          wrapper = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>
            #include <cstddef>

            extern "C" void #{mod.fetch('name')}_eval(void* state);

            #{defines.join("\n")}

            struct SimContext {
              unsigned int instance_count;
              uint8_t* states;
              uint8_t* memories;
            };

            static inline void set_u8(uint8_t* s, int o, uint8_t v) { s[o] = v; }
            static inline uint8_t get_u8(uint8_t* s, int o) { return s[o]; }
            static inline void set_u16(uint8_t* s, int o, uint16_t v) { memcpy(&s[o], &v, 2); }
            static inline uint16_t get_u16(uint8_t* s, int o) { uint16_t v; memcpy(&v, &s[o], 2); return v; }
            static inline void set_u32(uint8_t* s, int o, uint32_t v) { memcpy(&s[o], &v, 4); }
            static inline uint32_t get_u32(uint8_t* s, int o) { uint32_t v; memcpy(&v, &s[o], 4); return v; }
            static inline void set_bit(uint8_t* s, int o, uint8_t v) { s[o] = v & 1; }
            static inline uint8_t get_bit(uint8_t* s, int o) { return s[o] & 1; }
            static inline unsigned int clamp_instance_count(unsigned int requested) {
              if (requested == 0) return 1;
              if (requested > MAX_INSTANCE_COUNT) return MAX_INSTANCE_COUNT;
              return requested;
            }
            static inline uint8_t* state_for(SimContext* ctx, unsigned int instance_index) {
              return ctx->states + (static_cast<size_t>(instance_index) * STATE_SIZE);
            }
            static inline uint8_t* memory_for(SimContext* ctx, unsigned int instance_index) {
              return ctx->memories + (static_cast<size_t>(instance_index) * MEMORY_SIZE);
            }

            extern "C" {
            void* sim_create(unsigned int requested_instances) {
              SimContext* ctx = new SimContext();
              ctx->instance_count = clamp_instance_count(requested_instances);
              ctx->states = new uint8_t[static_cast<size_t>(ctx->instance_count) * STATE_SIZE];
              ctx->memories = new uint8_t[static_cast<size_t>(ctx->instance_count) * MEMORY_SIZE];
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                uint8_t* state = state_for(ctx, inst_i);
                uint8_t* memory = memory_for(ctx, inst_i);
                memset(state, 0, STATE_SIZE);
                memset(memory, 0, MEMORY_SIZE);
                set_bit(state, OFF_CLK, 0);
                set_bit(state, OFF_RST, 1);
                #{mod.fetch('name')}_eval(state);
              }
              return ctx;
            }

            void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return;
              delete[] ctx->states;
              delete[] ctx->memories;
              delete ctx;
            }

            void sim_eval(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                #{mod.fetch('name')}_eval(state_for(ctx, inst_i));
              }
            }

            static inline unsigned int run_cycles_internal(uint8_t* state, uint8_t* memory, unsigned int n) {
              for (unsigned int i = 0; i < n; ++i) {
                if (get_bit(state, OFF_HALTED)) {
                  return i;
                }

                set_bit(state, OFF_CLK, 0);
                #{mod.fetch('name')}_eval(state);

                uint16_t addr = get_u16(state, OFF_MEM_ADDR) & 0xFFFF;
                if (get_bit(state, OFF_MEM_WRITE_EN)) {
                  memory[addr] = get_u8(state, OFF_MEM_DATA_OUT);
                }
                set_u8(state, OFF_MEM_DATA_IN, memory[addr]);

                set_bit(state, OFF_CLK, 1);
                #{mod.fetch('name')}_eval(state);
                if (get_bit(state, OFF_HALTED)) {
                  return i + 1;
                }
              }
              return n;
            }

            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                uint8_t* state = state_for(ctx, inst_i);
                set_bit(state, OFF_RST, 1);
                run_cycles_internal(state, memory_for(ctx, inst_i), 1);
                set_bit(state, OFF_RST, 0);
                #{mod.fetch('name')}_eval(state);
              }
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                uint8_t* state = state_for(ctx, inst_i);
                #{poke_cases.join("\n    else ")}
              }
            }

            unsigned int sim_peek(void* sim, const char* name) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              uint8_t* state = state_for(ctx, 0);
              #{peek_cases.join("\n  ")}
              return 0;
            }

            unsigned int sim_runner_load_memory(void* sim, const unsigned char* data, unsigned int len, unsigned int offset) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                uint8_t* memory = memory_for(ctx, inst_i);
                for (unsigned int i = 0; i < len; ++i) {
                  unsigned int addr = (offset + i) & 0xFFFF;
                  memory[addr] = data[i];
                }
              }
              return len;
            }

            unsigned int sim_runner_read_memory(void* sim, unsigned int offset, unsigned int len, unsigned char* out) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              uint8_t* memory = memory_for(ctx, 0);
              for (unsigned int i = 0; i < len; ++i) {
                unsigned int addr = (offset + i) & 0xFFFF;
                out[i] = memory[addr];
              }
              return len;
            }

            unsigned int sim_runner_write_memory(void* sim, unsigned int offset, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                uint8_t* memory = memory_for(ctx, inst_i);
                for (unsigned int i = 0; i < len; ++i) {
                  unsigned int addr = (offset + i) & 0xFFFF;
                  memory[addr] = data[i];
                }
              }
              return len;
            }

            unsigned int sim_runner_run_cycles(void* sim, unsigned int n) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              unsigned int completed = n;
              for (unsigned int inst_i = 0; inst_i < ctx->instance_count; ++inst_i) {
                unsigned int inst_completed = run_cycles_internal(state_for(ctx, inst_i), memory_for(ctx, inst_i), n);
                if (inst_i == 0 || inst_completed < completed) {
                  completed = inst_completed;
                }
              }
              return completed;
            }
            }
          CPP

          File.write(path, wrapper)
        end

        def offset_define(name)
          "OFF_#{name.to_s.upcase.gsub(/[^A-Z0-9]/, '_')}"
        end

        def setter_expr(offset_macro, width_bits, source_value)
          if width_bits <= 1
            "set_bit(state, #{offset_macro}, #{source_value})"
          elsif width_bits <= 8
            "set_u8(state, #{offset_macro}, static_cast<uint8_t>(#{source_value}))"
          elsif width_bits <= 16
            "set_u16(state, #{offset_macro}, static_cast<uint16_t>(#{source_value}))"
          else
            "set_u32(state, #{offset_macro}, static_cast<uint32_t>(#{source_value}))"
          end
        end

        def getter_expr(offset_macro, width_bits)
          if width_bits <= 1
            "get_bit(state, #{offset_macro})"
          elsif width_bits <= 8
            "get_u8(state, #{offset_macro})"
          elsif width_bits <= 16
            "get_u16(state, #{offset_macro})"
          else
            "get_u32(state, #{offset_macro})"
          end
        end

        def load_library
          @lib = Fiddle.dlopen(shared_lib_path)
          @fn_sim_create = Fiddle::Function.new(@lib['sim_create'], [Fiddle::TYPE_UINT], Fiddle::TYPE_VOIDP)
          @fn_sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @fn_sim_eval = Fiddle::Function.new(@lib['sim_eval'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @fn_sim_reset = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @fn_sim_poke = Fiddle::Function.new(@lib['sim_poke'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT], Fiddle::TYPE_VOID)
          @fn_sim_peek = Fiddle::Function.new(@lib['sim_peek'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT)
          @fn_runner_load_memory = Fiddle::Function.new(
            @lib['sim_runner_load_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
            Fiddle::TYPE_UINT
          )
          @fn_runner_read_memory = Fiddle::Function.new(
            @lib['sim_runner_read_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )
          @fn_runner_write_memory = Fiddle::Function.new(
            @lib['sim_runner_write_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_UINT
          )
          @fn_runner_run_cycles = Fiddle::Function.new(
            @lib['sim_runner_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_UINT
          )

          @ctx = @fn_sim_create.call(@instance_count)
          raise LoadError, 'CPU8bit ArcilatorGPU simulation context initialization failed' if !@ctx || @ctx.to_i.zero?

          ObjectSpace.define_finalizer(self, self.class.finalizer(@fn_sim_destroy, @ctx))
        end

        def self.finalizer(destroy_fn, ctx)
          proc { destroy_fn.call(ctx) if ctx && !ctx.to_i.zero? }
        end

        def shared_lib_path
          ext = if RbConfig::CONFIG['host_os'] =~ /darwin/
            '.dylib'
          elsif RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
            '.dll'
          else
            '.so'
          end
          File.join(BUILD_DIR, "libcpu8bit_arcgpu_sim#{ext}")
        end

        def normalize_payload(data)
          case data
          when String
            data.b
          when Array
            data.pack('C*')
          else
            Array(data).pack('C*')
          end
        end

        def write_file_if_changed(path, content)
          if File.exist?(path) && File.read(path) == content
            return false
          end

          File.write(path, content)
          true
        end

        def last_log_lines(path, count: 8)
          return 'unknown error' unless File.exist?(path)

          File.read(path).lines.last(count).join.strip
        rescue StandardError
          'unknown error'
        end
      end
    end
  end
end
