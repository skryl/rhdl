# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/apple2/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::Apple2::ArcilatorRunner do
  let(:runner) { described_class.allocate }

  describe '#render_hires_color' do
    it 'uses live simulator RAM when native read hooks are available' do
      allow(runner).to receive(:instance_variable_get).and_call_original
      runner.instance_variable_set(:@sim, Object.new)

      allow(runner).to receive(:read_ram_byte) { |addr| addr & 0xFF }

      captured_ram = nil
      captured_base = nil
      renderer = instance_double(RHDL::Examples::Apple2::ColorRenderer)
      allow(RHDL::Examples::Apple2::ColorRenderer).to receive(:new).and_return(renderer)
      allow(renderer).to receive(:render) do |ram, base_addr:|
        captured_ram = ram
        captured_base = base_addr
        'rendered'
      end

      result = runner.render_hires_color(chars_wide: 16, composite: false, base_addr: 0x2000)

      expect(result).to eq('rendered')
      expect(captured_base).to eq(0x2000)
      expect(captured_ram[0x2000]).to eq(0x00)
      expect(captured_ram[0x2001]).to eq(0x01)
      expect(captured_ram[0x3FFF]).to eq(0xFF)
    end
  end
end
