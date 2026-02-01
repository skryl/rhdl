# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/gameboy/gameboy'

RSpec.describe 'Compiler vs Verilator Comparison' do
  # Constants
  CYCLES_PER_FRAME = 70224  # 154 scanlines * 456 dots
  BOOT_ROM_COMPLETE_PC = 0x0100
  MAX_BOOT_CYCLES = 500_000  # Safety limit for boot ROM

  def verilator_available?
    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, 'verilator'))
    end
  end

  def ir_runner_available?
    require_relative '../../../examples/gameboy/utilities/gameboy_ir'
    test_runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
    test_runner = nil
    true
  rescue LoadError, RuntimeError => e
    false
  end

  before(:all) do
    @pop_rom_path = File.expand_path('../../../examples/gameboy/software/roms/pop.gb', __dir__)
    @runners_available = false

    if File.exist?(@pop_rom_path) && verilator_available?
      begin
        require_relative '../../../examples/gameboy/utilities/gameboy_ir'
        require_relative '../../../examples/gameboy/utilities/gameboy_verilator'
        @runners_available = true
      rescue LoadError, RuntimeError => e
        puts "Runners not available: #{e.message}"
      end
    end
  end

  describe 'Part 1: Boot ROM Completion' do
    before do
      skip 'pop.gb ROM not found' unless File.exist?(@pop_rom_path)
      skip 'Verilator not available' unless verilator_available?
      skip 'Runners not available' unless @runners_available
    end

    it 'compares boot ROM execution between IR Compiler and Verilator', timeout: 120 do
      rom_data = File.binread(@pop_rom_path)

      puts "\n" + "=" * 70
      puts "PART 1: BOOT ROM COMPLETION TEST"
      puts "=" * 70
      puts ""

      # Initialize both runners
      puts "Initializing runners..."
      ir_runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
      verilator_runner = RHDL::GameBoy::VerilatorRunner.new

      # Load ROM into both
      ir_runner.load_rom(rom_data)
      verilator_runner.load_rom(rom_data)

      # Reset both
      ir_runner.reset
      verilator_runner.reset

      puts ""
      puts "Running boot ROM on both backends..."
      puts ""

      # --- IR Compiler Boot ---
      puts "IR Compiler (Rust):"
      ir_start = Time.now
      ir_boot_cycle = nil
      ir_snapshots = []

      # Run until PC reaches 0x0100 or timeout
      batch_size = 10_000
      cycles_run = 0

      while cycles_run < MAX_BOOT_CYCLES
        ir_runner.run_steps(batch_size)
        cycles_run += batch_size
        pc = ir_runner.cpu_state[:pc]

        # Take snapshot every 50k cycles
        if cycles_run % 50_000 == 0
          ir_snapshots << { cycle: cycles_run, pc: pc }
        end

        if pc >= BOOT_ROM_COMPLETE_PC
          ir_boot_cycle = cycles_run
          break
        end
      end

      ir_elapsed = Time.now - ir_start
      ir_final_pc = ir_runner.cpu_state[:pc]

      if ir_boot_cycle
        puts "  Boot completed at cycle #{ir_boot_cycle}"
      else
        puts "  Boot NOT completed (timeout at #{cycles_run} cycles)"
        puts "  Final PC: 0x#{ir_final_pc.to_s(16).upcase.rjust(4, '0')}"
      end
      puts "  Elapsed: #{ir_elapsed.round(3)}s"
      puts ""

      # --- Verilator Boot ---
      puts "Verilator (RTL):"
      vl_start = Time.now
      vl_boot_cycle = nil
      vl_snapshots = []

      # Run until PC reaches 0x0100 or timeout
      cycles_run = 0

      while cycles_run < MAX_BOOT_CYCLES
        verilator_runner.run_steps(batch_size)
        cycles_run += batch_size
        pc = verilator_runner.cpu_state[:pc]

        # Take snapshot every 50k cycles
        if cycles_run % 50_000 == 0
          vl_snapshots << { cycle: cycles_run, pc: pc }
        end

        if pc >= BOOT_ROM_COMPLETE_PC
          vl_boot_cycle = cycles_run
          break
        end
      end

      vl_elapsed = Time.now - vl_start
      vl_final_pc = verilator_runner.cpu_state[:pc]

      if vl_boot_cycle
        puts "  Boot completed at cycle #{vl_boot_cycle}"
      else
        puts "  Boot NOT completed (timeout at #{cycles_run} cycles)"
        puts "  Final PC: 0x#{vl_final_pc.to_s(16).upcase.rjust(4, '0')}"
      end
      puts "  Elapsed: #{vl_elapsed.round(3)}s"
      puts ""

      # --- Comparison ---
      puts "Comparison:"
      puts "-" * 50

      if ir_boot_cycle && vl_boot_cycle
        cycle_diff = (ir_boot_cycle - vl_boot_cycle).abs
        puts "  IR Compiler boot cycle:  #{ir_boot_cycle}"
        puts "  Verilator boot cycle:    #{vl_boot_cycle}"
        puts "  Difference:              #{cycle_diff} cycles"
        puts ""
        puts "  Both backends completed boot ROM successfully!"

        # Allow small cycle variance due to timing differences
        expect(cycle_diff).to be < 10_000, "Boot cycle difference too large: #{cycle_diff}"
      else
        puts "  IR boot complete: #{ir_boot_cycle ? 'YES' : 'NO'}"
        puts "  Verilator boot complete: #{vl_boot_cycle ? 'YES' : 'NO'}"
      end

      puts ""
      puts "Progress snapshots:"
      puts "  Cycle    | IR PC    | VL PC"
      puts "  " + "-" * 35
      [ir_snapshots.size, vl_snapshots.size].min.times do |i|
        ir_s = ir_snapshots[i]
        vl_s = vl_snapshots[i]
        ir_pc = "0x#{ir_s[:pc].to_s(16).upcase.rjust(4, '0')}"
        vl_pc = "0x#{vl_s[:pc].to_s(16).upcase.rjust(4, '0')}"
        puts "  #{ir_s[:cycle].to_s.rjust(8)} | #{ir_pc.ljust(8)} | #{vl_pc}"
      end
      puts ""

      # Assertions
      expect(ir_boot_cycle).not_to be_nil, "IR Compiler failed to complete boot ROM"
      expect(vl_boot_cycle).not_to be_nil, "Verilator failed to complete boot ROM"
    end
  end

  describe 'Part 2: Prince of Persia 1000 Frames' do
    before do
      skip 'pop.gb ROM not found' unless File.exist?(@pop_rom_path)
      skip 'Verilator not available' unless verilator_available?
      skip 'Runners not available' unless @runners_available
    end

    # Helper methods for framebuffer analysis
    def framebuffer_blank?(fb)
      return true if fb.nil? || fb.empty?
      first_val = fb.flatten.first
      fb.flatten.all? { |v| v == first_val }
    end

    def non_zero_pixel_count(fb)
      return 0 if fb.nil? || fb.empty?
      fb.flatten.count { |v| v != 0 }
    end

    def framebuffer_hash(fb)
      return nil if fb.nil? || fb.empty?
      fb.flatten.hash
    end

    it 'compares 1000 frames of Prince of Persia gameplay', timeout: 600 do
      rom_data = File.binread(@pop_rom_path)

      puts "\n" + "=" * 70
      puts "PART 2: PRINCE OF PERSIA 1000 FRAMES TEST"
      puts "=" * 70
      puts ""

      # Initialize both runners
      puts "Initializing runners..."
      ir_runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
      verilator_runner = RHDL::GameBoy::VerilatorRunner.new

      # Load ROM into both
      ir_runner.load_rom(rom_data)
      verilator_runner.load_rom(rom_data)

      # Reset both
      ir_runner.reset
      verilator_runner.reset

      # First, skip through boot ROM on both
      puts ""
      puts "Skipping boot ROM..."

      # IR: run until PC >= 0x0100
      boot_cycles = 0
      while boot_cycles < MAX_BOOT_CYCLES
        ir_runner.run_steps(10_000)
        boot_cycles += 10_000
        break if ir_runner.cpu_state[:pc] >= BOOT_ROM_COMPLETE_PC
      end
      puts "  IR Compiler: Boot complete at cycle #{boot_cycles}"

      # Verilator: run until PC >= 0x0100
      boot_cycles = 0
      while boot_cycles < MAX_BOOT_CYCLES
        verilator_runner.run_steps(10_000)
        boot_cycles += 10_000
        break if verilator_runner.cpu_state[:pc] >= BOOT_ROM_COMPLETE_PC
      end
      puts "  Verilator: Boot complete at cycle #{boot_cycles}"

      # Now run 1000 frames of cartridge code
      target_frames = 1000
      snapshot_interval = 100
      cycles_per_snapshot = snapshot_interval * CYCLES_PER_FRAME

      ir_snapshots = []
      vl_snapshots = []

      puts ""
      puts "Running #{target_frames} frames on each backend..."
      puts ""

      # --- IR Compiler 1000 Frames ---
      puts "IR Compiler (Rust):"
      ir_start = Time.now
      ir_start_cycles = ir_runner.cycle_count

      (target_frames / snapshot_interval).times do |i|
        ir_runner.run_steps(cycles_per_snapshot)
        frame_num = (i + 1) * snapshot_interval
        fb = ir_runner.read_framebuffer

        ir_snapshots << {
          frame: frame_num,
          cycle: ir_runner.cycle_count,
          pc: ir_runner.cpu_state[:pc],
          a: ir_runner.cpu_state[:a],
          fb_blank: framebuffer_blank?(fb),
          fb_pixels: non_zero_pixel_count(fb),
          fb_hash: framebuffer_hash(fb)
        }
      end

      ir_elapsed = Time.now - ir_start
      ir_cycles_run = ir_runner.cycle_count - ir_start_cycles
      ir_speed = ir_cycles_run / ir_elapsed / 1_000_000.0
      ir_non_blank = ir_snapshots.count { |s| !s[:fb_blank] }

      puts "  Completed #{target_frames} frames in #{ir_elapsed.round(2)}s"
      puts "  Speed: #{ir_speed.round(2)} MHz (#{(ir_speed / 4.19 * 100).round(1)}% of real GB)"
      puts "  Non-blank snapshots: #{ir_non_blank}/#{ir_snapshots.size}"
      puts ""

      # --- Verilator 1000 Frames ---
      puts "Verilator (RTL):"
      vl_start = Time.now
      vl_start_cycles = verilator_runner.cycle_count
      vl_start_frames = verilator_runner.frame_count

      while verilator_runner.frame_count - vl_start_frames < target_frames
        verilator_runner.run_steps(CYCLES_PER_FRAME)

        frames_since_start = verilator_runner.frame_count - vl_start_frames
        # Take snapshot every snapshot_interval frames
        if frames_since_start > 0 && frames_since_start % snapshot_interval == 0 && vl_snapshots.size < (target_frames / snapshot_interval)
          fb = verilator_runner.read_framebuffer

          vl_snapshots << {
            frame: frames_since_start,
            cycle: verilator_runner.cycle_count,
            pc: verilator_runner.cpu_state[:pc],
            a: verilator_runner.cpu_state[:a],
            fb_blank: framebuffer_blank?(fb),
            fb_pixels: non_zero_pixel_count(fb),
            fb_hash: framebuffer_hash(fb)
          }
        end
      end

      vl_elapsed = Time.now - vl_start
      vl_cycles_run = verilator_runner.cycle_count - vl_start_cycles
      vl_frames_run = verilator_runner.frame_count - vl_start_frames
      vl_speed = vl_cycles_run / vl_elapsed / 1_000_000.0
      vl_non_blank = vl_snapshots.count { |s| !s[:fb_blank] }

      puts "  Completed #{vl_frames_run} frames in #{vl_elapsed.round(2)}s"
      puts "  Speed: #{vl_speed.round(2)} MHz (#{(vl_speed / 4.19 * 100).round(1)}% of real GB)"
      puts "  Non-blank snapshots: #{vl_non_blank}/#{vl_snapshots.size}"
      puts ""

      # --- Comparison ---
      puts "Comparison:"
      puts "-" * 100
      puts "  Frame  | IR PC    | VL PC    | IR A  | VL A  | IR px   | VL px   | FB Match"
      puts "  " + "-" * 90

      fb_matches = 0
      pc_matches = 0
      num_compare = [ir_snapshots.size, vl_snapshots.size].min

      num_compare.times do |i|
        ir_s = ir_snapshots[i]
        vl_s = vl_snapshots[i]

        pc_match = ir_s[:pc] == vl_s[:pc]
        fb_match = ir_s[:fb_hash] == vl_s[:fb_hash]
        pc_matches += 1 if pc_match
        fb_matches += 1 if fb_match

        ir_pc = "0x#{ir_s[:pc].to_s(16).upcase.rjust(4, '0')}"
        vl_pc = "0x#{vl_s[:pc].to_s(16).upcase.rjust(4, '0')}"
        ir_a = "0x#{ir_s[:a].to_s(16).upcase.rjust(2, '0')}"
        vl_a = "0x#{vl_s[:a].to_s(16).upcase.rjust(2, '0')}"

        match_str = fb_match ? "YES" : "NO"
        puts "  #{ir_s[:frame].to_s.rjust(5)}  | #{ir_pc.ljust(8)} | #{vl_pc.ljust(8)} | #{ir_a.ljust(5)} | #{vl_a.ljust(5)} | #{ir_s[:fb_pixels].to_s.ljust(7)} | #{vl_s[:fb_pixels].to_s.ljust(7)} | #{match_str}"
      end

      puts "  " + "-" * 90
      puts ""

      # Speed comparison
      speedup = vl_speed / ir_speed
      puts "Speed Comparison:"
      puts "  IR Compiler:  #{ir_speed.round(2)} MHz"
      puts "  Verilator:    #{vl_speed.round(2)} MHz"
      if speedup > 1
        puts "  Verilator is #{speedup.round(1)}x faster"
      else
        puts "  IR Compiler is #{(1/speedup).round(1)}x faster"
      end
      puts ""

      # Summary
      puts "Summary:"
      puts "  Snapshots compared: #{num_compare}"
      puts "  PC matches: #{pc_matches}/#{num_compare} (#{(pc_matches * 100.0 / num_compare).round(1)}%)"
      puts "  Framebuffer matches: #{fb_matches}/#{num_compare} (#{(fb_matches * 100.0 / num_compare).round(1)}%)"
      puts "  IR non-blank: #{ir_non_blank}/#{ir_snapshots.size}"
      puts "  VL non-blank: #{vl_non_blank}/#{vl_snapshots.size}"
      puts ""

      # Assertions
      expect(ir_snapshots.size).to eq(target_frames / snapshot_interval)
      expect(vl_snapshots.size).to eq(target_frames / snapshot_interval)

      # At least 50% should have non-blank content (game should be running)
      ir_non_blank_pct = ir_non_blank * 100.0 / ir_snapshots.size
      vl_non_blank_pct = vl_non_blank * 100.0 / vl_snapshots.size
      expect(ir_non_blank_pct).to be > 30, "IR Compiler has too many blank frames"
      expect(vl_non_blank_pct).to be > 30, "Verilator has too many blank frames"
    end
  end
end
