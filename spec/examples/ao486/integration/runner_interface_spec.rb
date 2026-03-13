# frozen_string_literal: true

require 'spec_helper'
require_relative 'support'

RSpec.describe 'AO486 runner interface' do
  include Ao486IntegrationSupport

  it 'defines the concrete runner classes' do
    expect(ao486_runner_classes.fetch(:ir)).to eq(RHDL::Examples::AO486::IrRunner)
    expect(ao486_runner_classes.fetch(:verilator)).to eq(RHDL::Examples::AO486::VerilatorRunner)
    expect(ao486_runner_classes.fetch(:arcilator)).to eq(RHDL::Examples::AO486::ArcilatorRunner)
    expect(RHDL::Examples::AO486::HeadlessRunner).to eq(RHDL::Examples::AO486::HeadlessRunner)
  end

  it 'keeps a shared contract across the concrete runners' do
    ao486_runner_classes.each_value do |runner_class|
      missing = Ao486IntegrationSupport::REQUIRED_RUNNER_METHODS.reject { |method| runner_class.instance_methods.include?(method) }
      expect(missing).to eq([]), "#{runner_class} missing #{missing.join(', ')}"
    end
  end

  it 'constructs an IR-backed headless runner by default' do
    runner = RHDL::Examples::AO486::HeadlessRunner.new

    expect(runner.mode).to eq(:ir)
    expect(runner.sim_backend).to eq(:compile)
    expect(runner.runner).to be_a(RHDL::Examples::AO486::IrRunner)
    expect(runner.backend).to eq(:compile)
  end

  it 'selects the requested concrete runner for each AO486 mode' do
    expect(RHDL::Examples::AO486::HeadlessRunner.new(mode: :ir, sim: :compiler).runner)
      .to be_a(RHDL::Examples::AO486::IrRunner)
    expect(RHDL::Examples::AO486::HeadlessRunner.new(mode: :verilog).runner)
      .to be_a(RHDL::Examples::AO486::VerilatorRunner)
    expect(RHDL::Examples::AO486::HeadlessRunner.new(mode: :circt).runner)
      .to be_a(RHDL::Examples::AO486::ArcilatorRunner)
  end

  it 'delegates software loading and returns canonical runner state from headless run' do
    runner = RHDL::Examples::AO486::HeadlessRunner.new(mode: :verilog, headless: true, debug: true, speed: 1_000, cycles: 42)

    runner.load_bios
    runner.load_dos
    result = runner.run

    expect(result).to include(
      mode: :verilog,
      effective_mode: :verilog,
      backend: :verilator,
      simulator_type: :ao486_verilator,
      native: true,
      cycles: 42,
      speed: 1_000,
      bios_loaded: true,
      dos_loaded: true
    )
  end

  it 'renders the runner display buffer through the common adapter surface' do
    runner = RHDL::Examples::AO486::HeadlessRunner.new(mode: :arcilator)
    buffer = build_text_buffer
    write_text(buffer, 'AO486>', row: 0, col: 0)

    runner.update_display_buffer(buffer)
    frame = runner.render_display(debug_lines: ['backend=arcilator'])

    expect(frame).to include('_O486>')
    expect(frame).to include('|backend=arcilator')
  end

  it 'rejects unsupported runner modes' do
    expect {
      RHDL::Examples::AO486::HeadlessRunner.new(mode: :bogus)
    }.to raise_error(ArgumentError, /Unsupported AO486 mode/)
  end
end
