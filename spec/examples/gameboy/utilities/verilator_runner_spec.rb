# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../../examples/gameboy/utilities/runners/verilator_runner'

RSpec.describe RHDL::Examples::GameBoy::VerilogRunner do
  let(:runner) { described_class.allocate }

  describe '#runtime_staged_verilog_entry' do
    let(:env_key) { 'RHDL_GAMEBOY_USE_STAGED_VERILOG' }

    around do |example|
      original = ENV[env_key]
      begin
        ENV.delete(env_key)
        example.run
      ensure
        ENV[env_key] = original
      end
    end

    it 'does not use staged mixed verilog unless explicitly enabled' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        expect(runner.send(:runtime_staged_verilog_entry)).to be_nil
      end
    end

    it 'uses staged mixed verilog when explicitly enabled' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        ENV[env_key] = '1'
        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        expect(runner.send(:runtime_staged_verilog_entry)).to eq(staged)
      end
    end

    it 'prefers normalized verilog from import report when present' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        runtime = File.join(dir, '.mixed_import', 'gb.normalized.v')
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(runtime))
        File.write(runtime, '// runtime')
        File.write(staged, '// staged')
        File.write(
          File.join(dir, 'import_report.json'),
          JSON.pretty_generate(
            'artifacts' => {
              'normalized_verilog_path' => runtime,
              'pure_verilog_entry_path' => staged
            },
            'mixed_import' => {
              'normalized_verilog_path' => runtime,
              'pure_verilog_entry_path' => staged
            }
          )
        )

        ENV[env_key] = '1'
        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        expect(runner.send(:runtime_staged_verilog_entry)).to eq(runtime)
      end
    end
  end

  describe '#cpu_state' do
    before do
      allow(runner).to receive(:verilator_peek).and_return(0)
      allow(runner).to receive(:debug_port_available?).with('debug_pc').and_return(true)
      allow(runner).to receive(:simulator_type).and_return(:hdl_verilator)
      runner.instance_variable_set(:@cycles, 500)
      runner.instance_variable_set(:@halted, false)
    end

    it 'falls back to bus pc when debug pc is zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(1)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0x1234)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x9234)
    end

    it 'prefers debug pc when it is non-zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0x00AA)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(1)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0x1234)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x00AA)
    end
  end
end
