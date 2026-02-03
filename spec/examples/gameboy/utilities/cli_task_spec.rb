# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/gameboy'
require_relative '../../../../examples/gameboy/utilities/gameboy_hdl'
require_relative '../../../../examples/gameboy/utilities/lcd_renderer'

# Load the GameBoyCli class from bin/gb
# The bin/gb file has a guard that only runs CLI parsing when executed directly
$LOAD_PATH.unshift File.expand_path('../../../../examples/gameboy/utilities', __dir__)
load File.expand_path('../../../../examples/gameboy/bin/gb', __dir__)

RSpec.describe 'GameBoyCli Runner Selection' do
  # Check availability of various backends
  before(:all) do
    @ir_available = false
    begin
      require_relative '../../../../examples/gameboy/utilities/gameboy_ir'
      test_runner = RHDL::GameBoy::IrRunner.new(backend: :interpret)
      test_runner.reset
      @ir_available = true
    rescue LoadError, NoMethodError, Fiddle::DLError
      @ir_available = false
    end

    @verilator_available = system('which verilator > /dev/null 2>&1')
    if @verilator_available
      begin
        require_relative '../../../../examples/gameboy/utilities/gameboy_verilator'
      rescue LoadError
        @verilator_available = false
      end
    end
  end

  describe 'mode: :hdl' do
    describe 'with sim: :ruby' do
      let(:cli) { GameBoyCli.new(mode: :hdl, sim: :ruby) }

      it 'returns HdlRunner' do
        expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
      end

      it 'has simulator_type :hdl_ruby' do
        expect(cli.runner.simulator_type).to eq(:hdl_ruby)
      end

      it 'is not native' do
        expect(cli.runner.native?).to eq(false)
      end
    end

    describe 'with sim: :interpret' do
      let(:cli) { GameBoyCli.new(mode: :hdl, sim: :interpret) }

      it 'returns IrRunner when available, falls back to HdlRunner otherwise' do
        if @ir_available
          expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
        else
          expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
        end
      end
    end

    describe 'with sim: :jit' do
      let(:cli) { GameBoyCli.new(mode: :hdl, sim: :jit) }

      it 'returns IrRunner when available, falls back to HdlRunner otherwise' do
        if @ir_available
          expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
        else
          expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
        end
      end
    end

    describe 'with sim: :compile' do
      let(:cli) { GameBoyCli.new(mode: :hdl, sim: :compile) }

      it 'returns IrRunner when available, falls back to HdlRunner otherwise' do
        if @ir_available
          expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
        else
          expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
        end
      end
    end

    describe 'with default sim (compile)' do
      let(:cli) { GameBoyCli.new(mode: :hdl) }

      it 'defaults sim backend and uses appropriate runner' do
        # When native is available, uses IrRunner; otherwise HdlRunner
        if @ir_available
          expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
        else
          expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
        end
      end
    end
  end

  describe 'mode: :verilog' do
    context 'when Verilator is available' do
      before { skip "Verilator not available" unless @verilator_available }

      it 'returns VerilatorRunner' do
        cli = GameBoyCli.new(mode: :verilog)
        expect(cli.runner).to be_a(RHDL::GameBoy::VerilatorRunner)
      end

      it 'has simulator_type :hdl_verilator' do
        cli = GameBoyCli.new(mode: :verilog)
        expect(cli.runner.simulator_type).to eq(:hdl_verilator)
      end

      it 'is native' do
        cli = GameBoyCli.new(mode: :verilog)
        expect(cli.runner.native?).to eq(true)
      end
    end

    context 'when Verilator is not available' do
      before { skip "Verilator is available, cannot test unavailable path" if @verilator_available }

      it 'raises ArgumentError' do
        expect { GameBoyCli.new(mode: :verilog) }.to raise_error(ArgumentError, /Verilator/)
      end
    end
  end

  describe 'default mode' do
    let(:cli) { GameBoyCli.new({}) }

    it 'defaults to mode: :hdl' do
      # Default should be HDL mode with compile backend (or ruby fallback)
      expect(cli.runner).to respond_to(:simulator_type)
    end
  end

  describe 'invalid mode' do
    it 'raises ArgumentError for unknown mode' do
      expect { GameBoyCli.new(mode: :invalid) }.to raise_error(ArgumentError, /Unknown mode/)
    end
  end

  describe 'option combinations matrix' do
    # Test all valid combinations of mode and sim
    context 'mode: :hdl, sim: :ruby' do
      let(:cli) { GameBoyCli.new(mode: :hdl, sim: :ruby) }

      it 'returns HdlRunner' do
        expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
      end

      it 'native? returns false' do
        expect(cli.runner.native?).to eq(false)
      end
    end

    # Native backend combinations (conditional on availability)
    [:interpret, :jit, :compile].each do |backend|
      context "mode: :hdl, sim: #{backend} (native)" do
        it "returns IrRunner when available, HdlRunner otherwise" do
          cli = GameBoyCli.new(mode: :hdl, sim: backend)
          if @ir_available
            expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
            expect(cli.runner.native?).to eq(true)
          else
            expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
            expect(cli.runner.native?).to eq(false)
          end
        end
      end
    end
  end

  describe 'runner interface' do
    # Verify the returned runner has all required methods
    let(:required_methods) do
      [
        :load_rom, :reset, :run_steps,
        :cycle_count, :cpu_state, :halted?,
        :simulator_type, :native?,
        :read_framebuffer, :screen_dirty?, :clear_screen_dirty,
        :render_lcd_braille, :render_lcd_color,
        :speaker, :start_audio, :stop_audio,
        :inject_key, :release_key
      ]
    end

    describe 'HdlRunner from GameBoyCli' do
      let(:cli) { GameBoyCli.new(mode: :hdl, sim: :ruby) }

      it 'implements all required interface methods' do
        required_methods.each do |method|
          expect(cli.runner).to respond_to(method), "Expected runner to respond to #{method}"
        end
      end
    end
  end

  describe 'other options' do
    describe 'speed option' do
      it 'sets cycles_per_frame' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, speed: 500)
        # The speed option controls cycles_per_frame internally
        expect(cli.instance_variable_get(:@cycles_per_frame)).to eq(500)
      end

      it 'defaults to 100' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby)
        expect(cli.instance_variable_get(:@cycles_per_frame)).to eq(100)
      end
    end

    describe 'debug option' do
      it 'enables debug mode' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, debug: true)
        expect(cli.instance_variable_get(:@debug)).to eq(true)
      end

      it 'defaults to false' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby)
        expect(cli.instance_variable_get(:@debug)).to eq(false)
      end
    end

    describe 'renderer option' do
      it 'sets renderer type to :braille' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, renderer: :braille)
        expect(cli.instance_variable_get(:@renderer_type)).to eq(:braille)
      end

      it 'sets renderer type to :color' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, renderer: :color)
        expect(cli.instance_variable_get(:@renderer_type)).to eq(:color)
      end

      it 'defaults to :color' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby)
        expect(cli.instance_variable_get(:@renderer_type)).to eq(:color)
      end
    end

    describe 'audio option' do
      it 'enables audio' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, audio: true)
        expect(cli.instance_variable_get(:@audio_enabled)).to eq(true)
      end

      it 'defaults to false' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby)
        expect(cli.instance_variable_get(:@audio_enabled)).to eq(false)
      end
    end

    describe 'dmg_colors option' do
      it 'enables DMG green palette' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, dmg_colors: true)
        expect(cli.instance_variable_get(:@dmg_colors)).to eq(true)
      end

      it 'defaults to true' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby)
        expect(cli.instance_variable_get(:@dmg_colors)).to eq(true)
      end
    end

    describe 'lcd_width option' do
      it 'sets custom LCD width' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby, lcd_width: 60)
        expect(cli.instance_variable_get(:@lcd_width)).to eq(60)
      end

      it 'defaults to 80' do
        cli = GameBoyCli.new(mode: :hdl, sim: :ruby)
        expect(cli.instance_variable_get(:@lcd_width)).to eq(80)
      end
    end
  end
end
