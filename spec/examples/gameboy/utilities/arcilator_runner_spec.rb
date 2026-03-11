# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

require_relative '../../../../examples/gameboy/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::GameBoy::ArcilatorRunner do
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
end
