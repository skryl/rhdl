# frozen_string_literal: true

require 'spec_helper'

$LOAD_PATH.unshift File.expand_path('../../../examples/apple2/utilities', __dir__)
require 'color_renderer'

RSpec.describe RHDL::Apple2::ColorRenderer do
  let(:renderer) { described_class.new }

  # Create test RAM with hi-res page at $2000
  let(:ram) { Array.new(0x6000, 0) }

  describe '#hires_line_address' do
    it 'calculates correct address for line 0' do
      expect(renderer.hires_line_address(0, 0x2000)).to eq(0x2000)
    end

    it 'calculates correct address for line 1' do
      expect(renderer.hires_line_address(1, 0x2000)).to eq(0x2400)
    end

    it 'calculates correct address for line 8' do
      expect(renderer.hires_line_address(8, 0x2000)).to eq(0x2080)
    end

    it 'calculates correct address for line 64' do
      expect(renderer.hires_line_address(64, 0x2000)).to eq(0x2028)
    end

    it 'calculates correct address for line 128' do
      expect(renderer.hires_line_address(128, 0x2000)).to eq(0x2050)
    end
  end

  describe '#determine_color' do
    context 'with palette 0 (green/purple)' do
      it 'returns black for pattern 000' do
        expect(renderer.determine_color(0, 0, 0, 0, 0)).to eq(:black)
      end

      it 'returns black for pattern 001' do
        expect(renderer.determine_color(0, 0, 1, 0, 0)).to eq(:black)
      end

      it 'returns black for pattern 100' do
        expect(renderer.determine_color(1, 0, 0, 0, 0)).to eq(:black)
      end

      it 'returns white for pattern 011' do
        expect(renderer.determine_color(0, 1, 1, 0, 0)).to eq(:white)
      end

      it 'returns white for pattern 110' do
        expect(renderer.determine_color(1, 1, 0, 0, 0)).to eq(:white)
      end

      it 'returns white for pattern 111' do
        expect(renderer.determine_color(1, 1, 1, 0, 0)).to eq(:white)
      end

      it 'returns purple for isolated pixel at even position' do
        expect(renderer.determine_color(0, 1, 0, 0, 0)).to eq(:purple)
      end

      it 'returns green for isolated pixel at odd position' do
        expect(renderer.determine_color(0, 1, 0, 0, 1)).to eq(:green)
      end

      it 'returns green for gap at even position' do
        expect(renderer.determine_color(1, 0, 1, 0, 0)).to eq(:green)
      end

      it 'returns purple for gap at odd position' do
        expect(renderer.determine_color(1, 0, 1, 0, 1)).to eq(:purple)
      end
    end

    context 'with palette 1 (blue/orange)' do
      it 'returns blue for isolated pixel at even position' do
        expect(renderer.determine_color(0, 1, 0, 1, 0)).to eq(:blue)
      end

      it 'returns orange for isolated pixel at odd position' do
        expect(renderer.determine_color(0, 1, 0, 1, 1)).to eq(:orange)
      end

      it 'returns orange for gap at even position' do
        expect(renderer.determine_color(1, 0, 1, 1, 0)).to eq(:orange)
      end

      it 'returns blue for gap at odd position' do
        expect(renderer.determine_color(1, 0, 1, 1, 1)).to eq(:blue)
      end
    end
  end

  describe '#decode_hires_colors' do
    it 'decodes all black screen' do
      bitmap = renderer.decode_hires_colors(ram, 0x2000)
      expect(bitmap.length).to eq(192)
      expect(bitmap[0].length).to eq(280)
      expect(bitmap[0].all? { |c| c == :black }).to be true
    end

    it 'decodes white pixels for adjacent bits' do
      # Set first byte of first line to 0x7F (all 7 pixels on, high bit 0)
      ram[0x2000] = 0x7F
      bitmap = renderer.decode_hires_colors(ram, 0x2000)

      # All 7 pixels should be white (adjacent pixels)
      (0...7).each do |i|
        expect(bitmap[0][i]).to eq(:white), "pixel #{i} should be white"
      end
    end

    it 'decodes single purple pixel at even position' do
      # Isolated pixel at position 0 (even) with high bit 0
      ram[0x2000] = 0x01  # bit 0 set
      bitmap = renderer.decode_hires_colors(ram, 0x2000)

      expect(bitmap[0][0]).to eq(:purple)
    end

    it 'decodes single green pixel at odd position' do
      # Isolated pixel at position 1 (odd) with high bit 0
      ram[0x2000] = 0x02  # bit 1 set
      bitmap = renderer.decode_hires_colors(ram, 0x2000)

      expect(bitmap[0][1]).to eq(:green)
    end

    it 'decodes blue/orange with high bit set' do
      # High bit set (palette 1)
      ram[0x2000] = 0x81  # bit 0 set + high bit
      bitmap = renderer.decode_hires_colors(ram, 0x2000)

      expect(bitmap[0][0]).to eq(:blue)
    end
  end

  describe '#render' do
    it 'produces output with ANSI color codes' do
      output = renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to include("\e[")  # ANSI escape codes
    end

    it 'produces correct number of lines' do
      output = renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      lines = output.split("\n")
      expect(lines.length).to eq(96)  # 192 / 2 = 96 half-block rows
    end
  end

  describe '#render_lines' do
    it 'returns array of lines' do
      lines = renderer.render_lines(ram, base_addr: 0x2000, chars_wide: 40)
      expect(lines).to be_an(Array)
      expect(lines.length).to eq(96)
    end
  end

  describe '#color_char' do
    it 'returns space for black/black' do
      expect(renderer.color_char(:black, :black)).to eq(" ")
    end

    it 'returns full block for same non-black colors' do
      result = renderer.color_char(:green, :green)
      expect(result).to include("\u2588")  # Full block
      expect(result).to include("\e[38;2;")  # Foreground color
    end

    it 'returns lower half block for black/color' do
      result = renderer.color_char(:black, :green)
      expect(result).to include("\u2584")  # Lower half block
    end

    it 'returns upper half block for color/black' do
      result = renderer.color_char(:green, :black)
      expect(result).to include("\u2580")  # Upper half block
    end

    it 'returns upper half with fg/bg for different colors' do
      result = renderer.color_char(:green, :purple)
      expect(result).to include("\u2580")  # Upper half block
      expect(result).to include("\e[38;2;")  # Foreground color
      expect(result).to include("\e[48;2;")  # Background color
    end
  end

  describe 'COLORS constant' do
    it 'defines all 6 hires colors' do
      expect(described_class::COLORS.keys).to contain_exactly(
        :black, :white, :green, :purple, :orange, :blue
      )
    end

    it 'has RGB arrays with 3 values each' do
      described_class::COLORS.each do |name, rgb|
        expect(rgb.length).to eq(3), "#{name} should have 3 RGB values"
        rgb.each do |v|
          expect(v).to be_between(0, 255), "#{name} RGB values should be 0-255"
        end
      end
    end
  end

  describe '.render class method' do
    it 'renders using a new instance' do
      output = described_class.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end
  end
end
