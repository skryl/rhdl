# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/utilities/runners/ir_runner'

RSpec.describe 'Karateka boot from .dsk', :slow do
  let(:rom_path) { File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__) }
  let(:disk_path) { File.expand_path('../../../../examples/apple2/software/disks/karateka.dsk', __FILE__) }
  let(:karateka_mem_path) { File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__) }

  before do
    skip 'Slow test - set RUN_SLOW_TESTS=1 and run with --tag slow' unless ENV['RUN_SLOW_TESTS']
    skip 'IR Compiler not available (run `rake native:build target=ir_compiler`)' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    skip 'AppleIIgo ROM not found' unless File.exist?(rom_path)
    skip 'Karateka disk image not found' unless File.exist?(disk_path)
    skip 'Karateka memory dump not found (needed for validation)' unless File.exist?(karateka_mem_path)
  end

  it 'loads Karateka via DiskII and reaches game code', timeout: 300 do
    runner = RHDL::Examples::Apple2::IrSimulatorRunner.new(backend: :compile, sub_cycles: 2)

    # Force boot from slot 6 Disk II ROM at $C600
    rom = File.binread(rom_path).bytes
    rom[0x2FFC] = 0x00  # low byte of $C600
    rom[0x2FFD] = 0xC6  # high byte of $C600

    runner.load_rom(rom, base_addr: 0xD000)
    runner.load_disk(disk_path, drive: 0)
    runner.reset

    expected = File.binread(karateka_mem_path).bytes
    expected_slice = expected[0xB82A, 16]
    raise 'Invalid Karateka memdump (missing expected slice)' if expected_slice.nil? || expected_slice.length != 16

    loaded = false
    max_cycles = 200_000_000
    chunk = 5_000_000
    cycles = 0

    while cycles < max_cycles
      runner.run_steps(chunk)
      cycles += chunk

      actual_slice = runner.sim.apple2_read_ram(0xB82A, 16)
      if actual_slice == expected_slice
        loaded = true
        break
      end
    end

    expect(loaded).to be(true), "Expected Karateka code to be loaded at $B82A within #{max_cycles} cycles"

    pc = runner.cpu_state[:pc]
    expect(pc).to be_between(0x6000, 0xBFFF), "Expected CPU to be executing from RAM after boot, got PC=0x#{pc.to_s(16)}"

    # Sanity check: hires page should not be all zeros once the game is loaded
    hires_sample = runner.sim.apple2_read_ram(0x2000, 256)
    expect(hires_sample.any? { |b| b != 0 }).to be(true), 'Expected non-zero hi-res graphics data'
  end
end
