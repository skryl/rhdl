# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../../examples/8bit/utilities/runners/arcilator_gpu_runner'

RSpec.describe RHDL::Examples::CPU8Bit::ArcilatorGpuRunner do
  around do |example|
    original_cpu8bit_instances = ENV['RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES']
    original_bench_instances = ENV['RHDL_BENCH_ARCILATOR_GPU_INSTANCES']
    begin
      example.run
    ensure
      ENV['RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES'] = original_cpu8bit_instances
      ENV['RHDL_BENCH_ARCILATOR_GPU_INSTANCES'] = original_bench_instances
    end
  end

  describe '.detect_gpu_option_tokens' do
    around do |example|
      original = ENV['RHDL_ARCILATOR_GPU_OPTION']
      begin
        example.run
      ensure
        ENV['RHDL_ARCILATOR_GPU_OPTION'] = original
      end
    end

    it 'prefers explicit environment override' do
      ENV['RHDL_ARCILATOR_GPU_OPTION'] = '--lowering=arc-to-gpu --emit-metal'

      tokens = described_class.detect_gpu_option_tokens('arcilator help text without gpu option')
      expect(tokens).to eq(['--lowering=arc-to-gpu', '--emit-metal'])
    end

    it 'detects ArcToGPU option from arcilator help text' do
      tokens = described_class.detect_gpu_option_tokens("Usage:\n  --arc-to-gpu  Lower ARC dialect to GPU\n")
      expect(tokens).to eq(['--arc-to-gpu'])
    end
  end

  describe '.status' do
    before do
      allow(described_class).to receive(:macos_host?).and_return(false)
      allow(described_class).to receive(:command_success?).and_return(true)
    end

    it 'reports ready when tools are available' do
      allow(described_class).to receive(:command_available?).and_return(true)
      allow(described_class).to receive(:command_output).with(%w[arcilator --help]).and_return('--arc-to-gpu')

      status = described_class.status
      expect(status[:ready]).to be(true)
      expect(status[:missing_tools]).to eq([])
      expect(status[:missing_capabilities]).to eq([])
      expect(status[:gpu_option_tokens]).to eq(['--arc-to-gpu'])
    end

    it 'remains ready when no gpu option is advertised in arcilator help' do
      allow(described_class).to receive(:command_available?).and_return(true)
      allow(described_class).to receive(:command_output).with(%w[arcilator --help]).and_return('--help')

      status = described_class.status
      expect(status[:ready]).to be(true)
      expect(status[:missing_capabilities]).to eq([])
      expect(status[:gpu_option_tokens]).to eq([])
    end
  end

  describe '#build_simulation' do
    def with_build_dir(dir)
      original = described_class::BUILD_DIR
      described_class.send(:remove_const, :BUILD_DIR)
      described_class.const_set(:BUILD_DIR, dir)
      yield
    ensure
      described_class.send(:remove_const, :BUILD_DIR)
      described_class.const_set(:BUILD_DIR, original)
    end

    def write_artifact(path, contents = 'artifact')
      File.write(path, contents)
    end

    def exercise_build_simulation(dir)
      with_build_dir(dir) do
        runner = described_class.allocate
        shared_lib_path = runner.send(:shared_lib_path)
        fir_file = File.join(dir, 'cpu8bit.fir')
        mlir_file = File.join(dir, 'cpu8bit_hw.mlir')
        ll_file = File.join(dir, 'cpu8bit_arcgpu.ll')
        state_file = File.join(dir, 'cpu8bit_state.json')
        obj_file = File.join(dir, 'cpu8bit_arcgpu.o')
        wrapper_file = File.join(dir, 'cpu8bit_arcgpu_wrapper.cpp')

        [
          fir_file,
          mlir_file,
          ll_file,
          state_file,
          obj_file,
          wrapper_file,
          shared_lib_path
        ].each { |path| write_artifact(path) }

        allow(runner).to receive(:write_file_if_changed).and_return(false)
        allow(runner).to receive(:write_wrapper).and_return(false)
        allow(runner).to receive(:compile_with_arcilator)
        allow(runner).to receive(:link_shared_library)

        yield runner, fir_file, mlir_file, ll_file, state_file, obj_file, wrapper_file, shared_lib_path
      end
    end

    it 'rebuilds generated GPU objects when the runner source is newer than the cached object' do
      Dir.mktmpdir('arcilator-gpu-runner-spec') do |dir|
        exercise_build_simulation(dir) do |runner, fir_file, mlir_file, ll_file, state_file, obj_file, wrapper_file, shared_lib_path|
          stale = Time.at(0)
          File.utime(stale, stale, obj_file)

          runner.send(:build_simulation)

          expect(runner).to have_received(:compile_with_arcilator).with(fir_file, mlir_file, ll_file, state_file, obj_file)
          expect(runner).to have_received(:link_shared_library).with(wrapper_file, obj_file, shared_lib_path)
        end
      end
    end

    it 'relinks when the shared library is older than the generated wrapper and object' do
      Dir.mktmpdir('arcilator-gpu-runner-spec') do |dir|
        exercise_build_simulation(dir) do |runner, _fir_file, _mlir_file, _ll_file, _state_file, obj_file, wrapper_file, shared_lib_path|
          fresh = Time.now + 60
          stale = Time.at(0)
          File.utime(fresh, fresh, obj_file)
          File.utime(fresh, fresh, wrapper_file)
          File.utime(stale, stale, shared_lib_path)

          runner.send(:build_simulation)

          expect(runner).not_to have_received(:compile_with_arcilator)
          expect(runner).to have_received(:link_shared_library).with(wrapper_file, obj_file, shared_lib_path)
        end
      end
    end
  end

  describe 'instance count' do
    let(:runner) { described_class.allocate }

    it 'defaults to one instance' do
      ENV.delete('RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES')
      ENV.delete('RHDL_BENCH_ARCILATOR_GPU_INSTANCES')

      expect(runner.send(:normalize_instance_count, nil)).to eq(1)
    end

    it 'uses the CPU8bit-specific instance env var' do
      ENV['RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES'] = '8'
      ENV['RHDL_BENCH_ARCILATOR_GPU_INSTANCES'] = '4'

      expect(runner.send(:normalize_instance_count, nil)).to eq(8)
    end

    it 'falls back to the benchmark-wide instance env var' do
      ENV.delete('RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES')
      ENV['RHDL_BENCH_ARCILATOR_GPU_INSTANCES'] = '16'

      expect(runner.send(:normalize_instance_count, nil)).to eq(16)
    end

    it 'clamps the instance count to the maximum' do
      ENV['RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES'] = '999999'

      expect(runner.send(:normalize_instance_count, nil)).to eq(described_class::MAX_INSTANCE_COUNT)
    end

    it 'reports the configured parallel instance count' do
      allow(described_class).to receive(:ensure_available!).and_return({})
      allow_any_instance_of(described_class).to receive(:build_simulation)
      allow_any_instance_of(described_class).to receive(:load_library)
      allow_any_instance_of(described_class).to receive(:reset)

      instance = described_class.new(instances: 12)
      expect(instance.runner_parallel_instances).to eq(12)
    end
  end
end
