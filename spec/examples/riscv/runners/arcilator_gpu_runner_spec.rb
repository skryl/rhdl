# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../examples/riscv/utilities/runners/arcilator_gpu_runner'

RSpec.describe RHDL::Examples::RISCV::ArcilatorGpuRunner do
  describe '#compile_metal_shader' do
    it 'clears the clang module cache before compiling the Metal shader' do
      Dir.mktmpdir('riscv-arcilator-gpu-runner-spec') do |dir|
        runner = described_class.allocate

        allow(runner).to receive(:build_dir).and_return(dir)
        allow(runner).to receive(:run_or_raise)
        allow(FileUtils).to receive(:mkdir_p).and_call_original
        allow(FileUtils).to receive(:rm_rf).and_call_original

        module_cache_dir = File.join(dir, 'clang_module_cache')
        FileUtils.mkdir_p(module_cache_dir)
        File.write(File.join(module_cache_dir, 'stale.pcm'), 'stale')

        runner.send(
          :compile_metal_shader,
          metal_source_file: File.join(dir, 'kernel.metal'),
          metal_air_file: File.join(dir, 'kernel.air'),
          metal_lib_file: File.join(dir, 'kernel.metallib'),
          log_file: File.join(dir, 'build.log')
        )

        expect(FileUtils).to have_received(:rm_rf).with(module_cache_dir)
        expect(File.exist?(File.join(module_cache_dir, 'stale.pcm'))).to be(false)
      end
    end
  end

  describe '#build_config_signature' do
    it 'tracks the absolute build directory so repo moves invalidate stale GPU artifacts' do
      runner = described_class.allocate
      allow(runner).to receive(:build_dir).and_return('/tmp/riscv-gpu-build')
      runner.instance_variable_set(:@shared_lib_name, 'libriscv_arcilator_gpu_sim.so')

      signature = runner.send(:build_config_signature)

      expect(signature['build_dir']).to eq('/tmp/riscv-gpu-build')
    end
  end

  describe '#write_wrapper' do
    it 'resolves the metallib relative to the loaded shared library at runtime' do
      Dir.mktmpdir('riscv-arcilator-gpu-wrapper-spec') do |dir|
        metadata_path = File.join(dir, 'metadata.json')
        output_path = File.join(dir, 'wrapper.mm')

        File.write(
          metadata_path,
          JSON.pretty_generate(
            {
              'metal' => {
                'state_count' => 1,
                'state_scalar_bits' => 32,
                'entry' => 'kernel',
                'runtime_input_layout' => [],
                'runtime_output_layout' => []
              },
              'state_layout' => []
            }
          )
        )

        runner = described_class.allocate
        runner.instance_variable_set(:@build_variant, 'arcilator_gpu')

        runner.send(
          :write_wrapper,
          path: output_path,
          metadata_path: metadata_path,
          metallib_path: '/tmp/stale/riscv_cpu_arc_to_gpu.metallib'
        )

        wrapper = File.read(output_path)
        expect(wrapper).to include('#include <dlfcn.h>')
        expect(wrapper).to include('resolveMetallibPath()')
        expect(wrapper).to include('stringByDeletingLastPathComponent')
        expect(wrapper).to include('kMetallibFilename')
      end
    end
  end

  describe '#validate_sim_context!' do
    it 'raises when sim_create returns a null simulation context' do
      runner = described_class.allocate
      runner.instance_variable_set(:@sim_ctx, 0)

      expect { runner.send(:validate_sim_context!) }
        .to raise_error(LoadError, /sim_create returned null/i)
    end
  end
end
