# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/rhdl/cli/tasks/utilities/web_apple2_verilator_build'

RSpec.describe RHDL::CLI::Tasks::WebApple2VerilatorBuild do
  let(:mod) { described_class }

  describe '.missing_tools' do
    it 'returns an array of tool names' do
      result = mod.missing_tools
      expect(result).to be_an(Array)
      result.each { |entry| expect(entry).to be_a(String) }
    end

    it 'includes required tools in constants' do
      expect(mod::REQUIRED_TOOLS).to include('verilator', 'em++')
    end
  end

  describe '.tools_available?' do
    it 'matches missing_tools emptiness' do
      expect(mod.tools_available?).to eq(mod.missing_tools.empty?)
    end
  end

  describe '.build_signal_entries' do
    it 'contains both inputs and outputs' do
      entries = mod.build_signal_entries
      names = entries.map { |entry| entry[:name] }

      expect(names).to include('clk_14m', 'reset', 'ram_addr', 'pc_debug')
      expect(entries.find { |entry| entry[:name] == 'clk_14m' }[:is_input]).to eq(1)
      expect(entries.find { |entry| entry[:name] == 'ram_addr' }[:is_input]).to eq(0)
    end

    it 'includes width metadata' do
      entries = mod.build_signal_entries
      expect(entries.find { |entry| entry[:name] == 'ram_addr' }[:width]).to eq('SIG_U16')
      expect(entries.find { |entry| entry[:name] == 'speaker' }[:width]).to eq('SIG_BIT')
    end
  end

  describe '.build_wrapper_source' do
    subject(:source) { mod.build_wrapper_source }

    it 'exports required sim and runner API symbols' do
      %w[
        sim_create sim_destroy sim_free_error sim_wasm_alloc sim_wasm_dealloc
        sim_get_caps sim_signal sim_exec sim_trace sim_blob
        runner_get_caps runner_mem runner_run runner_control runner_probe
      ].each do |name|
        expect(source).to include("export_name(\"#{name}\")"), "missing export #{name}"
      end
    end

    it 'contains Apple II-specific runner constants' do
      expect(source).to include('RUNNER_KIND_APPLE2')
      expect(source).to include('RUNNER_MEM_SPACE_MAIN')
      expect(source).to include('RUNNER_CONTROL_SET_RESET_VECTOR')
    end

    it 'includes Verilator top and cycle bridge logic' do
      expect(source).to include('#include "Vapple2.h"')
      expect(source).to include('run_14m_cycle')
      expect(source).to include('ctx->dut->ram_addr')
    end
  end

  describe '.build' do
    it 'returns false with warning when required tools are missing' do
      allow(mod).to receive(:missing_tools).and_return(['verilator'])
      expect(mod).to receive(:warn).with(/verilator WASM build skipped/)
      expect(mod.build).to be(false)
    end
  end
end
