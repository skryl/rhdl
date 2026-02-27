# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/apple2/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::Apple2::ArcilatorRunner do
  let(:runner) { described_class.allocate }

  describe 'architecture-aware arcilator build commands' do
    it 'adds a macOS arm64 target triple to clang compile commands' do
      commands = []
      allow(runner).to receive(:llc_target_triple).and_return('arm64-apple-macosx')
      allow(runner).to receive(:darwin_host?).and_return(true)
      allow(runner).to receive(:command_available?).with('clang').and_return(true)
      allow(runner).to receive(:system) do |cmd|
        commands << cmd
        true
      end

      runner.send(:compile_arcilator)

      clang_cmd = commands.find { |cmd| cmd.start_with?('clang ') }
      expect(clang_cmd).to include('-target arm64-apple-macosx')
    end

    it 'adds a macOS arm64 arch flag to linker commands' do
      commands = []
      allow(runner).to receive(:build_target_arch).and_return('arm64')
      allow(runner).to receive(:darwin_host?).and_return(true)
      allow(runner).to receive(:command_available?).with('clang++').and_return(true)
      allow(runner).to receive(:write_cpp_wrapper)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(described_class::BUILD_DIR, 'arc_wrapper.cpp')).and_return(true)
      allow(runner).to receive(:system) do |cmd|
        commands << cmd
        true
      end

      runner.send(:build_shared_library)

      link_cmd = commands.find { |cmd| cmd.start_with?('clang++ ') }
      expect(link_cmd).to include(' -arch arm64 ')
    end

    it 'uses llc on non-macOS hosts' do
      commands = []
      allow(runner).to receive(:darwin_host?).and_return(false)
      allow(runner).to receive(:command_available?).with('llc').and_return(true)
      allow(runner).to receive(:system) do |cmd|
        commands << cmd
        true
      end

      expect { runner.send(:compile_arcilator) }.not_to raise_error

      llc_cmd = commands.find { |cmd| cmd.start_with?('llc ') }
      expect(llc_cmd).to include('-filetype=obj')
    end

    it 'detects macOS x86_64 and arm64 build targets' do
      expect(runner.send(:build_target_arch, host_os: 'darwin24.0.0', host_cpu: 'arm64')).to eq('arm64')
      expect(runner.send(:build_target_arch, host_os: 'darwin24.0.0', host_cpu: 'x86_64')).to eq('x86_64')
      expect(runner.send(:build_target_arch, host_os: 'linux', host_cpu: 'arm64')).to be_nil
    end
  end
end
