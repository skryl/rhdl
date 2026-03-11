# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'

RSpec.describe RHDL::Examples::AO486::IrRunner, timeout: 240 do
  it 'reaches the BIOS reset-vector fetch state with the compiler-backed runner' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    state = runner.run(cycles: 2)

    expect(state[:bios_loaded]).to be(true)
    expect(state[:simulator_type]).to eq(:ao486_ir_compile)
    expect(runner.peek('rst_n')).to eq(1)
    expect(runner.peek('pipeline_inst__decode_inst__eip')).to eq(0xFFF0)
    expect(runner.peek('memory_inst__prefetch_inst__prefetch_address')).to eq(0xFFFF0)
    expect(runner.peek('memory_inst__prefetch_inst__prefetch_length')).to eq(16)
  end

  it 'advances beyond the reset vector into BIOS code with the compiler-backed runner' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.run(cycles: 24)

    expect(runner.peek('pipeline_inst__decode_inst__eip')).to be >= 0xE05B
    expect(runner.peek('trace_wr_eip')).to be >= 0xE05B
  end

  it 'drains the early BIOS prefetch queue and branches past the CMOS shutdown read' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    retired_eips = []
    120.times do
      runner.run(cycles: 1)
      retired_eips << runner.peek('trace_wr_eip')
    end

    expect(retired_eips).to include(0xE06B)
    expect(retired_eips).to include(0xE071)
    expect(runner.peek('trace_wr_eip')).to be >= 0xE0A3
    expect(runner.peek('exception_inst__exc_vector')).to eq(0)
    expect(runner.peek('memory_inst__prefetch_control_inst__prefetchfifo_used')).to eq(0)
  end

  it 'seeds the IVT and skips the ROM helper before continuing POST setup' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    retired_eips = []
    220.times do
      runner.run(cycles: 1)
      retired_eips << runner.peek('trace_wr_eip')
    end

    expect(runner.read_bytes(0x0000, 4, mapped: true)).to eq([0x53, 0xFF, 0x00, 0xF0])
    expect(runner.read_bytes(0x0020, 4, mapped: false)).to eq([0xA5, 0xFE, 0x00, 0xF0])
    expect(runner.read_bytes(0x0040, 4, mapped: false)).to eq([0x65, 0xF0, 0x00, 0xF0])
    expect(runner.read_bytes(0x004C, 4, mapped: false)).to eq([0xFE, 0xE3, 0x00, 0xF0])
    expect(runner.read_bytes(0x0058, 4, mapped: false)).to eq([0x2E, 0xE8, 0x00, 0xF0])
    expect(runner.read_bytes(0x005C, 4, mapped: false)).to eq([0xD2, 0xEF, 0x00, 0xF0])
    expect(runner.read_bytes(0x0060, 4, mapped: false)).to eq([0x66, 0x86, 0x00, 0xF0])
    expect(runner.read_bytes(0x0068, 4, mapped: false)).to eq([0x6E, 0xFE, 0x00, 0xF0])
    expect(runner.read_bytes(0x0074, 4, mapped: false)).to eq([0x00, 0x00, 0x00, 0x00])
    expect(runner.read_bytes(0x0180, 4, mapped: false)).to eq([0x00, 0x00, 0x00, 0x00])
    expect(runner.read_bytes(0x01E0, 4, mapped: false)).to eq([0x00, 0x00, 0x00, 0x00])
    expect(retired_eips.any? { |eip| (0x8BF3..0x8C9C).cover?(eip) }).to be(false)
    expect(runner.peek('pipeline_inst__decode_inst__cs_cache')).to eq(0x930F0000FFFF)
  end

  it 'mirrors the DOS boot sector into both the legacy and relocated boot windows' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    expected_boot_sector = File.binread(runner.dos_path, 512).bytes
    expect(runner.read_bytes(described_class::DOS_BOOT_SECTOR_ADDR, 16, mapped: false)).to eq(expected_boot_sector.first(16))
    expect(runner.read_bytes(described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR, 16, mapped: false)).to eq(expected_boot_sector.first(16))
    expect(runner.read_bytes(described_class::DOS_BOOT_SECTOR_ADDR + 0x1FE, 2, mapped: false)).to eq([0x55, 0xAA])
    expect(runner.read_bytes(described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x1FE, 2, mapped: false)).to eq([0x55, 0xAA])
  end

  it 'seeds the DOS shortcut with the skipped POST BDA words and diskette parameter vector' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    expect(runner.read_bytes(described_class::BDA_EBDA_SEGMENT_ADDR, 2, mapped: false)).to eq([0xC0, 0x9F])
    expect(runner.read_bytes(described_class::BDA_EQUIPMENT_WORD_ADDR, 2, mapped: false)).to eq([0x0D, 0x00])
    expect(runner.read_bytes(described_class::BDA_BASE_MEMORY_WORD_ADDR, 2, mapped: false)).to eq([0x7F, 0x02])
    expect(runner.read_bytes(described_class::BDA_HARD_DISK_COUNT_ADDR, 1, mapped: false)).to eq([0x00])
    expect(runner.read_bytes(described_class::DOS_DISKETTE_PARAM_VECTOR_ADDR, 4, mapped: false)).to eq([0xDE, 0xEF, 0x00, 0xF0])
  end

  it 'starts the BIOS timer tick path during the DOS shortcut handoff', slow: true, timeout: 180 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    4.times { runner.run(cycles: 25_000) }

    ticks = runner.read_bytes(0x046C, 4, mapped: false)
      .each_with_index
      .sum { |byte, idx| byte << (8 * idx) }

    expect(ticks).to be > 0
    expect(runner.sim.runner_ao486_last_irq_vector).to eq(0x08)
  end

  it 'enters the DOS boot-sector window after the BIOS handoff' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    retired_eips = []
    1_200.times do
      runner.run(cycles: 1)
      retired_eips << runner.peek('trace_wr_eip')
    end

    expect(retired_eips.any? { |eip| (0x7C00..0x7DFF).cover?(eip) }).to be(true)
    expect(runner.peek('trace_wr_eip')).to be >= 0x0500
    expect(runner.peek('pipeline_inst__decode_inst__eip')).to be >= 0x0500
  end

  it 'preserves relocated near-call return addresses on the DOS path' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    payload = [
      0xE8, 0x0A, 0x00,
      0x41, 0x42, 0x00,
      0xC6, 0x06, 0x02, 0x06, 0x99,
      0xEB, 0xFE,
      0x5E,
      0x89, 0x36, 0x00, 0x06,
      0x83, 0xC6, 0x03,
      0x56,
      0xC3
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 2_000)

    expect(runner.read_bytes(0x0600, 2, mapped: false)).to eq([0x61, 0x7C])
  end

  it 'returns from the DOS INT 13h bridge back into the relocated boot loader fetch window', timeout: 360 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    runner.run(cycles: 3_500)

    expect(runner.peek('trace_wr_eip')).to be >= 0x7C00
    expect(runner.peek('pipeline_inst__decode_inst__eip')).to be >= 0x7C00
    expect(runner.peek('pipeline_inst__read_inst__rd_eip')).to be >= 0x7C00
    expect(runner.peek('pipeline_inst__execute_inst__exe_eip')).to be >= 0x7C00
  end

  it 'preserves the caller frame across a trivial DOS INT 13h reset call' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xBD, 0x00, 0x7C,       # mov bp, 0x7c00
      0xB8, 0x00, 0x00,       # mov ax, 0x0000
      0xBA, 0x00, 0x00,       # mov dx, 0x0000
      0xCD, 0x13,             # int 0x13
      0x89, 0x2E, 0x00, 0x09, # mov [0x0900], bp
      0xC6, 0x06, 0x02, 0x09, 0x5A, # mov byte [0x0902], 0x5a
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 3_000)

    expect(runner.read_bytes(0x0900, 2, mapped: false)).to eq([0x00, 0x7C])
    expect(runner.read_bytes(0x0902, 1, mapped: false)).to eq([0x5A])
    expect(runner.peek('trace_wr_eip')).to be >= 0x7C70
  end

  it 'returns from DOS INT 13h when the read buffer overlaps the live boot stack', timeout: 90 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload = [
      0xFA,                   # cli
      0xB8, 0xE0, 0x1F,       # mov ax, 0x1fe0
      0x8E, 0xD0,             # mov ss, ax
      0xBC, 0xA0, 0x7B,       # mov sp, 0x7ba0
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xBB, 0x00, 0x00,       # mov bx, 0x0000
      0xB8, 0x80, 0x27,       # mov ax, 0x2780
      0x8E, 0xC0,             # mov es, ax
      0xB8, 0x01, 0x02,       # mov ax, 0x0201
      0xB9, 0x09, 0x09,       # mov cx, 0x0909
      0xBA, 0x00, 0x00,       # mov dx, 0x0000
      0xCD, 0x13,             # int 0x13
      0xC6, 0x06, 0x00, 0x09, 0x5A, # mov byte [0x0900], 0x5a
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 5_000)

    expect(runner.read_bytes(0x0900, 1, mapped: false)).to eq([0x5A])
    expect(runner.peek('trace_wr_eip')).to be >= 0x7C7B
    expect(runner.peek('pipeline_inst__decode_inst__eip')).to be >= 0x7C7B
  end

  it 'returns DOS INT 13h AH=08 geometry through the runner-local stub' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload = [
      0xFA,                   # cli
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0xBD, 0x00, 0x7C,       # mov bp, 0x7c00
      0xB8, 0x00, 0x08,       # mov ax, 0x0800
      0xBA, 0x00, 0x00,       # mov dx, 0x0000
      0xCD, 0x13,             # int 0x13
      0x89, 0x1E, 0x00, 0x09, # mov [0x0900], bx
      0x89, 0x0E, 0x02, 0x09, # mov [0x0902], cx
      0x89, 0x16, 0x04, 0x09, # mov [0x0904], dx
      0xC6, 0x06, 0x06, 0x09, 0x5A, # mov byte [0x0906], 0x5a
      0xEB, 0xFE              # jmp $
    ]
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 3_000)

    expect(runner.read_bytes(0x0900, 2, mapped: false)).to eq([0x00, 0x04])
    expect(runner.read_bytes(0x0902, 2, mapped: false)).to eq([0x12, 0x4F])
    expect(runner.read_bytes(0x0904, 2, mapped: false)).to eq([0x02, 0x01])
    expect(runner.read_bytes(0x0906, 1, mapped: false)).to eq([0x5A])
  end

  it 'retargets a cross-line DOS fetch window after a control-flow jump' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    success_addr = 0x0900
    failure_addr = 0x0901
    runner.load_bytes(success_addr, [0x00, 0x00])

    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR
    {
      0x5E => [0xEA, 0x34, 0x7C, 0xE0, 0x1F],
      0x34 => [0x31, 0xC0, 0x8E, 0xD8, 0x90, 0x90, 0x90, 0x90, 0xE9, 0x41, 0x00, 0x90],
      0x40 => [0xC6, 0x06, failure_addr & 0xFF, (failure_addr >> 8) & 0xFF, 0xEE, 0xEB, 0xFE],
      0x80 => [0xC6, 0x06, success_addr & 0xFF, (success_addr >> 8) & 0xFF, 0x5A, 0xEB, 0xFE]
    }.each do |offset, bytes|
      bytes.each_with_index do |byte, idx|
        runner.write_memory(base + offset + idx, byte)
      end
    end

    runner.run(cycles: 3_000)

    expect(runner.read_bytes(success_addr, 1, mapped: false)).to eq([0x5A])
    expect(runner.read_bytes(failure_addr, 1, mapped: false)).to eq([0x00])
    expect(runner.peek('trace_wr_eip')).to be >= 0x7C80
    expect(runner.peek('exception_inst__exc_vector')).to eq(0)
  end

  it 'advances through later DOS loader milestones after the first real INT 13h handoff', timeout: 90 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    runner.run(cycles: 7_000)

    handoff_eip = runner.peek('trace_wr_eip')
    later_trace_eips = []
    12.times do
      runner.run(cycles: 1_000)
      later_trace_eips << runner.peek('trace_wr_eip')
    end

    expect(handoff_eip).to be >= 0x0540
    expect(later_trace_eips.max).to be >= 0x7C40
    expect(later_trace_eips.any? { |eip| eip >= 0x7C00 }).to be(true)
    expect(runner.peek('pipeline_inst__read_inst__rd_eip')).to be >= 0x0540
    expect(runner.peek('trace_arch_ecx')).to be > 0
  end

  it 'renders DOS INT 10h teletype output into the text buffer on the real runner path' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    payload = [
      0xB8, 0x03, 0x00,
      0xCD, 0x10,
      0xB8, 0x4F, 0x0E,
      0xCD, 0x10,
      0xB8, 0x4B, 0x0E,
      0xCD, 0x10,
      0xEB, 0xFE
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 2_000)

    expect(runner.read_bytes(0xB8000, 4, mapped: false)).to eq(['O'.ord, 0x07, 'K'.ord, 0x07])
    expect(runner.read_bytes(RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA, 2, mapped: false)).to eq([0x02, 0x00])
    expect(runner.render_display).to include('OK')
  end

  it 'renders DOS INT 10h write-string output on the real runner path' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    runner.load_bytes(0x0680, 'DOS'.bytes)
    payload = [
      0xB8, 0x03, 0x00,
      0xCD, 0x10,
      0xBB, 0x07, 0x00,
      0xB9, 0x03, 0x00,
      0xBA, 0x00, 0x00,
      0xBD, 0x80, 0x06,
      0x31, 0xC0,
      0x8E, 0xC0,
      0xB8, 0x01, 0x13,
      0xCD, 0x10,
      0xEB, 0xFE
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 2_500)

    expect(runner.read_bytes(0xB8000, 6, mapped: false)).to eq(['D'.ord, 0x07, 'O'.ord, 0x07, 'S'.ord, 0x07])
    expect(runner.read_bytes(RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA, 2, mapped: false)).to eq([0x03, 0x00])
    expect(runner.render_display).to include('DOS')
  end

  it 'renders the active hardware text page after syncing runtime windows' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.run(cycles: 0)

    page_base = RHDL::Examples::AO486::DisplayAdapter::TEXT_BASE +
      RHDL::Examples::AO486::DisplayAdapter::BUFFER_SIZE
    runner.sim.runner_write_memory(page_base, ['P'.ord, 0x07, '2'.ord, 0x07], mapped: false)
    runner.sim.runner_write_memory(RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA + 2, [0x01, 0x00], mapped: false)
    runner.sim.runner_write_memory(RHDL::Examples::AO486::DisplayAdapter::VIDEO_PAGE_BDA, [0x01], mapped: false)

    runner.run(cycles: 0)

    expect(runner.render_display.lines.first).to start_with('P_')
  end

  it 'consumes queued keyboard input through DOS INT 16h on the real runner path' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    payload = [
      0xB4, 0x00,
      0xCD, 0x16,
      0xA3, 0x00, 0x06,
      0xEB, 0xFE
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.send_keys("d")
    state = runner.run(cycles: 2_000)

    expect(runner.read_bytes(0x0600, 2, mapped: false)).to eq(['d'.ord, 0x20])
    expect(state[:keyboard_buffer_size]).to eq(0)
  end

  it 'surfaces queued keyboard input through raw PS/2 status/data ports on the real runner path', timeout: 240 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    payload = [
      0xBA, 0x64, 0x00,       # mov dx, 0x64
      0xEC,                   # in al, dx
      0xA2, 0x00, 0x06,       # mov [0x0600], al
      0xBA, 0x60, 0x00,       # mov dx, 0x60
      0xEC,                   # in al, dx
      0xA2, 0x01, 0x06,       # mov [0x0601], al
      0xBA, 0x64, 0x00,       # mov dx, 0x64
      0xEC,                   # in al, dx
      0xA2, 0x02, 0x06,       # mov [0x0602], al
      0xEB, 0xFE              # jmp $
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.send_keys('d')
    runner.run(cycles: 2_500)

    expect(runner.read_bytes(0x0600, 3, mapped: false)).to eq([0x19, 0x20, 0x18])
    expect(runner.state[:keyboard_buffer_size]).to eq(0)
  end

  it 'executes a boot-sector style REPE CMPSB match on the relocated DOS path', timeout: 240 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    runner.load_bytes(0x0680, 'KERNEL  SYS'.bytes)
    runner.load_bytes(0x0690, 'KERNEL  SYS'.bytes)

    payload = [
      0x31, 0xC0,             # xor ax, ax
      0x8E, 0xD8,             # mov ds, ax
      0x8E, 0xC0,             # mov es, ax
      0xFC,                   # cld
      0xBE, 0x80, 0x06,       # mov si, 0x0680
      0xBF, 0x90, 0x06,       # mov di, 0x0690
      0xB9, 0x0B, 0x00,       # mov cx, 11
      0xF3, 0xA6,             # repe cmpsb
      0x9C,                   # pushf
      0x58,                   # pop ax
      0x89, 0x36, 0x00, 0x06, # mov [0x0600], si
      0x89, 0x3E, 0x02, 0x06, # mov [0x0602], di
      0x89, 0x0E, 0x04, 0x06, # mov [0x0604], cx
      0xA3, 0x06, 0x06,       # mov [0x0606], ax
      0xEB, 0xFE              # jmp $
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end

    runner.run(cycles: 3_000)

    expect(runner.read_bytes(0x0600, 8, mapped: false)).to eq([0x8B, 0x06, 0x9B, 0x06, 0x00, 0x00, 0x46, 0x00])
    expect(runner.peek('exception_inst__exc_vector')).to eq(0)
  end

  it 'installs the DOS INT 1Ah bridge vector during the DOS handoff', timeout: 240 do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    runner.run(cycles: 1_200)

    expect(runner.read_bytes(0x0068, 4, mapped: false)).to eq([0x30, 0x11, 0x00, 0xF0])
  end

  it 'executes the relocated DOS BPB arithmetic slice without trapping' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.load_dos

    payload = [
      0xBD, 0x00, 0x7C,
      0x8B, 0x76, 0x1C,
      0x8B, 0x7E, 0x1E,
      0x03, 0x76, 0x0E,
      0x83, 0xD7, 0x00,
      0x8A, 0x46, 0x10,
      0x98,
      0xF7, 0x66, 0x16,
      0x8B, 0x5E, 0x0B,
      0xB1, 0x05,
      0xD3, 0xEB,
      0x8B, 0x46, 0x11,
      0x31, 0xD2,
      0xF7, 0xF3,
      0x89, 0x36, 0x00, 0x06,
      0x89, 0x3E, 0x02, 0x06,
      0xA3, 0x04, 0x06,
      0x89, 0x16, 0x06, 0x06,
      0x89, 0x1E, 0x08, 0x06,
      0xEB, 0xFE
    ]
    base = described_class::DOS_RELOCATED_BOOT_SECTOR_ADDR + 0x5E
    payload.each_with_index do |byte, idx|
      runner.write_memory(base + idx, byte)
    end
    runner.run(cycles: 5_000)

    expect(runner.read_bytes(0x0600, 10, mapped: false)).to eq([0x01, 0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00, 0x10, 0x00])
    expect(runner.peek('exception_inst__exc_vector')).to eq(0)
  end

end
