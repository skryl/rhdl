# frozen_string_literal: true

# Apple II Metal Runner
#
# Pipeline:
#   RHDL -> FIRRTL -> firtool (HW MLIR) -> arcilator (--until-after=arc-opt)
#   -> ArcToGpuLowering(profile: :apple2) -> Metal shader -> native Metal executor
#
# This runner preserves the Apple II runner ABI exposed by ArcilatorRunner
# (`sim_*` functions) while executing circuit eval on the generated Metal kernel.

require_relative 'arcilator_runner'
require 'rhdl/codegen/firrtl/arc_to_gpu_lowering'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

module RHDL
  module Examples
    module Apple2
      class MetalRunner < ArcilatorRunner
        BUILD_DIR = File.expand_path('../../../.metal_build', __dir__)

        REQUIRED_TOOLS = %w[firtool arcilator].freeze

        def self.status
          missing_tools = []
          REQUIRED_TOOLS.each { |tool| missing_tools << tool unless command_available?(tool) }

          unless command_available?('llc') || command_available?('clang')
            missing_tools << 'llc/clang'
          end

          if macos_host?
            missing_tools << 'xcrun' unless command_available?('xcrun')
            missing_tools << 'metal' unless command_success?(%w[xcrun -f metal])
            missing_tools << 'metallib' unless command_success?(%w[xcrun -f metallib])
            missing_tools << 'clang++/c++' unless command_available?('clang++') || command_available?('c++')
          else
            missing_tools << 'macOS Metal toolchain'
          end

          {
            ready: missing_tools.empty?,
            missing_tools: missing_tools.uniq
          }
        end

        def self.available?
          status[:ready]
        end

        def self.ensure_available!
          info = status
          return info if info[:ready]

          raise ArgumentError,
            "metal backend unavailable (missing tools: #{info[:missing_tools].join(', ')}). " \
            "Install CIRCT tools and the macOS Metal toolchain."
        end

        attr_reader :instance_count

        def initialize(sub_cycles: 14, instances: nil)
          @sub_cycles = sub_cycles.clamp(1, 14)
          @instance_count = normalize_instance_count(instances)
          self.class.ensure_available!

          puts 'Initializing Apple2 Metal simulation...'
          start_time = Time.now

          build_metal_simulation

          elapsed = Time.now - start_time
          puts "  Metal simulation built in #{elapsed.round(2)}s"
          puts "  Sub-cycles: #{@sub_cycles} (#{@sub_cycles == 14 ? 'full accuracy' : 'fast mode'})"
          puts "  Instances: #{@instance_count}"

          @cycles = 0
          @halted = false
          @text_page_dirty = false
          @ram = Array.new(48 * 1024, 0)
          @rom = Array.new(12 * 1024, 0)
          @ps2_encoder = PS2Encoder.new
          @speaker = Speaker.new
          @prev_speaker_state = 0
        end

        def simulator_type
          :hdl_metal
        end

        def dry_run_info
          {
            mode: :metal,
            simulator_type: :hdl_metal,
            native: true,
            instances: @instance_count
          }
        end

        private

        def build_metal_simulation
          FileUtils.mkdir_p(BUILD_DIR)

          fir_file = File.join(BUILD_DIR, 'apple2.fir')
          hw_mlir_file = File.join(BUILD_DIR, 'apple2_hw.mlir')
          arc_mlir_file = File.join(BUILD_DIR, 'apple2_arc.mlir')
          gpu_mlir_file = File.join(BUILD_DIR, 'apple2_arc_to_gpu.mlir')
          gpu_meta_file = File.join(BUILD_DIR, 'apple2_arc_to_gpu.json')
          metal_source_file = File.join(BUILD_DIR, 'apple2_arc_to_gpu.metal')
          metal_air_file = File.join(BUILD_DIR, 'apple2_arc_to_gpu.air')
          metal_lib_file = File.join(BUILD_DIR, 'apple2_arc_to_gpu.metallib')
          wrapper_file = File.join(BUILD_DIR, 'apple2_arcgpu_wrapper.mm')
          log_file = File.join(BUILD_DIR, 'apple2_metal.log')

          File.delete(log_file) if File.exist?(log_file)

          export_firrtl(fir_file)
          run_or_raise(%W[firtool #{fir_file} --ir-hw -o #{hw_mlir_file}], 'firtool HW lowering', log_file)
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
            profile: :apple2
          )

          module_cache_dir = File.join(BUILD_DIR, 'clang_module_cache')
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

          write_wrapper(
            path: wrapper_file,
            metadata_path: gpu_meta_file,
            metallib_path: metal_lib_file,
            instance_count: @instance_count
          )
          link_shared_library(wrapper_file, shared_lib_path, log_file: log_file)
          load_shared_library(shared_lib_path)
          if !@sim_ctx || (@sim_ctx.respond_to?(:to_i) && @sim_ctx.to_i.zero?)
            raise LoadError,
              'Metal simulation context initialization failed (sim_create returned null). ' \
              'Check Metal pipeline/toolchain compatibility for generated ArcToGPU kernel.'
          end
        end

        def export_firrtl(path)
          components = [
            TimingGenerator,
            VideoGenerator,
            CharacterROM,
            SpeakerToggle,
            CPU6502,
            DiskII,
            DiskIIROM,
            Keyboard,
            PS2Controller,
            Apple2
          ]
          module_defs = components.map(&:to_ir)
          firrtl = RHDL::Codegen::FIRRTL.generate_hierarchy(module_defs, top_name: 'apple2_apple2')
          File.write(path, firrtl)
        end

        def link_shared_library(wrapper_file, output_file, log_file:)
          cxx = if command_available?('clang++')
            'clang++'
          else
            'c++'
          end

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

        def write_wrapper(path:, metadata_path:, metallib_path:, instance_count:)
          metadata = JSON.parse(File.read(metadata_path))
          state_count = metadata.dig('metal', 'state_count').to_i
          state_scalar_bits = metadata.dig('metal', 'state_scalar_bits').to_i
          state_scalar_bits = 32 if state_scalar_bits <= 0
          state_scalar_cpp_type = state_scalar_bits > 32 ? 'uint64_t' : 'uint32_t'
          kernel_name = metadata.dig('metal', 'entry').to_s
          input_layout = Array(metadata['top_input_layout'])
          output_layout = Array(metadata['top_output_layout'])

          raise LoadError, 'ArcToGPU metadata missing metal entry' if kernel_name.empty?
          raise LoadError, 'ArcToGPU metadata missing state_count' if state_count <= 0

          input_field_names = input_layout.map { |entry| cpp_ident(entry.fetch('name')) }
          output_field_names = output_layout.map { |entry| cpp_ident(entry.fetch('name')) }
          widths = {}
          input_layout.each { |entry| widths[entry.fetch('name')] = entry.fetch('width').to_i }
          output_layout.each { |entry| widths[entry.fetch('name')] = entry.fetch('width').to_i }

          struct_input_fields = input_layout.map { |entry| "  uint32_t #{cpp_ident(entry.fetch('name'))};" }
          struct_output_fields = output_layout.map { |entry| "  uint32_t #{cpp_ident(entry.fetch('name'))};" }

          poke_cases = input_layout.map do |entry|
            name = entry.fetch('name')
            field = cpp_ident(name)
            width = entry.fetch('width').to_i
            <<~CPP
              if (!strcmp(name, "#{name}")) {
                io[0].#{field} = mask_width(value, #{width}u);
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
                return io[0].#{field} & #{mask_literal(width)};
              }
            CPP
          end

          default_lines = []
          default_lines << 'io->reset = 1u;' if input_field_names.include?(cpp_ident('reset'))
          default_lines << 'io->clk_14m = 0u;' if input_field_names.include?(cpp_ident('clk_14m'))
          default_lines << 'io->flash_clk = 0u;' if input_field_names.include?(cpp_ident('flash_clk'))
          default_lines << 'io->ps2_clk = 1u;' if input_field_names.include?(cpp_ident('ps2_clk'))
          default_lines << 'io->ps2_data = 1u;' if input_field_names.include?(cpp_ident('ps2_data'))
          default_lines << 'io->pause = 0u;' if input_field_names.include?(cpp_ident('pause'))
          default_lines << 'io->ram_do = 0u;' if input_field_names.include?(cpp_ident('ram_do'))
          default_lines << 'io->pd = 0u;' if input_field_names.include?(cpp_ident('pd'))
          default_lines << 'io->gameport = 0u;' if input_field_names.include?(cpp_ident('gameport'))

          reset_assert_line = input_field_names.include?(cpp_ident('reset')) ? 'io[0].reset = 1u;' : ''
          reset_deassert_line = input_field_names.include?(cpp_ident('reset')) ? 'io[0].reset = 0u;' : ''

          wrapper = <<~CPP
            #import <Foundation/Foundation.h>
            #import <Metal/Metal.h>
            #include <CoreFoundation/CoreFoundation.h>
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>
            #include <cstdio>

            static const uint32_t STATE_COUNT = #{state_count}u;
            static const uint32_t STATE_SCALAR_BITS = #{state_scalar_bits}u;
            static const uint32_t INSTANCE_COUNT = #{instance_count}u;
            static const uint32_t RAM_SIZE = 65536u;
            static const uint32_t ROM_SIZE = 12288u;
            static NSString* const kMetallibPath = @#{metallib_path.dump};
            static NSString* const kKernelName = @#{kernel_name.dump};
            using RhdlStateScalar = #{state_scalar_cpp_type};

            struct RhdlArcGpuIo {
              uint32_t cycle_budget;
              uint32_t cycles_ran;
              uint32_t last_clock;
              uint32_t prev_speaker;
              uint32_t speaker_toggles;
              uint32_t text_dirty;
            #{struct_input_fields.join("\n")}
            #{struct_output_fields.join("\n")}
            };

            static inline uint32_t mask_width(uint32_t value, uint32_t width) {
              if (width >= 32u) {
                return value;
              }
              return value & ((1u << width) - 1u);
            }

            @interface RhdlApple2MetalSim : NSObject
            @property(nonatomic, strong) id<MTLDevice> device;
            @property(nonatomic, strong) id<MTLCommandQueue> queue;
            @property(nonatomic, strong) id<MTLLibrary> library;
            @property(nonatomic, strong) id<MTLComputePipelineState> pipeline;
            @property(nonatomic, strong) id<MTLBuffer> stateBuffer;
            @property(nonatomic, strong) id<MTLBuffer> ramBuffer;
            @property(nonatomic, strong) id<MTLBuffer> romBuffer;
            @property(nonatomic, strong) id<MTLBuffer> ioBuffer;
            @property(nonatomic, assign) uint32_t instanceCount;
            - (instancetype)initWithMetallibPath:(NSString*)metallibPath kernelName:(NSString*)kernelName stateCount:(uint32_t)stateCount instanceCount:(uint32_t)instanceCount;
            - (BOOL)dispatchKernel;
            - (RhdlArcGpuIo*)io;
            - (RhdlStateScalar*)stateSlots;
            - (uint8_t*)ram;
            - (uint8_t*)rom;
            @end

            @implementation RhdlApple2MetalSim
            - (instancetype)initWithMetallibPath:(NSString*)metallibPath kernelName:(NSString*)kernelName stateCount:(uint32_t)stateCount instanceCount:(uint32_t)instanceCount {
              self = [super init];
              if (!self) {
                return nil;
              }
              self.instanceCount = instanceCount;

              self.device = MTLCreateSystemDefaultDevice();
              if (!self.device) {
                fprintf(stderr, "[apple2-metal] init failed: no MTL device\\n");
                return nil;
              }

              self.queue = [self.device newCommandQueue];
              if (!self.queue) {
                fprintf(stderr, "[apple2-metal] init failed: no command queue\\n");
                return nil;
              }

              NSError* error = nil;
              self.library = [self.device newLibraryWithFile:metallibPath error:&error];
              if (!self.library) {
                fprintf(stderr, "[apple2-metal] init failed: newLibraryWithFile %s\\n",
                        error ? [[error localizedDescription] UTF8String] : "unknown");
                return nil;
              }

              id<MTLFunction> fn = [self.library newFunctionWithName:kernelName];
              if (!fn) {
                fprintf(stderr, "[apple2-metal] init failed: missing kernel function %s\\n", [kernelName UTF8String]);
                return nil;
              }

              self.pipeline = [self.device newComputePipelineStateWithFunction:fn error:&error];
              if (!self.pipeline) {
                fprintf(stderr, "[apple2-metal] init failed: pipeline creation %s\\n",
                        error ? [[error localizedDescription] UTF8String] : "unknown");
                return nil;
              }

              self.stateBuffer = [self.device newBufferWithLength:sizeof(RhdlStateScalar) * stateCount * instanceCount options:MTLResourceStorageModeShared];
              self.ramBuffer = [self.device newBufferWithLength:RAM_SIZE * instanceCount options:MTLResourceStorageModeShared];
              self.romBuffer = [self.device newBufferWithLength:ROM_SIZE * instanceCount options:MTLResourceStorageModeShared];
              self.ioBuffer = [self.device newBufferWithLength:sizeof(RhdlArcGpuIo) * instanceCount options:MTLResourceStorageModeShared];
              if (!self.stateBuffer || !self.ramBuffer || !self.romBuffer || !self.ioBuffer) {
                fprintf(stderr, "[apple2-metal] init failed: buffer allocation\\n");
                return nil;
              }

              memset([self.stateBuffer contents], 0, sizeof(RhdlStateScalar) * stateCount * instanceCount);
              memset([self.ramBuffer contents], 0, RAM_SIZE * instanceCount);
              memset([self.romBuffer contents], 0, ROM_SIZE * instanceCount);
              memset([self.ioBuffer contents], 0, sizeof(RhdlArcGpuIo) * instanceCount);

              return self;
            }

            - (BOOL)dispatchKernel {
              id<MTLCommandBuffer> commandBuffer = [self.queue commandBuffer];
              if (!commandBuffer) {
                return NO;
              }
              id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
              if (!encoder) {
                return NO;
              }

              [encoder setComputePipelineState:self.pipeline];
              [encoder setBuffer:self.stateBuffer offset:0 atIndex:0];
              [encoder setBuffer:self.ramBuffer offset:0 atIndex:1];
              [encoder setBuffer:self.romBuffer offset:0 atIndex:2];
              [encoder setBuffer:self.ioBuffer offset:0 atIndex:3];

              MTLSize grid = MTLSizeMake(self.instanceCount, 1, 1);
              MTLSize tg = MTLSizeMake(1, 1, 1);
              [encoder dispatchThreads:grid threadsPerThreadgroup:tg];
              [encoder endEncoding];

              [commandBuffer commit];
              [commandBuffer waitUntilCompleted];
              if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
                NSError* cbError = commandBuffer.error;
                if (cbError) {
                  fprintf(stderr, "[apple2-metal] command buffer error: %s\\n", [[cbError localizedDescription] UTF8String]);
                }
                return NO;
              }
              return YES;
            }

            - (RhdlArcGpuIo*)io { return reinterpret_cast<RhdlArcGpuIo*>([self.ioBuffer contents]); }
            - (RhdlStateScalar*)stateSlots { return reinterpret_cast<RhdlStateScalar*>([self.stateBuffer contents]); }
            - (uint8_t*)ram { return reinterpret_cast<uint8_t*>([self.ramBuffer contents]); }
            - (uint8_t*)rom { return reinterpret_cast<uint8_t*>([self.romBuffer contents]); }
            @end

            static inline RhdlApple2MetalSim* as_sim(void* sim) {
              return (__bridge RhdlApple2MetalSim*)sim;
            }

            static inline unsigned int run_cycles_internal(RhdlApple2MetalSim* sim, unsigned int n, unsigned int* dirty_out) {
              if (!sim) {
                if (dirty_out) { *dirty_out = 0u; }
                return 0u;
              }
              RhdlArcGpuIo* io = [sim io];
              for (uint32_t i = 0; i < sim.instanceCount; ++i) {
                io[i].cycle_budget = n;
                io[i].speaker_toggles = 0u;
                io[i].text_dirty = 0u;
              }
              if (![sim dispatchKernel]) {
                io[0].cycles_ran = 0u;
                if (dirty_out) { *dirty_out = 0u; }
                return 0u;
              }
              if (dirty_out) {
                uint32_t any_dirty = 0u;
                for (uint32_t i = 0; i < sim.instanceCount; ++i) {
                  any_dirty |= (io[i].text_dirty & 1u);
                }
                *dirty_out = any_dirty;
              }
              return io[0].speaker_toggles;
            }

            extern "C" {
            void* sim_create(void) {
              @autoreleasepool {
                RhdlApple2MetalSim* sim = [[RhdlApple2MetalSim alloc] initWithMetallibPath:kMetallibPath kernelName:kKernelName stateCount:STATE_COUNT instanceCount:INSTANCE_COUNT];
                if (!sim) {
                  fprintf(stderr, "[apple2-metal] sim_create failed during init\\n");
                  return nullptr;
                }
                RhdlArcGpuIo* io = [sim io];
            #{indent_cpp(default_lines.map { |line| line.sub('io->', 'io[0].') })}
                for (uint32_t i = 0; i < sim.instanceCount; ++i) {
                  io[i] = io[0];
                }
                io[0].cycle_budget = 0u;
                io[0].last_clock = io[0].#{cpp_ident('clk_14m')};
                if (![sim dispatchKernel]) {
                  fprintf(stderr, "[apple2-metal] sim_create failed initial dispatch\\n");
                  return nullptr;
                }
                return (__bridge_retained void*)sim;
              }
            }

            void sim_destroy(void* sim) {
              if (!sim) {
                return;
              }
              @autoreleasepool {
                CFBridgingRelease(sim);
              }
            }

            void sim_eval(void* sim) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s) {
                return;
              }
              RhdlArcGpuIo* io = [s io];
              io[0].cycle_budget = 0u;
              (void)[s dispatchKernel];
            }

            void sim_reset(void* sim) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s) {
                return;
              }
              RhdlArcGpuIo* io = [s io];
            #{indent_cpp([reset_assert_line])}
              unsigned int dirty = 0u;
              (void)run_cycles_internal(s, 14u, &dirty);
            #{indent_cpp([reset_deassert_line])}
              (void)run_cycles_internal(s, 140u, &dirty);
              io[0].cycle_budget = 0u;
              io[0].speaker_toggles = 0u;
              io[0].text_dirty = 0u;
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s || !name) {
                return;
              }
              RhdlArcGpuIo* io = [s io];
            #{indent_cpp(poke_cases)}
            }

            unsigned int sim_peek(void* sim, const char* name) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s || !name) {
                return 0u;
              }
              RhdlArcGpuIo* io = [s io];
            #{indent_cpp(peek_cases)}
              if (!strcmp(name, "cycle_budget")) { return io[0].cycle_budget; }
              if (!strcmp(name, "cycles_ran")) { return io[0].cycles_ran; }
              if (!strcmp(name, "last_clock")) { return io[0].last_clock; }
              if (!strcmp(name, "speaker_toggles")) { return io[0].speaker_toggles; }
              if (!strcmp(name, "text_dirty")) { return io[0].text_dirty; }
              return 0u;
            }

            void sim_write_ram(void* sim, unsigned int addr, unsigned char value) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s) {
                return;
              }
              if (addr < RAM_SIZE) {
                uint8_t* ram = [s ram];
                for (uint32_t i = 0; i < s.instanceCount; ++i) {
                  ram[(i * RAM_SIZE) + addr] = value;
                }
              }
            }

            unsigned char sim_read_ram(void* sim, unsigned int addr) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s) {
                return 0u;
              }
              if (addr < RAM_SIZE) {
                return [s ram][addr];
              }
              return 0u;
            }

            void sim_write_rom(void* sim, unsigned int offset, unsigned char value) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s) {
                return;
              }
              if (offset < ROM_SIZE) {
                uint8_t* rom = [s rom];
                uint8_t* ram = [s ram];
                for (uint32_t i = 0; i < s.instanceCount; ++i) {
                  rom[(i * ROM_SIZE) + offset] = value;
                  ram[(i * RAM_SIZE) + 0xD000u + offset] = value;
                }
              }
            }

            unsigned int sim_run_cycles(void* sim, unsigned int n, unsigned int* dirty) {
              RhdlApple2MetalSim* s = as_sim(sim);
              return run_cycles_internal(s, n, dirty);
            }

            void sim_load_ram(void* sim, const unsigned char* data, unsigned int offset, unsigned int len) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s || !data) {
                return;
              }
              uint8_t* ram = [s ram];
              for (uint32_t inst = 0; inst < s.instanceCount; ++inst) {
                uint32_t base = inst * RAM_SIZE;
                for (unsigned int i = 0; i < len; ++i) {
                  unsigned int addr = offset + i;
                  if (addr >= RAM_SIZE) {
                    break;
                  }
                  ram[base + addr] = data[i];
                }
              }
            }

            void sim_load_rom(void* sim, const unsigned char* data, unsigned int len) {
              RhdlApple2MetalSim* s = as_sim(sim);
              if (!s || !data) {
                return;
              }
              uint8_t* rom = [s rom];
              uint8_t* ram = [s ram];
              unsigned int n = (len < ROM_SIZE) ? len : ROM_SIZE;
              for (uint32_t inst = 0; inst < s.instanceCount; ++inst) {
                uint32_t rom_base = inst * ROM_SIZE;
                uint32_t ram_base = inst * RAM_SIZE;
                for (unsigned int i = 0; i < n; ++i) {
                  rom[rom_base + i] = data[i];
                  ram[ram_base + 0xD000u + i] = data[i];
                }
              }
            }
            } // extern "C"
          CPP

          File.write(path, wrapper)
        end

        def run_or_raise(cmd, step_name, log_file)
          out, status = Open3.capture2e(*cmd)
          File.write(log_file, out, mode: 'a')
          return if status.success?

          raise LoadError, "#{step_name} failed: #{last_log_lines(log_file)}"
        end

        def last_log_lines(path, count: 8)
          return 'unknown error' unless File.exist?(path)

          File.read(path).lines.last(count).join.strip
        rescue StandardError
          'unknown error'
        end

        def shared_lib_path
          ext = if RbConfig::CONFIG['host_os'] =~ /darwin/
            '.dylib'
          elsif RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
            '.dll'
          else
            '.so'
          end
          File.join(BUILD_DIR, "libapple2_metal_sim#{ext}")
        end

        def cpp_ident(name)
          name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
        end

        def mask_literal(width)
          w = width.to_i
          return '0xFFFFFFFFu' if w >= 32
          format('0x%Xu', (1 << w) - 1)
        end

        def indent_cpp(lines, spaces: 12)
          lines = Array(lines).reject { |line| line.to_s.empty? }
          return '' if lines.empty?

          prefix = ' ' * spaces
          lines.map { |line| "#{prefix}#{line}" }.join("\n")
        end

        def normalize_instance_count(instances)
          raw = instances || ENV['RHDL_APPLE2_METAL_INSTANCES']
          value = raw.to_i
          value = 1 if value <= 0
          [value, 1024].min
        end

        class << self
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
      end
    end
  end
end
