# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../../examples/gameboy/utilities/runners/verilator_runner'
require_relative '../../../../examples/gameboy/utilities/clock_enable_waveform'

RSpec.describe RHDL::Examples::GameBoy::VerilogRunner do
  let(:runner) { described_class.allocate }

  describe '#runtime_staged_verilog_entry' do
    it 'does not use staged mixed verilog unless explicitly enabled' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, false)
        expect(runner.send(:runtime_staged_verilog_entry)).to be_nil
      end
    end

    it 'uses staged mixed verilog when explicitly enabled' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, true)
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

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, true)
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
      allow(runner).to receive(:verilator_peek).with('cpu_pc_internal').and_return(0xBEEF)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x00AA)
    end

    it 'falls back to internal imported cpu pc when debug and bus pc are zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0)
      allow(runner).to receive(:verilator_peek).with('cpu_pc_internal').and_return(0x00C7)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x00C7)
    end

    it 'falls back to internal imported cpu registers when debug outputs are zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0x1234)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0)
      allow(runner).to receive(:verilator_peek).with('cpu_pc_internal').and_return(0x00C7)
      allow(runner).to receive(:verilator_peek).with('debug_acc').and_return(0)
      allow(runner).to receive(:verilator_peek).with('debug_f').and_return(0)
      allow(runner).to receive(:verilator_peek).with('debug_sp').and_return(0)
      allow(runner).to receive(:verilator_peek).with('debug_acc_internal').and_return(0x42)
      allow(runner).to receive(:verilator_peek).with('debug_f_internal').and_return(0xB0)
      allow(runner).to receive(:verilator_peek).with('debug_sp_internal').and_return(0xC001)

      state = runner.send(:cpu_state)
      expect(state[:a]).to eq(0x42)
      expect(state[:f]).to eq(0xB0)
      expect(state[:sp]).to eq(0xC001)
    end
  end

  describe 'clock enable waveform' do
    it 'matches the reference speedcontrol divider phases' do
      sequence = 8.times.map { |phase| RHDL::Examples::GameBoy::ClockEnableWaveform.values_for_phase(phase) }
      expect(sequence).to eq([
        { ce: 1, ce_n: 0, ce_2x: 1 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 1, ce_2x: 1 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 }
      ])
    end
  end

  describe '#c_constant_tieoff_lines' do
    it 'zeros wide imported gb tie-off inputs in the native wrapper' do
      runner.instance_variable_set(:@top_module_name, 'gb')
      allow(runner).to receive(:resolve_port_name).with('gg_code').and_return('gg_code')
      allow(runner).to receive(:resolve_port_name).with('SaveStateExt_Dout').and_return('SaveStateExt_Dout')
      allow(runner).to receive(:resolve_port_name).with('SAVE_out_Dout').and_return('SAVE_out_Dout')

      lines = runner.send(:c_constant_tieoff_lines, indent: '  ')

      expect(lines).to include('ctx->dut->gg_code[i] = 0u;')
      expect(lines).to include('ctx->dut->SaveStateExt_Dout = 0ULL;')
      expect(lines).to include('ctx->dut->SAVE_out_Dout = 0ULL;')
    end
  end
end
