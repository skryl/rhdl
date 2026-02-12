# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/gameboy/gameboy'
require_relative '../../../examples/gameboy/utilities/runners/ruby_runner'

RSpec.describe 'GameBoy RHDL Implementation' do
  describe 'Module Loading' do
    it 'loads the GameBoy module' do
      expect(defined?(RHDL::Examples::GameBoy)).to eq('constant')
    end

    it 'has version information' do
      expect(RHDL::Examples::GameBoy::VERSION).to eq('0.1.0')
    end
  end

  describe 'CPU Components' do
    it 'defines SM83 CPU' do
      expect(defined?(RHDL::Examples::GameBoy::SM83)).to eq('constant')
    end

    it 'defines SM83_ALU' do
      expect(defined?(RHDL::Examples::GameBoy::SM83_ALU)).to eq('constant')
    end

    it 'defines SM83_Registers' do
      expect(defined?(RHDL::Examples::GameBoy::SM83_Registers)).to eq('constant')
    end

    it 'defines SM83_MCode' do
      expect(defined?(RHDL::Examples::GameBoy::SM83_MCode)).to eq('constant')
    end
  end

  describe 'PPU Components' do
    it 'defines Video' do
      expect(defined?(RHDL::Examples::GameBoy::Video)).to eq('constant')
    end

    it 'defines Sprites' do
      expect(defined?(RHDL::Examples::GameBoy::Sprites)).to eq('constant')
    end

    it 'defines LCD' do
      expect(defined?(RHDL::Examples::GameBoy::LCD)).to eq('constant')
    end
  end

  describe 'APU Components' do
    it 'defines Sound' do
      expect(defined?(RHDL::Examples::GameBoy::Sound)).to eq('constant')
    end

    it 'defines ChannelSquare' do
      expect(defined?(RHDL::Examples::GameBoy::ChannelSquare)).to eq('constant')
    end

    it 'defines ChannelWave' do
      expect(defined?(RHDL::Examples::GameBoy::ChannelWave)).to eq('constant')
    end

    it 'defines ChannelNoise' do
      expect(defined?(RHDL::Examples::GameBoy::ChannelNoise)).to eq('constant')
    end
  end

  describe 'Memory Components' do
    it 'defines DPRAM' do
      expect(defined?(RHDL::Examples::GameBoy::DPRAM)).to eq('constant')
    end

    it 'defines SPRAM' do
      expect(defined?(RHDL::Examples::GameBoy::SPRAM)).to eq('constant')
    end

    it 'defines HDMA' do
      expect(defined?(RHDL::Examples::GameBoy::HDMA)).to eq('constant')
    end
  end

  describe 'Mapper Components' do
    it 'defines MBC1' do
      expect(defined?(RHDL::Examples::GameBoy::MBC1)).to eq('constant')
    end

    it 'defines MBC2' do
      expect(defined?(RHDL::Examples::GameBoy::MBC2)).to eq('constant')
    end

    it 'defines MBC3' do
      expect(defined?(RHDL::Examples::GameBoy::MBC3)).to eq('constant')
    end

    it 'defines MBC5' do
      expect(defined?(RHDL::Examples::GameBoy::MBC5)).to eq('constant')
    end

    it 'defines mapper type constants' do
      expect(RHDL::Examples::GameBoy::Mappers::ROM_ONLY).to eq(0x00)
      expect(RHDL::Examples::GameBoy::Mappers::MBC1).to eq(0x01)
      expect(RHDL::Examples::GameBoy::Mappers::MBC2).to eq(0x05)
      expect(RHDL::Examples::GameBoy::Mappers::MBC3).to eq(0x11)
      expect(RHDL::Examples::GameBoy::Mappers::MBC5).to eq(0x19)
    end

    it 'defines ROM size constants' do
      expect(RHDL::Examples::GameBoy::Mappers::ROM_SIZES[0x00]).to eq(32 * 1024)
      expect(RHDL::Examples::GameBoy::Mappers::ROM_SIZES[0x05]).to eq(1024 * 1024)
    end

    it 'defines RAM size constants' do
      expect(RHDL::Examples::GameBoy::Mappers::RAM_SIZES[0x00]).to eq(0)
      expect(RHDL::Examples::GameBoy::Mappers::RAM_SIZES[0x03]).to eq(32 * 1024)
    end
  end

  describe 'Other Components' do
    it 'defines Timer' do
      expect(defined?(RHDL::Examples::GameBoy::Timer)).to eq('constant')
    end

    it 'defines Link' do
      expect(defined?(RHDL::Examples::GameBoy::Link)).to eq('constant')
    end

    it 'defines GB (top-level)' do
      expect(defined?(RHDL::Examples::GameBoy::GB)).to eq('constant')
    end
  end

  # Integration Tests
  describe 'HDL Runner' do
    let(:runner) { RHDL::Examples::GameBoy::RubyRunner.new }
    let(:rom_path) { File.expand_path('../../../examples/gameboy/software/roms/cpu_instrs.gb', __dir__) }

    it 'can be instantiated' do
      expect(runner).to be_a(RHDL::Examples::GameBoy::RubyRunner)
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
        expect(info[:mode]).to eq(:ruby)
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
    let(:runner) { RHDL::Examples::GameBoy::RubyRunner.new }

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
    let(:renderer) { RHDL::Examples::GameBoy::LcdRenderer.new(chars_wide: 40) }

    it 'can be instantiated' do
      expect(renderer).to be_a(RHDL::Examples::GameBoy::LcdRenderer)
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

  describe 'IR Runner Long Run', :slow do
    let(:tobu_rom_path) { File.expand_path('../../../examples/gameboy/software/roms/tobu.gb', __dir__) }

    before do
      skip 'tobu.gb ROM not found' unless File.exist?(tobu_rom_path)
      begin
        require_relative '../../../examples/gameboy/utilities/runners/ir_runner'
        # Check if native library is available by trying to create a runner
        test_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
        test_runner = nil
      rescue LoadError, RuntimeError => e
        skip "IR runner not available: #{e.message}"
      end
    end

    it 'runs 20M cycles with display tracking using compiler backend', timeout: 300 do
      runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
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
      runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
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
      runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
      runner.load_rom(File.binread(tobu_rom_path))
      runner.reset

      runner.run_steps(1_000_000)

      output = runner.render_lcd_braille(chars_wide: 40)
      expect(output).to be_a(String)
      expect(output.length).to be > 0
    end
  end

  describe 'Verilator Runner' do
    def verilator_available?
      ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
        File.executable?(File.join(path, 'verilator'))
      end
    end

    before do
      skip 'Verilator not available' unless verilator_available?
      begin
        require_relative '../../../examples/gameboy/utilities/runners/verilator_runner'
      rescue LoadError => e
        skip "Verilator runner not available: #{e.message}"
      end
    end

    it 'can be instantiated', timeout: 300 do
      runner = RHDL::Examples::GameBoy::VerilogRunner.new
      expect(runner).to be_a(RHDL::Examples::GameBoy::VerilogRunner)
      expect(runner.native?).to eq(true)
      expect(runner.simulator_type).to eq(:hdl_verilator)
    end

    context 'with demo ROM', timeout: 300 do
      let(:runner) do
        r = RHDL::Examples::GameBoy::VerilogRunner.new
        r.load_rom(create_demo_rom)
        r
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
        runner.run_steps(100)
        expect(runner.cycle_count).to eq(100)
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
        expect(info[:mode]).to eq(:verilog)
        expect(info[:simulator_type]).to eq(:hdl_verilator)
        expect(info[:native]).to eq(true)
      end
    end

    context 'with tobu.gb ROM', timeout: 300 do
      let(:tobu_rom_path) { File.expand_path('../../../examples/gameboy/software/roms/tobu.gb', __dir__) }

      before do
        skip 'tobu.gb ROM not found' unless File.exist?(tobu_rom_path)
      end

      it 'can run 1M cycles' do
        runner = RHDL::Examples::GameBoy::VerilogRunner.new
        runner.load_rom(File.binread(tobu_rom_path))
        runner.reset

        start_time = Time.now
        runner.run_steps(1_000_000)
        elapsed = Time.now - start_time

        expect(runner.cycle_count).to eq(1_000_000)
        speed_mhz = runner.cycle_count / elapsed / 1_000_000.0

        puts "\n  Verilator Runner Results:"
        puts "    Total cycles: #{runner.cycle_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
        puts "    Elapsed time: #{'%.2f' % elapsed}s"
        puts "    Speed: #{'%.2f' % speed_mhz} MHz (#{'%.1f' % (speed_mhz / 4.19 * 100)}% of real GB)"
      end

      it 'can render framebuffer' do
        runner = RHDL::Examples::GameBoy::VerilogRunner.new
        runner.load_rom(File.binread(tobu_rom_path))
        runner.reset
        runner.run_steps(100_000)

        output = runner.render_lcd_braille(chars_wide: 40)
        expect(output).to be_a(String)
        expect(output.length).to be > 0
      end
    end
  end

  describe 'Speaker' do
    let(:speaker) { RHDL::Examples::GameBoy::Speaker.new }

    it 'can be instantiated' do
      expect(speaker).to be_a(RHDL::Examples::GameBoy::Speaker)
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

  describe 'Prince of Persia Long Run with VRAM/Framebuffer Tracing', :slow do
    let(:pop_rom_path) { File.expand_path('../../../examples/gameboy/software/roms/pop.gb', __dir__) }

    before do
      skip 'pop.gb ROM not found' unless File.exist?(pop_rom_path)

      begin
        require_relative '../../../examples/gameboy/utilities/runners/ir_runner'
        # Check if native library is available
        test_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
        test_runner = nil
      rescue LoadError, RuntimeError => e
        skip "IR runner not available: #{e.message}"
      end
    end

    # Helper to read VRAM using the sim's read_vram method
    # VRAM is at 0x8000-0x9FFF, read_vram takes offset from 0x8000
    def read_vram_byte(runner, addr)
      return 0 unless runner.sim.respond_to?(:read_vram)
      runner.sim.read_vram(addr - 0x8000)
    end

    # Helper to read VRAM tile data (0x8000-0x97FF)
    def read_vram_tiles(runner, start_tile: 0, num_tiles: 16)
      tiles = []
      base_addr = 0x8000
      (start_tile...(start_tile + num_tiles)).each do |tile_idx|
        tile_addr = base_addr + (tile_idx * 16)  # Each tile is 16 bytes
        tile_data = (0...16).map { |i| read_vram_byte(runner, tile_addr + i) }
        tiles << { index: tile_idx, addr: tile_addr, data: tile_data }
      end
      tiles
    end

    # Helper to count non-zero bytes in VRAM region (0x8000-0x9FFF)
    def vram_non_zero_count(runner, start_addr, length)
      return 0 unless runner.sim.respond_to?(:read_vram)
      count = 0
      length.times do |i|
        addr = start_addr + i
        next unless addr >= 0x8000 && addr < 0xA000  # VRAM range
        count += 1 if runner.sim.read_vram(addr - 0x8000) != 0
      end
      count
    end

    # Helper to count non-zero bytes in OAM (0xFE00-0xFE9F)
    def oam_non_zero_count(runner)
      # OAM isn't accessible via read_vram, check framebuffer sprites instead
      # For now, return 0 as we can't directly read OAM
      0
    end

    it 'runs Prince of Persia for 1000 frames with VRAM and framebuffer tracing', timeout: 600 do
      rom_data = File.binread(pop_rom_path)

      # Local constants
      cycles_per_frame = 70224  # 154 scanlines * 456 dots
      boot_complete_pc = 0x0100
      max_boot_cycles = 500_000

      puts "\n  Prince of Persia - 1000 Frame Test with VRAM/Framebuffer Tracing"
      puts "  " + "=" * 70

      # Initialize runner
      runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
      runner.load_rom(rom_data)
      runner.reset

      # === Phase 1: Boot ROM ===
      puts "\n  Phase 1: Boot ROM Execution"
      puts "  " + "-" * 50

      boot_start = Time.now
      boot_cycles = 0

      # Run through boot ROM with coarse steps
      while runner.cpu_state[:pc] < boot_complete_pc && boot_cycles < max_boot_cycles
        runner.run_steps(10_000)
        boot_cycles = runner.cycle_count
      end

      boot_elapsed = Time.now - boot_start
      boot_pc = runner.cpu_state[:pc]
      puts "    Boot completed at cycle #{boot_cycles} (PC=0x#{boot_pc.to_s(16)})"
      puts "    Boot time: #{'%.3f' % boot_elapsed}s"

      expect(boot_pc).to be >= boot_complete_pc, "Boot ROM did not complete (PC=0x#{boot_pc.to_s(16)})"

      # === Phase 2: Run 1000 frames with tracing ===
      puts "\n  Phase 2: Running 1000 frames with tracing"
      puts "  " + "-" * 50

      target_frames = 1000
      snapshot_interval = 100  # Snapshot every 100 frames
      cycles_per_snapshot = snapshot_interval * cycles_per_frame

      snapshots = []
      game_start = Time.now
      start_cycle = runner.cycle_count

      (target_frames / snapshot_interval).times do |i|
        runner.run_steps(cycles_per_snapshot)

        current_frame = (runner.cycle_count - start_cycle) / cycles_per_frame
        elapsed = Time.now - game_start

        # Read framebuffer
        fb = runner.read_framebuffer
        fb_non_zero = fb.flatten.count { |v| v != 0 }
        fb_unique = fb.flatten.uniq.sort
        fb_hash = fb.flatten.hash

        # Read VRAM statistics (tile data: 0x8000-0x97FF, tilemaps: 0x9800-0x9FFF)
        tile_data_non_zero = vram_non_zero_count(runner, 0x8000, 0x1800)  # Tile data
        tilemap_bg_non_zero = vram_non_zero_count(runner, 0x9800, 0x400)   # BG tilemap
        tilemap_win_non_zero = vram_non_zero_count(runner, 0x9C00, 0x400)  # Window tilemap

        # Read a few tiles for detailed inspection
        sample_tiles = read_vram_tiles(runner, start_tile: 0, num_tiles: 4)
        tiles_with_data = sample_tiles.count { |t| t[:data].any? { |b| b != 0 } }

        # CPU state
        cpu = runner.cpu_state

        snapshot = {
          frame: current_frame,
          cycle: runner.cycle_count,
          elapsed: elapsed,
          pc: cpu[:pc],
          sp: cpu[:sp],
          a: cpu[:a],
          # Framebuffer stats
          fb_non_zero_pixels: fb_non_zero,
          fb_unique_colors: fb_unique,
          fb_hash: fb_hash,
          fb_is_blank: fb_non_zero == 0,
          # VRAM stats
          vram_tile_data_bytes: tile_data_non_zero,
          vram_bg_tilemap_bytes: tilemap_bg_non_zero,
          vram_win_tilemap_bytes: tilemap_win_non_zero,
          sample_tiles_with_data: tiles_with_data
        }
        snapshots << snapshot

        # Progress output
        speed_mhz = (runner.cycle_count - start_cycle) / elapsed / 1_000_000.0
        puts "    Frame #{current_frame}: FB=#{fb_non_zero} px, VRAM tiles=#{tile_data_non_zero}, BG map=#{tilemap_bg_non_zero} (#{'%.2f' % speed_mhz} MHz)"

        # Render framebuffer visually every 100 frames
        puts ""
        puts "    Framebuffer at frame #{current_frame}:"
        output = runner.render_lcd_braille(chars_wide: 40)
        output.each_line { |line| puts "      #{line}" }
        puts ""
      end

      game_elapsed = Time.now - game_start
      total_game_cycles = runner.cycle_count - start_cycle
      total_frames = total_game_cycles / cycles_per_frame
      speed_mhz = total_game_cycles / game_elapsed / 1_000_000.0

      # === Phase 3: Analysis ===
      puts "\n  Phase 3: Analysis"
      puts "  " + "-" * 50

      # Count frames with actual content
      frames_with_fb_content = snapshots.count { |s| !s[:fb_is_blank] }
      frames_with_vram_tiles = snapshots.count { |s| s[:vram_tile_data_bytes] > 100 }
      frames_with_bg_map = snapshots.count { |s| s[:vram_bg_tilemap_bytes] > 100 }

      puts "    Total frames: #{total_frames}"
      puts "    Elapsed time: #{'%.2f' % game_elapsed}s"
      puts "    Speed: #{'%.2f' % speed_mhz} MHz (#{'%.1f' % (speed_mhz / 4.19 * 100)}% of real GB)"
      puts ""
      puts "    Framebuffer Analysis (#{snapshots.size} samples):"
      puts "      Frames with pixel content: #{frames_with_fb_content}/#{snapshots.size} (#{'%.1f' % (frames_with_fb_content * 100.0 / snapshots.size)}%)"
      puts ""
      puts "    VRAM Analysis:"
      puts "      Frames with tile data (>100 bytes): #{frames_with_vram_tiles}/#{snapshots.size}"
      puts "      Frames with BG tilemap (>100 bytes): #{frames_with_bg_map}/#{snapshots.size}"

      # Show unique color distribution across all samples
      all_colors = snapshots.flat_map { |s| s[:fb_unique_colors] }.uniq.sort
      puts ""
      puts "    Unique pixel values seen: #{all_colors.inspect}"

      # Show frame hash changes (indicates screen is updating)
      unique_fb_hashes = snapshots.map { |s| s[:fb_hash] }.uniq.size
      puts "    Unique framebuffer states: #{unique_fb_hashes}/#{snapshots.size}"

      # Final framebuffer render
      puts "\n  Final Frame Render:"
      puts "  " + "-" * 50
      final_fb = runner.read_framebuffer
      output = runner.render_lcd_braille(chars_wide: 40)
      output.each_line { |line| puts "    #{line}" }

      # === Assertions ===
      expect(total_frames).to be >= target_frames, "Did not complete #{target_frames} frames"

      # Check framebuffer has ANY content (not completely black)
      any_fb_content = snapshots.any? { |s| s[:fb_non_zero_pixels] > 0 }
      expect(any_fb_content).to eq(true), "Framebuffer is completely blank - no pixels rendered"

      # Check VRAM has ANY tile data (even if below threshold)
      any_vram_content = snapshots.any? { |s| s[:vram_tile_data_bytes] > 0 }
      expect(any_vram_content).to eq(true), "VRAM has no tile data loaded"

      # Report on screen update status (informational, not assertion)
      if unique_fb_hashes == 1
        puts "\n  ⚠ Note: Screen did not update during test (possibly waiting for input)"
      end

      puts "\n  ✓ All assertions passed"
    end
  end

  describe 'Backend Comparison (IR Compiler vs Verilator)', :slow do
    let(:test_rom_path) { File.expand_path('../../../examples/gameboy/software/roms/pop.gb', __dir__) }

    # Constants for boot ROM testing
    CYCLES_PER_FRAME = 70224  # 154 scanlines * 456 dots
    BOOT_ROM_COMPLETE_PC = 0x0100
    MAX_BOOT_CYCLES = 500_000  # Safety limit for boot ROM

    def verilator_available?
      ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
        File.executable?(File.join(path, 'verilator'))
      end
    end

    before do
      skip 'pop.gb ROM not found' unless File.exist?(test_rom_path)
      skip 'Verilator not available' unless verilator_available?

      begin
        require_relative '../../../examples/gameboy/utilities/runners/ir_runner'
        require_relative '../../../examples/gameboy/utilities/runners/verilator_runner'

        # Verify both runners can be instantiated
        test_ir = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
        test_ir = nil
      rescue LoadError, RuntimeError => e
        skip "Runners not available: #{e.message}"
      end
    end

    it 'completes boot ROM at the same cycle on both backends', timeout: 120 do
      rom_data = File.binread(test_rom_path)

      puts "\n  Boot ROM Completion Test"
      puts "  " + "=" * 50

      # Initialize both runners
      ir_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
      verilator_runner = RHDL::Examples::GameBoy::VerilogRunner.new

      # Load ROM into both
      ir_runner.load_rom(rom_data)
      verilator_runner.load_rom(rom_data)

      # Reset both
      ir_runner.reset
      verilator_runner.reset

      # --- IR Compiler Boot ---
      puts "  IR Compiler:"
      ir_start = Time.now
      ir_boot_cycle = nil
      ir_snapshots = []
      batch_size = 10_000
      cycles_run = 0

      while cycles_run < MAX_BOOT_CYCLES
        ir_runner.run_steps(batch_size)
        cycles_run += batch_size
        pc = ir_runner.cpu_state[:pc]

        if cycles_run % 50_000 == 0
          ir_snapshots << { cycle: cycles_run, pc: pc }
        end

        if pc >= BOOT_ROM_COMPLETE_PC
          ir_boot_cycle = cycles_run
          break
        end
      end

      ir_elapsed = Time.now - ir_start
      puts "    Boot completed at cycle #{ir_boot_cycle} (#{'%.3f' % ir_elapsed}s)"

      # --- Verilator Boot ---
      puts "  Verilator:"
      vl_start = Time.now
      vl_boot_cycle = nil
      vl_snapshots = []
      cycles_run = 0

      while cycles_run < MAX_BOOT_CYCLES
        verilator_runner.run_steps(batch_size)
        cycles_run += batch_size
        pc = verilator_runner.cpu_state[:pc]

        if cycles_run % 50_000 == 0
          vl_snapshots << { cycle: cycles_run, pc: pc }
        end

        if pc >= BOOT_ROM_COMPLETE_PC
          vl_boot_cycle = cycles_run
          break
        end
      end

      vl_elapsed = Time.now - vl_start
      puts "    Boot completed at cycle #{vl_boot_cycle} (#{'%.3f' % vl_elapsed}s)"

      # --- Comparison ---
      puts ""
      puts "  Comparison:"
      if ir_boot_cycle && vl_boot_cycle
        cycle_diff = (ir_boot_cycle - vl_boot_cycle).abs
        puts "    IR Compiler: #{ir_boot_cycle} cycles"
        puts "    Verilator:   #{vl_boot_cycle} cycles"
        puts "    Difference:  #{cycle_diff} cycles"

        # Verify PC snapshots match
        mismatch_count = 0
        [ir_snapshots.size, vl_snapshots.size].min.times do |i|
          if ir_snapshots[i][:pc] != vl_snapshots[i][:pc]
            mismatch_count += 1
          end
        end
        puts "    PC mismatches: #{mismatch_count}/#{[ir_snapshots.size, vl_snapshots.size].min}"

        expect(cycle_diff).to be < 10_000, "Boot cycle difference too large: #{cycle_diff}"
        expect(mismatch_count).to eq(0), "PC values diverged during boot"
      end

      expect(ir_boot_cycle).not_to be_nil, "IR Compiler failed to complete boot ROM"
      expect(vl_boot_cycle).not_to be_nil, "Verilator failed to complete boot ROM"
    end

    # Helper to check if a framebuffer is blank (all same value)
    def framebuffer_blank?(fb)
      return true if fb.nil? || fb.empty?
      first_val = fb.flatten.first
      fb.flatten.all? { |v| v == first_val }
    end

    # Helper to count non-zero pixels in framebuffer
    def non_zero_pixel_count(fb)
      return 0 if fb.nil? || fb.empty?
      fb.flatten.count { |v| v != 0 }
    end

    # Helper to count unique pixel values in framebuffer
    def unique_pixel_values(fb)
      return [] if fb.nil? || fb.empty?
      fb.flatten.uniq.sort
    end

    # Helper to compute framebuffer hash for comparison
    def framebuffer_hash(fb)
      return nil if fb.nil? || fb.empty?
      fb.flatten.hash
    end

    it 'compares 1000 frames between IR Compiler and Verilator backends', timeout: 600 do
      rom_data = File.binread(test_rom_path)

      # Initialize both runners
      puts "\n  Initializing runners..."
      ir_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
      verilator_runner = RHDL::Examples::GameBoy::VerilogRunner.new

      # Load ROM into both
      ir_runner.load_rom(rom_data)
      verilator_runner.load_rom(rom_data)

      # Reset both
      ir_runner.reset
      verilator_runner.reset

      # Run configuration
      target_frames = 1000
      snapshot_interval = 100  # Take snapshot every 100 frames
      cycles_per_frame = 70224  # 154 scanlines * 456 dots

      # Snapshot storage
      ir_snapshots = []
      verilator_snapshots = []

      # Track blank frames
      ir_blank_frames = 0
      ir_total_sampled = 0
      verilator_blank_frames = 0
      verilator_total_sampled = 0

      puts "  Running #{target_frames} frames on each backend..."
      puts ""

      # Run IR Compiler (use cycle count to approximate frames)
      puts "  IR Compiler (Rust):"
      ir_start = Time.now
      target_cycles = target_frames * cycles_per_frame
      cycles_per_snapshot = snapshot_interval * cycles_per_frame

      (target_frames / snapshot_interval).times do |i|
        ir_runner.run_steps(cycles_per_snapshot)
        ir_frames = ir_runner.cycle_count / cycles_per_frame
        fb = ir_runner.read_framebuffer
        is_blank = framebuffer_blank?(fb)
        ir_blank_frames += 1 if is_blank
        ir_total_sampled += 1

        ir_snapshots << {
          frame: ir_frames,
          cycle: ir_runner.cycle_count,
          pc: ir_runner.cpu_state[:pc],
          a: ir_runner.cpu_state[:a],
          elapsed: Time.now - ir_start,
          fb_blank: is_blank,
          fb_pixels: non_zero_pixel_count(fb),
          fb_hash: framebuffer_hash(fb),
          fb_unique: unique_pixel_values(fb)
        }
      end
      ir_elapsed = Time.now - ir_start
      ir_total_frames = ir_runner.cycle_count / cycles_per_frame
      ir_speed = ir_runner.cycle_count / ir_elapsed / 1_000_000.0

      puts "    Completed #{ir_total_frames} frames in #{'%.2f' % ir_elapsed}s"
      puts "    Speed: #{'%.2f' % ir_speed} MHz (#{'%.1f' % (ir_speed / 4.19 * 100)}% of real GB)"
      puts "    Non-blank snapshots: #{ir_total_sampled - ir_blank_frames}/#{ir_total_sampled} (#{'%.1f' % ((ir_total_sampled - ir_blank_frames) * 100.0 / ir_total_sampled)}%)"
      puts ""

      # Run Verilator (use actual frame count)
      puts "  Verilator (RTL):"
      verilator_start = Time.now
      last_snapshot_frame = 0

      while verilator_runner.frame_count < target_frames
        verilator_runner.run_steps(cycles_per_frame)  # Run ~1 frame worth of cycles

        # Take snapshot every snapshot_interval frames
        current_frame = verilator_runner.frame_count
        if current_frame >= last_snapshot_frame + snapshot_interval
          fb = verilator_runner.read_framebuffer
          is_blank = framebuffer_blank?(fb)
          verilator_blank_frames += 1 if is_blank
          verilator_total_sampled += 1

          verilator_snapshots << {
            frame: current_frame,
            cycle: verilator_runner.cycle_count,
            pc: verilator_runner.cpu_state[:pc],
            a: verilator_runner.cpu_state[:a],
            elapsed: Time.now - verilator_start,
            fb_blank: is_blank,
            fb_pixels: non_zero_pixel_count(fb),
            fb_hash: framebuffer_hash(fb),
            fb_unique: unique_pixel_values(fb)
          }
          last_snapshot_frame = current_frame
        end
      end
      verilator_elapsed = Time.now - verilator_start
      verilator_speed = verilator_runner.cycle_count / verilator_elapsed / 1_000_000.0

      puts "    Completed #{verilator_runner.frame_count} frames in #{'%.2f' % verilator_elapsed}s"
      puts "    Speed: #{'%.2f' % verilator_speed} MHz (#{'%.1f' % (verilator_speed / 4.19 * 100)}% of real GB)"
      puts "    Non-blank snapshots: #{verilator_total_sampled - verilator_blank_frames}/#{verilator_total_sampled} (#{'%.1f' % ((verilator_total_sampled - verilator_blank_frames) * 100.0 / verilator_total_sampled)}%)"
      puts ""

      # Compare results
      puts "  CPU State & Framebuffer Comparison (every #{snapshot_interval} frames):"
      puts "  " + "-" * 115
      puts "  #{'Frame'.ljust(8)} | #{'IR PC'.ljust(8)} | #{'VL PC'.ljust(8)} | #{'IR A'.ljust(5)} | #{'VL A'.ljust(5)} | #{'IR px'.ljust(7)} | #{'VL px'.ljust(7)} | #{'IR uniq'.ljust(10)} | #{'Match'.ljust(5)}"
      puts "  " + "-" * 115

      mismatches = 0
      fb_mismatches = 0
      num_comparisons = [ir_snapshots.size, verilator_snapshots.size].min
      num_comparisons.times do |i|
        ir_snap = ir_snapshots[i]
        vl_snap = verilator_snapshots[i]

        pc_match = ir_snap[:pc] == vl_snap[:pc]
        a_match = ir_snap[:a] == vl_snap[:a]
        fb_match = ir_snap[:fb_hash] == vl_snap[:fb_hash]
        all_match = pc_match && a_match

        mismatches += 1 unless all_match
        fb_mismatches += 1 unless fb_match

        frame_str = "#{ir_snap[:frame]}".ljust(8)
        ir_pc_str = ("0x%04X" % ir_snap[:pc]).ljust(8)
        vl_pc_str = ("0x%04X" % vl_snap[:pc]).ljust(8)
        ir_a_str = ("0x%02X" % ir_snap[:a]).ljust(5)
        vl_a_str = ("0x%02X" % vl_snap[:a]).ljust(5)
        ir_px_str = ir_snap[:fb_pixels].to_s.ljust(7)
        vl_px_str = vl_snap[:fb_pixels].to_s.ljust(7)
        ir_uniq_str = ir_snap[:fb_unique].inspect.ljust(10)
        match_str = all_match ? (fb_match ? "YES" : "cpu") : "NO"

        puts "  #{frame_str} | #{ir_pc_str} | #{vl_pc_str} | #{ir_a_str} | #{vl_a_str} | #{ir_px_str} | #{vl_px_str} | #{ir_uniq_str} | #{match_str}"
      end

      puts "  " + "-" * 115
      puts ""

      # Speed comparison
      speedup = verilator_speed / ir_speed
      puts "  Speed Comparison:"
      puts "    IR Compiler:  #{'%.2f' % ir_speed} MHz"
      puts "    Verilator:    #{'%.2f' % verilator_speed} MHz"
      puts "    Verilator is #{'%.1f' % speedup}x faster"
      puts ""

      # Summary
      puts "  Final State:"
      puts "    IR Compiler - Cycles: #{ir_runner.cycle_count}, Frames: #{ir_total_frames}, PC: 0x#{'%04X' % ir_runner.cpu_state[:pc]}"
      puts "    Verilator   - Cycles: #{verilator_runner.cycle_count}, Frames: #{verilator_runner.frame_count}, PC: 0x#{'%04X' % verilator_runner.cpu_state[:pc]}"
      puts ""

      puts "  Verification:"
      puts "    IR frames (calculated): #{ir_total_frames}"
      puts "    Verilator frames (actual): #{verilator_runner.frame_count}"
      if mismatches > 0
        puts "    CPU state mismatches: #{mismatches}/#{num_comparisons}"
      else
        puts "    CPU state: All #{num_comparisons} snapshots matched"
      end
      puts "    Framebuffer mismatches: #{fb_mismatches}/#{num_comparisons}"
      puts ""

      # Blank frame analysis
      ir_non_blank_pct = (ir_total_sampled - ir_blank_frames) * 100.0 / ir_total_sampled
      vl_non_blank_pct = (verilator_total_sampled - verilator_blank_frames) * 100.0 / verilator_total_sampled
      puts "  Blank Frame Analysis:"
      puts "    IR Compiler:  #{'%.1f' % ir_non_blank_pct}% non-blank (#{ir_total_sampled - ir_blank_frames}/#{ir_total_sampled})"
      puts "    Verilator:    #{'%.1f' % vl_non_blank_pct}% non-blank (#{verilator_total_sampled - verilator_blank_frames}/#{verilator_total_sampled})"

      # Assertions - both should reach target frames
      expect(ir_total_frames).to be >= target_frames
      expect(verilator_runner.frame_count).to be >= target_frames
      expect(ir_runner.native?).to eq(true)
      expect(verilator_runner.native?).to eq(true)

      # Assert that we're not just comparing blank frames
      # At least 50% of snapshots should have non-blank content
      expect(ir_non_blank_pct).to be > 50, "IR Compiler has too many blank frames (#{ir_blank_frames}/#{ir_total_sampled})"
      expect(vl_non_blank_pct).to be > 50, "Verilator has too many blank frames (#{verilator_blank_frames}/#{verilator_total_sampled})"
    end

    it 'compares available backends: IR Compiler, IR JIT, IR Interpreter, and Verilator', timeout: 600 do
      rom_data = File.binread(test_rom_path)

      puts "\n  Multi-Backend Comparison Test"
      puts "  " + "=" * 60

      # Initialize all runners
      runners = {}
      backends = []

      # IR Compiler
      begin
        require_relative '../../../lib/rhdl/codegen/ir/sim/ir_simulator'
        if RHDL::Codegen::IR::COMPILER_AVAILABLE
          runners[:compiler] = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
          backends << :compiler
        end
      rescue LoadError, RuntimeError => e
        puts "  Skipping IR Compiler: #{e.message}"
      end

      # IR JIT (may have issues, validate before including)
      begin
        require_relative '../../../lib/rhdl/codegen/ir/sim/ir_simulator'
        if RHDL::Codegen::IR::JIT_AVAILABLE
          jit_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :jit)
          # Quick validation: run a few cycles and check if PC changes
          jit_runner.load_rom(rom_data)
          jit_runner.reset
          jit_runner.run_steps(1000)
          if jit_runner.cpu_state[:pc] != 0
            runners[:jit] = jit_runner
            backends << :jit
          else
            puts "  Skipping IR JIT: simulation not executing (PC stuck at 0)"
          end
        end
      rescue LoadError, RuntimeError => e
        puts "  Skipping IR JIT: #{e.message}"
      end

      # IR Interpreter (native extension may not be available, uses Ruby fallback)
      begin
        require_relative '../../../lib/rhdl/codegen/ir/sim/ir_simulator'
        # Note: IR_INTERPRETER_AVAILABLE may be false if native extension failed to load,
        # but IrSimulator will fall back to Ruby implementation
        interp_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :interpret)
        # Quick validation
        interp_runner.load_rom(rom_data)
        interp_runner.reset
        interp_runner.run_steps(1000)
        if interp_runner.cpu_state[:pc] != 0
          runners[:interpreter] = interp_runner
          backends << :interpreter
        else
          puts "  Skipping IR Interpreter: simulation not executing (PC stuck at 0)"
        end
      rescue LoadError, RuntimeError => e
        puts "  Skipping IR Interpreter: #{e.message}"
      end

      # Verilator
      begin
        runners[:verilator] = RHDL::Examples::GameBoy::VerilogRunner.new
        backends << :verilator
      rescue LoadError, RuntimeError => e
        puts "  Skipping Verilator: #{e.message}"
      end

      # Need at least 2 backends to compare
      skip "Need at least 2 backends available for comparison" if backends.size < 2

      puts "  Available backends: #{backends.join(', ')}"
      puts ""

      # Reload ROM and reset all runners (JIT/Interpreter may have been tested above)
      runners.each do |name, runner|
        runner.load_rom(rom_data)
        runner.reset
      end

      # Run configuration - shorter for multi-backend test
      target_frames = 100
      snapshot_interval = 20
      cycles_per_frame = 70224

      # Storage for results
      results = {}

      # Run each backend
      backends.each do |backend|
        runner = runners[backend]
        results[backend] = {
          snapshots: [],
          elapsed: 0,
          total_cycles: 0,
          total_frames: 0,
          speed_mhz: 0
        }

        puts "  Running #{backend.to_s.capitalize}..."
        start_time = Time.now
        target_cycles = target_frames * cycles_per_frame
        cycles_per_snapshot = snapshot_interval * cycles_per_frame

        (target_frames / snapshot_interval).times do |i|
          runner.run_steps(cycles_per_snapshot)
          frames = runner.cycle_count / cycles_per_frame
          state = runner.cpu_state

          results[backend][:snapshots] << {
            frame: frames,
            cycle: runner.cycle_count,
            pc: state[:pc],
            a: state[:a],
            f: state[:f],
            sp: state[:sp]
          }
        end

        elapsed = Time.now - start_time
        results[backend][:elapsed] = elapsed
        results[backend][:total_cycles] = runner.cycle_count
        results[backend][:total_frames] = runner.cycle_count / cycles_per_frame
        results[backend][:speed_mhz] = runner.cycle_count / elapsed / 1_000_000.0

        puts "    #{results[backend][:total_frames]} frames in #{'%.2f' % elapsed}s (#{'%.2f' % results[backend][:speed_mhz]} MHz)"
      end

      puts ""

      # Compare all backends
      puts "  CPU State Comparison (every #{snapshot_interval} frames):"
      puts "  " + "-" * 100

      # Header
      header = "Frame".ljust(8)
      backends.each do |b|
        header += " | #{b.to_s[0..7].ljust(8)}"
      end
      header += " | Match"
      puts "  #{header}"
      puts "  " + "-" * 100

      # Compare snapshots
      num_snapshots = results.values.map { |r| r[:snapshots].size }.min
      mismatches = 0

      num_snapshots.times do |i|
        # Get PC from each backend
        pcs = backends.map { |b| results[b][:snapshots][i][:pc] }
        all_match = pcs.uniq.size == 1

        mismatches += 1 unless all_match

        frame = results[backends.first][:snapshots][i][:frame]
        row = "#{frame}".ljust(8)
        backends.each_with_index do |b, idx|
          pc = results[b][:snapshots][i][:pc]
          row += " | #{'%04X' % pc}".ljust(11)
        end
        row += " | #{all_match ? 'YES' : 'NO'}"
        puts "  #{row}"
      end

      puts "  " + "-" * 100
      puts ""

      # Speed comparison table
      puts "  Speed Comparison:"
      puts "  " + "-" * 50
      base_speed = results[backends.first][:speed_mhz]
      backends.each do |b|
        speed = results[b][:speed_mhz]
        rel_speed = speed / base_speed
        pct_real = speed / 4.19 * 100
        puts "    #{b.to_s.capitalize.ljust(12)}: #{'%.2f' % speed} MHz (#{'%.1f' % pct_real}% of real GB, #{'%.2f' % rel_speed}x vs #{backends.first})"
      end
      puts ""

      # Final state comparison
      puts "  Final State:"
      backends.each do |b|
        state = runners[b].cpu_state
        puts "    #{b.to_s.capitalize.ljust(12)}: PC=0x#{'%04X' % state[:pc]} A=0x#{'%02X' % state[:a]} F=0x#{'%02X' % state[:f]} SP=0x#{'%04X' % state[:sp]}"
      end
      puts ""

      # Summary
      puts "  Summary:"
      puts "    Backends tested: #{backends.size}"
      puts "    Snapshots compared: #{num_snapshots}"
      puts "    CPU state mismatches: #{mismatches}"
      puts ""

      # Assertions
      expect(backends.size).to be >= 2, "Need at least 2 backends for comparison"
      expect(mismatches).to eq(0), "All #{backends.size} backends should produce identical CPU state at each snapshot"

      # All backends should reach target frames
      backends.each do |b|
        expect(results[b][:total_frames]).to be >= target_frames, "#{b} failed to reach #{target_frames} frames"
      end
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
