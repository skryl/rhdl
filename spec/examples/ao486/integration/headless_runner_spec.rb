# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/runners/headless_runner'

RSpec.describe RHDL::Examples::AO486::HeadlessRunner do
  let(:text_base) { RHDL::Examples::AO486::DisplayAdapter::TEXT_BASE }

  it 'defaults to compiler-backed IR mode' do
    runner = described_class.new(headless: true)

    expect(runner.mode).to eq(:ir)
    expect(runner.sim_backend).to eq(:compile)
    expect(runner.state[:backend]).to eq(:ir)
  end

  it 'loads BIOS ROMs from examples/ao486/software/rom into mapped ROM windows' do
    runner = described_class.new(headless: true)
    boot0_path = runner.bios_paths.fetch(:boot0)
    boot1_path = runner.bios_paths.fetch(:boot1)
    boot0_bytes = File.binread(boot0_path, 8).bytes
    boot1_bytes = File.binread(boot1_path, 8).bytes

    runner.load_bios

    expect(runner.runner.read_bytes(RHDL::Examples::AO486::BackendRunner::BOOT0_ADDR, 8)).to eq(boot0_bytes)
    expect(runner.runner.read_bytes(RHDL::Examples::AO486::BackendRunner::BOOT1_ADDR, 8)).to eq(boot1_bytes)
    expect(runner.state[:bios_loaded]).to be(true)
  end

  it 'loads the persistent DOS floppy image from examples/ao486/software/bin' do
    runner = described_class.new(headless: true)

    runner.load_dos

    expect(runner.state[:dos_loaded]).to be(true)
    expect(runner.state[:floppy_image_size]).to eq(File.size(runner.dos_path))
  end

  it 'renders text mode content with debug state below the display' do
    runner = described_class.new(headless: true, debug: true, speed: 1234)
    runner.load_bytes(text_base, ['O'.ord, 0x07, 'K'.ord, 0x07])
    runner.load_bytes(RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA, [2, 0])

    screen = runner.read_text_screen

    expect(screen).to include('OK')
    expect(screen).to include('Mode:IR')
    expect(screen).to include('Speed:1.2K')
  end

  it 'exposes the same runner contract across all AO486 public modes', timeout: 60 do
    {
      ir: :ir,
      verilog: :verilator,
      circt: :arcilator
    }.each do |mode, backend|
      runner = described_class.new(mode: mode, headless: true, cycles: 1)
      runner.send_keys("dir\r")
      state = runner.run

      expect(state[:effective_mode]).to eq(mode)
      expect(state[:backend]).to eq(backend)
      expect(state[:keyboard_buffer_size]).to be_between(3, 4)
    end
  end

  it 'keeps running backend chunks in interactive mode until interrupted' do
    runner = described_class.new(mode: :verilog, speed: 10_000)
    backend = instance_double(
      'AO486Backend',
      cycles_run: 20_000,
      state: {
        backend: :verilator,
        cycles_run: 20_000,
        bios_loaded: false,
        dos_loaded: false,
        floppy_image_size: 0,
        keyboard_buffer_size: 0,
        shell_prompt_detected: false,
        native: true,
        cursor: { row: 0, col: 0 }
      }
    )

    allow(backend).to receive(:run)
    runner.instance_variable_set(:@runner, backend)
    allow(runner).to receive(:read_text_screen).and_return("frame")
    allow(runner).to receive(:setup_terminal_input_mode).and_return(nil)
    allow(runner).to receive(:restore_terminal_input_mode)
    allow(runner).to receive(:sleep)
    allow(runner).to receive(:print)
    allow($stdout).to receive(:tty?).and_return(true)
    allow($stdout).to receive(:flush)

    iterations = 0
    allow(runner).to receive(:handle_keyboard_input) do |running_flag:|
      iterations += 1
      running_flag.call if iterations == 2
    end

    result = runner.run

    expect(backend).to have_received(:run).with(cycles: nil, speed: 10_000, headless: false).twice
    expect(result[:cycles]).to eq(20_000)
  end
end
