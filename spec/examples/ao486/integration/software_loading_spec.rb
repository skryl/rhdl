# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative 'support'

RSpec.describe 'AO486 software loading' do
  let(:runner) { RHDL::Examples::AO486::IrRunner.new }

  it 'resolves software helpers under examples/ao486/software' do
    expect(runner.software_root).to end_with('/examples/ao486/software')
    expect(runner.software_path('rom', 'boot0.rom')).to eq(runner.bios_paths.fetch(:boot0))
    expect(runner.dos_path).to eq(runner.software_path('bin', 'fdboot.img'))
  end

  it 'loads the checked-in BIOS ROMs' do
    bios = runner.load_bios

    expect(bios.keys).to eq(%i[boot0 boot1])
    expect(bios.fetch(:boot0)).to include(path: runner.bios_paths.fetch(:boot0), size: 65_536)
    expect(bios.fetch(:boot1)).to include(path: runner.bios_paths.fetch(:boot1), size: 32_768)
    expect(runner.bios_loaded?).to be(true)
  end

  it 'loads the checked-in DOS floppy image' do
    dos = runner.load_dos

    expect(dos).to include(path: runner.dos_path, size: 1_474_560)
    expect(dos.fetch(:bytes).bytesize).to eq(1_474_560)
    expect(runner.dos_loaded?).to be(true)
  end

  it 'fails clearly when a BIOS ROM path is missing' do
    missing_path = File.join(Dir.tmpdir, "ao486-missing-#{$$}-boot0.rom")

    expect {
      runner.load_bios(boot0: missing_path)
    }.to raise_error(ArgumentError, /AO486 BIOS ROM not found: #{Regexp.escape(File.expand_path(missing_path))}/)
  end

  it 'fails clearly when a DOS image path is missing' do
    missing_path = File.join(Dir.tmpdir, "ao486-missing-#{$$}-fdboot.img")

    expect {
      runner.load_dos(path: missing_path)
    }.to raise_error(ArgumentError, /AO486 DOS image not found: #{Regexp.escape(File.expand_path(missing_path))}/)
  end
end
