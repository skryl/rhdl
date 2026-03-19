# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative 'support'

RSpec.describe 'AO486 software loading' do
  let(:runner) { RHDL::Examples::AO486::IrRunner.new }

  it 'resolves software helpers under examples/ao486/software' do
    expect(runner.software_root).to end_with('/examples/ao486/software')
    expect(runner.software_path('rom', 'boot0.rom')).to eq(runner.bios_paths.fetch(:boot0))
    expect(runner.dos_path).to eq(runner.software_path('bin', 'msdos4_disk1.img'))
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

    expect(dos).to include(path: runner.dos_path, size: 368_640)
    expect(dos.fetch(:bytes).bytesize).to eq(368_640)
    expect(runner.dos_loaded?).to be(true)
  end

  it 'stores a second DOS floppy image without activating it and can hot swap to it' do
    disk1_path = runner.software_path('bin', 'msdos4_disk1.img')
    disk2_path = runner.software_path('bin', 'msdos4_disk2.img')

    disk1 = runner.load_dos(path: disk1_path, slot: 0)
    disk2 = runner.load_dos(path: disk2_path, slot: 1, activate: false)

    expect(disk1).to include(path: File.expand_path(disk1_path), slot: 0, active: true)
    expect(disk2).to include(path: File.expand_path(disk2_path), slot: 1, active: false)
    expect(runner.state[:active_floppy_slot]).to eq(0)
    expect(runner.state[:floppy_slots]).to eq(
      0 => { path: File.expand_path(disk1_path), size: File.size(disk1_path) },
      1 => { path: File.expand_path(disk2_path), size: File.size(disk2_path) }
    )
    expect(runner.floppy_image.byteslice(0, 16)).to eq(File.binread(disk1_path, 16))

    swap = runner.swap_dos(1)

    expect(swap).to include(slot: 1, path: File.expand_path(disk2_path), active: true)
    expect(runner.state[:active_floppy_slot]).to eq(1)
    expect(runner.floppy_image.byteslice(0, 16)).to eq(File.binread(disk2_path, 16))
  end

  it 'infers 360KB floppy geometry for the checked-in MS-DOS 4.00 disk' do
    disk1_path = runner.software_path('bin', 'msdos4_disk1.img')

    runner.load_dos(path: disk1_path, slot: 0)

    expect(runner.state[:active_floppy_geometry]).to eq(
      bytes_per_sector: 512,
      sectors_per_track: 9,
      heads: 2,
      cylinders: 40,
      drive_type: 1
    )
  end

  it 'seeds floppy BDA state from the mounted custom-disk geometry' do
    disk1_path = runner.software_path('bin', 'msdos4_disk1.img')

    runner.load_bios
    runner.load_dos(path: disk1_path, slot: 0)

    expect(runner.memory[0x048B]).to eq(0xA8)
    expect(runner.memory[0x048F]).to eq(0x04)
    expect(runner.memory[0x0490]).to eq(0x93)
    expect(runner.memory[0x0492]).to eq(0x84)
  end

  it 'builds the DOS bootstrap with the same private DOS interrupt vectors' do
    runner.load_bios
    runner.load_dos

    expect(runner.instance_variable_get(:@dos_bootstrap_mode)).to eq(:generic)

    bootstrap = runner.send(:dos_bootstrap_bytes)
    vector_writes = [
      [0x0040, RHDL::Examples::AO486::IrRunner::DOS_INT10_STUB_OFFSET, RHDL::Examples::AO486::IrRunner::DOS_INT10_STUB_SEGMENT],
      [0x004C, RHDL::Examples::AO486::IrRunner::DOS_INT13_STUB_OFFSET, RHDL::Examples::AO486::IrRunner::DOS_INT13_STUB_SEGMENT],
      [0x0058, RHDL::Examples::AO486::IrRunner::DOS_INT16_STUB_OFFSET, RHDL::Examples::AO486::IrRunner::DOS_INT16_STUB_SEGMENT],
      [0x0068, RHDL::Examples::AO486::IrRunner::DOS_INT1A_STUB_OFFSET, RHDL::Examples::AO486::IrRunner::DOS_INT1A_STUB_SEGMENT]
    ]

    vector_writes.each do |addr, offset, segment|
      expect(bootstrap.each_cons(12).to_a).to include(
        [
          0xC7, 0x06, addr & 0xFF, (addr >> 8) & 0xFF, offset & 0xFF, (offset >> 8) & 0xFF,
          0xC7, 0x06, (addr + 2) & 0xFF, ((addr + 2) >> 8) & 0xFF, segment & 0xFF, (segment >> 8) & 0xFF
        ]
      )
    end
  end

  it 'replaces the live backend disk image when hot swapping to a smaller floppy payload', timeout: 120 do
    backend = if RHDL::Sim::Native::IR::JIT_AVAILABLE
                :jit
              elsif RHDL::Sim::Native::IR::COMPILER_AVAILABLE
                :compile
              end
    skip 'IR native backend unavailable' if backend.nil?

    Dir.mktmpdir('ao486_disk_swap_spec') do |dir|
      disk1_path = File.join(dir, 'disk1.img')
      disk2_path = File.join(dir, 'disk2.img')
      File.binwrite(disk1_path, "\xAA" * 16)
      File.binwrite(disk2_path, "\xBB" * 8)

      native_runner = RHDL::Examples::AO486::IrRunner.new(backend: backend, headless: true)
      native_runner.load_dos(path: disk1_path, slot: 0)
      native_runner.load_dos(path: disk2_path, slot: 1, activate: false)
      native_runner.send(:ensure_sim!)

      expect(native_runner.sim.runner_read_disk(0, 16)).to eq([0xAA] * 16)

      native_runner.swap_dos(1)

      expect(native_runner.sim.runner_read_disk(0, 16)).to eq(([0xBB] * 8) + ([0x00] * 8))
    end
  end

  it 'fails clearly when a BIOS ROM path is missing' do
    missing_path = File.join(Dir.tmpdir, "ao486-missing-#{$$}-boot0.rom")

    expect {
      runner.load_bios(boot0: missing_path)
    }.to raise_error(ArgumentError, /AO486 BIOS ROM not found: #{Regexp.escape(File.expand_path(missing_path))}/)
  end

  it 'fails clearly when a DOS image path is missing' do
    missing_path = File.join(Dir.tmpdir, "ao486-missing-#{$$}-msdos4.img")

    expect {
      runner.load_dos(path: missing_path)
    }.to raise_error(ArgumentError, /AO486 DOS image not found: #{Regexp.escape(File.expand_path(missing_path))}/)
  end

  it 'fails clearly when swapping to an unloaded floppy slot' do
    expect {
      runner.swap_dos(1)
    }.to raise_error(ArgumentError, /AO486 DOS slot 1 has not been loaded/)
  end
end
