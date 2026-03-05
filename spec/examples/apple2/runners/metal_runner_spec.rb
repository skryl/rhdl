# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/apple2/utilities/runners/metal_runner'

RSpec.describe RHDL::Examples::Apple2::MetalRunner do
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
        .to raise_error(ArgumentError, /metal backend unavailable/i)
    end
  end

  describe 'instance metadata' do
    let(:runner) { described_class.allocate }

    it 'reports metal simulator type' do
      expect(runner.simulator_type).to eq(:hdl_metal)
    end

    it 'reports dry-run metadata for metal mode' do
      expect(runner.dry_run_info).to include(
        mode: :metal,
        simulator_type: :hdl_metal,
        native: true
      )
    end
  end
end
