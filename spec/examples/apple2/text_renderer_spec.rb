# frozen_string_literal: true

require 'spec_helper'

$LOAD_PATH.unshift File.expand_path('../../../examples/apple2/utilities', __dir__)
require 'text_renderer'

RSpec.describe RHDL::Apple2::TextRenderer do
  let(:renderer) { described_class.new }

  # Create a test screen array (24 rows x 40 cols)
  let(:blank_screen) do
    Array.new(24) { Array.new(40, 0xA0) }  # 0xA0 = space with high bit set
  end

  let(:hello_screen) do
    screen = Array.new(24) { Array.new(40, 0xA0) }
    "HELLO".each_char.with_index do |char, i|
      screen[0][i] = char.ord | 0x80
    end
    screen
  end

  describe '#render' do
    it 'produces output with borders' do
      output = renderer.render(blank_screen)
      expect(output).to include("+")
      expect(output).to include("-")
      expect(output).to include("|")
    end

    it 'has correct border width' do
      output = renderer.render(blank_screen)
      lines = output.split("\n")
      # Top border should be 42 chars: + + 40 dashes + +
      expect(lines.first).to eq("+" + ("-" * 40) + "+")
    end

    it 'renders character content' do
      output = renderer.render(hello_screen)
      expect(output).to include("HELLO")
    end

    it 'converts high-bit ASCII to normal ASCII' do
      # Character code 0xC1 (A with high bit) should render as 'A'
      screen = Array.new(24) { Array.new(40, 0xA0) }
      screen[0][0] = 0xC1  # 'A' with high bit
      output = renderer.render(screen)
      expect(output).to include("|A")
    end

    it 'converts control characters to spaces' do
      screen = Array.new(24) { Array.new(40, 0xA0) }
      screen[0][0] = 0x00  # Control character
      output = renderer.render(screen)
      # Should be space, not control character
      lines = output.split("\n")
      expect(lines[1][1]).to eq(" ")
    end
  end

  describe '#render_lines' do
    it 'returns array of lines' do
      lines = renderer.render_lines(blank_screen)
      expect(lines).to be_an(Array)
    end

    it 'returns correct number of lines' do
      lines = renderer.render_lines(blank_screen)
      # 1 top border + 24 content + 1 bottom border = 26 lines
      expect(lines.length).to eq(26)
    end

    it 'lines do not contain newlines' do
      lines = renderer.render_lines(blank_screen)
      lines.each do |line|
        expect(line).not_to include("\n")
      end
    end
  end

  describe 'green screen mode' do
    let(:green_renderer) { described_class.new(green: true) }

    it 'includes ANSI green foreground code' do
      output = green_renderer.render(blank_screen)
      expect(output).to include("\e[32m")
    end

    it 'includes ANSI black background code' do
      output = green_renderer.render(blank_screen)
      expect(output).to include("\e[40m")
    end

    it 'includes ANSI reset code' do
      output = green_renderer.render(blank_screen)
      expect(output).to include("\e[0m")
    end
  end

  describe 'constants' do
    it 'defines correct screen dimensions' do
      expect(described_class::SCREEN_ROWS).to eq(24)
      expect(described_class::SCREEN_COLS).to eq(40)
    end
  end
end
