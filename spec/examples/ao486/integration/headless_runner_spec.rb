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
    expect(screen).to include('backend=ir')
    expect(screen).to include('speed=1234')
  end

  it 'exposes the same runner contract across all AO486 backend classes' do
    %i[ir verilator arcilator].each do |mode|
      runner = described_class.new(mode: mode, headless: true)
      runner.send_keys("dir\r")
      state = runner.run

      expect(state[:backend]).to eq(mode)
      expect(state[:keyboard_buffer_size]).to eq(4)
    end
  end
end
