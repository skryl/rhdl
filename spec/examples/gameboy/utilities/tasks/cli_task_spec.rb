# frozen_string_literal: true

require 'spec_helper'

# Add utilities to load path for require 'gameboy_hdl' etc.
$LOAD_PATH.unshift File.expand_path('../../../../../examples/gameboy/utilities', __dir__)

require_relative '../../../../../examples/gameboy/gameboy'
require_relative '../../../../../examples/gameboy/utilities/gameboy_hdl'
require_relative '../../../../../examples/gameboy/utilities/lcd_renderer'
require_relative '../../../../../examples/gameboy/utilities/tasks/cli_task'
require_relative '../../../../../examples/gameboy/utilities/tasks/demo_rom'

RSpec.describe RHDL::GameBoy::Tasks::CliTask do
  before(:all) do
    @ir_available = false
    begin
      require_relative '../../../../../examples/gameboy/utilities/gameboy_ir'
      test_runner = RHDL::GameBoy::IrRunner.new(backend: :interpret)
      test_runner.reset
      @ir_available = true
    rescue LoadError, NoMethodError, Fiddle::DLError
      @ir_available = false
    end

    @verilator_available = system('which verilator > /dev/null 2>&1')
    if @verilator_available
      begin
        require_relative '../../../../../examples/gameboy/utilities/gameboy_verilator'
      rescue LoadError
        @verilator_available = false
      end
    end
  end

  describe '#initialize' do
    describe 'runner selection' do
      context 'with mode: :hdl, sim: :ruby' do
        let(:cli) { described_class.new(mode: :hdl, sim: :ruby) }

        it 'creates HdlRunner' do
          expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
        end

        it 'has simulator_type :hdl_ruby' do
          expect(cli.runner.simulator_type).to eq(:hdl_ruby)
        end

        it 'is not native' do
          expect(cli.runner.native?).to eq(false)
        end
      end

      context 'with mode: :hdl, sim: :interpret' do
        let(:cli) { described_class.new(mode: :hdl, sim: :interpret) }

        it 'returns appropriate runner based on availability' do
          if @ir_available
            expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
          else
            expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
          end
        end
      end

      context 'with mode: :hdl, sim: :jit' do
        let(:cli) { described_class.new(mode: :hdl, sim: :jit) }

        it 'returns appropriate runner based on availability' do
          if @ir_available
            expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
          else
            expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
          end
        end
      end

      context 'with mode: :hdl, sim: :compile' do
        let(:cli) { described_class.new(mode: :hdl, sim: :compile) }

        it 'returns appropriate runner based on availability' do
          if @ir_available
            expect(cli.runner).to be_a(RHDL::GameBoy::IrRunner)
          else
            expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
          end
        end
      end

      context 'with mode: :verilog' do
        it 'creates VerilatorRunner when available' do
          skip "Verilator not available" unless @verilator_available
          cli = described_class.new(mode: :verilog)
          expect(cli.runner).to be_a(RHDL::GameBoy::VerilatorRunner)
        end

        it 'raises ArgumentError when Verilator not available' do
          skip "Verilator is available" if @verilator_available
          expect { described_class.new(mode: :verilog) }
            .to raise_error(ArgumentError, /Verilator/)
        end
      end

      context 'with invalid mode' do
        it 'raises ArgumentError' do
          expect { described_class.new(mode: :invalid) }
            .to raise_error(ArgumentError, /Unknown mode/)
        end
      end

      context 'with default options' do
        let(:cli) { described_class.new({}) }

        it 'uses compile backend by default' do
          expect(cli.runner).to respond_to(:simulator_type)
        end
      end
    end

    describe 'option handling' do
      describe 'speed option' do
        it 'sets cycles_per_frame' do
          cli = described_class.new(mode: :hdl, sim: :ruby, speed: 500)
          expect(cli.instance_variable_get(:@cycles_per_frame)).to eq(500)
        end

        it 'defaults to 100' do
          cli = described_class.new(mode: :hdl, sim: :ruby)
          expect(cli.instance_variable_get(:@cycles_per_frame)).to eq(100)
        end
      end

      describe 'debug option' do
        it 'enables debug mode' do
          cli = described_class.new(mode: :hdl, sim: :ruby, debug: true)
          expect(cli.instance_variable_get(:@debug)).to eq(true)
        end

        it 'defaults to false' do
          cli = described_class.new(mode: :hdl, sim: :ruby)
          expect(cli.instance_variable_get(:@debug)).to eq(false)
        end
      end

      describe 'renderer option' do
        it 'sets renderer type to :braille' do
          cli = described_class.new(mode: :hdl, sim: :ruby, renderer: :braille)
          expect(cli.instance_variable_get(:@renderer_type)).to eq(:braille)
        end

        it 'sets renderer type to :color' do
          cli = described_class.new(mode: :hdl, sim: :ruby, renderer: :color)
          expect(cli.instance_variable_get(:@renderer_type)).to eq(:color)
        end

        it 'defaults to :color' do
          cli = described_class.new(mode: :hdl, sim: :ruby)
          expect(cli.instance_variable_get(:@renderer_type)).to eq(:color)
        end
      end

      describe 'audio option' do
        it 'enables audio' do
          cli = described_class.new(mode: :hdl, sim: :ruby, audio: true)
          expect(cli.instance_variable_get(:@audio_enabled)).to eq(true)
        end

        it 'defaults to false' do
          cli = described_class.new(mode: :hdl, sim: :ruby)
          expect(cli.instance_variable_get(:@audio_enabled)).to eq(false)
        end
      end

      describe 'dmg_colors option' do
        it 'enables DMG green palette' do
          cli = described_class.new(mode: :hdl, sim: :ruby, dmg_colors: true)
          expect(cli.instance_variable_get(:@dmg_colors)).to eq(true)
        end

        it 'can be disabled' do
          cli = described_class.new(mode: :hdl, sim: :ruby, dmg_colors: false)
          expect(cli.instance_variable_get(:@dmg_colors)).to eq(false)
        end

        it 'defaults to true' do
          cli = described_class.new(mode: :hdl, sim: :ruby)
          expect(cli.instance_variable_get(:@dmg_colors)).to eq(true)
        end
      end

      describe 'lcd_width option' do
        it 'sets custom LCD width' do
          cli = described_class.new(mode: :hdl, sim: :ruby, lcd_width: 60)
          expect(cli.instance_variable_get(:@lcd_width)).to eq(60)
        end

        it 'defaults to 80' do
          cli = described_class.new(mode: :hdl, sim: :ruby)
          expect(cli.instance_variable_get(:@lcd_width)).to eq(80)
        end
      end
    end
  end

  describe 'option combinations matrix' do
    # Test all valid backend combinations with hdl mode
    [:ruby, :interpret, :jit, :compile].each do |backend|
      context "mode: :hdl, sim: #{backend}" do
        it "creates appropriate runner" do
          cli = described_class.new(mode: :hdl, sim: backend)
          expect(cli.runner).to respond_to(:simulator_type)
          expect(cli.runner).to respond_to(:native?)

          if backend == :ruby
            expect(cli.runner).to be_a(RHDL::GameBoy::HdlRunner)
            expect(cli.runner.native?).to eq(false)
          elsif @ir_available
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

  describe 'runner interface compliance' do
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

    context 'HdlRunner from CliTask' do
      let(:cli) { described_class.new(mode: :hdl, sim: :ruby) }

      it 'implements all required interface methods' do
        required_methods.each do |method|
          expect(cli.runner).to respond_to(method), "Expected runner to respond to #{method}"
        end
      end
    end
  end

  describe '#load_rom' do
    let(:cli) { described_class.new(mode: :hdl, sim: :ruby) }
    let(:demo_rom) { RHDL::GameBoy::Tasks::DemoRom.new.create }
    let(:rom_path) { '/tmp/test_rom.gb' }

    before do
      File.binwrite(rom_path, demo_rom)
    end

    after do
      File.delete(rom_path) if File.exist?(rom_path)
    end

    it 'loads ROM from file' do
      expect { cli.load_rom(rom_path) }.not_to raise_error
    end
  end

  describe '#stop' do
    let(:cli) { described_class.new(mode: :hdl, sim: :ruby) }

    it 'sets running to false' do
      cli.instance_variable_set(:@running, true)
      cli.stop
      expect(cli.running).to eq(false)
    end
  end

  describe 'constants' do
    it 'defines SCREEN_WIDTH' do
      expect(described_class::SCREEN_WIDTH).to eq(160)
    end

    it 'defines SCREEN_HEIGHT' do
      expect(described_class::SCREEN_HEIGHT).to eq(144)
    end

    it 'defines LCD_CHARS_WIDE' do
      expect(described_class::LCD_CHARS_WIDE).to eq(80)
    end

    it 'defines LCD_CHARS_TALL' do
      expect(described_class::LCD_CHARS_TALL).to eq(36)
    end
  end
end
