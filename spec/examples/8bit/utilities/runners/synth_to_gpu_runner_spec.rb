# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../../../examples/8bit/utilities/runners/synth_to_gpu_runner'

RSpec.describe RHDL::Examples::CPU8Bit::SynthToGpuRunner do
  def base_metadata
    {
      'metal' => {
        'state_count' => 2,
        'state_scalar_bits' => 32,
        'entry' => 'cpu8bit_arcgpu_kernel'
      },
      'top_input_layout' => [
        { 'name' => 'rst', 'width' => 1 }
      ],
      'top_output_layout' => [
        { 'name' => 'halted', 'width' => 1 }
      ],
      'state_layout' => [
        { 'index' => 0, 'width' => 16 }
      ],
      'poke_alias_state_slots' => {}
    }
  end

  def write_wrapper_for(pipeline:, metadata:, instances: 1, execution_mode: nil)
    Dir.mktmpdir('cpu8bit_synth_to_gpu_runner_spec') do |dir|
      metadata_path = File.join(dir, 'metadata.json')
      wrapper_path = File.join(dir, 'wrapper.mm')
      File.write(metadata_path, JSON.pretty_generate(metadata))

      runner = described_class.allocate
      runner.instance_variable_set(:@pipeline, pipeline)
      runner.instance_variable_set(:@parallel_instances, instances)
      if pipeline == :gem_gpu
        mode = execution_mode || :instruction_stream
        runner.instance_variable_set(:@gem_execution_mode, mode)
      end
      runner.send(:write_wrapper, path: wrapper_path, metadata_path: metadata_path, metallib_path: '/tmp/fake.metallib')
      return File.read(wrapper_path)
    end
  end

  describe '#write_wrapper' do
    it 'embeds GEM schedule constants and chunked cycle loop for gem_gpu pipeline' do
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        instances: 8,
        metadata: base_metadata.merge(
          'gem' => {
            'partition_count' => 4,
            'max_layer_depth' => 5,
            'execution' => {
              'dispatch_cycle_granularity' => 20
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_PARTITION_COUNT = 4u;')
      expect(wrapper).to include('static const uint32_t GEM_LAYER_DEPTH = 5u;')
      expect(wrapper).to include('static const uint32_t GEM_DISPATCH_CYCLE_GRANULARITY = 20u;')
      expect(wrapper).to include('static const uint32_t GEM_EXECUTION_MODE = 1u;')
      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_COUNT = 0u;')
      expect(wrapper).to include('static const uint32_t GEM_STATE_READ_COUNT = 0u;')
      expect(wrapper).to include('static const uint32_t GEM_CONTROL_STEP_COUNT = 0u;')
      expect(wrapper).to include('static const uint32_t GEM_DEPENDENCY_EDGE_COUNT = 0u;')
      expect(wrapper).to include('static const uint32_t GEM_READY_LAYER_COUNT = 0u;')
      expect(wrapper).to include('static const uint32_t GEM_SCHEDULER_MODE = (GEM_DEPENDENCY_EDGE_COUNT > 0u && GEM_READY_LAYER_COUNT > 1u) ? 1u : 0u;')
      expect(wrapper).to include('static const uint32_t GEM_DYNAMIC_SCHEDULER_ENABLED = 1u;')
      expect(wrapper).to include('static const uint32_t GEM_READY_LAYER_OFFSETS[2] = { 0u, 1u };')
      expect(wrapper).to include('static const uint32_t GEM_READY_LAYER_PARTITIONS[1] = { 0u };')
      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORD_COUNT = 15u;')
      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORDS[15] = { 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u };')
      expect(wrapper).to include('unsigned int sim_execution_mode(void* sim)')
      expect(wrapper).to include('unsigned int sim_scheduler_mode(void* sim)')
      expect(wrapper).to include('static const uint32_t INSTANCE_COUNT = 8u;')
      expect(wrapper).to include('dispatchThreads:gridSize threadsPerThreadgroup:groupSize')
      expect(wrapper).to include('[enc setBuffer:self.instructionBuffer offset:0 atIndex:3];')
      expect(wrapper).to include('ioForInstance')
      expect(wrapper).to include('sim_parallel_instances')
      expect(wrapper).to include('while (remaining > 0u)')
      expect(wrapper).to include('unsigned int step_target = remaining > chunk ? chunk : remaining;')
      expect(wrapper).to include('return ran;')
    end

    it 'keeps single-dispatch runner loop for non-gem pipelines' do
      wrapper = write_wrapper_for(pipeline: :synth_to_gpu, metadata: base_metadata)

      expect(wrapper).to include('io->cycle_budget = n;')
      expect(wrapper).to include('unsigned int min_cycles = 0xFFFFFFFFu;')
      expect(wrapper).to include('return (min_cycles == 0xFFFFFFFFu) ? 0u : min_cycles;')
      expect(wrapper).not_to include('while (remaining > 0u)')
    end

    it 'embeds GEM instruction-stream metadata constants when present' do
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        execution_mode: :instruction_stream,
        metadata: base_metadata.merge(
          'gem' => {
            'partition_count' => 2,
            'max_layer_depth' => 4,
            'execution' => {
              'dispatch_cycle_granularity' => 8,
              'partition_dependency_edge_count' => 3,
              'ready_layer_count' => 2,
              'ready_layers' => [[0], [1, 2]]
            },
            'instruction_stream' => {
              'instruction_count' => 3,
              'block_boundaries' => [0, 2, 3],
              'extern_refs' => ['%cfalse', '%ctrue'],
              'instructions' => [
                {
                  'dst_node' => 0,
                  'src' => [
                    { 'kind' => 'extern', 'id' => 0, 'inverted' => false },
                    { 'kind' => 'extern', 'id' => 1, 'inverted' => false }
                  ]
                },
                {
                  'dst_node' => 1,
                  'src' => [
                    { 'kind' => 'node', 'id' => 0, 'inverted' => false },
                    { 'kind' => 'extern', 'id' => 0, 'inverted' => true }
                  ]
                },
                {
                  'dst_node' => 2,
                  'src' => [
                    { 'kind' => 'node', 'id' => 0, 'inverted' => false },
                    { 'kind' => 'node', 'id' => 1, 'inverted' => false }
                  ]
                }
              ],
              'primitive_counts' => {
                'state_read' => 5
              },
              'control_program' => [
                { 'op' => 'cycle_begin' },
                { 'op' => 'cycle_end' }
              ],
              'checksum_sha256' => '89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567'
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_COUNT = 3u;')
      expect(wrapper).to include('static const uint32_t GEM_BLOCK_COUNT = 2u;')
      expect(wrapper).to include('static const uint32_t GEM_STATE_READ_COUNT = 5u;')
      expect(wrapper).to include('static const uint32_t GEM_CONTROL_STEP_COUNT = 2u;')
      expect(wrapper).to include('static const uint32_t GEM_DEPENDENCY_EDGE_COUNT = 3u;')
      expect(wrapper).to include('static const uint32_t GEM_READY_LAYER_COUNT = 2u;')
      expect(wrapper).to include('static const uint32_t GEM_STREAM_CHECKSUM32 = 0x89abcdefu;')
      expect(wrapper).to include('static const uint32_t GEM_DYNAMIC_SCHEDULER_ENABLED = 0u;')
      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORD_COUNT = 31u;')
      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORDS[31] =')
      expect(wrapper).to include('{ 3u, 4u, 0u, 2u, 6u')
      expect(wrapper).to include(', 2u, 0u, 6u, 2u, 0u, 1u, 0u, 0u')
      expect(wrapper).to include('static const uint32_t GEM_READY_LAYER_OFFSETS[3] = { 0u, 1u, 3u };')
      expect(wrapper).to include('static const uint32_t GEM_READY_LAYER_PARTITIONS[3] = { 0u, 1u, 2u };')
      expect(wrapper).to include('if (GEM_EXECUTION_MODE == 1u && GEM_INSTRUCTION_COUNT > 0u)')
      expect(wrapper).to include('uint64_t stream_weight = static_cast<uint64_t>(GEM_INSTRUCTION_COUNT) +')
      expect(wrapper).to include('uint64_t ready_layers = GEM_READY_LAYER_COUNT > 0u ?')
      expect(wrapper).to include('if (GEM_EXECUTION_MODE == 1u && GEM_DYNAMIC_SCHEDULER_ENABLED == 1u && GEM_SCHEDULER_MODE == 1u)')
      expect(wrapper).to include('for (uint32_t layer = 0u; layer < layer_count && step_progress < step_target; ++layer)')
      expect(wrapper).to include('uint32_t layer_begin = GEM_READY_LAYER_OFFSETS[layer];')
      expect(wrapper).to include('uint32_t layer_weight = layer_end > layer_begin ? (layer_end - layer_begin) : 1u;')
    end

    it 'allows disabling dynamic scheduler via environment override' do
      old = ENV['RHDL_GEM_GPU_DYNAMIC_SCHEDULER']
      ENV['RHDL_GEM_GPU_DYNAMIC_SCHEDULER'] = '0'
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        execution_mode: :instruction_stream,
        metadata: base_metadata.merge(
          'gem' => {
            'partition_count' => 2,
            'max_layer_depth' => 4,
            'execution' => {
              'dispatch_cycle_granularity' => 8,
              'partition_dependency_edge_count' => 3,
              'ready_layer_count' => 2,
              'ready_layers' => [[0], [1]]
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_DYNAMIC_SCHEDULER_ENABLED = 0u;')
      expect(wrapper).to include('if (GEM_EXECUTION_MODE != 1u || GEM_DYNAMIC_SCHEDULER_ENABLED == 0u)')
    ensure
      if old.nil?
        ENV.delete('RHDL_GEM_GPU_DYNAMIC_SCHEDULER')
      else
        ENV['RHDL_GEM_GPU_DYNAMIC_SCHEDULER'] = old
      end
    end

    it 'packs output watch sources into instruction word payload' do
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        execution_mode: :instruction_stream,
        metadata: base_metadata.merge(
          'gem' => {
            'instruction_stream' => {
              'instruction_count' => 1,
              'extern_refs' => ['%cfalse'],
              'output_watch_override' => true,
              'instructions' => [
                {
                  'dst_node' => 0,
                  'src' => [
                    { 'kind' => 'extern', 'id' => 0, 'inverted' => false },
                    { 'kind' => 'extern', 'id' => 0, 'inverted' => true }
                  ]
                }
              ],
              'output_watch_sources' => [
                { 'kind' => 'node', 'id' => 0, 'inverted' => false },
                { 'kind' => 'extern', 'id' => 0, 'inverted' => true },
                { 'kind' => 'extern', 'id' => 0, 'inverted' => false },
                { 'kind' => 'extern', 'id' => 0, 'inverted' => false }
              ]
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORD_COUNT = 24u;')
      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORDS[24] = { 1u, 5u,')
      expect(wrapper).to include(', 4u, 0u, 3u, 2u, 2u, 0u, 1u, 0u, 0u, 0u')
    end

    it 'allows forcing output watch override via environment flag' do
      old = ENV['RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE']
      ENV['RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE'] = '1'
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        execution_mode: :instruction_stream,
        metadata: base_metadata.merge(
          'gem' => {
            'instruction_stream' => {
              'instruction_count' => 0,
              'extern_refs' => []
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORDS[15] = { 0u, 1u,')
    ensure
      if old.nil?
        ENV.delete('RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE')
      else
        ENV['RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE'] = old
      end
    end

    it 'packs extern source descriptors when present' do
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        execution_mode: :instruction_stream,
        metadata: base_metadata.merge(
          'state_layout' => [
            { 'index' => 0, 'width' => 16, 'result_ref' => '%pc_reg__q' }
          ],
          'gem' => {
            'instruction_stream' => {
              'instruction_count' => 0,
              'extern_refs' => ['%pc0', '%rst0', '%c1'],
              'extern_ref_values' => [0, 0, 1],
              'extern_sources' => [
                { 'kind' => 'state_bit', 'state_index' => 0, 'bit' => 3 },
                { 'kind' => 'io_bit', 'field' => 'rst', 'bit' => 0 },
                { 'kind' => 'const', 'value' => 1 }
              ]
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORDS[21] = { 0u, 12u,')
      expect(wrapper).to include(', 3u, 0u, 0u, 1u, 3u, 24577u, 2u, 8u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u };')
    end

    it 'packs watch-eval subset indices when present' do
      wrapper = write_wrapper_for(
        pipeline: :gem_gpu,
        execution_mode: :instruction_stream,
        metadata: base_metadata.merge(
          'gem' => {
            'instruction_stream' => {
              'instruction_count' => 3,
              'extern_refs' => [],
              'instructions' => [
                { 'dst_node' => 0, 'src' => [{ 'kind' => 'extern', 'id' => 0, 'inverted' => false }, { 'kind' => 'extern', 'id' => 0, 'inverted' => false }] },
                { 'dst_node' => 1, 'src' => [{ 'kind' => 'node', 'id' => 0, 'inverted' => false }, { 'kind' => 'extern', 'id' => 0, 'inverted' => false }] },
                { 'dst_node' => 2, 'src' => [{ 'kind' => 'node', 'id' => 1, 'inverted' => false }, { 'kind' => 'extern', 'id' => 0, 'inverted' => false }] }
              ],
              'watch_eval_indices' => [0, 2]
            }
          }
        )
      )

      expect(wrapper).to include('static const uint32_t GEM_INSTRUCTION_WORDS[29] = { 3u, 0u,')
      expect(wrapper).to include(', 0u, 0u, 0u, 0u, 2u, 0u, 2u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u };')
    end
  end
end
