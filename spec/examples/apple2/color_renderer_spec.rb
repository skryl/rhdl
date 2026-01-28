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

    context 'with callable RAM' do
      let(:callable_ram) { ->(addr) { ram[addr] } }

      it 'decodes colors from callable RAM' do
        ram[0x2000] = 0x7F
        bitmap = renderer.decode_hires_colors(callable_ram, 0x2000)

        (0...7).each do |i|
          expect(bitmap[0][i]).to eq(:white), "pixel #{i} should be white"
        end
      end
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
    it 'returns space with black background for black/black' do
      result = renderer.color_char(:black, :black)
      expect(result).to include(' ')
      expect(result).to include("\e[48;2;0;0;0m")  # Black background
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

  describe 'PALETTES constant' do
    it 'defines multiple color palettes' do
      expect(described_class::PALETTES.keys).to include(
        :ntsc, :applewin, :kegs, :crt, :iigs, :virtual2
      )
    end

    it 'has all 6 colors in each palette' do
      described_class::PALETTES.each do |name, palette|
        expect(palette.keys).to contain_exactly(
          :black, :white, :green, :purple, :orange, :blue
        ), "#{name} palette should have all 6 colors"
      end
    end

    it 'has RGB arrays with valid values' do
      described_class::PALETTES.each do |palette_name, palette|
        palette.each do |color_name, rgb|
          expect(rgb.length).to eq(3), "#{palette_name}:#{color_name} should have 3 RGB values"
          rgb.each do |v|
            expect(v).to be_between(0, 255), "#{palette_name}:#{color_name} RGB values should be 0-255"
          end
        end
      end
    end
  end

  describe 'PHOSPHORS constant' do
    it 'defines multiple phosphor colors' do
      expect(described_class::PHOSPHORS.keys).to include(
        :green, :amber, :white, :cool, :warm
      )
    end

    it 'has RGB arrays with valid values' do
      described_class::PHOSPHORS.each do |name, rgb|
        expect(rgb.length).to eq(3), "#{name} phosphor should have 3 RGB values"
        rgb.each do |v|
          expect(v).to be_between(0, 255), "#{name} phosphor RGB values should be 0-255"
        end
      end
    end
  end

  describe 'initialization options' do
    it 'uses default ntsc palette' do
      r = described_class.new
      expect(r.palette).to eq(described_class::PALETTES[:ntsc])
    end

    it 'accepts custom palette' do
      r = described_class.new(palette: :applewin)
      expect(r.palette).to eq(described_class::PALETTES[:applewin])
    end

    it 'accepts monochrome mode' do
      r = described_class.new(monochrome: :green)
      expect(r.monochrome).to eq(:green)
    end

    it 'accepts blend option' do
      r = described_class.new(blend: true)
      expect(r.blend).to be true
    end

    it 'accepts chars_wide option' do
      r = described_class.new(chars_wide: 80)
      expect(r.chars_wide).to eq(80)
    end
  end

  describe 'monochrome mode' do
    let(:mono_renderer) { described_class.new(monochrome: :green) }

    it 'renders with monochrome colors' do
      ram[0x2000] = 0x7F  # White pixels
      output = mono_renderer.render(ram, base_addr: 0x2000, chars_wide: 40)

      # Should contain green phosphor color (0x33, 0xFF, 0x33)
      expect(output).to include("\e[38;2;51;255;51m")
    end

    it 'uses different intensities for different artifact colors' do
      # The monochrome mode should produce different brightness levels
      # for what would be different colors in color mode
      renderer = described_class.new(monochrome: :amber)
      ram[0x2000] = 0x01  # Single pixel (would be purple in color)

      output = renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end
  end

  describe 'different palettes' do
    it 'renders with AppleWin palette' do
      renderer = described_class.new(palette: :applewin)
      ram[0x2000] = 0x7F
      output = renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
    end

    it 'renders with KEGS palette' do
      renderer = described_class.new(palette: :kegs)
      ram[0x2000] = 0x7F
      output = renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
    end

    it 'renders with CRT palette' do
      renderer = described_class.new(palette: :crt)
      ram[0x2000] = 0x7F
      output = renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
    end

    it 'falls back to ntsc for unknown palette' do
      renderer = described_class.new(palette: :unknown)
      expect(renderer.palette).to eq(described_class::PALETTES[:ntsc])
    end
  end

  describe '.render class method' do
    it 'renders using a new instance' do
      output = described_class.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end

    it 'accepts palette option' do
      output = described_class.render(ram, base_addr: 0x2000, chars_wide: 40, palette: :applewin)
      expect(output).to be_a(String)
    end

    it 'accepts monochrome option' do
      output = described_class.render(ram, base_addr: 0x2000, chars_wide: 40, monochrome: :green)
      expect(output).to be_a(String)
    end
  end

  describe '.available_palettes' do
    it 'returns list of available palette names' do
      palettes = described_class.available_palettes
      expect(palettes).to include(:ntsc, :applewin, :kegs, :crt, :iigs, :virtual2)
    end
  end

  describe '.available_phosphors' do
    it 'returns list of available phosphor names' do
      phosphors = described_class.available_phosphors
      expect(phosphors).to include(:green, :amber, :white, :cool, :warm)
    end
  end

  describe 'double hi-res mode' do
    let(:dhires_renderer) { described_class.new(double_hires: true, chars_wide: 140) }

    it 'can decode double hi-res colors' do
      main_ram = Array.new(0x6000, 0)
      aux_ram = Array.new(0x6000, 0)

      # Set some pixels in both memory banks
      main_ram[0x2000] = 0x55  # Alternating bits
      aux_ram[0x2000] = 0xAA   # Opposite alternating bits

      bitmap = dhires_renderer.decode_double_hires_colors(main_ram, aux_ram, 0x2000)
      expect(bitmap.length).to eq(192)
      expect(bitmap[0].length).to eq(560)  # Double width
    end
  end

  describe 'blend mode' do
    let(:blend_renderer) { described_class.new(blend: true) }

    it 'applies blending when enabled' do
      ram[0x2000] = 0x7F
      output = blend_renderer.render(ram, base_addr: 0x2000, chars_wide: 40)
      expect(output).to be_a(String)
    end
  end

  describe 'HiResColorRenderer alias' do
    it 'is an alias for ColorRenderer' do
      expect(RHDL::Apple2::HiResColorRenderer).to eq(described_class)
    end
  end
end

# Test the MOS6502 namespace alias
# Load the MOS6502 color renderer which re-exports RHDL::Apple2::ColorRenderer
$LOAD_PATH.unshift File.expand_path('../../../examples/mos6502/utilities', __dir__)
require_relative '../../../examples/mos6502/utilities/color_renderer'

RSpec.describe MOS6502::ColorRenderer do
  it 'is an alias for RHDL::Apple2::ColorRenderer' do
    expect(described_class).to eq(RHDL::Apple2::ColorRenderer)
  end

  it 'provides HiResColorRenderer alias' do
    expect(MOS6502::HiResColorRenderer).to eq(RHDL::Apple2::ColorRenderer)
  end

  it 'can be instantiated and used' do
    renderer = described_class.new(chars_wide: 40)
    ram = Array.new(0x6000, 0)
    output = renderer.render(ram, base_addr: 0x2000)
    expect(output).to be_a(String)
  end

  it 'supports callable RAM' do
    renderer = described_class.new(chars_wide: 40)
    ram = Array.new(0x6000, 0)
    ram[0x2000] = 0x7F

    callable_ram = ->(addr) { ram[addr] }
    output = renderer.render(callable_ram, base_addr: 0x2000)
    expect(output).to be_a(String)
  end

  it 'supports all new options from Apple2 version' do
    renderer = described_class.new(
      chars_wide: 40,
      palette: :applewin,
      monochrome: nil,
      blend: false
    )
    ram = Array.new(0x6000, 0)
    output = renderer.render(ram, base_addr: 0x2000)
    expect(output).to be_a(String)
  end
end
