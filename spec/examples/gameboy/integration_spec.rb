# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/gameboy/gameboy'
require_relative '../../../examples/gameboy/utilities/gameboy_hdl'

RSpec.describe 'GameBoy Integration' do
  let(:rom_path) { File.expand_path('../../../examples/gameboy/software/roms/cpu_instrs.gb', __dir__) }

  describe 'HDL Runner' do
    let(:runner) { RHDL::GameBoy::HdlRunner.new }

    it 'can be instantiated' do
      expect(runner).to be_a(RHDL::GameBoy::HdlRunner)
    end

    it 'starts with zero cycles' do
      expect(runner.cycle_count).to eq(0)
    end

    it 'reports simulator type as :hdl_ruby' do
      expect(runner.simulator_type).to eq(:hdl_ruby)
    end

    it 'is not native' do
      expect(runner.native?).to eq(false)
    end

    context 'with demo ROM' do
      before do
        # Create a minimal valid Game Boy ROM
        @demo_rom = create_demo_rom
        runner.load_rom(@demo_rom)
      end

      it 'loads the ROM' do
        # ROM should be loaded
        expect(runner.read(0x104)).to eq(0xCE)  # First byte of Nintendo logo
        expect(runner.read(0x105)).to eq(0xED)  # Second byte
      end

      it 'can reset' do
        runner.reset
        expect(runner.cycle_count).to eq(0)
        expect(runner.halted?).to eq(false)
      end

      it 'can run steps' do
        runner.reset
        runner.run_steps(10)
        expect(runner.cycle_count).to eq(10)
      end

      it 'provides CPU state' do
        runner.reset
        state = runner.cpu_state
        expect(state).to be_a(Hash)
        expect(state).to have_key(:pc)
        expect(state).to have_key(:cycles)
      end

      it 'provides dry run info' do
        info = runner.dry_run_info
        expect(info[:mode]).to eq(:hdl)
        expect(info[:simulator_type]).to eq(:hdl_ruby)
        expect(info[:native]).to eq(false)
      end
    end

    context 'with cpu_instrs.gb', if: File.exist?(File.expand_path('../../../examples/gameboy/software/roms/cpu_instrs.gb', __dir__)) do
      before do
        runner.load_rom(File.binread(rom_path))
        runner.reset
      end

      it 'loads the ROM correctly' do
        # Check Nintendo logo
        expect(runner.read(0x104)).to eq(0xCE)
        expect(runner.read(0x105)).to eq(0xED)

        # Check title
        title_bytes = (0x134...0x143).map { |addr| runner.read(addr) }
        title = title_bytes.pack('C*').gsub(/\x00.*/, '')
        expect(title).to eq('CPU_INSTRS')
      end

      it 'can run boot sequence' do
        # Run some cycles to simulate boot
        runner.run_steps(1000)
        expect(runner.cycle_count).to eq(1000)
      end

      it 'tracks screen state' do
        runner.run_steps(100)
        expect(runner.screen_dirty?).to be_in([true, false])
        runner.clear_screen_dirty
        expect(runner.screen_dirty?).to eq(false)
      end

      it 'can render LCD output' do
        runner.run_steps(100)
        output = runner.render_lcd_braille(chars_wide: 40)
        expect(output).to be_a(String)
        expect(output.length).to be > 0
      end
    end
  end

  describe 'Memory Operations' do
    let(:runner) { RHDL::GameBoy::HdlRunner.new }

    it 'reads and writes WRAM' do
      runner.write(0xC000, 0x42)
      expect(runner.read(0xC000)).to eq(0x42)
    end

    it 'reads and writes HRAM' do
      runner.write(0xFF80, 0x55)
      expect(runner.read(0xFF80)).to eq(0x55)
    end

    it 'reads and writes VRAM' do
      runner.write(0x8000, 0xAA)
      expect(runner.read(0x8000)).to eq(0xAA)
    end

    it 'returns 0xFF for unusable memory' do
      expect(runner.read(0xFEA0)).to eq(0xFF)
    end

    it 'masks address to 16 bits' do
      runner.write(0xC000, 0x12)
      expect(runner.read(0x1C000)).to eq(0x12)  # Should mask to 0xC000
    end
  end

  describe 'LCD Renderer' do
    let(:renderer) { RHDL::GameBoy::LcdRenderer.new(chars_wide: 40) }

    it 'can be instantiated' do
      expect(renderer).to be_a(RHDL::GameBoy::LcdRenderer)
    end

    it 'renders empty framebuffer' do
      framebuffer = Array.new(144) { Array.new(160, 0) }
      output = renderer.render_braille(framebuffer)
      expect(output).to be_a(String)
      # Should have 36 lines (144 / 4)
      expect(output.split("\n").length).to eq(36)
    end

    it 'renders framebuffer with pattern' do
      framebuffer = Array.new(144) { |y| Array.new(160) { |x| (x + y) % 4 } }
      output = renderer.render_braille(framebuffer)
      expect(output).to be_a(String)
    end

    it 'renders color output' do
      framebuffer = Array.new(144) { |y| Array.new(160) { |x| (x / 40) % 4 } }
      output = renderer.render_color(framebuffer)
      expect(output).to include("\e[")  # Should have ANSI codes
    end

    it 'renders ASCII output' do
      framebuffer = Array.new(144) { Array.new(160, 0) }
      output = renderer.render_ascii(framebuffer)
      expect(output).to be_a(String)
      expect(output).not_to include("\e[")  # No ANSI codes
    end

    it 'can frame output' do
      framebuffer = Array.new(144) { Array.new(160, 0) }
      content = renderer.render_braille(framebuffer)
      framed = renderer.frame(content, title: "TEST")
      expect(framed).to include("TEST")
      expect(framed).to include("+")
      expect(framed).to include("|")
    end
  end

  describe 'Speaker' do
    let(:speaker) { RHDL::GameBoy::Speaker.new }

    it 'can be instantiated' do
      expect(speaker).to be_a(RHDL::GameBoy::Speaker)
    end

    it 'starts disabled' do
      expect(speaker.enabled).to eq(false)
    end

    it 'tracks toggle count' do
      expect(speaker.toggle_count).to eq(0)
      speaker.toggle
      speaker.toggle
      expect(speaker.toggle_count).to eq(2)
    end

    it 'provides status' do
      expect(speaker.status).to be_a(String)
    end

    it 'provides debug info' do
      info = speaker.debug_info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:toggle_count)
      expect(info).to have_key(:enabled)
    end
  end

  private

  def create_demo_rom
    rom = Array.new(32 * 1024, 0)

    # Nintendo logo at 0x104
    nintendo_logo = [
      0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
      0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
      0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
      0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
      0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
      0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
    ]
    nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

    # Title
    "RHDL TEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

    # Header checksum
    checksum = 0
    (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
    rom[0x14D] = checksum

    # Entry point - JP 0x150
    rom[0x100] = 0x00  # NOP
    rom[0x101] = 0xC3  # JP
    rom[0x102] = 0x50  # low
    rom[0x103] = 0x01  # high

    # Simple program at 0x150
    pc = 0x150
    rom[pc] = 0x3E; pc += 1  # LD A, $91
    rom[pc] = 0x91; pc += 1
    rom[pc] = 0xE0; pc += 1  # LDH ($40), A
    rom[pc] = 0x40; pc += 1
    rom[pc] = 0x76; pc += 1  # HALT

    rom.pack('C*')
  end
end
