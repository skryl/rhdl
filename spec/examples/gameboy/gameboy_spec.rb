# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/gameboy/gameboy'
require_relative '../../../examples/gameboy/utilities/gameboy_hdl'

RSpec.describe 'GameBoy RHDL Implementation' do
  describe 'Module Loading' do
    it 'loads the GameBoy module' do
      expect(defined?(GameBoy)).to eq('constant')
    end

    it 'has version information' do
      expect(GameBoy::VERSION).to eq('0.1.0')
    end
  end

  describe 'CPU Components' do
    it 'defines SM83 CPU' do
      expect(defined?(GameBoy::SM83)).to eq('constant')
    end

    it 'defines SM83_ALU' do
      expect(defined?(GameBoy::SM83_ALU)).to eq('constant')
    end

    it 'defines SM83_Registers' do
      expect(defined?(GameBoy::SM83_Registers)).to eq('constant')
    end

    it 'defines SM83_MCode' do
      expect(defined?(GameBoy::SM83_MCode)).to eq('constant')
    end
  end

  describe 'PPU Components' do
    it 'defines Video' do
      expect(defined?(GameBoy::Video)).to eq('constant')
    end

    it 'defines Sprites' do
      expect(defined?(GameBoy::Sprites)).to eq('constant')
    end

    it 'defines LCD' do
      expect(defined?(GameBoy::LCD)).to eq('constant')
    end
  end

  describe 'APU Components' do
    it 'defines Sound' do
      expect(defined?(GameBoy::Sound)).to eq('constant')
    end

    it 'defines ChannelSquare' do
      expect(defined?(GameBoy::ChannelSquare)).to eq('constant')
    end

    it 'defines ChannelWave' do
      expect(defined?(GameBoy::ChannelWave)).to eq('constant')
    end

    it 'defines ChannelNoise' do
      expect(defined?(GameBoy::ChannelNoise)).to eq('constant')
    end
  end

  describe 'Memory Components' do
    it 'defines DPRAM' do
      expect(defined?(GameBoy::DPRAM)).to eq('constant')
    end

    it 'defines SPRAM' do
      expect(defined?(GameBoy::SPRAM)).to eq('constant')
    end

    it 'defines HDMA' do
      expect(defined?(GameBoy::HDMA)).to eq('constant')
    end
  end

  describe 'Mapper Components' do
    it 'defines MBC1' do
      expect(defined?(GameBoy::MBC1)).to eq('constant')
    end

    it 'defines MBC2' do
      expect(defined?(GameBoy::MBC2)).to eq('constant')
    end

    it 'defines MBC3' do
      expect(defined?(GameBoy::MBC3)).to eq('constant')
    end

    it 'defines MBC5' do
      expect(defined?(GameBoy::MBC5)).to eq('constant')
    end

    it 'defines mapper type constants' do
      expect(GameBoy::Mappers::ROM_ONLY).to eq(0x00)
      expect(GameBoy::Mappers::MBC1).to eq(0x01)
      expect(GameBoy::Mappers::MBC2).to eq(0x05)
      expect(GameBoy::Mappers::MBC3).to eq(0x11)
      expect(GameBoy::Mappers::MBC5).to eq(0x19)
    end

    it 'defines ROM size constants' do
      expect(GameBoy::Mappers::ROM_SIZES[0x00]).to eq(32 * 1024)
      expect(GameBoy::Mappers::ROM_SIZES[0x05]).to eq(1024 * 1024)
    end

    it 'defines RAM size constants' do
      expect(GameBoy::Mappers::RAM_SIZES[0x00]).to eq(0)
      expect(GameBoy::Mappers::RAM_SIZES[0x03]).to eq(32 * 1024)
    end
  end

  describe 'Other Components' do
    it 'defines Timer' do
      expect(defined?(GameBoy::Timer)).to eq('constant')
    end

    it 'defines Link' do
      expect(defined?(GameBoy::Link)).to eq('constant')
    end

    it 'defines GB (top-level)' do
      expect(defined?(GameBoy::GB)).to eq('constant')
    end
  end

  # Integration Tests
  describe 'HDL Runner' do
    let(:runner) { RHDL::GameBoy::HdlRunner.new }
    let(:rom_path) { File.expand_path('../../../examples/gameboy/software/roms/cpu_instrs.gb', __dir__) }

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
        @demo_rom = create_demo_rom
        runner.load_rom(@demo_rom)
      end

      it 'loads the ROM' do
        expect(runner.read(0x104)).to eq(0xCE)
        expect(runner.read(0x105)).to eq(0xED)
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
        expect(runner.read(0x104)).to eq(0xCE)
        expect(runner.read(0x105)).to eq(0xED)

        title_bytes = (0x134...0x143).map { |addr| runner.read(addr) }
        title = title_bytes.pack('C*').gsub(/\x00.*/, '')
        expect(title).to eq('CPU_INSTRS')
      end

      it 'can run boot sequence' do
        runner.run_steps(1000)
        expect(runner.cycle_count).to eq(1000)
      end

      it 'tracks screen state' do
        runner.run_steps(100)
        expect([true, false]).to include(runner.screen_dirty?)
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
      expect(runner.read(0x1C000)).to eq(0x12)
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
      expect(output).to include("\e[")
    end

    it 'renders ASCII output' do
      framebuffer = Array.new(144) { Array.new(160, 0) }
      output = renderer.render_ascii(framebuffer)
      expect(output).to be_a(String)
      expect(output).not_to include("\e[")
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

  describe 'IR Runner Long Run' do
    let(:tobu_rom_path) { File.expand_path('../../../examples/gameboy/software/roms/tobu.gb', __dir__) }

    before do
      skip 'tobu.gb ROM not found' unless File.exist?(tobu_rom_path)
      begin
        require_relative '../../../examples/gameboy/utilities/gameboy_ir'
        # Check if native library is available by trying to create a runner
        test_runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
        test_runner = nil
      rescue LoadError, RuntimeError => e
        skip "IR runner not available: #{e.message}"
      end
    end

    it 'runs 20M cycles with display tracking using compiler backend' do
      runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
      runner.load_rom(File.binread(tobu_rom_path))
      runner.reset

      total_cycles = 20_000_000
      batch_size = 1_000_000
      batches = total_cycles / batch_size

      display_snapshots = []
      frame_count = 0

      start_time = Time.now

      batches.times do |i|
        runner.run_steps(batch_size)

        cycles_per_frame = 154 * 456
        current_frames = runner.cycle_count / cycles_per_frame

        if current_frames > frame_count
          frame_count = current_frames

          if frame_count % 10 == 0
            snapshot = {
              cycle: runner.cycle_count,
              frame: frame_count,
              screen_dirty: runner.screen_dirty?,
              elapsed: Time.now - start_time
            }
            display_snapshots << snapshot
          end
        end

        runner.clear_screen_dirty
      end

      elapsed = Time.now - start_time
      speed_mhz = runner.cycle_count / elapsed / 1_000_000.0

      expect(runner.cycle_count).to eq(total_cycles)
      expect(runner.native?).to eq(true)
      expect(display_snapshots.length).to be > 0

      total_frames = runner.cycle_count / (154 * 456)
      expect(total_frames).to be > 200

      puts "\n  IR Runner (compile) Results:"
      puts "    Total cycles: #{runner.cycle_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      puts "    Total frames: #{total_frames}"
      puts "    Elapsed time: #{'%.2f' % elapsed}s"
      puts "    Speed: #{'%.2f' % speed_mhz} MHz (#{'%.1f' % (speed_mhz / 4.19 * 100)}% of real GB)"
      puts "    Display snapshots: #{display_snapshots.length}"
    end

    it 'tracks LY register changes during execution' do
      runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
      runner.load_rom(File.binread(tobu_rom_path))
      runner.reset

      cycles_per_frame = 154 * 456
      runner.run_steps(cycles_per_frame * 5)

      expect(runner.cycle_count).to eq(cycles_per_frame * 5)

      screen_lines = runner.read_screen
      expect(screen_lines).to be_a(Array)
      expect(screen_lines.length).to be > 0
    end

    it 'can render framebuffer after long run' do
      runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
      runner.load_rom(File.binread(tobu_rom_path))
      runner.reset

      runner.run_steps(1_000_000)

      output = runner.render_lcd_braille(chars_wide: 40)
      expect(output).to be_a(String)
      expect(output.length).to be > 0
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

    nintendo_logo = [
      0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
      0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
      0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
      0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
      0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
      0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
    ]
    nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

    "RHDL TEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

    checksum = 0
    (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
    rom[0x14D] = checksum

    rom[0x100] = 0x00
    rom[0x101] = 0xC3
    rom[0x102] = 0x50
    rom[0x103] = 0x01

    pc = 0x150
    rom[pc] = 0x3E; pc += 1
    rom[pc] = 0x91; pc += 1
    rom[pc] = 0xE0; pc += 1
    rom[pc] = 0x40; pc += 1
    rom[pc] = 0x76; pc += 1

    rom.pack('C*')
  end
end
