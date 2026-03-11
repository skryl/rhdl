# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/display_adapter'

RSpec.describe RHDL::Examples::AO486::DisplayAdapter do
  let(:text_base) { described_class::TEXT_BASE }

  it 'renders text mode cells from 0xB8000 memory' do
    memory = {
      text_base => 'H'.ord,
      text_base + 1 => 0x07,
      text_base + 2 => 'I'.ord,
      text_base + 3 => 0x07
    }

    adapter = described_class.new(width: 4, height: 1)

    expect(adapter.render(memory: memory)).to eq('HI  ')
  end

  it 'renders a debug panel below the display' do
    memory = {
      text_base => 'A'.ord,
      text_base + 2 => ':'.ord,
      described_class::CURSOR_BDA => 1,
      described_class::CURSOR_BDA + 1 => 0
    }

    adapter = described_class.new(width: 4, height: 1)
    screen = adapter.render(memory: memory, debug_lines: ['backend=ir', 'cycles=12'])

    expect(screen).to include('A_  ')
    expect(screen).to include("+----------+\n|backend=ir|\n|cycles=12 |\n+----------+")
  end

  it 'renders the active text page selected in the BIOS data area' do
    page_stride = described_class::DEFAULT_ROW_STRIDE * described_class::DEFAULT_HEIGHT
    page1_base = text_base + page_stride
    memory = {
      page1_base => 'P'.ord,
      page1_base + 1 => 0x07,
      page1_base + 2 => '2'.ord,
      page1_base + 3 => 0x07,
      described_class::VIDEO_PAGE_BDA => 1
    }

    adapter = described_class.new(width: 4, height: 1)

    expect(adapter.render(memory: memory, cursor: nil)).to eq('P2  ')
  end
end
