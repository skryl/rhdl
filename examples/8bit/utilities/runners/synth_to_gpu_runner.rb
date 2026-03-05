# frozen_string_literal: true

require 'fileutils'
require 'fiddle'
require 'json'
require 'open3'
require 'rbconfig'
require 'rhdl/codegen'
require 'rhdl/codegen/circt/firrtl'
require 'rhdl/codegen/firrtl/arc_to_gpu_lowering'
require 'rhdl/codegen/firrtl/synth_to_gpu_lowering'
require 'rhdl/codegen/firrtl/gem_to_gpu_lowering'
require_relative '../../hdl/cpu/cpu'

module RHDL
  module Examples
    module CPU8Bit
      # Native runner for 8-bit CPU using local ArcToGPU/SynthToGPU/GEM-to-GPU
      # lowering + Metal execution.
      #
      # Pipeline:
      #   RHDL CPU -> FIRRTL -> firtool (HW MLIR)
      #   -> (ArcToGPU) arcilator --emit-mlir --until-after=arc-opt
      #      OR (SynthToGPU/GEM) circt-opt HW->Synth AIG bits
      #   -> ArcToGpuLowering/SynthToGpuLowering/GemToGpuLowering(profile: :cpu8bit)
      #   -> Metal shader + Objective-C++ shim shared library
      class SynthToGpuRunner
        BUILD_ROOT = File.expand_path('../../.metal_build', __dir__)
        REQUIRED_TOOLS = %w[firtool circt-opt].freeze
        ARC_PIPELINE_TOOLS = %w[arcilator].freeze

        attr_reader :backend, :parallel_instances, :gem_execution_mode

        def self.status(pipeline: :synth_to_gpu)
          missing_tools = REQUIRED_TOOLS.reject { |tool| command_available?(tool) }
          missing_tools.concat(ARC_PIPELINE_TOOLS.reject { |tool| command_available?(tool) }) if pipeline.to_sym == :arc_to_gpu
          missing_tools << 'c++/clang++' unless command_available?('c++') || command_available?('clang++')

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

        def self.ensure_available!(pipeline: :synth_to_gpu)
          info = status(pipeline: pipeline)
          return info if info[:ready]

          raise ArgumentError,
            "#{pipeline} backend unavailable (missing tools: #{info[:missing_tools].join(', ')}). " \
            'Install CIRCT tools and the macOS Metal toolchain.'
        end

        def initialize(pipeline: :synth_to_gpu)
          @pipeline = pipeline.to_sym
          unless %i[synth_to_gpu arc_to_gpu gem_gpu].include?(@pipeline)
            raise ArgumentError, "Unsupported cpu8bit Metal pipeline #{@pipeline.inspect}"
          end

          @parallel_instances = configured_parallel_instances
          # Keep legacy behavior for non-GEM runners unless explicitly overridden.
          @parallel_instances = 1 if @pipeline != :gem_gpu && ENV['RHDL_CPU8BIT_GPU_INSTANCES'].nil?
          @gem_execution_mode = configured_gem_execution_mode
          @backend = @pipeline
          self.class.ensure_available!(pipeline: @pipeline)
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
          if defined?(@fn_parallel_instances) && @fn_parallel_instances
            value = @fn_parallel_instances.call(@ctx).to_i
            return value if value.positive?
          end
          @parallel_instances
        end

        def runner_execution_mode
          if defined?(@fn_execution_mode) && @fn_execution_mode
            mode = @fn_execution_mode.call(@ctx).to_i
            return :instruction_stream if mode == 1
          end
          gem_execution_mode
        end

        def runner_scheduler_mode
          if defined?(@fn_scheduler_mode) && @fn_scheduler_mode
            mode = @fn_scheduler_mode.call(@ctx).to_i
            return :dynamic_ready_layers if mode == 1
          end
          :disabled
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

        def pipeline_name
          @pipeline.to_s
        end

        def build_dir
          suffix = if @pipeline == :gem_gpu
            "_m#{gem_execution_mode_tag}" \
              "_ds#{gem_dynamic_scheduler_enabled_code}" \
              "_ow#{gem_output_watch_override_enabled? ? 1 : 0}"
          else
            ''
          end
          File.join(BUILD_ROOT, "#{pipeline_name}_i#{@parallel_instances}#{suffix}")
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)

          fir_file = File.join(build_dir, 'cpu8bit.fir')
          hw_mlir_file = File.join(build_dir, 'cpu8bit_hw.mlir')
          arc_mlir_file = File.join(build_dir, 'cpu8bit_arc.mlir')
          synth_bits_mlir_file = File.join(build_dir, 'cpu8bit_synth_bits.mlir')
          gpu_mlir_file = File.join(build_dir, "cpu8bit_#{pipeline_name}.mlir")
          gpu_meta_file = File.join(build_dir, "cpu8bit_#{pipeline_name}.json")
          metal_source_file = File.join(build_dir, "cpu8bit_#{pipeline_name}.metal")
          metal_air_file = File.join(build_dir, "cpu8bit_#{pipeline_name}.air")
          metal_lib_file = File.join(build_dir, "cpu8bit_#{pipeline_name}.metallib")
          wrapper_file = File.join(build_dir, "cpu8bit_#{pipeline_name}_wrapper.mm")
          log_file = File.join(build_dir, "cpu8bit_#{pipeline_name}.log")
          outputs = [shared_lib_path, gpu_meta_file, metal_source_file, metal_lib_file, wrapper_file]

          needs_rebuild = outputs.any? { |path| !File.exist?(path) }
          unless needs_rebuild
            deps = [
              __FILE__,
              File.expand_path('../../hdl/cpu.rb', __dir__),
              File.expand_path('../../../../lib/rhdl/codegen/firrtl/arc_to_gpu_lowering.rb', __dir__),
              File.expand_path('../../../../lib/rhdl/codegen/firrtl/synth_to_gpu_lowering.rb', __dir__),
              File.expand_path('../../../../lib/rhdl/codegen/firrtl/gem_to_gpu_lowering.rb', __dir__),
              File.expand_path('../../../../lib/rhdl/codegen/firrtl/arc_to_gpu_lowering/profiles/cpu8bit.rb', __dir__)
            ].select { |path| File.exist?(path) }
            newest_dep = deps.map { |path| File.mtime(path) }.max
            oldest_output = outputs.map { |path| File.mtime(path) }.min
            needs_rebuild = newest_dep && oldest_output && newest_dep > oldest_output
          end

          return unless needs_rebuild

          File.delete(log_file) if File.exist?(log_file)
          export_firrtl(fir_file)
          run_or_raise(%W[firtool #{fir_file} --ir-hw -o #{hw_mlir_file}], 'firtool HW lowering', log_file)

          if @pipeline == :arc_to_gpu
            run_or_raise(
              ['arcilator', hw_mlir_file, '--emit-mlir', '--until-after=arc-opt', '-o', arc_mlir_file],
              'arcilator Arc emission',
              log_file
            )
            RHDL::Codegen::FIRRTL::ArcToGpuLowering.lower(
              arc_mlir_path: arc_mlir_file,
              gpu_mlir_path: gpu_mlir_file,
              metadata_path: gpu_meta_file,
              metal_source_path: metal_source_file,
              profile: :cpu8bit
            )
          else
            synth_pipeline = [
              'builtin.module(hw.module(' \
              'hw-aggregate-to-comb,' \
              'convert-comb-to-synth{target-ir=aig additional-legal-ops="comb.divu,comb.modu"},' \
              'synth-lower-word-to-bits,' \
              'synth-structural-hash' \
              '),canonicalize,cse)'
            ].join
            run_or_raise(
              ['circt-opt', hw_mlir_file, "--pass-pipeline=#{synth_pipeline}", '-o', synth_bits_mlir_file],
              'circt-opt HW->Synth(AIG bits) netlistization',
              log_file
            )
            if @pipeline == :gem_gpu
              with_env(
                'RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER' => (gem_execution_mode == :instruction_stream ? '1' : '0')
              ) do
                RHDL::Codegen::FIRRTL::GemToGpuLowering.lower(
                  synth_mlir_path: synth_bits_mlir_file,
                  gpu_mlir_path: gpu_mlir_file,
                  metadata_path: gpu_meta_file,
                  metal_source_path: metal_source_file,
                  profile: :cpu8bit,
                  partition_size: gem_partition_size
                )
              end
            else
              RHDL::Codegen::FIRRTL::SynthToGpuLowering.lower(
                synth_mlir_path: synth_bits_mlir_file,
                gpu_mlir_path: gpu_mlir_file,
                metadata_path: gpu_meta_file,
                metal_source_path: metal_source_file,
                profile: :cpu8bit
              )
            end
          end

          compile_metal_shader(
            metal_source_file: metal_source_file,
            metal_air_file: metal_air_file,
            metal_lib_file: metal_lib_file,
            log_file: log_file
          )

          write_wrapper(path: wrapper_file, metadata_path: gpu_meta_file, metallib_path: metal_lib_file)
          link_shared_library(wrapper_file, shared_lib_path, log_file: log_file)
        end

        def export_firrtl(path)
          ir = RHDL::HDL::CPU::CPU.to_flat_ir(top_name: 'cpu8bit')
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate(ir)
          File.write(path, firrtl)
        end

        def compile_metal_shader(metal_source_file:, metal_air_file:, metal_lib_file:, log_file:)
          run_or_raise(
            ['xcrun', '-sdk', 'macosx', 'metal', '-c', '-O3', metal_source_file, '-o', metal_air_file],
            'metal shader compile',
            log_file
          )
          run_or_raise(
            ['xcrun', '-sdk', 'macosx', 'metallib', metal_air_file, '-o', metal_lib_file],
            'metallib link',
            log_file
          )
        end

        def write_wrapper(path:, metadata_path:, metallib_path:)
          metadata = JSON.parse(File.read(metadata_path))
          state_count = metadata.dig('metal', 'state_count').to_i
          state_scalar_bits = metadata.dig('metal', 'state_scalar_bits').to_i
          state_scalar_bits = 32 if state_scalar_bits <= 0
          state_scalar_cpp_type = state_scalar_bits > 32 ? 'uint64_t' : 'uint32_t'
          kernel_name = metadata.dig('metal', 'entry').to_s
          base_objc_class_name =
            case @pipeline
            when :arc_to_gpu then 'RhdlCpu8ArcToGpuSim'
            when :gem_gpu then 'RhdlCpu8GemGpuSim'
            else 'RhdlCpu8SynthToGpuSim'
            end
          objc_class_name = "#{base_objc_class_name}_i#{@parallel_instances}"
          if @pipeline == :gem_gpu
            objc_class_name = "#{objc_class_name}_m#{gem_execution_mode_tag}" \
              "_ds#{gem_dynamic_scheduler_enabled_code}" \
              "_ow#{gem_output_watch_override_enabled? ? 1 : 0}"
          end
          input_layout = Array(metadata['top_input_layout'])
          output_layout = Array(metadata['top_output_layout'])
          state_layout = Array(metadata['state_layout'])
          alias_slots = metadata.fetch('poke_alias_state_slots', {})
          gem_partition_count,
            gem_layer_depth,
            gem_dispatch_cycle_granularity,
            gem_instruction_count,
            gem_block_count,
            gem_state_read_count,
            gem_control_step_count,
            gem_dependency_edge_count,
            gem_ready_layer_count,
            gem_stream_checksum =
            gem_execution_constants(metadata)
          ready_layers = gem_ready_layers(metadata)
          ready_layer_offsets = [0]
          ready_layer_partitions = []
          ready_layers.each do |layer|
            ready_layer_partitions.concat(layer)
            ready_layer_offsets << ready_layer_partitions.length
          end
          ready_layer_offsets = [0, 1] if ready_layer_offsets.length < 2
          ready_layer_partitions = [0] if ready_layer_partitions.empty?
          ready_layer_offsets_cpp = cpp_uint_array(ready_layer_offsets)
          ready_layer_partitions_cpp = cpp_uint_array(ready_layer_partitions)
          gem_instruction_words_list = gem_instruction_words(metadata)
          gem_instruction_words_cpp = cpp_uint_array(gem_instruction_words_list)
          gem_mode_code = gem_execution_mode_code
          gem_dynamic_scheduler_flag = gem_dynamic_scheduler_enabled_code
          run_cycles_body = runner_run_cycles_body

          raise LoadError, "#{@pipeline} metadata missing kernel entry" if kernel_name.empty?
          raise LoadError, "#{@pipeline} metadata missing state_count" if state_count <= 0

          state_width_by_index = {}
          state_layout.each { |entry| state_width_by_index[entry.fetch('index').to_i] = entry.fetch('width').to_i }

          poke_input_cases = input_layout.map do |entry|
            name = entry.fetch('name')
            width = entry.fetch('width').to_i
            <<~CPP.chomp
              if (!strcmp(name, "#{name}")) {
                io->#{name} = mask_width(value, #{width}u);
                return;
              }
            CPP
          end

          poke_state_cases = alias_slots.map do |name, index|
            idx = index.to_i
            width = state_width_by_index.fetch(idx, 32)
            <<~CPP.chomp
              if (!strcmp(name, "#{name}")) {
                state[#{idx}] = static_cast<StateScalar>(mask_width(value, #{width}u));
                return;
              }
            CPP
          end

          peek_output_cases = output_layout.map do |entry|
            name = entry.fetch('name')
            width = entry.fetch('width').to_i
            <<~CPP.chomp
              if (!strcmp(name, "#{name}")) {
                return mask_width(io->#{name}, #{width}u);
              }
            CPP
          end

          peek_input_cases = input_layout.map do |entry|
            name = entry.fetch('name')
            width = entry.fetch('width').to_i
            <<~CPP.chomp
              if (!strcmp(name, "#{name}")) {
                return mask_width(io->#{name}, #{width}u);
              }
            CPP
          end

          peek_state_cases = alias_slots.map do |name, index|
            idx = index.to_i
            width = state_width_by_index.fetch(idx, 32)
            <<~CPP.chomp
              if (!strcmp(name, "#{name}")) {
                return mask_width(static_cast<uint32_t>(state[#{idx}]), #{width}u);
              }
            CPP
          end

          wrapper = <<~CPP
            #import <Foundation/Foundation.h>
            #import <Metal/Metal.h>
            #include <cstdint>
            #include <cstring>

            struct RhdlArcGpuIo {
              uint32_t rst;
              uint32_t clk;
              uint32_t last_clk;
              uint32_t mem_data_in;
              uint32_t mem_data_out;
              uint32_t mem_addr;
              uint32_t mem_write_en;
              uint32_t mem_read_en;
              uint32_t pc_out;
              uint32_t acc_out;
              uint32_t sp_out;
              uint32_t halted;
              uint32_t state_out;
              uint32_t zero_flag_out;
              uint32_t cycle_budget;
              uint32_t cycles_ran;
            };

            using StateScalar = #{state_scalar_cpp_type};
            static NSString* const kMetallibPath = @#{metallib_path.dump};
            static NSString* const kKernelName = @#{kernel_name.dump};
            static const uint32_t STATE_COUNT = #{state_count}u;
            static const uint32_t MEMORY_BYTES = 65536u;
            static const uint32_t INSTANCE_COUNT = #{@parallel_instances}u;
            static const uint32_t GEM_PARTITION_COUNT = #{gem_partition_count}u;
            static const uint32_t GEM_LAYER_DEPTH = #{gem_layer_depth}u;
            static const uint32_t GEM_DISPATCH_CYCLE_GRANULARITY = #{gem_dispatch_cycle_granularity}u;
            static const uint32_t GEM_EXECUTION_MODE = #{gem_mode_code}u;
            static const uint32_t GEM_INSTRUCTION_COUNT = #{gem_instruction_count}u;
            static const uint32_t GEM_BLOCK_COUNT = #{gem_block_count}u;
            static const uint32_t GEM_STATE_READ_COUNT = #{gem_state_read_count}u;
            static const uint32_t GEM_CONTROL_STEP_COUNT = #{gem_control_step_count}u;
            static const uint32_t GEM_DEPENDENCY_EDGE_COUNT = #{gem_dependency_edge_count}u;
            static const uint32_t GEM_READY_LAYER_COUNT = #{gem_ready_layer_count}u;
            static const uint32_t GEM_STREAM_CHECKSUM32 = 0x#{gem_stream_checksum.to_s(16).rjust(8, '0')}u;
            static const uint32_t GEM_SCHEDULER_MODE = (GEM_DEPENDENCY_EDGE_COUNT > 0u && GEM_READY_LAYER_COUNT > 1u) ? 1u : 0u;
            static const uint32_t GEM_DYNAMIC_SCHEDULER_ENABLED = #{gem_dynamic_scheduler_flag}u;
            static const uint32_t GEM_READY_LAYER_OFFSETS[#{ready_layer_offsets.length}] = #{ready_layer_offsets_cpp};
            static const uint32_t GEM_READY_LAYER_PARTITIONS[#{ready_layer_partitions.length}] = #{ready_layer_partitions_cpp};
            static const uint32_t GEM_INSTRUCTION_WORD_COUNT = #{gem_instruction_words_list.length}u;
            static const uint32_t GEM_INSTRUCTION_WORDS[#{gem_instruction_words_list.length}] = #{gem_instruction_words_cpp};

            static inline uint32_t mask_width(uint32_t value, uint32_t width) {
              if (width >= 32u) { return value; }
              if (width == 0u) { return 0u; }
              return value & ((1u << width) - 1u);
            }

            @interface #{objc_class_name} : NSObject
            @property(nonatomic, strong) id<MTLDevice> device;
            @property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
            @property(nonatomic, strong) id<MTLLibrary> library;
            @property(nonatomic, strong) id<MTLComputePipelineState> pipeline;
            @property(nonatomic, strong) id<MTLBuffer> stateBuffer;
            @property(nonatomic, strong) id<MTLBuffer> memoryBuffer;
            @property(nonatomic, strong) id<MTLBuffer> ioBuffer;
            @property(nonatomic, strong) id<MTLBuffer> instructionBuffer;
            - (instancetype)initWithMetallibPath:(NSString*)metallibPath kernelName:(NSString*)kernelName;
            - (BOOL)dispatch;
            - (RhdlArcGpuIo*)ioForInstance:(uint32_t)instance;
            - (StateScalar*)stateSlotsForInstance:(uint32_t)instance;
            - (uint8_t*)memoryForInstance:(uint32_t)instance;
            - (RhdlArcGpuIo*)io;
            - (StateScalar*)stateSlots;
            - (uint8_t*)memory;
            @end

            @implementation #{objc_class_name}
            - (instancetype)initWithMetallibPath:(NSString*)metallibPath kernelName:(NSString*)kernelName {
              self = [super init];
              if (!self) { return nil; }

              self.device = MTLCreateSystemDefaultDevice();
              if (!self.device) { return nil; }

              self.commandQueue = [self.device newCommandQueue];
              if (!self.commandQueue) { return nil; }

              NSError* error = nil;
              self.library = [self.device newLibraryWithFile:metallibPath error:&error];
              if (!self.library) { return nil; }

              id<MTLFunction> fn = [self.library newFunctionWithName:kernelName];
              if (!fn) { return nil; }

              self.pipeline = [self.device newComputePipelineStateWithFunction:fn error:&error];
              if (!self.pipeline) { return nil; }

              uint64_t stateBytes = (uint64_t)sizeof(StateScalar) * (uint64_t)STATE_COUNT * (uint64_t)INSTANCE_COUNT;
              uint64_t memoryBytes = (uint64_t)MEMORY_BYTES * (uint64_t)INSTANCE_COUNT;
              uint64_t ioBytes = (uint64_t)sizeof(RhdlArcGpuIo) * (uint64_t)INSTANCE_COUNT;
              uint64_t instructionBytes = (uint64_t)sizeof(uint32_t) * (uint64_t)GEM_INSTRUCTION_WORD_COUNT;
              self.stateBuffer = [self.device newBufferWithLength:stateBytes options:MTLResourceStorageModeShared];
              self.memoryBuffer = [self.device newBufferWithLength:memoryBytes options:MTLResourceStorageModeShared];
              self.ioBuffer = [self.device newBufferWithLength:ioBytes options:MTLResourceStorageModeShared];
              self.instructionBuffer = [self.device newBufferWithLength:instructionBytes options:MTLResourceStorageModeShared];
              if (!self.stateBuffer || !self.memoryBuffer || !self.ioBuffer || !self.instructionBuffer) { return nil; }

              memset(self.stateBuffer.contents, 0, stateBytes);
              memset(self.memoryBuffer.contents, 0, memoryBytes);
              memset(self.ioBuffer.contents, 0, ioBytes);
              memcpy(self.instructionBuffer.contents, GEM_INSTRUCTION_WORDS, instructionBytes);
              return self;
            }

            - (BOOL)dispatch {
              id<MTLCommandBuffer> cb = [self.commandQueue commandBuffer];
              if (!cb) { return NO; }

              id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
              if (!enc) { return NO; }

              [enc setComputePipelineState:self.pipeline];
              [enc setBuffer:self.stateBuffer offset:0 atIndex:0];
              [enc setBuffer:self.memoryBuffer offset:0 atIndex:1];
              [enc setBuffer:self.ioBuffer offset:0 atIndex:2];
              [enc setBuffer:self.instructionBuffer offset:0 atIndex:3];

              MTLSize gridSize = MTLSizeMake(INSTANCE_COUNT, 1, 1);
              MTLSize groupSize = MTLSizeMake(1, 1, 1);
              [enc dispatchThreads:gridSize threadsPerThreadgroup:groupSize];
              [enc endEncoding];

              [cb commit];
              [cb waitUntilCompleted];
              return cb.status == MTLCommandBufferStatusCompleted;
            }

            - (RhdlArcGpuIo*)ioForInstance:(uint32_t)instance {
              uint32_t idx = instance < INSTANCE_COUNT ? instance : 0u;
              return reinterpret_cast<RhdlArcGpuIo*>(self.ioBuffer.contents) + idx;
            }

            - (StateScalar*)stateSlotsForInstance:(uint32_t)instance {
              uint32_t idx = instance < INSTANCE_COUNT ? instance : 0u;
              return reinterpret_cast<StateScalar*>(self.stateBuffer.contents) + (uint64_t)idx * (uint64_t)STATE_COUNT;
            }

            - (uint8_t*)memoryForInstance:(uint32_t)instance {
              uint32_t idx = instance < INSTANCE_COUNT ? instance : 0u;
              return reinterpret_cast<uint8_t*>(self.memoryBuffer.contents) + (uint64_t)idx * (uint64_t)MEMORY_BYTES;
            }

            - (RhdlArcGpuIo*)io { return [self ioForInstance:0u]; }
            - (StateScalar*)stateSlots { return [self stateSlotsForInstance:0u]; }
            - (uint8_t*)memory { return [self memoryForInstance:0u]; }
            @end

            static inline #{objc_class_name}* as_sim(void* sim) {
              return (__bridge #{objc_class_name}*)sim;
            }

            extern "C" {
            void* sim_create(void) {
              @autoreleasepool {
                #{objc_class_name}* sim = [[#{objc_class_name} alloc] initWithMetallibPath:kMetallibPath kernelName:kKernelName];
                if (!sim) { return nullptr; }

                for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                  RhdlArcGpuIo* io = [sim ioForInstance:instance];
                  io->rst = 1u;
                  io->cycle_budget = 1u;
                }
                if (![sim dispatch]) { return nullptr; }

                for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                  RhdlArcGpuIo* io = [sim ioForInstance:instance];
                  io->rst = 0u;
                  io->cycle_budget = 0u;
                }
                if (![sim dispatch]) { return nullptr; }

                return (__bridge_retained void*)sim;
              }
            }

            void sim_destroy(void* sim) {
              if (!sim) { return; }
              @autoreleasepool {
                #{objc_class_name}* s = (__bridge_transfer #{objc_class_name}*)sim;
                (void)s;
              }
            }

            void sim_eval(void* sim) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s) { return; }
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                RhdlArcGpuIo* io = [s ioForInstance:instance];
                io->cycle_budget = 0u;
              }
              [s dispatch];
            }

            void sim_reset(void* sim) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s) { return; }
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                RhdlArcGpuIo* io = [s ioForInstance:instance];
                io->rst = 1u;
                io->cycle_budget = 1u;
              }
              [s dispatch];
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                RhdlArcGpuIo* io = [s ioForInstance:instance];
                io->rst = 0u;
                io->cycle_budget = 0u;
              }
              [s dispatch];
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s || !name) { return; }
              RhdlArcGpuIo* io = [s io];
              StateScalar* state = [s stateSlots];

            #{indent_cpp_cases(poke_input_cases + poke_state_cases)}
            }

            unsigned int sim_peek(void* sim, const char* name) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s || !name) { return 0u; }
              RhdlArcGpuIo* io = [s io];
              StateScalar* state = [s stateSlots];

            #{indent_cpp_cases(peek_output_cases + peek_input_cases + peek_state_cases)}
              return 0u;
            }

            unsigned int sim_runner_load_memory(void* sim, const unsigned char* data, unsigned int len, unsigned int offset) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s || !data) { return 0u; }
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                uint8_t* mem = [s memoryForInstance:instance];
                for (unsigned int i = 0; i < len; ++i) {
                  unsigned int addr = (offset + i) & 0xFFFFu;
                  mem[addr] = data[i];
                }
              }
              return len;
            }

            unsigned int sim_runner_read_memory(void* sim, unsigned int offset, unsigned int len, unsigned char* out) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s || !out) { return 0u; }
              uint8_t* mem = [s memory];
              for (unsigned int i = 0; i < len; ++i) {
                unsigned int addr = (offset + i) & 0xFFFFu;
                out[i] = mem[addr];
              }
              return len;
            }

            unsigned int sim_runner_write_memory(void* sim, unsigned int offset, const unsigned char* data, unsigned int len) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s || !data) { return 0u; }
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                uint8_t* mem = [s memoryForInstance:instance];
                for (unsigned int i = 0; i < len; ++i) {
                  unsigned int addr = (offset + i) & 0xFFFFu;
                  mem[addr] = data[i];
                }
              }
              return len;
            }

            unsigned int sim_runner_run_cycles(void* sim, unsigned int n) {
              #{objc_class_name}* s = as_sim(sim);
              if (!s) { return 0u; }
            #{run_cycles_body}
            }

            unsigned int sim_parallel_instances(void* sim) {
              (void)sim;
              return INSTANCE_COUNT;
            }

            unsigned int sim_execution_mode(void* sim) {
              (void)sim;
              return GEM_EXECUTION_MODE;
            }

            unsigned int sim_scheduler_mode(void* sim) {
              (void)sim;
              if (GEM_EXECUTION_MODE != 1u || GEM_DYNAMIC_SCHEDULER_ENABLED == 0u) {
                return 0u;
              }
              return GEM_SCHEDULER_MODE;
            }
            }
          CPP

          File.write(path, wrapper)
        end

        def indent_cpp_cases(cases)
          return "              (void)io;\n              (void)state;" if cases.empty?

          cases.join("\n\n").lines.map { |line| "              #{line}" }.join
        end

        def run_or_raise(cmd, step_name, log_file)
          out, status = Open3.capture2e(*cmd)
          File.write(log_file, out, mode: 'a')
          return if status.success?

          raise LoadError, "#{step_name} failed for cpu8bit #{@pipeline} runner: #{last_log_lines(log_file)}"
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
            '-O3',
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

        def load_library
          @lib = Fiddle.dlopen(shared_lib_path)
          @fn_sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
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
          begin
            @fn_parallel_instances = Fiddle::Function.new(
              @lib['sim_parallel_instances'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
          rescue Fiddle::DLError
            @fn_parallel_instances = nil
          end

          begin
            @fn_execution_mode = Fiddle::Function.new(
              @lib['sim_execution_mode'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
          rescue Fiddle::DLError
            @fn_execution_mode = nil
          end

          begin
            @fn_scheduler_mode = Fiddle::Function.new(
              @lib['sim_scheduler_mode'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
          rescue Fiddle::DLError
            @fn_scheduler_mode = nil
          end

          @ctx = @fn_sim_create.call
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
          File.join(build_dir, "libcpu8bit_#{pipeline_name}_sim#{ext}")
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

        def last_log_lines(path, count = 20)
          return 'no log output' unless File.exist?(path)

          File.readlines(path).last(count).join.strip
        rescue StandardError
          'no log output'
        end

        def gem_partition_size
          raw = ENV['RHDL_GEM_GPU_PARTITION_SIZE'].to_i
          raw.positive? ? raw : RHDL::Codegen::FIRRTL::GemToGpuLowering::DEFAULT_PARTITION_SIZE
        end

        def with_env(overrides)
          previous = {}
          overrides.each do |key, value|
            previous[key] = ENV.key?(key) ? ENV[key] : :__missing__
            if value.nil?
              ENV.delete(key)
            else
              ENV[key] = value
            end
          end
          yield
        ensure
          previous.each do |key, value|
            if value == :__missing__
              ENV.delete(key)
            else
              ENV[key] = value
            end
          end
        end
        private :with_env

        def configured_gem_execution_mode
          return :legacy_eval unless @pipeline == :gem_gpu

          raw = ENV.fetch('RHDL_GEM_GPU_EXECUTION_MODE', '').strip.downcase
          return :instruction_stream if raw.empty?

          case raw
          when 'instruction_stream', 'stream', 'vbp_stream'
            :instruction_stream
          when 'legacy_eval', 'legacy', 'eval'
            :legacy_eval
          else
            raise ArgumentError,
              "Unsupported gem_gpu execution mode #{raw.inspect}. " \
              "Use 'instruction_stream' or 'legacy_eval'."
          end
        end
        private :configured_gem_execution_mode

        def gem_execution_mode_tag
          return 'legacy' unless @pipeline == :gem_gpu

          gem_execution_mode == :instruction_stream ? 'stream' : 'legacy'
        end
        private :gem_execution_mode_tag

        def gem_execution_mode_code
          return 0 unless @pipeline == :gem_gpu

          gem_execution_mode == :instruction_stream ? 1 : 0
        end
        private :gem_execution_mode_code

        def gem_dynamic_scheduler_enabled_code
          return 0 unless @pipeline == :gem_gpu

          raw = ENV.fetch('RHDL_GEM_GPU_DYNAMIC_SCHEDULER', '').strip.downcase
          return (@parallel_instances > 1 ? 1 : 0) if raw.empty?
          return 1 if %w[1 true yes on].include?(raw)
          return 0 if %w[0 false no off].include?(raw)

          (@parallel_instances > 1 ? 1 : 0)
        end
        private :gem_dynamic_scheduler_enabled_code

        def configured_parallel_instances
          raw = ENV['RHDL_CPU8BIT_GPU_INSTANCES'].to_i
          count = raw.positive? ? raw : 1
          [[count, 1].max, 1024].min
        end

        def gem_execution_constants(metadata)
          return [1, 1, 1, 0, 0, 0, 0, 0, 0, 0] unless @pipeline == :gem_gpu

          gem = metadata.fetch('gem', {})
          execution = gem.fetch('execution', {})
          instruction_stream = gem.fetch('instruction_stream', {})
          primitive_counts = instruction_stream.fetch('primitive_counts', {})
          control_program = Array(instruction_stream['control_program'])
          partition_count = [gem.fetch('partition_count', 0).to_i, 1].max
          layer_depth = [gem.fetch('max_layer_depth', 0).to_i, 1].max
          dispatch_cycle_granularity = execution.fetch('dispatch_cycle_granularity', 0).to_i
          if dispatch_cycle_granularity <= 0
            dispatch_cycle_granularity = [partition_count * layer_depth, 1].max
          end
          instruction_count = [instruction_stream.fetch('instruction_count', 0).to_i, 0].max
          block_count = [Array(instruction_stream['block_boundaries']).length - 1, 0].max
          state_read_count = [primitive_counts.fetch('state_read', 0).to_i, 0].max
          control_step_count = [control_program.length, 0].max
          dependency_edge_count = [execution.fetch('partition_dependency_edge_count', 0).to_i, 0].max
          ready_layer_count = [execution.fetch('ready_layer_count', 0).to_i, 0].max
          checksum_hex = instruction_stream.fetch('checksum_sha256', '').to_s
          checksum32 = checksum_hex[0, 8].to_i(16) & 0xFFFF_FFFF
          [
            partition_count,
            layer_depth,
            dispatch_cycle_granularity,
            instruction_count,
            block_count,
            state_read_count,
            control_step_count,
            dependency_edge_count,
            ready_layer_count,
            checksum32
          ]
        end

        def gem_ready_layers(metadata)
          return [[0]] unless @pipeline == :gem_gpu

          gem = metadata.fetch('gem', {})
          execution = gem.fetch('execution', {})
          layers = Array(execution['ready_layers']).map do |layer|
            Array(layer).map(&:to_i).uniq.sort
          end.reject(&:empty?)
          return layers unless layers.empty?

          order = Array(execution['partition_order']).map(&:to_i).uniq
          return [order] unless order.empty?

          [[0]]
        end
        private :gem_ready_layers

        def cpp_uint_array(values)
          list = Array(values).map { |v| v.to_i }
          list = [0] if list.empty?
          "{ #{list.map { |v| "#{v}u" }.join(', ')} }"
        end
        private :cpp_uint_array

        def gem_instruction_words(metadata)
          return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] unless @pipeline == :gem_gpu

          gem = metadata.fetch('gem', {})
          stream = gem.fetch('instruction_stream', {})
          extern_refs = Array(stream['extern_refs']).map(&:to_s)
          extern_values = gem_extern_values(stream, extern_refs)
          extern_descriptors = gem_extern_descriptors(stream)
          watch_eval_indices = gem_watch_eval_indices(stream, instruction_count: stream.fetch('instruction_count', 0).to_i)
          output_fields = gem_output_fields(stream)
          output_widths = gem_output_widths(stream, field_count: output_fields.length)
          output_bit_sources = gem_packed_sources(
            stream['output_bit_sources'],
            extern_refs: extern_refs,
            extern_table_mode: true
          )
          expected_output_bits = output_widths.sum
          output_bit_sources = output_bit_sources.first(expected_output_bits)
          output_bit_sources.concat(Array.new(expected_output_bits - output_bit_sources.length, 0)) if output_bit_sources.length < expected_output_bits
          state_slot_indices = Array(stream['state_slot_indices']).map { |slot| slot.to_i & 0xFFFF_FFFF }
          state_widths = gem_state_widths(stream, slot_count: state_slot_indices.length)
          expected_state_bits = state_widths.sum
          state_next_bit_sources = gem_packed_sources(
            stream['state_next_bit_sources'],
            extern_refs: extern_refs,
            extern_table_mode: true
          ).first(expected_state_bits)
          state_next_bit_sources.concat(Array.new(expected_state_bits - state_next_bit_sources.length, 0)) if state_next_bit_sources.length < expected_state_bits
          state_reset_bit_sources = gem_packed_sources(
            stream['state_reset_bit_sources'],
            extern_refs: extern_refs,
            extern_table_mode: true
          ).first(expected_state_bits)
          state_reset_bit_sources.concat(Array.new(expected_state_bits - state_reset_bit_sources.length, 0)) if state_reset_bit_sources.length < expected_state_bits
          state_reset_enable_sources = gem_packed_sources(
            stream['state_reset_enable_sources'],
            extern_refs: extern_refs,
            extern_table_mode: true
          ).first(state_slot_indices.length)
          state_reset_enable_sources.concat(Array.new(state_slot_indices.length - state_reset_enable_sources.length, 0)) if state_reset_enable_sources.length < state_slot_indices.length
          extern_table_mode = extern_values.any?
          instructions = Array(stream['instructions'])
          max_instructions = 4096
          count = [instructions.length, max_instructions].min
          watch_sources = Array(stream['output_watch_sources'])
          watch_count = [watch_sources.length, 32].min
          flags = stream.fetch('flags', 0).to_i & 0xFFFF_FFFF
          watch_override = stream.fetch('output_watch_override', false)
          watch_override = true if gem_output_watch_override_enabled?
          if watch_override == true || %w[1 true yes on].include?(watch_override.to_s.downcase)
            flags |= 0x1
          end
          flags |= 0x4 if extern_table_mode
          flags |= 0x8 if extern_descriptors.any?
          stream_semantics_ready =
            output_fields.any? &&
            output_widths.length == output_fields.length &&
            output_bit_sources.length == output_widths.sum &&
            state_slot_indices.any? &&
            state_widths.length == state_slot_indices.length &&
            state_next_bit_sources.length == state_widths.sum &&
            state_reset_bit_sources.length == state_widths.sum &&
            state_reset_enable_sources.length == state_slot_indices.length
          flags |= 0x10 if stream_semantics_ready
          words = [count, flags]

          instructions.first(count).each do |inst|
            dst = [inst.fetch('dst_node', 0).to_i, 0].max
            src = Array(inst['src'])
            src0 = pack_gem_instruction_source(src[0], extern_refs, extern_table_mode: extern_table_mode)
            src1 = pack_gem_instruction_source(src[1], extern_refs, extern_table_mode: extern_table_mode)
            words << dst
            words << src0
            words << src1
            words << 0
          end

          words << watch_count
          watch_sources.first(watch_count).each do |watch|
            src = watch
            src = watch['src'] if watch.is_a?(Hash) && watch.key?('src')
            src = watch[:src] if watch.is_a?(Hash) && watch.key?(:src)
            words << pack_gem_instruction_source(src, extern_refs, extern_table_mode: extern_table_mode)
          end

          control_program = Array(stream['control_program'])
          control_codes = control_program.map { |step| pack_gem_control_op(step) }.compact
          words << control_codes.length
          words.concat(control_codes)
          words << extern_values.length
          words.concat(extern_values.map { |value| value.to_i & 0x1 })
          words << extern_descriptors.length
          words.concat(extern_descriptors.map { |value| value.to_i & 0xFFFF_FFFF })
          words << watch_eval_indices.length
          words.concat(watch_eval_indices.map { |value| value.to_i & 0xFFFF_FFFF })
          words << output_fields.length
          words.concat(output_fields.map { |field| gem_io_field_code(field) & 0xFF })
          words << output_widths.length
          words.concat(output_widths.map { |width| width.to_i & 0x3F })
          words << output_bit_sources.length
          words.concat(output_bit_sources.map { |value| value.to_i & 0xFFFF_FFFF })
          words << state_slot_indices.length
          words.concat(state_slot_indices)
          words << state_widths.length
          words.concat(state_widths.map { |width| width.to_i & 0x3F })
          words << state_next_bit_sources.length
          words.concat(state_next_bit_sources.map { |value| value.to_i & 0xFFFF_FFFF })
          words << state_reset_bit_sources.length
          words.concat(state_reset_bit_sources.map { |value| value.to_i & 0xFFFF_FFFF })
          words << state_reset_enable_sources.length
          words.concat(state_reset_enable_sources.map { |value| value.to_i & 0xFFFF_FFFF })

          words
        end
        private :gem_instruction_words

        def gem_extern_values(stream, extern_refs)
          explicit = Array(stream['extern_ref_values'])
          return explicit.map { |value| value.to_i & 0x1 } unless explicit.empty?

          extern_refs.map do |ref|
            ref.match?(/ctrue|c1\b|true/i) ? 1 : 0
          end
        end
        private :gem_extern_values

        def gem_extern_descriptors(stream)
          Array(stream['extern_sources']).map { |source| pack_gem_extern_descriptor(source) }
        end
        private :gem_extern_descriptors

        def gem_watch_eval_indices(stream, instruction_count:)
          max = [instruction_count.to_i, 0].max
          Array(stream['watch_eval_indices']).map(&:to_i).select { |idx| idx >= 0 && idx < max }.uniq.sort
        end
        private :gem_watch_eval_indices

        def gem_output_fields(stream)
          Array(stream['output_fields']).map(&:to_s).reject(&:empty?)
        end
        private :gem_output_fields

        def gem_output_widths(stream, field_count:)
          widths = Array(stream['output_widths']).map(&:to_i).map { |width| [[width, 0].max, 32].min }
          widths = widths.first(field_count)
          widths.concat(Array.new(field_count - widths.length, 0)) if widths.length < field_count
          widths
        end
        private :gem_output_widths

        def gem_state_widths(stream, slot_count:)
          widths = Array(stream['state_widths']).map(&:to_i).map { |width| [[width, 0].max, 32].min }
          widths = widths.first(slot_count)
          widths.concat(Array.new(slot_count - widths.length, 0)) if widths.length < slot_count
          widths
        end
        private :gem_state_widths

        def gem_packed_sources(sources, extern_refs:, extern_table_mode:)
          Array(sources).map do |source|
            pack_gem_instruction_source(source, extern_refs, extern_table_mode: extern_table_mode)
          end
        end
        private :gem_packed_sources

        def pack_gem_extern_descriptor(source)
          return 3 unless source.is_a?(Hash)

          kind = source.fetch('kind', source[:kind]).to_s
          case kind
          when 'const'
            value = source.fetch('value', source[:value]).to_i & 0x1
            (0 << 0) | (value << 3)
          when 'state_bit'
            state_index = source.fetch('state_index', source[:state_index]).to_i & 0x3FF
            bit = source.fetch('bit', source[:bit]).to_i & 0x3F
            (1 << 0) | (state_index << 3) | (bit << 13)
          when 'io_bit'
            field = source.fetch('field', source[:field]).to_s
            field_code = gem_io_field_code(field)
            bit = source.fetch('bit', source[:bit]).to_i & 0x3F
            (2 << 0) | ((field_code & 0xFF) << 3) | (bit << 11)
          when 'state_divu_bit'
            lhs_state_index = source.fetch('lhs_state_index', source[:lhs_state_index]).to_i & 0x3FF
            rhs_state_index = source.fetch('rhs_state_index', source[:rhs_state_index]).to_i & 0x3FF
            bit = source.fetch('bit', source[:bit]).to_i & 0x3F
            (4 << 0) | (lhs_state_index << 3) | (rhs_state_index << 13) | (bit << 23)
          when 'state_modu_bit'
            lhs_state_index = source.fetch('lhs_state_index', source[:lhs_state_index]).to_i & 0x3FF
            rhs_state_index = source.fetch('rhs_state_index', source[:rhs_state_index]).to_i & 0x3FF
            bit = source.fetch('bit', source[:bit]).to_i & 0x3F
            (5 << 0) | (lhs_state_index << 3) | (rhs_state_index << 13) | (bit << 23)
          else
            3
          end
        rescue KeyError
          3
        end
        private :pack_gem_extern_descriptor

        def gem_io_field_code(field)
          case field
          when 'rst' then 0
          when 'clk' then 1
          when 'last_clk' then 2
          when 'mem_data_in' then 3
          when 'mem_data_out' then 4
          when 'mem_addr' then 5
          when 'mem_write_en' then 6
          when 'mem_read_en' then 7
          when 'pc_out' then 8
          when 'acc_out' then 9
          when 'sp_out' then 10
          when 'halted' then 11
          when 'state_out' then 12
          when 'zero_flag_out' then 13
          when 'cycle_budget' then 14
          when 'cycles_ran' then 15
          else
            255
          end
        end
        private :gem_io_field_code

        def gem_output_watch_override_enabled?
          raw = ENV.fetch('RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE', '').strip.downcase
          return false if raw.empty?
          return true if %w[1 true yes on].include?(raw)
          return false if %w[0 false no off].include?(raw)

          false
        end
        private :gem_output_watch_override_enabled?

        def pack_gem_control_op(step)
          op_name =
            if step.is_a?(Hash)
              step.fetch('op', step[:op]).to_s
            else
              step.to_s
            end
          return nil if op_name.empty?

          case op_name
          when 'cycle_begin' then 0
          when 'eval_low' then 1
          when 'mem_write' then 2
          when 'mem_read' then 3
          when 'eval_high' then 4
          when 'output_materialize' then 5
          when 'cycle_end' then 6
          else
            nil
          end
        end
        private :pack_gem_control_op

        def pack_gem_instruction_source(src, extern_refs, extern_table_mode: false)
          return 0 unless src.is_a?(Hash)

          kind = src.fetch('kind', '').to_s
          id = src.fetch('id', 0).to_i
          inverted = src.fetch('inverted', false) ? 1 : 0

          if kind == 'extern'
            if extern_table_mode
              packed_id = [id, 0].max
            else
              ref = id >= 0 ? extern_refs[id].to_s : ''
              const_value = ref.match?(/ctrue|c1\b|true/i) ? 1 : 0
              packed_id = const_value
            end
            kind_bit = 1
          else
            packed_id = [id, 0].max
            kind_bit = 0
          end

          ((packed_id & 0x3FFF_FFFF) << 2) | ((kind_bit & 0x1) << 1) | (inverted & 0x1)
        end
        private :pack_gem_instruction_source

        def runner_run_cycles_body
          if @pipeline == :gem_gpu
            <<~CPP.lines.map { |line| "              #{line}" }.join.chomp
              unsigned int remaining = n;
              unsigned int ran = 0u;
              unsigned int chunk = GEM_DISPATCH_CYCLE_GRANULARITY;
              uint64_t scaled_chunk = static_cast<uint64_t>(chunk) * 16384ull;
              if (GEM_EXECUTION_MODE == 1u && GEM_INSTRUCTION_COUNT > 0u) {
                uint64_t block_scale = GEM_BLOCK_COUNT > 0u ? static_cast<uint64_t>(GEM_BLOCK_COUNT) : 1ull;
                uint64_t stream_weight = static_cast<uint64_t>(GEM_INSTRUCTION_COUNT) +
                  static_cast<uint64_t>(GEM_STATE_READ_COUNT) +
                  static_cast<uint64_t>(GEM_CONTROL_STEP_COUNT);
                if (stream_weight == 0ull) { stream_weight = 1ull; }
                scaled_chunk = (scaled_chunk * block_scale) / stream_weight;
                uint64_t ready_layers = GEM_READY_LAYER_COUNT > 0u ? static_cast<uint64_t>(GEM_READY_LAYER_COUNT) : 1ull;
                scaled_chunk *= ready_layers;
                if (scaled_chunk == 0ull) { scaled_chunk = 1ull; }
              }
              if (scaled_chunk > 0x7FFFFFFFu) { scaled_chunk = 0x7FFFFFFFu; }
              chunk = static_cast<unsigned int>(scaled_chunk);
              if (chunk == 0u) { chunk = 1u; }
              while (remaining > 0u) {
                unsigned int step_target = remaining > chunk ? chunk : remaining;
                unsigned int step_progress = 0u;

                if (GEM_EXECUTION_MODE == 1u && GEM_DYNAMIC_SCHEDULER_ENABLED == 1u && GEM_SCHEDULER_MODE == 1u) {
                  unsigned int layer_count = GEM_READY_LAYER_COUNT > 0u ? GEM_READY_LAYER_COUNT : 1u;
                  unsigned int remaining_weight = GEM_READY_LAYER_OFFSETS[layer_count];
                  if (remaining_weight == 0u) { remaining_weight = layer_count; }

                  for (uint32_t layer = 0u; layer < layer_count && step_progress < step_target; ++layer) {
                    uint32_t layer_begin = GEM_READY_LAYER_OFFSETS[layer];
                    uint32_t layer_end = GEM_READY_LAYER_OFFSETS[layer + 1u];
                    uint32_t layer_weight = layer_end > layer_begin ? (layer_end - layer_begin) : 1u;

                    unsigned int remaining_step = step_target - step_progress;
                    unsigned int layer_budget = remaining_step;
                    if ((layer + 1u) < layer_count) {
                      uint64_t weighted = static_cast<uint64_t>(remaining_step) * static_cast<uint64_t>(layer_weight);
                      layer_budget = static_cast<unsigned int>(weighted / static_cast<uint64_t>(remaining_weight));
                      if (layer_budget == 0u) { layer_budget = 1u; }
                      if (layer_budget > remaining_step) { layer_budget = remaining_step; }
                    }

                    for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                      RhdlArcGpuIo* io = [s ioForInstance:instance];
                      io->cycle_budget = layer_budget;
                    }
                    if (![s dispatch]) { break; }

                    unsigned int layer_ran = 0xFFFFFFFFu;
                    for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                      RhdlArcGpuIo* io = [s ioForInstance:instance];
                      if (io->cycles_ran < layer_ran) { layer_ran = io->cycles_ran; }
                    }
                    if (layer_ran == 0xFFFFFFFFu) { layer_ran = 0u; }
                    step_progress += layer_ran;
                    if (layer_ran == 0u || layer_ran < layer_budget) { break; }
                    if (remaining_weight > layer_weight) {
                      remaining_weight -= layer_weight;
                    } else {
                      remaining_weight = 1u;
                    }
                  }
                } else {
                  for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                    RhdlArcGpuIo* io = [s ioForInstance:instance];
                    io->cycle_budget = step_target;
                  }
                  if (![s dispatch]) { break; }
                  unsigned int step_ran = 0xFFFFFFFFu;
                  for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                    RhdlArcGpuIo* io = [s ioForInstance:instance];
                    if (io->cycles_ran < step_ran) { step_ran = io->cycles_ran; }
                  }
                  if (step_ran == 0xFFFFFFFFu) { step_ran = 0u; }
                  step_progress = step_ran;
                }

                ran += step_progress;
                if (step_progress == 0u || step_progress < step_target) { break; }
                remaining -= step_progress;
              }
              return ran;
            CPP
          else
            <<~CPP.lines.map { |line| "              #{line}" }.join.chomp
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                RhdlArcGpuIo* io = [s ioForInstance:instance];
                io->cycle_budget = n;
              }
              if (![s dispatch]) { return 0u; }
              unsigned int min_cycles = 0xFFFFFFFFu;
              for (uint32_t instance = 0u; instance < INSTANCE_COUNT; ++instance) {
                RhdlArcGpuIo* io = [s ioForInstance:instance];
                if (io->cycles_ran < min_cycles) { min_cycles = io->cycles_ran; }
              }
              return (min_cycles == 0xFFFFFFFFu) ? 0u : min_cycles;
            CPP
          end
        end
      end
    end
  end
end
