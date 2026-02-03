# frozen_string_literal: true

require 'spec_helper'

# Add utilities to load path for require 'gameboy_hdl' etc.
$LOAD_PATH.unshift File.expand_path('../../../../../examples/gameboy/utilities', __dir__)

require_relative '../../../../../examples/gameboy/gameboy'
require_relative '../../../../../examples/gameboy/utilities/gameboy_hdl'
require_relative '../../../../../examples/gameboy/utilities/tasks/runner_factory'

RSpec.describe RHDL::GameBoy::Tasks::RunnerFactory do
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
    it 'accepts valid mode and backend' do
      factory = described_class.new(mode: :hdl, backend: :ruby)
      expect(factory.mode).to eq(:hdl)
      expect(factory.backend).to eq(:ruby)
    end

    it 'uses default mode and backend when not specified' do
      factory = described_class.new
      expect(factory.mode).to eq(:hdl)
      expect(factory.backend).to eq(:compile)
    end

    it 'raises ArgumentError for invalid mode' do
      expect { described_class.new(mode: :invalid) }
        .to raise_error(ArgumentError, /Unknown mode/)
    end

    it 'raises ArgumentError for invalid backend' do
      expect { described_class.new(backend: :invalid) }
        .to raise_error(ArgumentError, /Unknown backend/)
    end
  end

  describe '#create' do
    context 'with mode: :hdl, backend: :ruby' do
      let(:factory) { described_class.new(mode: :hdl, backend: :ruby) }

      it 'returns HdlRunner' do
        runner = factory.create
        expect(runner).to be_a(RHDL::GameBoy::HdlRunner)
      end

      it 'sets fallback_used to false' do
        factory.create
        expect(factory.fallback_used).to eq(false)
      end
    end

    context 'with mode: :hdl, backend: :interpret' do
      let(:factory) { described_class.new(mode: :hdl, backend: :interpret) }

      it 'returns IrRunner when available, HdlRunner otherwise' do
        runner = factory.create
        if @ir_available
          expect(runner).to be_a(RHDL::GameBoy::IrRunner)
          expect(factory.fallback_used).to eq(false)
        else
          expect(runner).to be_a(RHDL::GameBoy::HdlRunner)
          expect(factory.fallback_used).to eq(true)
        end
      end
    end

    context 'with mode: :hdl, backend: :jit' do
      let(:factory) { described_class.new(mode: :hdl, backend: :jit) }

      it 'returns IrRunner when available, HdlRunner otherwise' do
        runner = factory.create
        if @ir_available
          expect(runner).to be_a(RHDL::GameBoy::IrRunner)
        else
          expect(runner).to be_a(RHDL::GameBoy::HdlRunner)
        end
      end
    end

    context 'with mode: :hdl, backend: :compile' do
      let(:factory) { described_class.new(mode: :hdl, backend: :compile) }

      it 'returns IrRunner when available, HdlRunner otherwise' do
        runner = factory.create
        if @ir_available
          expect(runner).to be_a(RHDL::GameBoy::IrRunner)
        else
          expect(runner).to be_a(RHDL::GameBoy::HdlRunner)
        end
      end
    end

    context 'with mode: :verilog' do
      it 'returns VerilatorRunner when available' do
        skip "Verilator not available" unless @verilator_available
        factory = described_class.new(mode: :verilog)
        runner = factory.create
        expect(runner).to be_a(RHDL::GameBoy::VerilatorRunner)
      end

      it 'raises ArgumentError when Verilator not available' do
        skip "Verilator is available" if @verilator_available
        factory = described_class.new(mode: :verilog)
        expect { factory.create }.to raise_error(ArgumentError, /Verilator/)
      end
    end
  end

  describe '#runner_info' do
    it 'returns nil before create is called' do
      factory = described_class.new(mode: :hdl, backend: :ruby)
      expect(factory.runner_info).to be_nil
    end

    it 'returns runner info after create' do
      factory = described_class.new(mode: :hdl, backend: :ruby)
      factory.create

      info = factory.runner_info
      expect(info[:mode]).to eq(:hdl)
      expect(info[:backend]).to eq(:ruby)
      expect(info[:fallback_used]).to eq(false)
      expect(info[:simulator_type]).to eq(:hdl_ruby)
      expect(info[:native]).to eq(false)
    end

    it 'reflects fallback when native not available' do
      factory = described_class.new(mode: :hdl, backend: :compile)
      factory.create

      info = factory.runner_info
      if @ir_available
        expect(info[:fallback_used]).to eq(false)
        expect(info[:native]).to eq(true)
      else
        expect(info[:fallback_used]).to eq(true)
        expect(info[:backend]).to eq(:ruby)
        expect(info[:native]).to eq(false)
      end
    end
  end

  describe 'constants' do
    it 'defines VALID_MODES' do
      expect(described_class::VALID_MODES).to eq([:hdl, :verilog])
    end

    it 'defines VALID_BACKENDS' do
      expect(described_class::VALID_BACKENDS).to eq([:ruby, :interpret, :jit, :compile])
    end

    it 'defines DEFAULT_MODE' do
      expect(described_class::DEFAULT_MODE).to eq(:hdl)
    end

    it 'defines DEFAULT_BACKEND' do
      expect(described_class::DEFAULT_BACKEND).to eq(:compile)
    end
  end
end
