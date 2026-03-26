# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/runners/verilator_runner'

RSpec.describe RHDL::Examples::AO486::VerilatorRunner, timeout: 360 do
  def dos622_disk_path
    File.expand_path('../../../../examples/ao486/software/bin/msdos622_boot.img', __dir__)
  end

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
    runner.load_dos(path: dos622_disk_path)
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

  it 'rejects DL=0x81 reads when only one hard disk is mounted on the generic custom-DOS path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)
    runner.load_hdd(path: runner.software_path('bin', 'fs.img'))
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

    expect(runner.sim.runner_ao486_dos_int13_state).to include(
      ax: 0x0201,
      bx: 0x0000,
      cx: 0x0001,
      dx: 0x0081,
      es: 0x0070,
      result_ax: 0x0100,
      flags: 1
    )
  end

  it 'returns a CF-set INT 13h failure to guest code for DL=0x81 on the single-HDD runner path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)
    runner.load_hdd(path: runner.software_path('bin', 'fs.img'))

    base = described_class::DOS_BOOT_SECTOR_ADDR
    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD0,             # mov ss, ax
      0xBC, 0x00, 0x08,       # mov sp, 0x0800
      0x8E, 0xD8,             # mov ds, ax
      0x8E, 0xC0,             # mov es, ax
      0xBB, 0x00, 0x00,       # mov bx, 0x0000
      0xB8, 0x01, 0x02,       # mov ax, 0x0201
      0xB9, 0x01, 0x00,       # mov cx, 0x0001
      0xBA, 0x81, 0x00,       # mov dx, 0x0081
      0xCD, 0x13,             # int 0x13
      0x89, 0x06, 0x00, 0x06, # mov [0x0600], ax
      0x9C,                   # pushf
      0x58,                   # pop ax
      0xA3, 0x02, 0x06,       # mov [0x0602], ax
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.load_bytes(base + idx, [byte])
    end

    runner.run(cycles: 10_000)

    ax = runner.read_bytes(0x0600, 2, mapped: false)
    flags = runner.read_bytes(0x0602, 2, mapped: false)
    flags_value = flags[0] | (flags[1] << 8)

    expect(ax).to eq([0x00, 0x01])
    expect(flags_value & 0x0001).to eq(0x0001)
    expect(runner.state.dig(:dos_bridge, :int13)).to include(
      dx: 0x0081,
      result_ax: 0x0100,
      flags: 1
    )
  end

  it 'records recent DOS INT 13h requests with CHS/LBA detail on the generic custom-DOS path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)
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
    runner.load_dos(path: runner.software_path('bin', 'msdos622_boot.img'))

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

  it 'returns a non-zero RTC time through INT 1Ah AH=02 on the live Verilator runner path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos622_boot.img'))
    runner.send(:ensure_sim!)

    runner.sim.send(:write_io_value, 0x0F00, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0F01, 1, 0x02)
    runner.sim.send(:write_io_value, 0x0F06, 1, 0x00)

    expect(runner.sim.runner_ao486_dos_int1a_state).to include(
      ax: 0x0200,
      result_ax: 0x0000,
      flags: 0
    )
    expect(
      runner.sim.runner_ao486_dos_int1a_state[:result_cx] |
      runner.sim.runner_ao486_dos_int1a_state[:result_dx]
    ).not_to eq(0)
  end

  it 'reports A20 gate support through the real INT 15h stub on the DOS 6.22 path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)

    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xB8, 0x03, 0x24,       # mov ax, 0x2403
      0xCD, 0x15,             # int 0x15
      0xA3, 0x00, 0x09,       # mov [0x0900], ax
      0x89, 0x1E, 0x02, 0x09, # mov [0x0902], bx
      0x9C,                   # pushf
      0x58,                   # pop ax
      0xA3, 0x04, 0x09,       # mov [0x0904], ax
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(described_class::DOS_BOOT_SECTOR_ADDR + idx, byte)
    end

    runner.run(cycles: 5_000)

    ax = runner.read_bytes(0x0900, 2, mapped: false)
    bx = runner.read_bytes(0x0902, 2, mapped: false)
    flags = runner.read_bytes(0x0904, 2, mapped: false)
    flags_value = flags[0] | (flags[1] << 8)

    expect(ax).to eq([0x00, 0x00])
    expect(bx).to eq([0x03, 0x00])
    expect(flags_value & 0x0001).to eq(0x0000)
  end

  it 'returns cleanly from the real INT 2Ah stub on the DOS 6.22 path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)

    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xB8, 0x34, 0x12,       # mov ax, 0x1234
      0xCD, 0x2A,             # int 0x2A
      0xA3, 0x00, 0x09,       # mov [0x0900], ax
      0x9C,                   # pushf
      0x58,                   # pop ax
      0xA3, 0x02, 0x09,       # mov [0x0902], ax
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(described_class::DOS_BOOT_SECTOR_ADDR + idx, byte)
    end

    runner.run(cycles: 5_000)

    ax = runner.read_bytes(0x0900, 2, mapped: false)
    flags = runner.read_bytes(0x0902, 2, mapped: false)
    flags_value = flags[0] | (flags[1] << 8)

    expect(ax).to eq([0x34, 0x12])
    expect(flags_value & 0x0001).to eq(0x0000)
  end

  it 'returns cleanly from the real INT 2Fh stub on the DOS 6.22 path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)

    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xB8, 0x78, 0x56,       # mov ax, 0x5678
      0xCD, 0x2F,             # int 0x2F
      0xA3, 0x00, 0x09,       # mov [0x0900], ax
      0x9C,                   # pushf
      0x58,                   # pop ax
      0xA3, 0x02, 0x09,       # mov [0x0902], ax
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(described_class::DOS_BOOT_SECTOR_ADDR + idx, byte)
    end

    runner.run(cycles: 5_000)

    ax = runner.read_bytes(0x0900, 2, mapped: false)
    flags = runner.read_bytes(0x0902, 2, mapped: false)
    flags_value = flags[0] | (flags[1] << 8)

    expect(ax).to eq([0x78, 0x56])
    expect(flags_value & 0x0001).to eq(0x0000)
  end

  it 'issues early multi-sector floppy reads on the DOS 6.22 boot disk path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos622_boot.img'))

    runner.run(cycles: 4_600)

    expect(runner.sim.runner_ao486_dos_int13_history.last).to include(
      function: 0x02,
      drive: 0x00,
      lba: 19,
      result_ax: 0x0001,
      flags: 0
    )
  end

  it 'keeps advancing the DOS 6.22 loader without the old generic-loader fault address' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: runner.software_path('bin', 'msdos622_boot.img'))

    state = runner.run(cycles: 20_000)
    expect(runner.sim.runner_ao486_dos_int13_history.length).to be >= 5
    expect(runner.sim.runner_ao486_dos_int13_history.last).to include(
      function: 0x02,
      drive: 0x00,
      lba: 35,
      result_ax: 0x0001,
      flags: 0
    )
    expect(state[:exception_eip]).not_to eq(0x0346)
    expect(state.dig(:pc, :trace)).not_to eq(0x0346)
  end

  it 'boots the verbose DOS 6.22 image to A:\\>', slow: true, timeout: 720 do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)

    state = runner.run(cycles: 8_000_000)
    final_display = runner.render_display
    pc_tail = runner.sim.runner_ao486_pc_history.last(12)
    int13_tail = runner.sim.runner_ao486_dos_int13_history.last(12)
    vector_2a = runner.read_bytes(0x2A * 4, 4, mapped: false)
    vector_2f = runner.read_bytes(0x2F * 4, 4, mapped: false)

    expect(state[:shell_prompt_detected]).to be(
      true
    ), [
      "state=#{state.slice(:shell_prompt_detected, :exception_vector, :exception_eip, :cycles_run).inspect}",
      "pc_tail=#{pc_tail.inspect}",
      "int13_tail=#{int13_tail.inspect}",
      "vector_2a=#{vector_2a.inspect}",
      "vector_2f=#{vector_2f.inspect}",
      final_display
    ].join("\n")
    expect(vector_2a).to eq([0x00, 0x8D, 0x00, 0xF0])
    expect(final_display).to include('Booting MS-DOS 6.22')
    expect(final_display).to include('A:\\>')
  end

  it 'accepts keyboard input at the DOS 6.22 shell prompt', slow: true, timeout: 900 do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)

    state = runner.run(cycles: 8_000_000)
    expect(state[:shell_prompt_detected]).to be(true)

    runner.send_keys("VER\r")
    state = runner.run(cycles: 1_000_000)
    final_display = runner.render_display

    expect(state[:exception_vector]).not_to eq(0)
    expect(final_display).to include('A:\\>VER')
    expect(final_display).to include('MS-DOS Version')
    expect(final_display).not_to include('Divide overflow')
  end

  it 'keeps the single-disk DOS path out of the INT 12h self-loop', slow: true do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)

    runner.run(cycles: 100_000)

    saved_vector_addr =
      (described_class::SimBridge::DOS_INT12_WRAPPER_SEGMENT << 4) +
      described_class::SimBridge::DOS_INT12_WRAPPER_SAVED_VECTOR_OFFSET

    expect(runner.read_bytes(saved_vector_addr, 4, mapped: false)).to eq([0x41, 0xF8, 0x00, 0xF0])
    expect(runner.render_display).not_to include('Error - Interrupt 12')
  end

  it 'reports mounted floppy geometry and drive count through INT 13h AH=08 on the generic custom-DOS hot-swap path' do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)
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
      result_cx: 0x4F12,
      result_dx: 0x0101
    )

    runner.load_dos(path: dos622_disk_path, slot: 1, activate: false)

    runner.sim.send(:write_io_value, 0x0ED0, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED1, 1, 0x08)
    runner.sim.send(:write_io_value, 0x0ED6, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0ED7, 1, 0x00)
    runner.sim.send(:write_io_value, 0x0EDA, 1, 0x00)

    expect(runner.sim.runner_ao486_dos_int13_state).to include(
      result_bx: 0x0400,
      result_cx: 0x4F12,
      result_dx: 0x0102
    )
  end

  it 'returns the mounted generic-DOS geometry through the real INT 13h AH=08 stub', slow: true do
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    runner = described_class.new(headless: true)
    runner.load_bios
    runner.load_dos(path: dos622_disk_path)
    runner.load_dos(path: dos622_disk_path, slot: 1, activate: false)

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

    expect(runner.read_bytes(0x0900, 6, mapped: false)).to eq([0x01, 0x00, 0x12, 0x4F, 0x02, 0x01])
  end

end
