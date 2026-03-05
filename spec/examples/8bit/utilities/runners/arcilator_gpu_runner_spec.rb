# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/8bit/utilities/runners/arcilator_gpu_runner'

RSpec.describe RHDL::Examples::CPU8Bit::ArcilatorGpuRunner do
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
end
