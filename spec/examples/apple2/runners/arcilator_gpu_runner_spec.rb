# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../examples/apple2/utilities/runners/arcilator_gpu_runner'

RSpec.describe RHDL::Examples::Apple2::ArcilatorGpuRunner do
  describe '.status' do
    it 'reports ready when required tools are available' do
      allow(described_class).to receive(:command_available?).and_return(true)
      allow(described_class).to receive(:macos_host?).and_return(true)
      allow(described_class).to receive(:command_success?).and_return(true)

      status = described_class.status
      expect(status[:ready]).to be(true)
      expect(status[:missing_tools]).to eq([])
    end

    it 'reports missing metal toolchain on non-macos hosts' do
      allow(described_class).to receive(:command_available?).and_return(true)
      allow(described_class).to receive(:macos_host?).and_return(false)
      allow(described_class).to receive(:command_success?).and_return(false)

      status = described_class.status
      expect(status[:ready]).to be(false)
      expect(status[:missing_tools]).to include('macOS Metal toolchain')
    end
  end

  describe '.ensure_available!' do
    it 'raises with a clear message when unavailable' do
      allow(described_class).to receive(:status).and_return(
        { ready: false, missing_tools: %w[xcrun metal metallib] }
      )

      expect { described_class.ensure_available! }
        .to raise_error(ArgumentError, /arcilator_gpu backend unavailable/i)
    end
  end

  describe 'instance metadata' do
    let(:runner) { described_class.allocate }

    it 'reports arcilator gpu simulator type' do
      expect(runner.simulator_type).to eq(:hdl_arcilator_gpu)
    end

    it 'reports dry-run metadata for arcilator gpu mode' do
      expect(runner.dry_run_info).to include(
        mode: :arcilator_gpu,
        simulator_type: :hdl_arcilator_gpu,
        native: true
      )
    end
  end

  describe '#build_arcilator_gpu_simulation' do
    it 'clears the clang module cache before compiling the Metal shader' do
      Dir.mktmpdir('apple2-arcilator-gpu-runner-spec') do |dir|
        runner = described_class.allocate
        runner.instance_variable_set(:@instance_count, 1)

        allow(runner).to receive(:build_dir).and_return(dir)
        allow(runner).to receive(:shared_lib_path).and_return(File.join(dir, 'libapple2_arcilator_gpu_sim.dylib'))
        allow(runner).to receive(:export_firrtl)
        allow(runner).to receive(:write_wrapper)
        allow(runner).to receive(:link_shared_library)
        allow(runner).to receive(:load_shared_library) do
          runner.instance_variable_set(:@sim_ctx, Object.new)
        end
        allow(runner).to receive(:run_or_raise)
        allow(RHDL::Codegen::FIRRTL::ArcToGpuLowering).to receive(:lower)
        allow(FileUtils).to receive(:mkdir_p).and_call_original
        allow(FileUtils).to receive(:rm_rf).and_call_original

        module_cache_dir = File.join(dir, 'clang_module_cache')
        FileUtils.mkdir_p(module_cache_dir)
        File.write(File.join(module_cache_dir, 'stale.pcm'), 'stale')

        runner.send(:build_arcilator_gpu_simulation)

        expect(FileUtils).to have_received(:rm_rf).with(module_cache_dir)
        expect(File.exist?(File.join(module_cache_dir, 'stale.pcm'))).to be(false)
      end
    end
  end
end
