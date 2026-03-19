# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/runners/verilator_runner'

RSpec.describe RHDL::Examples::AO486::VerilatorRunner, timeout: 360 do
  it 'preserves SP across repeated DOS INT 13h reads on the real runner path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos

    base = described_class::DOS_BOOT_SECTOR_ADDR
    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD0,             # mov ss, ax
      0xBC, 0x00, 0x08,       # mov sp, 0x0800
      0x8E, 0xD8,             # mov ds, ax
      0xB8, 0x00, 0x02,       # mov ax, 0x0200
      0x8E, 0xC0,             # mov es, ax
      0xBB, 0x00, 0x00,       # mov bx, 0x0000
      0xB8, 0x01, 0x02,       # mov ax, 0x0201
      0xB9, 0x02, 0x00,       # mov cx, 0x0002
      0xBA, 0x00, 0x00,       # mov dx, 0x0000
      0xBE, 0x04, 0x00,       # mov si, 4
      0xCD, 0x13,             # int 0x13
      0x4E,                   # dec si
      0x75, 0xFB,             # jne back to int 0x13
      0x89, 0x26, 0x00, 0x06, # mov [0x0600], sp
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.load_bytes(base + idx, [byte])
    end

    runner.run(cycles: 5_000)

    expect(runner.read_bytes(0x0600, 2, mapped: false)).to eq([0x00, 0x08])
    expect(runner.state.dig(:dos_bridge, :int13)).to include(
      es: 0x0200,
      bx: 0x0000,
      cx: 0x0002,
      dx: 0x0000
    )
  end

  it 'programs PIT channel 0 through lobyte/hibyte writes on the real runner path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos

    base = described_class::DOS_BOOT_SECTOR_ADDR
    payload = [
      0xFA,             # cli
      0xB0, 0x36,       # mov al, 0x36
      0xE6, 0x43,       # out 0x43, al
      0xB0, 0x04,       # mov al, 4
      0xE6, 0x40,       # out 0x40, al
      0x30, 0xC0,       # xor al, al
      0xE6, 0x40,       # out 0x40, al
      0xEB, 0xFE        # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.load_bytes(base + idx, [byte])
    end

    runner.run(cycles: 3_000)

    bios_ticks = runner.read_bytes(0x046C, 4, mapped: false).each_with_index.sum { |byte, idx| byte << (idx * 8) }
    expect(bios_ticks).to be >= 100
  end

  it 'copies a floppy boot sector into RAM through the raw DMA/FDC runner bridge' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos
    runner.send(:ensure_sim!)

    boot_sector = Array.new(512) { |idx| (idx * 7) & 0xFF }
    expect(runner.sim.runner_load_disk(boot_sector, 0)).to be(true)

    runner.sim.send(:write_io_value, 0x000C, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0004, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0004, 1, 0x7C)
    runner.sim.send(:write_io_value, 0x000C, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0005, 1, 0xFF)
    runner.sim.send(:write_io_value, 0x0005, 1, 0x01)
    runner.sim.send(:write_io_value, 0x0081, 1, 0x00)
    runner.sim.send(:write_io_value, 0x000B, 1, 0x46)
    runner.sim.send(:write_io_value, 0x000A, 1, 0x02)
    runner.sim.send(:write_io_value, 0x03F2, 1, 0x1C)
    [0xE6, 0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0x1B, 0xFF].each do |byte|
      runner.sim.send(:write_io_value, 0x03F5, 1, byte)
    end

    expect(runner.read_bytes(0x7C00, 16, mapped: false)).to eq(boot_sector.first(16))
  end

  it 'aliases hard-disk style DL values back onto the mounted floppy on the generic custom-DOS path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk1.img'))
    runner.send(:ensure_sim!)

    state_before = runner.sim.runner_ao486_dos_int13_state
    expect(state_before[:flags]).to eq(0)

    runner.sim.send(:write_io_value, 0x0ED0, 1, 0x01)
    runner.sim.send(:write_io_value, 0x0ED1, 1, 0x02)
    runner.sim.send(:write_io_value, 0x0ED2, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED3, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED4, 1, 0x01)
    runner.sim.send(:write_io_value, 0x0ED5, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED6, 1, 0x81)
    runner.sim.send(:write_io_value, 0x0ED7, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED8, 1, 0x70)
    runner.sim.send(:write_io_value, 0x0ED9, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0EDA, 1, 0x00)

    int13 = runner.sim.runner_ao486_dos_int13_state
    expect(int13).to include(
      ax: 0x0201,
      bx: 0x0000,
      cx: 0x0001,
      dx: 0x0081,
      es: 0x0070,
      result_ax: 0x0001,
      flags: 0
    )
  end

  it 'records recent DOS INT 13h requests with CHS/LBA detail on the generic custom-DOS path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk1.img'))
    runner.send(:ensure_sim!)

    runner.sim.send(:write_io_value, 0x0ED0, 1, 0x01)
    runner.sim.send(:write_io_value, 0x0ED1, 1, 0x02)
    runner.sim.send(:write_io_value, 0x0ED2, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED3, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED4, 1, 0x01)
    runner.sim.send(:write_io_value, 0x0ED5, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED6, 1, 0x81)
    runner.sim.send(:write_io_value, 0x0ED7, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED8, 1, 0x70)
    runner.sim.send(:write_io_value, 0x0ED9, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0EDA, 1, 0x00)

    expect(runner.sim.runner_ao486_dos_int13_history.last).to include(
      function: 0x02,
      ax: 0x0201,
      bx: 0x0000,
      cx: 0x0001,
      dx: 0x0081,
      es: 0x0070,
      drive: 0x00,
      cylinder: 0x00,
      head: 0x00,
      sector: 0x01,
      lba: 0,
      result_ax: 0x0001,
      flags: 0
    )
  end

  it 'records recent PC history snapshots on the live Verilator runner path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos400_pcjs_disk1.img'))

    runner.run(cycles: 5_000)

    expect(runner.sim.runner_ao486_pc_history).not_to be_empty
    expect(runner.sim.runner_ao486_pc_history.last).to include(
      :trace,
      :decode,
      :arch,
      :cs_cache,
      :exception_vector,
      :exception_eip
    )
  end

  it 'repairs BPB-derived generic DOS stage vars on the PCjs MS-DOS 4.00 Disk 1 path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos400_pcjs_disk1.img'))

    runner.run(cycles: 4_600)

    expect(runner.read_bytes(0x079B, 2, mapped: false)).to eq([0x00, 0x02])
    expect(runner.read_bytes(0x07AB, 2, mapped: false)).to eq([0x09, 0x00])
    expect(runner.read_bytes(0x07B7, 1, mapped: false)).to eq([0x02])
    expect(runner.read_bytes(0x07AE, 1, mapped: false)).to eq([0x01])
  end

  it 'repairs the relocated generic DOS CHS helper on the PCjs MS-DOS 4.00 Disk 1 path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos400_pcjs_disk1.img'))

    runner.run(cycles: 20_000)

    helper_addr = 0x0700 + described_class::SimBridge::GENERIC_DOS_STAGE_CHS_HELPER_OFFSET
    expect(
      runner.read_bytes(
        helper_addr,
        described_class::SimBridge::GENERIC_DOS_STAGE_CHS_HELPER_PATCH.length,
        mapped: false
      )
    ).to eq(described_class::SimBridge::GENERIC_DOS_STAGE_CHS_HELPER_PATCH)

    state = runner.run(cycles: 20_000)
    expect(state[:exception_eip]).not_to eq(0x0346)
    expect(state.dig(:pc, :trace)).not_to eq(0x0346)
  end

  it 'keeps later PCjs MS-DOS 4.00 Disk 1 INT 13h requests sane on the generic DOS path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos400_pcjs_disk1.img'))

    runner.run(cycles: 30_000)

    expect(runner.sim.runner_ao486_dos_int13_history.last).to include(
      function: 0x02,
      ax: 0x0202,
      cx: 0x0006,
      dx: 0x0100,
      es: 0x0000,
      result_ax: 0x0002,
      flags: 0
    )
  end

  it 'keeps the dual-disk beta path on the established late plateau', slow: true do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk1.img'))
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk2.img'), slot: 1, activate: false)
    runner.load_hdd(path: runner.software_path('bin', 'fs.img'))

    state = runner.run(cycles: 500_000)
    cs_cache = runner.peek('trace_cs_cache')
    cs_base = (((cs_cache >> 56) & 0xFF) << 24) | ((cs_cache >> 16) & 0xFFFFFF)

    expect(state[:shell_prompt_detected]).to be(false)
    expect(state.dig(:pc, :trace)).to eq(0xFEA4)
    expect(state.dig(:pc, :decode)).to eq(0xFEA4)
    expect(state.dig(:pc, :arch)).to eq(0xFEA4)
    expect(state[:exception_eip]).to eq(0x5171)
    expect(cs_base).to eq(0x3F10)
    expect(runner.sim.runner_ao486_dos_int13_history.last(2)).to match(
      [
        include(drive: 0x80, lba: 0, result_ax: 0x0001, flags: 0),
        include(drive: 0x81, lba: 0, result_ax: 0x0001, flags: 0)
      ]
    )
  end

  it 'reports mounted floppy geometry and drive count through INT 13h AH=08 on the generic custom-DOS hot-swap path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk1.img'))
    runner.send(:ensure_sim!)

    runner.sim.send(:write_io_value, 0x0ED0, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED1, 1, 0x08)
    runner.sim.send(:write_io_value, 0x0ED6, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED7, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0EDA, 1, 0x00)

    expect(runner.sim.runner_ao486_dos_int13_state).to include(
      ax: 0x0800,
      dx: 0x0000,
      result_ax: 0x0000,
      result_bx: 0x0400,
      result_cx: 0x2709,
      result_dx: 0x0101
    )

    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk2.img'), slot: 1, activate: false)

    runner.sim.send(:write_io_value, 0x0ED0, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED1, 1, 0x08)
    runner.sim.send(:write_io_value, 0x0ED6, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED7, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0EDA, 1, 0x00)

    expect(runner.sim.runner_ao486_dos_int13_state).to include(
      result_bx: 0x0400,
      result_cx: 0x2709,
      result_dx: 0x0102
    )
  end

  it 'returns the mounted generic-DOS geometry through the real INT 13h AH=08 stub', slow: true do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk1.img'))
    runner.load_dos(path: runner.software_path('bin', 'msdos4_disk2.img'), slot: 1, activate: false)

    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xB8, 0x00, 0x08,       # mov ax, 0x0800
      0xBA, 0x00, 0x00,       # mov dx, 0x0000
      0xCD, 0x13,             # int 0x13
      0x89, 0x1E, 0x00, 0x09, # mov [0x0900], bx
      0x89, 0x0E, 0x02, 0x09, # mov [0x0902], cx
      0x89, 0x16, 0x04, 0x09, # mov [0x0904], dx
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(described_class::DOS_BOOT_SECTOR_ADDR + idx, byte)
    end

    runner.run(cycles: 5_000)

    expect(runner.read_bytes(0x0900, 6, mapped: false)).to eq([0x01, 0x00, 0x09, 0x27, 0x02, 0x01])
  end

end
