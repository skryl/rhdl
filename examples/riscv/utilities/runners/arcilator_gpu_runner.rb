# frozen_string_literal: true

# RV32I Arcilator GPU Runner - Native RTL simulation via ArcToGPU + Metal

require_relative 'arcilator_runner'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'rhdl/codegen/firrtl/firrtl'
require 'rhdl/codegen/firrtl/arc_to_gpu_lowering'

module RHDL
  module Examples
    module RISCV
      class ArcilatorGpuRunner < ArcilatorRunner
        BUILD_BASE = File.expand_path('../../.hdl_build', __dir__)
        REQUIRED_TOOLS = %w[firtool circt-opt arcilator].freeze
        MAX_INSTANCE_COUNT = 1024
        DEFAULT_ARC_TO_GPU_PROFILE = :riscv
        DEFAULT_BUILD_VARIANT = 'arcilator_gpu'
        DEFAULT_SHARED_LIB_NAME = 'libriscv_arcilator_gpu_sim.so'
        DEFAULT_BACKEND_SYMBOL = :arcilator_gpu
        DEFAULT_SIMULATOR_TYPE = :hdl_arcilator_gpu
        ARC_TO_GPU_BUILD_ENV_VARS = %w[
          RHDL_ARC_TO_GPU_RISCV_CORE_SPECIALIZE
        ].freeze

        class << self
          def status
            missing_tools = []
            REQUIRED_TOOLS.each { |tool| missing_tools << tool unless command_available?(tool) }

            unless command_available?('clang++') || command_available?('c++')
              missing_tools << 'clang++/c++'
            end

            if macos_host?
              missing_tools << 'xcrun' unless command_available?('xcrun')
              missing_tools << 'metal' unless command_success?(%w[xcrun -f metal])
              missing_tools << 'metallib' unless command_success?(%w[xcrun -f metallib])
            else
              missing_tools << 'macOS Metal toolchain'
            end

            {
              ready: missing_tools.empty?,
              missing_tools: missing_tools.uniq
            }
          end

          def available?
            status[:ready]
          end

          def ensure_available!
            info = status
            return info if info[:ready]

            raise LoadError,
              "arcilator_gpu backend unavailable (missing tools: #{info[:missing_tools].join(', ')}). " \
              'Install CIRCT tools and the macOS Metal toolchain.'
          end

          private

          def command_available?(tool)
            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
              File.executable?(File.join(path, tool))
            end
          end

          def command_success?(cmd)
            _out, status = Open3.capture2e(*cmd)
            status.success?
          rescue StandardError
            false
          end

          def macos_host?
            RUBY_PLATFORM.include?('darwin')
          end
        end

        attr_reader :instance_count

        def initialize(
          mem_size: Memory::DEFAULT_SIZE,
          instances: nil,
          core_specialize: nil,
          arc_to_gpu_profile: DEFAULT_ARC_TO_GPU_PROFILE,
          build_variant: DEFAULT_BUILD_VARIANT,
          shared_lib_name: DEFAULT_SHARED_LIB_NAME,
          backend_symbol: DEFAULT_BACKEND_SYMBOL,
          simulator_type_symbol: DEFAULT_SIMULATOR_TYPE
        )
          normalized_mem_size = normalize_mem_size(mem_size)
          @instance_count = normalize_instance_count(instances)
          @core_specialize = normalize_core_specialize(core_specialize)
          @arc_to_gpu_profile = arc_to_gpu_profile.to_sym
          @build_variant = build_variant.to_s
          @shared_lib_name = shared_lib_name.to_s
          @backend_symbol = backend_symbol.to_sym
          @simulator_type_symbol = simulator_type_symbol.to_sym
          env_overrides = {
            'RHDL_RISCV_ARCILATOR_GPU_INSTANCES_RUNTIME' => @instance_count.to_s,
            'RHDL_ARC_TO_GPU_RISCV_CORE_SPECIALIZE' => (@core_specialize ? '1' : '0'),
            'RHDL_RISCV_ARCILATOR_GPU_CORE_SPECIALIZE_RUNTIME' => (@core_specialize ? '1' : '0')
          }
          previous_env = env_overrides.to_h { |key, _value| [key, ENV[key]] }
          env_overrides.each { |key, value| ENV[key] = value }
          initialize_backend_runner(
            backend_sym: @backend_symbol,
            simulator_type_sym: @simulator_type_symbol,
            mem_size: normalized_mem_size
          )
        ensure
          if previous_env
            previous_env.each do |key, value|
              if value.nil?
                ENV.delete(key)
              else
                ENV[key] = value
              end
            end
          end
        end

        def read_pc
          if @sim_read_pc_fn
            @sim_read_pc_fn.call(@sim_ctx).to_i & 0xFFFF_FFFF
          else
            eval_cpu
            super
          end
        rescue StandardError
          eval_cpu
          super
        end

        def read_reg(index)
          idx = index.to_i & 0x1F
          return 0 if idx.zero?

          if @sim_read_reg_fn
            @sim_read_reg_fn.call(@sim_ctx, idx).to_i & 0xFFFF_FFFF
          else
            super
          end
        rescue StandardError
          super
        end

        def current_inst
          if @sim_read_inst_fn
            @sim_read_inst_fn.call(@sim_ctx).to_i & 0xFFFF_FFFF
          else
            eval_cpu
            super
          end
        rescue StandardError
          eval_cpu
          super
        end

        def dispatch_count
          return nil unless @sim_dispatch_count_fn

          @sim_dispatch_count_fn.call(@sim_ctx).to_i
        rescue StandardError
          nil
        end

        def wait_count
          return nil unless @sim_wait_count_fn

          @sim_wait_count_fn.call(@sim_ctx).to_i
        rescue StandardError
          nil
        end

        def fast_dispatch_count
          return nil unless @sim_fast_dispatch_count_fn

          @sim_fast_dispatch_count_fn.call(@sim_ctx).to_i
        rescue StandardError
          nil
        end

        def fallback_dispatch_count
          return nil unless @sim_fallback_dispatch_count_fn

          @sim_fallback_dispatch_count_fn.call(@sim_ctx).to_i
        rescue StandardError
          nil
        end

        private

        def load_shared_library
          super
          load_optional_metrics_symbols
          validate_sim_context!
        end

        def load_optional_metrics_symbols
          @sim_read_pc_fn = Fiddle::Function.new(
            @lib['sim_read_pc'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_read_reg_fn = Fiddle::Function.new(
            @lib['sim_read_reg'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )
          @sim_read_inst_fn = Fiddle::Function.new(
            @lib['sim_read_inst'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_dispatch_count_fn = Fiddle::Function.new(
            @lib['sim_dispatch_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_wait_count_fn = Fiddle::Function.new(
            @lib['sim_wait_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_fast_dispatch_count_fn = Fiddle::Function.new(
            @lib['sim_fast_dispatch_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @sim_fallback_dispatch_count_fn = Fiddle::Function.new(
            @lib['sim_fallback_dispatch_count'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
        rescue Fiddle::DLError, NameError
          @sim_read_pc_fn = nil
          @sim_read_reg_fn = nil
          @sim_read_inst_fn = nil
          @sim_dispatch_count_fn = nil
          @sim_wait_count_fn = nil
          @sim_fast_dispatch_count_fn = nil
          @sim_fallback_dispatch_count_fn = nil
        end

        def normalize_mem_size(mem_size)
          size = mem_size.to_i
          size = Memory::DEFAULT_SIZE if size <= 0
          return size if power_of_two?(size)

          next_pow2 = 1
          next_pow2 <<= 1 while next_pow2 < size
          warn "ArcilatorGpuRunner mem_size #{size} is not power-of-two; rounding up to #{next_pow2}."
          next_pow2
        end

        def power_of_two?(value)
          value > 0 && (value & (value - 1)).zero?
        end

        def normalize_instance_count(instances)
          raw = instances || ENV['RHDL_RISCV_ARCILATOR_GPU_INSTANCES'] || ENV['RHDL_BENCH_ARCILATOR_GPU_INSTANCES']
          value = raw.to_i
          value = 1 if value <= 0
          [value, MAX_INSTANCE_COUNT].min
        end

        def normalize_core_specialize(core_specialize)
          return core_specialize unless core_specialize.nil?

          raw = ENV['RHDL_RISCV_ARCILATOR_GPU_CORE_SPECIALIZE']
          return false if raw.nil?

          !%w[0 false no off].include?(raw.to_s.strip.downcase)
        end

        def check_tools_available!
          self.class.ensure_available!
        end

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, @build_variant)
        end

        def shared_lib_path
          File.join(build_dir, @shared_lib_name)
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)

          fir_file = File.join(build_dir, 'riscv_cpu.fir')
          parsed_mlir_file = File.join(build_dir, 'riscv_cpu_parsed.mlir')
          lowered_mlir_file = File.join(build_dir, 'riscv_cpu_lowered.mlir')
          hw_mlir_file = File.join(build_dir, 'riscv_cpu_hw.mlir')
          arc_mlir_file = File.join(build_dir, 'riscv_cpu_arc.mlir')
          gpu_mlir_file = File.join(build_dir, 'riscv_cpu_arc_to_gpu.mlir')
          gpu_meta_file = File.join(build_dir, 'riscv_cpu_arc_to_gpu.json')
          metal_source_file = File.join(build_dir, 'riscv_cpu_arc_to_gpu.metal')
          metal_air_file = File.join(build_dir, 'riscv_cpu_arc_to_gpu.air')
          metal_lib_file = File.join(build_dir, 'riscv_cpu_arc_to_gpu.metallib')
          wrapper_file = File.join(build_dir, 'riscv_arcgpu_wrapper.mm')
          build_config_file = File.join(build_dir, 'riscv_metal_build_config.json')
          log_file = File.join(build_dir, 'riscv_metal.log')
          lib_file = shared_lib_path
          expected_build_config = build_config_signature

          needs_rebuild = !File.exist?(lib_file)
          outputs = [gpu_meta_file, metal_source_file, metal_lib_file, wrapper_file, lib_file, build_config_file]
          needs_rebuild ||= outputs.any? { |path| !File.exist?(path) }

          unless needs_rebuild
            deps = [
              __FILE__,
              File.expand_path('../../hdl/cpu.rb', __dir__),
              File.expand_path('../../../../lib/rhdl/codegen/firrtl/firrtl.rb', __dir__),
              File.expand_path('../../../../lib/rhdl/codegen/firrtl/arc_to_gpu_lowering.rb', __dir__),
              File.expand_path(
                "../../../../lib/rhdl/codegen/firrtl/arc_to_gpu_lowering/profiles/#{@arc_to_gpu_profile}.rb",
                __dir__
              )
            ].select { |path| File.exist?(path) }

            newest_dep = deps.map { |path| File.mtime(path) }.max
            oldest_output = outputs.map { |path| File.mtime(path) }.min
            needs_rebuild = newest_dep && oldest_output && newest_dep > oldest_output
            needs_rebuild ||= read_build_config(build_config_file) != expected_build_config
          end

          if needs_rebuild
            File.delete(log_file) if File.exist?(log_file)
            export_firrtl(fir_file)
            run_or_raise(%W[firtool #{fir_file} --parse-only -o #{parsed_mlir_file}], 'firtool parse', log_file)
            run_or_raise(
              ['circt-opt', parsed_mlir_file, "--pass-pipeline=#{firrtl_pipeline_without_comb_check}", '-o', lowered_mlir_file],
              'circt-opt FIRRTL pipeline',
              log_file
            )
            run_or_raise(
              ['firtool', '--format=mlir', lowered_mlir_file, '--ir-hw', '-o', hw_mlir_file],
              'firtool HW lowering',
              log_file
            )
            emit_gpu_input_mlir(
              hw_mlir_file: hw_mlir_file,
              arc_mlir_file: arc_mlir_file,
              log_file: log_file
            )

            RHDL::Codegen::FIRRTL::ArcToGpuLowering.lower(
              arc_mlir_path: arc_mlir_file,
              gpu_mlir_path: gpu_mlir_file,
              metadata_path: gpu_meta_file,
              metal_source_path: metal_source_file,
              profile: @arc_to_gpu_profile
            )

            compile_metal_shader(
              metal_source_file: metal_source_file,
              metal_air_file: metal_air_file,
              metal_lib_file: metal_lib_file,
              log_file: log_file
            )

            write_wrapper(
              path: wrapper_file,
              metadata_path: gpu_meta_file,
              metallib_path: metal_lib_file
            )
            link_shared_library(wrapper_file, lib_file, log_file: log_file)
            File.write(build_config_file, JSON.pretty_generate(expected_build_config))
          end

          @lib_path = lib_file
        end

        def export_firrtl(path)
          flat_ir = CPU.to_flat_ir(top_name: 'riscv_cpu')
          firrtl = RHDL::Codegen::FIRRTL.generate(flat_ir)
          File.write(path, firrtl)
        end

        def build_config_signature
          {
            'format' => 4,
            'arc_to_gpu_profile' => @arc_to_gpu_profile.to_s,
            'build_dir' => build_dir,
            'shared_lib_path' => shared_lib_path,
            'arc_to_gpu_env' => ARC_TO_GPU_BUILD_ENV_VARS.to_h { |name| [name, ENV[name].to_s] }
          }
        end

        def read_build_config(path)
          return nil unless File.exist?(path)

          JSON.parse(File.read(path))
        rescue JSON::ParserError
          nil
        end

        def compile_metal_shader(metal_source_file:, metal_air_file:, metal_lib_file:, log_file:)
          module_cache_dir = File.join(build_dir, 'clang_module_cache')
          FileUtils.rm_rf(module_cache_dir)
          FileUtils.mkdir_p(module_cache_dir)
          run_or_raise(
            [
              'xcrun', '-sdk', 'macosx', 'metal', '-c', '-O3',
              "-fmodules-cache-path=#{module_cache_dir}",
              metal_source_file, '-o', metal_air_file
            ],
            'metal shader compile',
            log_file
          )
          run_or_raise(
            ['xcrun', '-sdk', 'macosx', 'metallib', metal_air_file, '-o', metal_lib_file],
            'metallib link',
            log_file
          )
        end

        def link_shared_library(wrapper_file, output_file, log_file:)
          cxx = command_available?('clang++') ? 'clang++' : 'c++'
          cmd = [
            cxx,
            '-std=c++17',
            '-x',
            'objective-c++',
            '-fobjc-arc',
            '-dynamiclib',
            '-O2',
            '-o',
            output_file,
            wrapper_file,
            '-framework',
            'Foundation',
            '-framework',
            'Metal'
          ]
          run_or_raise(cmd, 'Objective-C++ link', log_file)
        end

        def run_or_raise(cmd, step_name, log_file)
          out, status = Open3.capture2e(*cmd)
          File.write(log_file, out, mode: 'a')
          return if status.success?

          raise LoadError, "#{step_name} failed for RISC-V Metal runner: #{last_log_lines(log_file)}"
        end

        def emit_gpu_input_mlir(
          hw_mlir_file:,
          arc_mlir_file:,
          log_file:
        )
          run_or_raise(
            ['arcilator', hw_mlir_file, '--emit-mlir', '--until-after=arc-opt', '-o', arc_mlir_file],
            'arcilator Arc emission',
            log_file
          )
        end

        def last_log_lines(log_file, count = 20)
          return 'no log output' unless File.exist?(log_file)

          File.readlines(log_file).last(count).join.strip
        end

        def validate_sim_context!
          return unless !@sim_ctx || (@sim_ctx.respond_to?(:to_i) && @sim_ctx.to_i.zero?)

          raise LoadError,
            'ArcilatorGPU simulation context initialization failed (sim_create returned null). ' \
            'Check the generated Metal library path and GPU toolchain compatibility.'
        end

        def cpp_ident(name)
          name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
        end

        def write_wrapper(path:, metadata_path:, metallib_path:)
          metadata = JSON.parse(File.read(metadata_path))
          state_count = metadata.dig('metal', 'state_count').to_i
          state_scalar_bits = metadata.dig('metal', 'state_scalar_bits').to_i
          state_scalar_bits = 32 if state_scalar_bits <= 0
          state_scalar_bytes = state_scalar_bits > 32 ? 8 : 4
          state_scalar_cpp_type = state_scalar_bits > 32 ? 'uint64_t' : 'uint32_t'
          kernel_name = metadata.dig('metal', 'entry').to_s
          input_layout = metadata.dig('metal', 'runtime_input_layout')
          input_layout = metadata['top_input_layout'] if input_layout.nil?
          input_layout = Array(input_layout)
          output_layout = metadata.dig('metal', 'runtime_output_layout')
          output_layout = metadata['top_output_layout'] if output_layout.nil?
          output_layout = Array(output_layout)
          state_layout = Array(metadata['state_layout'])
          introspection = metadata.dig('metal', 'introspection') || {}

          raise LoadError, 'ArcToGPU metadata missing metal entry' if kernel_name.empty?
          raise LoadError, 'ArcToGPU metadata missing state_count' if state_count <= 0

          pc_slot = introspection['pc_slot']
          pc_width = introspection['pc_width']
          if pc_slot.nil?
            pc_slot_entry = state_layout.find { |entry| entry.fetch('result_ref', '').include?('pc_reg__pc') }
            pc_slot_entry ||= state_layout.find { |entry| entry.fetch('result_ref', '').include?('pc_reg__q') }
            pc_slot = pc_slot_entry ? pc_slot_entry.fetch('index').to_i : -1
            pc_width = pc_slot_entry ? pc_slot_entry.fetch('width').to_i : 32
          end
          pc_slot = pc_slot.to_i
          pc_width = pc_width.to_i

          regfile_base_slot = introspection['regfile_base_slot']
          regfile_length = introspection['regfile_length']
          if regfile_base_slot.nil? || regfile_length.nil?
            regfile_entry = state_layout.find do |entry|
              entry.fetch('kind', '') == 'arc_memory' &&
                entry.fetch('length', 0).to_i == 32 &&
                entry.fetch('index_width', 0).to_i == 5 &&
                entry.fetch('width', 0).to_i == 32 &&
                entry.fetch('slots_per_element', 1).to_i == 1
            end
            regfile_base_slot = regfile_entry ? regfile_entry.fetch('index').to_i : -1
            regfile_length = regfile_entry ? regfile_entry.fetch('length').to_i : 0
          end
          regfile_base_slot = regfile_base_slot.to_i
          regfile_length = regfile_length.to_i

          struct_input_fields = input_layout.map { |entry| "  uint32_t #{cpp_ident(entry.fetch('name'))};" }
          struct_output_fields = output_layout.map { |entry| "  uint32_t #{cpp_ident(entry.fetch('name'))};" }

          poke_cases = input_layout.map do |entry|
            name = entry.fetch('name')
            field = cpp_ident(name)
            width = entry.fetch('width').to_i
            <<~CPP
              if (!strcmp(name, "#{name}")) {
                uint32_t masked = mask_width(value, #{width}u);
                for (uint32_t inst = 0u; inst < ctx->sim.instanceCount; ++inst) {
                  RhdlArcGpuIo* io_inst = [ctx->sim ioAtIndex:inst];
                  if (io_inst) {
                    io_inst->#{field} = masked;
                  }
                }
                return;
              }
            CPP
          end

          peek_cases = (input_layout + output_layout).map do |entry|
            name = entry.fetch('name')
            field = cpp_ident(name)
            width = entry.fetch('width').to_i
            <<~CPP
              if (!strcmp(name, "#{name}")) {
                return io->#{field} & mask_width(0xFFFFFFFFu, #{width}u);
              }
            CPP
          end

          input_field_set = input_layout.each_with_object({}) { |entry, acc| acc[cpp_ident(entry.fetch('name'))] = true }

          init_defaults = []
          init_defaults << 'io->cycle_budget = 0u;'
          init_defaults << 'io->cycles_ran = 0u;'
          init_defaults << 'io->mem_mask = memMask;'
          init_defaults << 'io->clk = 0u;' if input_field_set[cpp_ident('clk')]
          init_defaults << 'io->rst = 1u;' if input_field_set[cpp_ident('rst')]
          init_defaults << 'io->irq_software = 0u;' if input_field_set[cpp_ident('irq_software')]
          init_defaults << 'io->irq_timer = 0u;' if input_field_set[cpp_ident('irq_timer')]
          init_defaults << 'io->irq_external = 0u;' if input_field_set[cpp_ident('irq_external')]
          init_defaults << 'io->inst_data = 0u;' if input_field_set[cpp_ident('inst_data')]
          init_defaults << 'io->data_rdata = 0u;' if input_field_set[cpp_ident('data_rdata')]
          init_defaults << 'io->inst_ptw_pte0 = 0u;' if input_field_set[cpp_ident('inst_ptw_pte0')]
          init_defaults << 'io->inst_ptw_pte1 = 0u;' if input_field_set[cpp_ident('inst_ptw_pte1')]
          init_defaults << 'io->data_ptw_pte0 = 0u;' if input_field_set[cpp_ident('data_ptw_pte0')]
          init_defaults << 'io->data_ptw_pte1 = 0u;' if input_field_set[cpp_ident('data_ptw_pte1')]
          init_defaults << 'io->debug_reg_addr = 0u;' if input_field_set[cpp_ident('debug_reg_addr')]

          reset_assert_line = input_field_set[cpp_ident('rst')] ? 'io->rst = 1u;' : ''
          reset_deassert_line = input_field_set[cpp_ident('rst')] ? 'io->rst = 0u;' : ''
          reset_clk_low_line = input_field_set[cpp_ident('clk')] ? 'io->clk = 0u;' : ''
          reset_clk_high_line = input_field_set[cpp_ident('clk')] ? 'io->clk = 1u;' : ''
          objc_sim_class = "RhdlRiscvMetalSim_#{cpp_ident(@build_variant)}"

          wrapper = <<~CPP
            #import <Foundation/Foundation.h>
            #import <Metal/Metal.h>
            #include <CoreFoundation/CoreFoundation.h>
            #include <dlfcn.h>
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>
            #include <cstdio>

            static const uint32_t STATE_COUNT = #{state_count}u;
            static const uint32_t STATE_SCALAR_BITS = #{state_scalar_bits}u;
            static const uint32_t STATE_SCALAR_BYTES = #{state_scalar_bytes}u;
            static const uint32_t MAX_INSTANCE_COUNT = #{MAX_INSTANCE_COUNT}u;
            static const int32_t PC_SLOT_INDEX = #{pc_slot};
            static const uint32_t PC_SLOT_WIDTH = #{pc_width}u;
            static const int32_t REGFILE_BASE_SLOT = #{regfile_base_slot};
            static const uint32_t REGFILE_LENGTH = #{regfile_length}u;
            static NSString* const kMetallibFilename = @#{File.basename(metallib_path).dump};
            static NSString* const kMetallibFallbackPath = @#{metallib_path.dump};
            static NSString* const kKernelName = @#{kernel_name.dump};
            using RhdlStateScalar = #{state_scalar_cpp_type};

            struct RhdlArcGpuIo {
              uint32_t cycle_budget;
              uint32_t cycles_ran;
              uint32_t mem_mask;
              uint32_t _reserved;
            #{struct_input_fields.join("\n")}
            #{struct_output_fields.join("\n")}
            };

            static inline uint32_t mask_width(uint32_t value, uint32_t width) {
              if (width >= 32u) {
                return value;
              }
              if (width == 0u) {
                return 0u;
              }
              return value & ((1u << width) - 1u);
            }

            static inline uint32_t resolve_instance_count() {
              const char* raw = getenv("RHDL_RISCV_ARCILATOR_GPU_INSTANCES_RUNTIME");
              if (!raw || *raw == '\\0') {
                return 1u;
              }
              char* end = nullptr;
              unsigned long parsed = strtoul(raw, &end, 10);
              if (end == raw || parsed == 0ul) {
                return 1u;
              }
              if (parsed > (unsigned long)MAX_INSTANCE_COUNT) {
                return MAX_INSTANCE_COUNT;
              }
              return (uint32_t)parsed;
            }

            static inline uint32_t read_word_le(const uint8_t* mem, uint32_t mask, uint32_t addr) {
              uint32_t a = addr & mask;
              return (uint32_t)mem[a] |
                ((uint32_t)mem[(a + 1u) & mask] << 8u) |
                ((uint32_t)mem[(a + 2u) & mask] << 16u) |
                ((uint32_t)mem[(a + 3u) & mask] << 24u);
            }

            static NSString* resolveMetallibPath() {
              Dl_info info;
              if (dladdr((const void*)&resolveMetallibPath, &info) != 0 && info.dli_fname) {
                NSString* dylibPath = [NSString stringWithUTF8String:info.dli_fname];
                NSString* candidate = [[dylibPath stringByDeletingLastPathComponent]
                  stringByAppendingPathComponent:kMetallibFilename];
                if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
                  return candidate;
                }
              }
              return kMetallibFallbackPath;
            }

            @interface #{objc_sim_class} : NSObject
            @property(nonatomic, strong) id<MTLDevice> device;
            @property(nonatomic, strong) id<MTLCommandQueue> queue;
            @property(nonatomic, strong) id<MTLLibrary> library;
            @property(nonatomic, strong) id<MTLComputePipelineState> pipeline;
            @property(nonatomic, strong) id<MTLBuffer> stateBuffer;
            @property(nonatomic, strong) id<MTLBuffer> instBuffer;
            @property(nonatomic, strong) id<MTLBuffer> dataBuffer;
            @property(nonatomic, strong) id<MTLBuffer> ioBuffer;
            @property(nonatomic, assign) uint32_t memSize;
            @property(nonatomic, assign) uint32_t memMask;
            @property(nonatomic, assign) uint32_t instanceCount;
            @property(nonatomic, assign) uint32_t threadgroupWidth;
            @property(nonatomic, assign) uint32_t dispatchCount;
            @property(nonatomic, assign) uint32_t waitCount;
            @property(nonatomic, assign) uint32_t fastDispatchCount;
            - (instancetype)initWithMetallibPath:(NSString*)metallibPath kernelName:(NSString*)kernelName stateCount:(uint32_t)stateCount stateScalarBytes:(uint32_t)stateScalarBytes memSize:(uint32_t)memSize instanceCount:(uint32_t)instanceCount;
            - (BOOL)dispatchKernelWithBudget:(uint32_t)budget;
            - (RhdlArcGpuIo*)io;
            - (RhdlStateScalar*)stateSlots;
            - (uint8_t*)instMem;
            - (uint8_t*)dataMem;
            - (RhdlArcGpuIo*)ioAtIndex:(uint32_t)index;
            - (RhdlStateScalar*)stateSlotsAtIndex:(uint32_t)index;
            - (uint8_t*)instMemAtIndex:(uint32_t)index;
            - (uint8_t*)dataMemAtIndex:(uint32_t)index;
            @end

            @implementation #{objc_sim_class}
            - (instancetype)initWithMetallibPath:(NSString*)metallibPath kernelName:(NSString*)kernelName stateCount:(uint32_t)stateCount stateScalarBytes:(uint32_t)stateScalarBytes memSize:(uint32_t)memSize instanceCount:(uint32_t)instanceCount {
              self = [super init];
              if (!self) {
                return nil;
              }

              self.memSize = memSize;
              self.memMask = (memSize > 0u) ? (memSize - 1u) : 0u;
              self.instanceCount = (instanceCount > 0u) ? instanceCount : 1u;
              self.threadgroupWidth = 1u;
              self.dispatchCount = 0u;
              self.waitCount = 0u;
              self.fastDispatchCount = 0u;

              self.device = MTLCreateSystemDefaultDevice();
              if (!self.device) {
                fprintf(stderr, "[riscv-arcilator-gpu] init failed: no MTL device\\n");
                return nil;
              }

              self.queue = [self.device newCommandQueue];
              if (!self.queue) {
                fprintf(stderr, "[riscv-arcilator-gpu] init failed: no command queue\\n");
                return nil;
              }

              NSError* error = nil;
              NSURL* libURL = [NSURL fileURLWithPath:metallibPath];
              self.library = [self.device newLibraryWithURL:libURL error:&error];
              if (!self.library) {
                fprintf(
                  stderr,
                  "[riscv-arcilator-gpu] failed to load metallib %s: %s\\n",
                  metallibPath.UTF8String,
                  error.localizedDescription.UTF8String
                );
                return nil;
              }

              id<MTLFunction> fn = [self.library newFunctionWithName:kernelName];
              if (!fn) {
                fprintf(stderr, "[riscv-arcilator-gpu] kernel not found: %s\\n", kernelName.UTF8String);
                return nil;
              }

              self.pipeline = [self.device newComputePipelineStateWithFunction:fn error:&error];
              if (!self.pipeline) {
                fprintf(stderr, "[riscv-arcilator-gpu] failed to build pipeline: %s\\n", error.localizedDescription.UTF8String);
                return nil;
              }

              uint32_t executionWidth = (uint32_t)self.pipeline.threadExecutionWidth;
              uint32_t maxThreads = (uint32_t)self.pipeline.maxTotalThreadsPerThreadgroup;
              uint32_t preferredTg = executionWidth > 0u ? executionWidth : 1u;
              if (maxThreads > 0u && preferredTg > maxThreads) {
                preferredTg = maxThreads;
              }
              if (preferredTg == 0u) {
                preferredTg = 1u;
              }
              if (preferredTg > self.instanceCount) {
                preferredTg = self.instanceCount;
              }
              self.threadgroupWidth = preferredTg;

              uint64_t stateBytes = (uint64_t)stateCount * (uint64_t)stateScalarBytes * (uint64_t)self.instanceCount;
              uint64_t memBytes = (uint64_t)memSize * (uint64_t)self.instanceCount;
              uint64_t ioBytes = (uint64_t)sizeof(RhdlArcGpuIo) * (uint64_t)self.instanceCount;
              self.stateBuffer = [self.device newBufferWithLength:stateBytes options:MTLResourceStorageModeShared];
              self.instBuffer = [self.device newBufferWithLength:memBytes options:MTLResourceStorageModeShared];
              // Unified memory model: instruction and data views alias the same buffer.
              self.dataBuffer = self.instBuffer;
              self.ioBuffer = [self.device newBufferWithLength:ioBytes options:MTLResourceStorageModeShared];

              if (!self.stateBuffer || !self.instBuffer || !self.ioBuffer) {
                fprintf(stderr, "[riscv-arcilator-gpu] failed to allocate GPU buffers\\n");
                return nil;
              }

              memset(self.stateBuffer.contents, 0, stateBytes);
              memset(self.instBuffer.contents, 0, memBytes);
              memset(self.ioBuffer.contents, 0, ioBytes);

              RhdlArcGpuIo* io = [self ioAtIndex:0u];
              if (io) {
                uint32_t memMask = self.memMask;
            #{init_defaults.join("\n")}
                for (uint32_t i = 1u; i < self.instanceCount; ++i) {
                  RhdlArcGpuIo* ioInst = [self ioAtIndex:i];
                  if (ioInst) {
                    *ioInst = *io;
                  }
                }
              }

              return self;
            }

            - (BOOL)dispatchKernelWithBudget:(uint32_t)budget {
              id<MTLCommandBuffer> commandBuffer = [self.queue commandBuffer];
              if (!commandBuffer) {
                return NO;
              }

              id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
              if (!encoder) {
                return NO;
              }

              RhdlArcGpuIo* io0 = [self ioAtIndex:0u];
              if (!io0) {
                [encoder endEncoding];
                return NO;
              }

              for (uint32_t i = 0u; i < self.instanceCount; ++i) {
                RhdlArcGpuIo* io = [self ioAtIndex:i];
                if (!io) {
                  continue;
                }
                io->cycle_budget = budget;
                io->cycles_ran = 0u;
              }

              [encoder setComputePipelineState:self.pipeline];
              [encoder setBuffer:self.stateBuffer offset:0 atIndex:0];
              [encoder setBuffer:self.instBuffer offset:0 atIndex:1];
              [encoder setBuffer:self.dataBuffer offset:0 atIndex:2];
              [encoder setBuffer:self.ioBuffer offset:0 atIndex:3];
              MTLSize grid = MTLSizeMake(self.instanceCount, 1, 1);
              uint32_t tgWidth = self.threadgroupWidth > 0u ? self.threadgroupWidth : 1u;
              if (tgWidth > self.instanceCount) {
                tgWidth = self.instanceCount;
              }
              MTLSize tg = MTLSizeMake(tgWidth, 1, 1);
              [encoder dispatchThreads:grid threadsPerThreadgroup:tg];
              [encoder endEncoding];

              self.dispatchCount = self.dispatchCount + 1u;
              self.fastDispatchCount = self.fastDispatchCount + 1u;
              [commandBuffer commit];
              [commandBuffer waitUntilCompleted];
              self.waitCount = self.waitCount + 1u;
              if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
                return NO;
              }
              return YES;
            }

            - (RhdlArcGpuIo*)io {
              return (RhdlArcGpuIo*)self.ioBuffer.contents;
            }

            - (RhdlStateScalar*)stateSlots {
              return (RhdlStateScalar*)self.stateBuffer.contents;
            }

            - (uint8_t*)instMem {
              return (uint8_t*)self.instBuffer.contents;
            }

            - (uint8_t*)dataMem {
              return (uint8_t*)self.instBuffer.contents;
            }

            - (RhdlArcGpuIo*)ioAtIndex:(uint32_t)index {
              if (index >= self.instanceCount) {
                return nullptr;
              }
              return ((RhdlArcGpuIo*)self.ioBuffer.contents) + index;
            }

            - (RhdlStateScalar*)stateSlotsAtIndex:(uint32_t)index {
              if (index >= self.instanceCount) {
                return nullptr;
              }
              return ((RhdlStateScalar*)self.stateBuffer.contents) + ((size_t)index * (size_t)STATE_COUNT);
            }

            - (uint8_t*)instMemAtIndex:(uint32_t)index {
              if (index >= self.instanceCount) {
                return nullptr;
              }
              return ((uint8_t*)self.instBuffer.contents) + ((size_t)index * (size_t)self.memSize);
            }

            - (uint8_t*)dataMemAtIndex:(uint32_t)index {
              if (index >= self.instanceCount) {
                return nullptr;
              }
              return ((uint8_t*)self.instBuffer.contents) + ((size_t)index * (size_t)self.memSize);
            }
            @end

            struct SimContext {
              __strong #{objc_sim_class}* sim;
            };

            static inline SimContext* ctx_cast(void* raw) {
              return static_cast<SimContext*>(raw);
            }

            extern "C" {

            void* sim_create(unsigned int mem_size) {
              @autoreleasepool {
                uint32_t resolvedMemSize = mem_size > 0u ? mem_size : 1u;
                uint32_t resolvedInstanceCount = resolve_instance_count();
                SimContext* ctx = new SimContext();
                ctx->sim = [[#{objc_sim_class} alloc]
                  initWithMetallibPath:resolveMetallibPath()
                           kernelName:kKernelName
                           stateCount:STATE_COUNT
                     stateScalarBytes:STATE_SCALAR_BYTES
                              memSize:resolvedMemSize
                        instanceCount:resolvedInstanceCount];
                if (!ctx->sim) {
                  delete ctx;
                  return nullptr;
                }
                return ctx;
              }
            }

            void sim_destroy(void* sim) {
              if (!sim) {
                return;
              }
              @autoreleasepool {
                SimContext* ctx = ctx_cast(sim);
                ctx->sim = nil;
                delete ctx;
              }
            }

            void sim_reset(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return;
              }
              @autoreleasepool {
                RhdlArcGpuIo* io = [ctx->sim io];
                if (!io) {
                  return;
                }
                RhdlArcGpuIo base = io[0];
                #{reset_assert_line.sub('io->', 'base.')}
                #{reset_clk_low_line.sub('io->', 'base.')}
                for (uint32_t i = 0u; i < ctx->sim.instanceCount; ++i) {
                  io[i] = base;
                }
                [ctx->sim dispatchKernelWithBudget:0u];
                #{reset_clk_high_line.sub('io->', 'base.')}
                for (uint32_t i = 0u; i < ctx->sim.instanceCount; ++i) {
                  io[i] = base;
                }
                [ctx->sim dispatchKernelWithBudget:0u];
                #{reset_clk_low_line.sub('io->', 'base.')}
                #{reset_deassert_line.sub('io->', 'base.')}
                for (uint32_t i = 0u; i < ctx->sim.instanceCount; ++i) {
                  io[i] = base;
                }
                [ctx->sim dispatchKernelWithBudget:0u];
              }
            }

            void sim_eval(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return;
              }
              @autoreleasepool {
                [ctx->sim dispatchKernelWithBudget:0u];
              }
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim || !name) {
                return;
              }
              RhdlArcGpuIo* io = [ctx->sim ioAtIndex:0u];
              if (!io) {
                return;
              }
            #{poke_cases.join("\n")}
            }

            unsigned int sim_peek(void* sim, const char* name) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim || !name) {
                return 0u;
              }
              RhdlArcGpuIo* io = [ctx->sim ioAtIndex:0u];
              if (!io) {
                return 0u;
              }
            #{peek_cases.join("\n")}
              return 0u;
            }

            unsigned int sim_read_pc(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              if (PC_SLOT_INDEX < 0) {
                return 0u;
              }
              RhdlStateScalar* slots = [ctx->sim stateSlotsAtIndex:0u];
              if (!slots) {
                return 0u;
              }
              uint32_t value = (uint32_t)slots[PC_SLOT_INDEX];
              return mask_width(value, PC_SLOT_WIDTH);
            }

            unsigned int sim_read_reg(void* sim, unsigned int index) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              uint32_t reg_index = index & 0x1Fu;
              if (reg_index == 0u) {
                return 0u;
              }
              if (REGFILE_BASE_SLOT < 0 || reg_index >= REGFILE_LENGTH) {
                return 0u;
              }
              RhdlStateScalar* slots = [ctx->sim stateSlotsAtIndex:0u];
              if (!slots) {
                return 0u;
              }
              return (uint32_t)slots[REGFILE_BASE_SLOT + (int32_t)reg_index];
            }

            unsigned int sim_read_inst(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              const uint8_t* inst = [ctx->sim instMemAtIndex:0u];
              if (!inst) {
                return 0u;
              }
              uint32_t pc = sim_read_pc(sim);
              return read_word_le(inst, ctx->sim.memMask, pc);
            }

            void sim_write_pc(void* sim, unsigned int value) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return;
              }
              if (PC_SLOT_INDEX >= 0) {
                for (uint32_t i = 0u; i < ctx->sim.instanceCount; ++i) {
                  RhdlStateScalar* slots = [ctx->sim stateSlotsAtIndex:i];
                  if (slots) {
                    slots[PC_SLOT_INDEX] = (RhdlStateScalar)mask_width(value, PC_SLOT_WIDTH);
                  }
                }
              }
              [ctx->sim dispatchKernelWithBudget:0u];
            }

            void sim_load_mem(void* sim, int mem_type, const unsigned char* data, unsigned int size, unsigned int base_addr) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim || !data || size == 0u) {
                return;
              }
              uint32_t mask = ctx->sim.memMask;
              for (uint32_t inst = 0u; inst < ctx->sim.instanceCount; ++inst) {
                uint8_t* target = mem_type == 0 ? [ctx->sim instMemAtIndex:inst] : [ctx->sim dataMemAtIndex:inst];
                if (!target) {
                  continue;
                }
                for (uint32_t i = 0u; i < size; ++i) {
                  target[(base_addr + i) & mask] = data[i];
                }
              }
            }

            unsigned int sim_read_mem_word(void* sim, int mem_type, unsigned int addr) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              const uint8_t* target = mem_type == 0 ? [ctx->sim instMemAtIndex:0u] : [ctx->sim dataMemAtIndex:0u];
              return read_word_le(target, ctx->sim.memMask, addr);
            }

            void sim_run_cycles(void* sim, unsigned int n_cycles) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return;
              }
              [ctx->sim dispatchKernelWithBudget:n_cycles];
            }

            unsigned int sim_dispatch_count(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              return ctx->sim.dispatchCount;
            }

            unsigned int sim_wait_count(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              return ctx->sim.waitCount;
            }

            unsigned int sim_fast_dispatch_count(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              return ctx->sim.fastDispatchCount;
            }

            unsigned int sim_fallback_dispatch_count(void* sim) {
              SimContext* ctx = ctx_cast(sim);
              if (!ctx || !ctx->sim) {
                return 0u;
              }
              return 0u;
            }

            void sim_uart_rx_push(void* sim, const unsigned char* data, unsigned int len) {
              (void)sim;
              (void)data;
              (void)len;
            }

            unsigned int sim_uart_tx_len(void* sim) {
              (void)sim;
              return 0u;
            }

            unsigned int sim_uart_tx_copy(void* sim, unsigned char* out, unsigned int max_len) {
              (void)sim;
              (void)out;
              (void)max_len;
              return 0u;
            }

            void sim_uart_tx_clear(void* sim) {
              (void)sim;
            }

            unsigned int sim_disk_load(void* sim, const unsigned char* data, unsigned int size, unsigned int base_addr) {
              (void)sim;
              (void)data;
              (void)size;
              (void)base_addr;
              return 0u;
            }

            unsigned int sim_disk_read_byte(void* sim, unsigned int offset) {
              (void)sim;
              (void)offset;
              return 0u;
            }

            } // extern "C"
          CPP

          File.write(path, wrapper)
        end
      end
    end
  end
end
