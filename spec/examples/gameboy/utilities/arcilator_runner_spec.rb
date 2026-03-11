# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

require_relative '../../../../examples/gameboy/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::GameBoy::ArcilatorRunner do
  describe '#load_import_report!' do
    it 'falls back to the staged core mlir when import_report.json is absent' do
      Dir.mktmpdir('rhdl_gameboy_arc_report') do |dir|
        mixed_dir = File.join(dir, '.mixed_import')
        FileUtils.mkdir_p(mixed_dir)
        core_mlir = File.join(mixed_dir, 'gb.core.mlir')
        File.write(core_mlir, 'module {}')

        runner = described_class.allocate
        report = runner.send(:load_import_report!, dir)

        expect(report.dig('artifacts', 'core_mlir_path')).to eq(core_mlir)
        expect(report.dig('mixed_import', 'top_name')).to eq('gb')
      end
    end
  end

  describe '#parse_state_file!' do
    it 'extracts the required imported core port signals from arcilator state JSON' do
      Dir.mktmpdir('rhdl_gameboy_arc_state') do |dir|
        state_path = File.join(dir, 'state.json')
        states = described_class::SIGNAL_SPECS.each_with_index.map do |(_key, spec), idx|
          {
            'name' => spec.fetch(:name),
            'type' => spec.fetch(:preferred_type),
            'offset' => idx * 8,
            'numBits' => 8
          }
        end

        File.write(
          state_path,
          JSON.pretty_generate(
            [
              {
                'name' => 'gb',
                'numStateBytes' => 4096,
                'states' => states
              }
            ]
          )
        )

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, { 'mixed_import' => { 'top_name' => 'gb' } })

        info = runner.send(:parse_state_file!, state_path)
        expect(info.fetch(:module_name)).to eq('gb')
        expect(info.fetch(:state_size)).to eq(4096)
        expect(info.fetch(:signals)).to include(:clk_sys, :reset, :cart_do, :lcd_clkena, :joy_p54)
        expect(info.fetch(:signals).fetch(:lcd_data_gb)).to include(offset: kind_of(Integer), bits: 8)
      end
    end
  end

  describe '#llvm_threads' do
    it 'defaults to 8 threads and clamps invalid values' do
      runner = described_class.allocate
      previous = ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS']

      ENV.delete('RHDL_GAMEBOY_ARC_LLVM_THREADS')
      expect(runner.send(:llvm_threads)).to eq(8)

      ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS'] = 'bogus'
      expect(runner.send(:llvm_threads)).to eq(8)

      ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS'] = '12'
      expect(runner.send(:llvm_threads)).to eq(12)
    ensure
      previous.nil? ? ENV.delete('RHDL_GAMEBOY_ARC_LLVM_THREADS') : ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS'] = previous
    end
  end
end
