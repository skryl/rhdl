# frozen_string_literal: true

require 'spec_helper'

$LOAD_PATH.unshift File.expand_path('../../../examples/apple2/utilities', __dir__)
require 'braille_renderer'

RSpec.describe RHDL::Apple2::BrailleRenderer do
  let(:renderer) { described_class.new }

  # Create a test bitmap (192 rows x 280 pixels)
  let(:blank_bitmap) do
    Array.new(192) { Array.new(280, 0) }
  end

  let(:filled_bitmap) do
    Array.new(192) { Array.new(280, 1) }
  end

  describe '#render' do
    it 'produces output for blank bitmap' do
      output = renderer.render(blank_bitmap, chars_wide: 40)
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end

    it 'produces braille characters' do
      output = renderer.render(blank_bitmap, chars_wide: 40)
      # Blank braille character is U+2800
      expect(output).to include("\u2800")
    end

    it 'produces filled braille for filled bitmap' do
      output = renderer.render(filled_bitmap, chars_wide: 40, invert: false)
      # Full braille character is U+28FF
      expect(output).to include("\u28FF")
    end

    it 'respects invert option' do
      inverted_output = renderer.render(blank_bitmap, chars_wide: 40, invert: true)
      normal_output = renderer.render(blank_bitmap, chars_wide: 40, invert: false)
      expect(inverted_output).not_to eq(normal_output)
    end

    it 'produces correct number of lines' do
      output = renderer.render(blank_bitmap, chars_wide: 40)
      lines = output.split("\n")
      # 192 / 4 = 48 braille character rows
      expect(lines.length).to eq(48)
    end

    it 'produces correct line width' do
      output = renderer.render(blank_bitmap, chars_wide: 40)
      lines = output.split("\n")
      # Each line should have 40 braille characters
      expect(lines.first.length).to eq(40)
    end
  end

  describe '#render_lines' do
    it 'returns array of lines' do
      lines = renderer.render_lines(blank_bitmap, chars_wide: 40)
      expect(lines).to be_an(Array)
      expect(lines.length).to eq(48)
    end

    it 'lines do not contain newlines' do
      lines = renderer.render_lines(blank_bitmap, chars_wide: 40)
      lines.each do |line|
        expect(line).not_to include("\n")
      end
    end
  end

  describe 'green screen mode' do
    let(:green_renderer) { described_class.new(green: true) }

    it 'includes ANSI green foreground code' do
      output = green_renderer.render(blank_bitmap, chars_wide: 40)
      expect(output).to include("\e[32m")
    end

    it 'includes ANSI black background code' do
      output = green_renderer.render(blank_bitmap, chars_wide: 40)
      expect(output).to include("\e[40m")
    end

    it 'includes ANSI reset code' do
      output = green_renderer.render(blank_bitmap, chars_wide: 40)
      expect(output).to include("\e[0m")
    end
  end

  describe 'DOT_MAP constant' do
    it 'defines correct braille dot mappings' do
      expect(described_class::DOT_MAP[0]).to eq([0x01, 0x08])  # row 0
      expect(described_class::DOT_MAP[1]).to eq([0x02, 0x10])  # row 1
      expect(described_class::DOT_MAP[2]).to eq([0x04, 0x20])  # row 2
      expect(described_class::DOT_MAP[3]).to eq([0x40, 0x80])  # row 3
    end
  end

  describe 'scaling' do
    it 'scales correctly at different widths' do
      narrow = renderer.render(filled_bitmap, chars_wide: 20)
      wide = renderer.render(filled_bitmap, chars_wide: 80)

      narrow_lines = narrow.split("\n")
      wide_lines = wide.split("\n")

      expect(narrow_lines.first.length).to eq(20)
      expect(wide_lines.first.length).to eq(80)
    end
  end
end
