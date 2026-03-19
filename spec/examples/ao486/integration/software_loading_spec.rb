# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'tempfile'
require_relative 'support'
require_relative '../../../../examples/ao486/utilities/import/cpu_importer'

RSpec.describe 'AO486 software loading' do
  let(:runner) { RHDL::Examples::AO486::IrRunner.new }

  def fat12_next(fat, cluster)
    offset = (cluster * 3) / 2
    word = fat.byteslice(offset, 2).unpack1('v')
    cluster.even? ? (word & 0x0FFF) : (word >> 4)
  end

  def read_fat12_root_file(path, name)
    raw = File.binread(path)
    bytes_per_sector = raw.byteslice(11, 2).unpack1('v')
    sectors_per_cluster = raw.getbyte(13)
    reserved = raw.byteslice(14, 2).unpack1('v')
    fats = raw.getbyte(16)
    root_entries = raw.byteslice(17, 2).unpack1('v')
    sectors_per_fat = raw.byteslice(22, 2).unpack1('v')
    root_dir_sectors = ((root_entries * 32) + (bytes_per_sector - 1)) / bytes_per_sector
    fat_start = reserved * bytes_per_sector
    fat = raw.byteslice(fat_start, sectors_per_fat * bytes_per_sector)
    root_start = (reserved + fats * sectors_per_fat) * bytes_per_sector
    data_start = (reserved + fats * sectors_per_fat + root_dir_sectors) * bytes_per_sector
    root = raw.byteslice(root_start, root_entries * 32)

    entry = nil
    (0...(root.bytesize / 32)).each do |i|
      candidate = root.byteslice(i * 32, 32)
      first = candidate.getbyte(0)
      break if first == 0x00
      next if first == 0xE5
      next if candidate.getbyte(11) == 0x0F

      root_name = candidate.byteslice(0, 8).delete(' ').strip
      root_ext = candidate.byteslice(8, 3).delete(' ').strip
      full_name = root_ext.empty? ? root_name : "#{root_name}.#{root_ext}"
      next unless full_name == name

      entry = {
        cluster: candidate.byteslice(26, 2).unpack1('v'),
        size: candidate.byteslice(28, 4).unpack1('V')
      }
      break
    end

    raise "#{name} not found in #{path}" unless entry

    cluster = entry.fetch(:cluster)
    remaining = entry.fetch(:size)
    content = +""
    seen = {}
    while cluster >= 2 && cluster < 0xFF8 && !seen[cluster] && remaining.positive?
      seen[cluster] = true
      offset = data_start + (cluster - 2) * sectors_per_cluster * bytes_per_sector
      chunk = raw.byteslice(offset, sectors_per_cluster * bytes_per_sector)
      take = [chunk.bytesize, remaining].min
      content << chunk.byteslice(0, take)
      remaining -= take
      cluster = fat12_next(fat, cluster)
    end

    content
  end

  it 'resolves software helpers under examples/ao486/software' do
    expect(runner.software_root).to end_with('/examples/ao486/software')
    expect(runner.software_path('rom', 'boot0.rom')).to eq(runner.bios_paths.fetch(:boot0))
    expect(runner.dos_path).to eq(runner.software_path('bin', 'msdos622_boot.img'))
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

  it 'keeps the checked-in DOS 6.22 AUTOEXEC.BAT verbose for boot tracing' do
    autoexec = read_fat12_root_file(runner.dos_path, 'AUTOEXEC.BAT')

    expect(autoexec).to eq("ECHO ON\r\nECHO Booting MS-DOS 6.22\r\nPROMPT $P$G\r\n")
  end

  it 'keeps the checked-in DOS 6.22 CONFIG.SYS free of CD-ROM drivers' do
    config = read_fat12_root_file(runner.dos_path, 'CONFIG.SYS')

    expect(config).to eq(
      "FILES=30\r\n" \
      "BUFFERS=20\r\n" \
      "LASTDRIVE=Z\r\n"
    )
  end

  it 'stores a second DOS floppy image without activating it and can hot swap to it' do
    disk1_path = runner.software_path('bin', 'msdos622_boot.img')

    Tempfile.create(['msdos622_boot_copy', '.img']) do |copy|
      copy.binmode
      bytes = File.binread(disk1_path).bytes
      bytes[0, 16] = Array.new(16, 0xA5)
      copy.write(bytes.pack('C*'))
      copy.flush

      disk2_path = copy.path
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
  end

  it 'infers 1.44MB floppy geometry for the checked-in DOS 6.22 boot disk' do
    disk1_path = runner.software_path('bin', 'msdos622_boot.img')

    runner.load_dos(path: disk1_path, slot: 0)

    expect(runner.state[:active_floppy_geometry]).to eq(
      bytes_per_sector: 512,
      sectors_per_track: 18,
      heads: 2,
      cylinders: 80,
      drive_type: 4
    )
  end

  it 'seeds floppy BDA state from the mounted custom-disk geometry' do
    disk1_path = runner.software_path('bin', 'msdos622_boot.img')

    runner.load_bios
    runner.load_dos(path: disk1_path, slot: 0)

    expect(runner.memory[0x048B]).to eq(0x00)
    expect(runner.memory[0x048F]).to eq(0x07)
    expect(runner.memory[0x0490]).to eq(0x16)
    expect(runner.memory[0x0492]).to eq(0x07)
  end

  it 'wraps the checked-in FAT16 hard disk volume in an MBR-presented disk image' do
    hdd = runner.load_hdd(path: runner.software_path('bin', 'fs.img'))
    image = runner.instance_variable_get(:@hdd_image)

    expect(hdd).to include(path: runner.hdd_path, size: 33_546_240, wrapped: true)
    expect(hdd.fetch(:presented_size)).to eq(34_062_336)
    expect(hdd.fetch(:geometry)).to include(
      bytes_per_sector: 512,
      sectors_per_track: 63,
      heads: 16,
      cylinders: 66,
      total_sectors: 66_528
    )
    expect(image.byteslice(0x1BE + 4, 1).unpack1('C')).to eq(0x04)
    expect(image.byteslice(0x1BE + 8, 4).unpack1('V')).to eq(63)
    expect(image.byteslice(0x1BE + 12, 4).unpack1('V')).to eq(65_520)
    expect(image.byteslice((63 * 512) + 28, 4).unpack1('V')).to eq(63)
    expect(image.byteslice((63 * 512) + 510, 2)).to eq("\x55\xAA".b)
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
