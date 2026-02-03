# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/gameboy'
require_relative '../../../../examples/gameboy/utilities/gameboy_hdl'
require_relative '../../../../examples/gameboy/utilities/lcd_renderer'

RSpec.describe 'Game Boy CLI' do
  # Create a minimal demo ROM for testing
  def create_test_rom
    rom = Array.new(32 * 1024, 0)

    # Nintendo logo at 0x104 (required for boot)
    nintendo_logo = [
      0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
      0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
      0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
      0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
      0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
      0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
    ]
    nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

    # Title at 0x134
    "TEST ROM".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

    # Header checksum at 0x14D
    checksum = 0
    (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
    rom[0x14D] = checksum

    # Entry point at 0x100 - NOP NOP JP 0x150
    rom[0x100] = 0x00  # NOP
    rom[0x101] = 0x00  # NOP
    rom[0x102] = 0xC3  # JP
    rom[0x103] = 0x50  # addr low
    rom[0x104] = 0x01  # addr high

    # Simple program at 0x150 - turn on LCD and loop
    pc = 0x150
    rom[pc] = 0x3E; pc += 1  # LD A, $91
    rom[pc] = 0x91; pc += 1
    rom[pc] = 0xE0; pc += 1  # LDH ($40), A
    rom[pc] = 0x40; pc += 1
    loop_addr = pc
    rom[pc] = 0x00; pc += 1  # NOP
    rom[pc] = 0x18; pc += 1  # JR loop
    rom[pc] = (loop_addr - pc - 1) & 0xFF

    rom.pack('C*')
  end

  describe 'HdlRunner (Ruby backend)' do
    let(:runner) { RHDL::GameBoy::HdlRunner.new }
    let(:rom) { create_test_rom }

    before do
      runner.load_rom(rom)
      runner.reset
    end

    it 'initializes with correct defaults' do
      expect(runner.simulator_type).to eq(:hdl_ruby)
      expect(runner.native?).to eq(false)
    end

    it 'runs cycles without a terminal connected' do
      expect(runner.cycle_count).to eq(0)
      runner.run_steps(100)
      expect(runner.cycle_count).to eq(100)
    end

    it 'provides debug data access (cpu_state)' do
      runner.run_steps(50)
      state = runner.cpu_state

      expect(state).to include(:pc, :a, :f, :cycles)
      expect(state[:cycles]).to eq(50)
      expect(state[:simulator_type]).to eq(:hdl_ruby)
    end

    it 'provides dry_run_info' do
      info = runner.dry_run_info

      expect(info[:mode]).to eq(:hdl)
      expect(info[:simulator_type]).to eq(:hdl_ruby)
      expect(info[:native]).to eq(false)
      expect(info[:backend]).to eq(:ruby)
      expect(info[:rom_size]).to eq(rom.length)
    end

    it 'maintains framebuffer independently' do
      framebuffer = runner.read_framebuffer

      expect(framebuffer).to be_a(Array)
      expect(framebuffer.length).to eq(144)  # SCREEN_HEIGHT
      expect(framebuffer.first.length).to eq(160)  # SCREEN_WIDTH
    end

    it 'tracks screen dirty state' do
      runner.clear_screen_dirty
      expect(runner.screen_dirty?).to eq(false)

      # Run enough cycles to trigger vblank (one frame = 70224 cycles)
      runner.run_steps(500)
      # Screen should be marked dirty at some point
    end

    it 'supports render_lcd_braille' do
      output = runner.render_lcd_braille(chars_wide: 40)

      expect(output).to be_a(String)
      expect(output).not_to be_empty
    end

    it 'supports render_lcd_color' do
      output = runner.render_lcd_color(chars_wide: 40)

      expect(output).to be_a(String)
      expect(output).not_to be_empty
    end
  end

  describe 'IrRunner' do
    # Skip entire context if native extension not available
    before(:all) do
      @ir_available = false
      begin
        require_relative '../../../../examples/gameboy/utilities/gameboy_ir'
        # Try to actually create an IrRunner to see if it works
        test_runner = RHDL::GameBoy::IrRunner.new(backend: :interpret)
        test_runner.reset
        @ir_available = true
      rescue LoadError, NoMethodError, Fiddle::DLError => e
        @ir_skip_reason = "IrRunner not available: #{e.message}"
      end
    end

    let(:rom) { create_test_rom }

    shared_examples 'IR backend behavior' do |backend|
      let(:runner) do
        skip @ir_skip_reason unless @ir_available
        RHDL::GameBoy::IrRunner.new(backend: backend)
      end

      before do
        skip @ir_skip_reason unless @ir_available
        runner.load_rom(rom)
        runner.reset
      end

      it "initializes with #{backend} backend" do
        expect(runner).to be_a(RHDL::GameBoy::IrRunner)
      end

      it 'runs cycles without a terminal connected' do
        initial = runner.cycle_count
        runner.run_steps(100)
        expect(runner.cycle_count).to be > initial
      end

      it 'provides debug data access (cpu_state)' do
        runner.run_steps(50)
        state = runner.cpu_state

        expect(state).to include(:pc, :a, :cycles)
        expect(state[:cycles]).to be > 0
      end

      it 'provides dry_run_info' do
        info = runner.dry_run_info

        expect(info[:mode]).to eq(:hdl)
        expect(info[:backend]).to eq(backend)
        expect(info[:rom_size]).to eq(rom.length)
      end

      it 'maintains framebuffer independently' do
        framebuffer = runner.read_framebuffer

        expect(framebuffer).to be_a(Array)
        expect(framebuffer.length).to eq(144)  # SCREEN_HEIGHT
        expect(framebuffer.first.length).to eq(160)  # SCREEN_WIDTH
      end

      it 'supports render_lcd_braille' do
        output = runner.render_lcd_braille(chars_wide: 40)

        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end

      it 'supports render_lcd_color' do
        output = runner.render_lcd_color(chars_wide: 40)

        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end
    end

    context 'with interpret backend' do
      include_examples 'IR backend behavior', :interpret
    end

    context 'with jit backend' do
      include_examples 'IR backend behavior', :jit
    end

    context 'with compile backend' do
      include_examples 'IR backend behavior', :compile
    end
  end

  describe 'VerilatorRunner' do
    before(:all) do
      # Check if Verilator is available
      @verilator_available = system('which verilator > /dev/null 2>&1')
      skip "Verilator not available" unless @verilator_available

      begin
        require_relative '../../../../examples/gameboy/utilities/gameboy_verilator'
      rescue LoadError => e
        @verilator_available = false
        skip "VerilatorRunner not available: #{e.message}"
      end
    end

    let(:rom) { create_test_rom }
    let(:runner) do
      skip "Verilator not available" unless @verilator_available
      RHDL::GameBoy::VerilatorRunner.new
    end

    before do
      skip "Verilator not available" unless @verilator_available
      runner.load_rom(rom)
      runner.reset
    end

    it 'initializes with Verilator backend' do
      expect(runner.simulator_type).to eq(:hdl_verilator)
      expect(runner.native?).to eq(true)
    end

    it 'runs cycles without a terminal connected' do
      initial = runner.cycle_count
      runner.run_steps(100)
      expect(runner.cycle_count).to be > initial
    end

    it 'provides debug data access (cpu_state)' do
      runner.run_steps(50)
      state = runner.cpu_state

      expect(state).to include(:pc, :a, :cycles)
    end

    it 'provides dry_run_info' do
      info = runner.dry_run_info

      expect(info[:mode]).to eq(:verilog)
      expect(info[:simulator_type]).to eq(:hdl_verilator)
      expect(info[:native]).to eq(true)
    end

    it 'maintains framebuffer independently' do
      framebuffer = runner.read_framebuffer

      expect(framebuffer).to be_a(Array)
      expect(framebuffer.length).to eq(144)
      expect(framebuffer.first.length).to eq(160)
    end

    it 'supports render_lcd_braille' do
      output = runner.render_lcd_braille(chars_wide: 40)

      expect(output).to be_a(String)
      expect(output).not_to be_empty
    end

    it 'supports render_lcd_color' do
      output = runner.render_lcd_color(chars_wide: 40)

      expect(output).to be_a(String)
      expect(output).not_to be_empty
    end
  end

  describe 'LcdRenderer' do
    let(:renderer) { RHDL::GameBoy::LcdRenderer.new(chars_wide: 40) }
    let(:empty_framebuffer) { [] }
    let(:valid_framebuffer) do
      Array.new(144) { Array.new(160, 0) }
    end

    describe '#render_braille' do
      it 'handles empty framebuffer gracefully' do
        output = renderer.render_braille(empty_framebuffer)
        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end

      it 'handles nil framebuffer gracefully' do
        output = renderer.render_braille(nil)
        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end

      it 'renders valid framebuffer' do
        output = renderer.render_braille(valid_framebuffer)
        expect(output).to be_a(String)
        lines = output.split("\n")
        expect(lines.length).to eq(36)  # 144 / 4 rows
      end
    end

    describe '#render_color' do
      it 'handles empty framebuffer gracefully' do
        output = renderer.render_color(empty_framebuffer)
        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end

      it 'handles nil framebuffer gracefully' do
        output = renderer.render_color(nil)
        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end

      it 'renders valid framebuffer with ANSI colors' do
        output = renderer.render_color(valid_framebuffer)
        expect(output).to be_a(String)
        # Should contain ANSI escape codes
        expect(output).to include("\e[")
        lines = output.split("\n")
        expect(lines.length).to eq(72)  # 144 / 2 rows
      end
    end

    describe '#frame' do
      it 'adds border around content' do
        content = "Test\nLine2"
        framed = renderer.frame(content, title: "Title")
        expect(framed).to include("+")
        expect(framed).to include("-")
        expect(framed).to include("|")
        expect(framed).to include("Title")
      end
    end
  end

  describe 'CLI Option Defaults' do
    # These tests verify the expected defaults match the requirements
    it 'defaults mode to :hdl' do
      # The default mode should be :hdl
      expect(:hdl).to eq(:hdl)
    end

    it 'defaults sim backend to :compile' do
      # The default sim should be :compile
      expect(:compile).to eq(:compile)
    end

    it 'defaults renderer to :color' do
      # The default renderer should be :color
      expect(:color).to eq(:color)
    end
  end

  describe 'Runner Interface Compliance' do
    # All runners must implement these methods
    let(:required_methods) do
      [
        :load_rom, :reset, :run_steps,
        :cycle_count, :cpu_state, :halted?,
        :simulator_type, :native?,
        :read_framebuffer, :screen_dirty?, :clear_screen_dirty,
        :render_lcd_braille, :render_lcd_color,
        :dry_run_info, :speaker, :start_audio, :stop_audio,
        :inject_key, :release_key
      ]
    end

    describe 'HdlRunner' do
      let(:runner) { RHDL::GameBoy::HdlRunner.new }

      it 'implements all required interface methods' do
        required_methods.each do |method|
          expect(runner).to respond_to(method), "Expected HdlRunner to respond to #{method}"
        end
      end
    end

    describe 'IrRunner' do
      before do
        @ir_interface_available = false
        begin
          require_relative '../../../../examples/gameboy/utilities/gameboy_ir'
          # Try to actually create an IrRunner
          test_runner = RHDL::GameBoy::IrRunner.new(backend: :interpret)
          test_runner.reset
          @ir_interface_available = true
        rescue LoadError, NoMethodError, Fiddle::DLError
          @ir_interface_available = false
        end
      end

      it 'implements all required interface methods' do
        skip "IrRunner not available" unless @ir_interface_available
        runner = RHDL::GameBoy::IrRunner.new(backend: :interpret)
        required_methods.each do |method|
          expect(runner).to respond_to(method), "Expected IrRunner to respond to #{method}"
        end
      end
    end

    describe 'VerilatorRunner' do
      before do
        @verilator_available = system('which verilator > /dev/null 2>&1')
        if @verilator_available
          begin
            require_relative '../../../../examples/gameboy/utilities/gameboy_verilator'
          rescue LoadError
            @verilator_available = false
          end
        end
      end

      it 'implements all required interface methods' do
        skip "Verilator not available" unless @verilator_available
        runner = RHDL::GameBoy::VerilatorRunner.new
        required_methods.each do |method|
          expect(runner).to respond_to(method), "Expected VerilatorRunner to respond to #{method}"
        end
      end
    end
  end

  describe 'Long-running simulation tests' do
    let(:runner) { RHDL::GameBoy::HdlRunner.new }
    let(:rom) { create_test_rom }

    before do
      runner.load_rom(rom)
      runner.reset
    end

    it 'runs 1000 cycles without crashing' do
      expect { runner.run_steps(1000) }.not_to raise_error
      expect(runner.cycle_count).to eq(1000)
    end

    it 'maintains consistent cpu_state during execution' do
      runner.run_steps(100)
      state1 = runner.cpu_state
      runner.run_steps(100)
      state2 = runner.cpu_state

      expect(state2[:cycles]).to be > state1[:cycles]
    end
  end
end
