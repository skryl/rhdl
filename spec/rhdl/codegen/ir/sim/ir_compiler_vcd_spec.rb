# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'
require 'tempfile'

RSpec.describe 'IrCompiler VCD Tracing' do
  # Tests for the VCD (Value Change Dump) signal tracing functionality.
  # VCD is the IEEE 1364-2001 standard format for waveform dumps,
  # viewable in tools like GTKWave.
  #
  # These tests use the Game Boy IR since it's a realistic, well-tested IR
  # that exercises the full VCD tracing functionality.

  before(:all) do
    skip 'IR Compiler not available' unless RHDL::Codegen::IR::COMPILER_AVAILABLE

    @rom_path = File.expand_path('../../../../../../examples/gameboy/software/roms/pop.gb', __FILE__)
    @rom_available = File.exist?(@rom_path)
  end

  def create_gameboy_simulator
    require_relative '../../../../../examples/gameboy/gameboy'
    require_relative '../../../../../examples/gameboy/utilities/runners/ir_runner'

    runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
    if @rom_available
      rom_data = File.binread(@rom_path)
      runner.load_rom(rom_data)
    end
    runner.reset
    runner
  end

  describe 'trace control' do
    it 'starts disabled by default' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      expect(sim.trace_enabled?).to be false
    end

    it 'can start and stop tracing' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_start
      expect(sim.trace_enabled?).to be true

      sim.trace_stop
      expect(sim.trace_enabled?).to be false
    end

    it 'can clear trace data' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('clk')
      sim.trace_start

      # Run some cycles and capture
      10.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      expect(sim.trace_change_count).to be > 0

      sim.trace_clear
      expect(sim.trace_change_count).to eq(0)
    end
  end

  describe 'signal selection' do
    it 'reports traced signals after configuration' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('cpu')
      expect(sim.trace_signal_count).to be > 0
    end

    it 'can add signals by name' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      # Find an actual signal name to test with
      # Use pattern matching to discover a valid signal name
      count = sim.trace_add_signals_matching('cpu_addr')
      expect(count).to be > 0

      result = sim.trace_add_signal('nonexistent_signal_xyz')
      expect(result).to be false
    end

    it 'can add signals by pattern matching' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      count = sim.trace_add_signals_matching('vram')
      expect(count).to be > 0

      puts "\n  Found #{count} signals matching 'vram'"
    end

    it 'can trace all signals' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_all_signals
      traced_count = sim.trace_signal_count
      total_count = sim.signal_count

      expect(traced_count).to be > 0
      # Note: traced count may be slightly less than signal_count due to
      # how signals are indexed (some may not have names in name_to_idx map)
      expect(traced_count).to be >= (total_count * 0.95)  # At least 95% coverage

      puts "\n  Total signals: #{total_count}, Traced: #{traced_count}"
    end

    it 'can clear signal selection' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_all_signals
      expect(sim.trace_signal_count).to be > 0

      sim.trace_clear_signals
      expect(sim.trace_signal_count).to eq(0)
    end
  end

  describe 'buffer mode tracing' do
    it 'captures signal changes in buffer mode' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('clk')
      sim.trace_add_signals_matching('cpu_addr')
      sim.trace_add_signals_matching('cpu_do')

      sim.trace_start

      # Run some cycles
      100.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      # Should have captured changes
      expect(sim.trace_change_count).to be > 0

      puts "\n  Captured #{sim.trace_change_count} signal changes"
    end

    it 'generates valid VCD output' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('cpu')
      sim.trace_start

      50.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd

      # Verify VCD structure
      expect(vcd).to include('$timescale')
      expect(vcd).to include('$scope module')
      expect(vcd).to include('$var wire')
      expect(vcd).to include('$upscope $end')
      expect(vcd).to include('$enddefinitions $end')
      expect(vcd).to include('$dumpvars')
      expect(vcd).to include('#')  # Time markers

      puts "\n  VCD output size: #{vcd.length} bytes"
    end

    it 'can save VCD to file' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('vram')
      sim.trace_start

      50.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      Tempfile.create(['test_trace', '.vcd']) do |f|
        path = f.path
        result = sim.trace_save_vcd(path)
        expect(result).to be true
        expect(File.exist?(path)).to be true
        expect(File.size(path)).to be > 0

        content = File.read(path)
        expect(content).to include('$timescale')

        puts "\n  Saved VCD file: #{File.size(path)} bytes"
      end
    end
  end

  describe 'streaming mode tracing' do
    it 'can write VCD directly to file in streaming mode' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      Tempfile.create(['stream_trace', '.vcd']) do |f|
        path = f.path

        sim.trace_add_signals_matching('cpu')
        result = sim.trace_start_streaming(path)
        expect(result).to be true
        expect(sim.trace_enabled?).to be true

        # Run cycles
        100.times do
          runner.run_steps(1)
          sim.trace_capture
        end

        sim.trace_stop

        # File should exist with content
        expect(File.exist?(path)).to be true
        content = File.read(path)
        expect(content.length).to be > 0
        expect(content).to include('$timescale')

        puts "\n  Streamed VCD file: #{content.length} bytes"
      end
    end
  end

  describe 'VCD format compliance' do
    it 'uses correct VCD variable declarations' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('cpu_addr')
      sim.trace_start

      10.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd

      # Check for proper wire declarations
      # Format: $var wire <width> <id> <name> $end
      expect(vcd).to match(/\$var wire \d+ \S+ \w+ \$end/)
    end

    it 'properly encodes multi-bit values' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      # cpu_addr is a 16-bit signal
      sim.trace_add_signals_matching('cpu_addr')
      sim.trace_start

      20.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd

      # Multi-bit values use b<binary> <id> format
      expect(vcd).to match(/b[01]+ \S+/)
    end

    it 'uses correct time markers' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('clk')
      sim.trace_start

      10.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd

      # Time markers start with #
      expect(vcd).to match(/#\d+/)
    end
  end

  describe 'configuration options' do
    it 'can set custom timescale' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      result = sim.trace_set_timescale('10ps')
      expect(result).to be true

      sim.trace_add_signals_matching('clk')
      sim.trace_start

      5.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd
      expect(vcd).to include('$timescale 10ps $end')
    end

    it 'can set custom module name' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      result = sim.trace_set_module_name('gameboy_core')
      expect(result).to be true

      sim.trace_add_signals_matching('clk')
      sim.trace_start

      5.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd
      expect(vcd).to include('$scope module gameboy_core $end')
    end
  end

  describe 'edge cases' do
    it 'handles tracing with minimal signal changes' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      # Select a signal that changes infrequently
      sim.trace_add_signals_matching('boot_rom_enabled')
      sim.trace_start

      # Capture same state multiple times
      5.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      # Should still produce valid VCD
      vcd = sim.trace_to_vcd
      expect(vcd).not_to be_empty
      expect(vcd).to include('$timescale')
    end

    it 'handles empty trace (no captures)' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      sim.trace_add_signals_matching('cpu')
      sim.trace_start
      sim.trace_stop

      vcd = sim.trace_to_vcd
      # Should still have header
      expect(vcd).to include('$timescale')
    end

    it 'handles multiple trace sessions' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      # First session
      sim.trace_add_signals_matching('clk')
      sim.trace_start

      20.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      first_count = sim.trace_change_count
      expect(first_count).to be > 0

      # Clear and start second session
      sim.trace_clear
      expect(sim.trace_change_count).to eq(0)

      sim.trace_start

      5.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      # Second session should have independent count
      second_count = sim.trace_change_count
      expect(second_count).to be < first_count

      puts "\n  First session: #{first_count} changes, Second session: #{second_count} changes"
    end
  end

  describe 'VRAM signal tracing for debugging' do
    it 'can trace VRAM write signals during boot ROM' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      # Add VRAM-related signals for debugging
      vram_count = sim.trace_add_signals_matching('vram')
      cpu_addr_count = sim.trace_add_signals_matching('cpu_addr')
      cpu_do_count = sim.trace_add_signals_matching('cpu_do')

      puts "\n  Tracing signals: #{vram_count} vram, #{cpu_addr_count} cpu_addr, #{cpu_do_count} cpu_do"

      sim.trace_set_module_name('gameboy')
      sim.trace_start

      # Run enough cycles to see some VRAM activity
      500.times do
        runner.run_steps(1)
        sim.trace_capture
      end

      sim.trace_stop

      vcd = sim.trace_to_vcd

      puts "  VCD output: #{vcd.length} bytes"
      puts "  Total changes: #{sim.trace_change_count}"

      expect(vcd.length).to be > 1000
      expect(sim.trace_change_count).to be > 0
    end

    it 'can save detailed boot ROM trace to file' do
      skip 'ROM not available' unless @rom_available

      runner = create_gameboy_simulator
      sim = runner.sim

      trace_path = File.join(Dir.tmpdir, "gameboy_boot_trace_#{Process.pid}.vcd")

      begin
        # Trace boot ROM related signals
        sim.trace_add_signals_matching('boot')
        sim.trace_add_signals_matching('cpu_addr')
        sim.trace_add_signals_matching('cpu_do')
        sim.trace_add_signals_matching('cpu_wr')
        sim.trace_add_signals_matching('vram_wren')
        sim.trace_add_signals_matching('sel_vram')

        sim.trace_set_module_name('gameboy_boot')
        sim.trace_set_timescale('1ns')

        # Use streaming mode for large traces
        result = sim.trace_start_streaming(trace_path)
        expect(result).to be true

        # Run boot ROM
        1000.times do
          runner.run_steps(1)
          sim.trace_capture
        end

        sim.trace_stop

        expect(File.exist?(trace_path)).to be true
        size = File.size(trace_path)
        expect(size).to be > 0

        puts "\n  Boot trace saved to: #{trace_path}"
        puts "  File size: #{size} bytes"

        # Verify VCD structure
        content = File.read(trace_path)
        expect(content).to include('$scope module gameboy_boot $end')
        expect(content).to include('$timescale 1ns $end')
      ensure
        File.delete(trace_path) if File.exist?(trace_path)
      end
    end
  end
end
