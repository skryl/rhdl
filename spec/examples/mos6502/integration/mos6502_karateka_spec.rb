# frozen_string_literal: true

require 'spec_helper'

# Load the runner utilities
require_relative '../../../../examples/mos6502/utilities/apple2/bus'
require_relative '../../../../examples/mos6502/utilities/simulators/isa_simulator'
require_relative '../../../../examples/mos6502/utilities/runners/isa_runner'
require_relative '../../../../examples/mos6502/utilities/renderers/color_renderer'

RSpec.describe 'MOS6502 Karateka Mode' do
  let(:karateka_mem) { File.expand_path('../../../../examples/mos6502/software/disks/karateka_mem.bin', __dir__) }
  let(:appleiigo_rom) { File.expand_path('../../../../examples/mos6502/software/roms/appleiigo.rom', __dir__) }

  before(:each) do
    skip "Karateka memory dump not found" unless File.exist?(karateka_mem)
    skip "AppleIIGo ROM not found" unless File.exist?(appleiigo_rom)
  end

  # Helper to set reset vector bypassing ROM protection
  # ROM protection blocks writes to $FFFC/$FFFD after load_rom is called
  def set_reset_vector(bus, addr)
    memory = bus.instance_variable_get(:@memory)
    memory[0xFFFC] = addr & 0xFF
    memory[0xFFFD] = (addr >> 8) & 0xFF
  end

  describe 'ISA mode with karateka' do
    let(:runner) do
      bus = RHDL::Examples::MOS6502::Apple2Bus.new("test_bus")
      cpu = RHDL::Examples::MOS6502::ISASimulator.new(bus)
      RHDL::Examples::MOS6502::RubyISARunner.new(bus, cpu)
    end

    it 'loads ROM and memory dump successfully' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      # Load ROM at $D000 and memory dump at $0000
      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)

      # Set up reset vector to karateka entry point (bypass ROM protection)
      set_reset_vector(runner.bus, 0xB82A)

      # Verify reset vector is set correctly
      reset_lo = runner.bus.read(0xFFFC)
      reset_hi = runner.bus.read(0xFFFD)
      reset_addr = reset_lo | (reset_hi << 8)
      expect(reset_addr).to eq(0xB82A)
    end

    it 'resets CPU to entry point and runs cycles' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)

      # Set up reset vector (bypass ROM protection)
      set_reset_vector(runner.bus, 0xB82A)

      # Reset CPU - this should set PC to $B82A
      runner.reset

      state = runner.cpu_state
      expect(state[:pc]).to eq(0xB82A)

      # Run some cycles
      runner.run_steps(100)

      # PC should have advanced
      new_state = runner.cpu_state
      expect(new_state[:cycles]).to be > 0
    end

    it 'executes karateka code for 1000 cycles without crashing' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)

      # Set up reset vector (bypass ROM protection)
      set_reset_vector(runner.bus, 0xB82A)

      runner.reset

      # Run 1000 cycles
      runner.run_steps(1000)

      state = runner.cpu_state
      # Should have executed cycles without halting (no BRK)
      expect(state[:halted]).to be(false)
      expect(state[:cycles]).to be >= 1000
    end

    it 'can read and write to text page memory' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)

      # Text page is at $0400-$07FF
      # Write a test value
      runner.bus.write(0x0400, 0x41)  # 'A'
      expect(runner.bus.read(0x0400)).to eq(0x41)

      # Read screen array (returns 24 rows of 40 columns each)
      screen = runner.read_screen_array
      expect(screen).to be_a(Array)
      expect(screen.length).to eq(24)  # 24 lines
      expect(screen.first.length).to eq(40)  # 40 columns per line
    end
  end

  describe 'HDL mode with karateka', :slow do
    # Note: HDL mode tests are marked slow and may be skipped in normal runs
    # They require the IR simulator which may not have native extensions built

    # Helper to create and run an IR simulator with the given backend
    def run_hdl_test(sim_type, rom_bytes, mem_bytes)
      begin
        require_relative '../../../examples/mos6502/utilities/runners/ir_runner'
      rescue LoadError => e
        skip "IR simulator runner not available: #{e.message}"
      end

      begin
        runner = IRSimulatorRunner.new(sim_type)
        runner.load_rom(rom_bytes, base_addr: 0xD000)
        runner.load_ram(mem_bytes, base_addr: 0x0000)
      rescue RuntimeError => e
        skip "IR #{sim_type} backend not available: #{e.message}"
      rescue JSON::NestingError => e
        skip "MOS6502 CPU IR is too deeply nested for JSON conversion: #{e.message}"
      end

      # Set up reset vector (bypass ROM protection - uses runner method for Rust+Ruby sync)
      runner.set_reset_vector(0xB82A)

      runner.reset

      state = runner.cpu_state
      expect(state[:pc]).to be_a(Integer)

      # Run 100k cycles to verify sustained execution
      runner.run_steps(100_000)

      new_state = runner.cpu_state
      expect(new_state[:cycles]).to be >= 100_000
    end

    it 'loads and runs with IR interpret backend' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes
      run_hdl_test(:interpret, rom_bytes, mem_bytes)
    end

    it 'loads and runs with IR jit backend' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes
      run_hdl_test(:jit, rom_bytes, mem_bytes)
    end

    it 'loads and runs with IR compile backend' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes
      run_hdl_test(:compile, rom_bytes, mem_bytes)
    end
  end

  describe 'ISA mode behavior consistency' do
    let(:runner) do
      bus = RHDL::Examples::MOS6502::Apple2Bus.new("test_bus")
      cpu = RHDL::Examples::MOS6502::ISASimulator.new(bus)
      RHDL::Examples::MOS6502::RubyISARunner.new(bus, cpu)
    end

    it 'executes deterministically - same input produces same output' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      # First run
      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)
      set_reset_vector(runner.bus, 0xB82A)
      runner.reset
      runner.run_steps(500)
      state1 = runner.cpu_state

      # Create new runner and do second run
      bus2 = RHDL::Examples::MOS6502::Apple2Bus.new("test_bus2")
      cpu2 = RHDL::Examples::MOS6502::ISASimulator.new(bus2)
      runner2 = RHDL::Examples::MOS6502::RubyISARunner.new(bus2, cpu2)

      runner2.load_rom(rom_bytes, base_addr: 0xD000)
      runner2.load_ram(mem_bytes, base_addr: 0x0000)
      set_reset_vector(runner2.bus, 0xB82A)
      runner2.reset
      runner2.run_steps(500)
      state2 = runner2.cpu_state

      # Should produce identical results
      expect(state2[:pc]).to eq(state1[:pc])
      expect(state2[:a]).to eq(state1[:a])
      expect(state2[:x]).to eq(state1[:x])
      expect(state2[:y]).to eq(state1[:y])
      expect(state2[:sp]).to eq(state1[:sp])
    end
  end

  describe 'Color graphics rendering', :slow do
    let(:runner) do
      bus = RHDL::Examples::MOS6502::Apple2Bus.new("test_bus")
      cpu = RHDL::Examples::MOS6502::ISASimulator.new(bus)
      RHDL::Examples::MOS6502::RubyISARunner.new(bus, cpu)
    end

    it 'produces color graphics output after 6 million cycles' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)

      # Set up reset vector (bypass ROM protection)
      set_reset_vector(runner.bus, 0xB82A)

      # Set HIRES mode soft switches
      runner.bus.read(0xC050)  # TXTCLR - graphics mode
      runner.bus.read(0xC052)  # MIXCLR - full screen
      runner.bus.read(0xC054)  # PAGE1 - page 1
      runner.bus.read(0xC057)  # HIRES - hi-res mode

      runner.reset

      # Run 6 million cycles to get through intro animation
      runner.run_steps(6_000_000)

      state = runner.cpu_state
      expect(state[:halted]).to be(false)
      expect(state[:cycles]).to be >= 6_000_000

      # Render color graphics
      color_output = runner.bus.render_hires_color(chars_wide: 70)

      # Verify we got output
      expect(color_output).to be_a(String)
      expect(color_output.length).to be > 0

      # Color output should have ANSI escape sequences for colors
      expect(color_output).to include("\e[")

      # Should have multiple lines (96 lines in color mode for 192 pixels / 2)
      lines = color_output.split("\n")
      expect(lines.length).to eq(96)

      # Verify the renderer uses color escape sequences (truecolor format)
      # The output may be mostly black during loading, but should have some color content
      # or at minimum the structure of the color output
      color_escapes = color_output.scan(/\e\[38;2;\d+;\d+;\d+m/)
      reset_escapes = color_output.scan(/\e\[0m/)

      # At minimum, we should have reset sequences (for line endings)
      expect(reset_escapes.length).to be >= 96, "Expected reset sequences at end of each line"

      # Check that the color renderer can produce the expected NTSC colors
      # These are the hex values for the color palette
      # Green: 20, 245, 60 (0x14, 0xF5, 0x3C)
      # Purple: 214, 96, 239 (0xD6, 0x60, 0xEF)
      # Orange: 255, 106, 60 (0xFF, 0x6A, 0x3C)
      # Blue: 20, 207, 253 (0x14, 0xCF, 0xFD)
      # White: 255, 255, 255
      # If there are any foreground colors, verify they're from the expected palette
      if color_escapes.any?
        valid_colors = [
          "38;2;20;245;60",   # green
          "38;2;214;96;239",  # purple
          "38;2;255;106;60",  # orange
          "38;2;20;207;253",  # blue
          "38;2;255;255;255"  # white
        ]
        colors_found = color_escapes.map { |e| e.gsub(/\e\[/, "").gsub(/m$/, "") }
        colors_found.each do |color|
          expect(valid_colors).to include(color), "Unexpected color: #{color}"
        end
      end

      # Verify the hires page has been modified (has non-zero content)
      hires_bytes = (0x2000..0x3FFF).map { |addr| runner.bus.read(addr) }
      non_zero_bytes = hires_bytes.count { |b| b != 0 }
      expect(non_zero_bytes).to be > 0, "Expected hi-res page to have content after 6M cycles"
    end

    it 'color renderer produces valid output for hires memory' do
      rom_bytes = File.binread(appleiigo_rom).bytes
      mem_bytes = File.binread(karateka_mem).bytes

      runner.load_rom(rom_bytes, base_addr: 0xD000)
      runner.load_ram(mem_bytes, base_addr: 0x0000)

      # The karateka memory dump already has graphics content at HIRES page 1 ($2000-$3FFF)
      # Test that the color renderer can process it directly
      renderer = RHDL::Examples::MOS6502::ColorRenderer.new(chars_wide: 70)

      # Create a memory accessor that reads from the bus
      ram = ->(addr) { runner.bus.read(addr) }

      color_output = renderer.render(ram, base_addr: 0x2000, chars_wide: 70)

      expect(color_output).to be_a(String)
      expect(color_output.length).to be > 0

      # Should have 96 lines (192 pixels / 2 for half-block chars)
      lines = color_output.split("\n")
      expect(lines.length).to eq(96)
    end
  end
end
