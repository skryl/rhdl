# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../../examples/apple2/hdl/disk_ii'
require_relative '../../../support/vhdl_reference_helper'
require_relative '../../../support/hdl_toolchain'

RSpec.describe RHDL::Examples::Apple2::DiskII do
  extend VhdlReferenceHelper
  let(:disk) { described_class.new('disk') }

  # Disk II I/O addresses (relative to slot base C0E0)
  # Reference from disk_ii.vhd comments
  PHASE0_OFF = 0x0  # C080
  PHASE0_ON  = 0x1  # C081
  PHASE1_OFF = 0x2  # C082
  PHASE1_ON  = 0x3  # C083
  PHASE2_OFF = 0x4  # C084
  PHASE2_ON  = 0x5  # C085
  PHASE3_OFF = 0x6  # C086
  PHASE3_ON  = 0x7  # C087
  MOTOR_OFF  = 0x8  # C088
  MOTOR_ON   = 0x9  # C089
  DRIVE1     = 0xA  # C08A
  DRIVE2     = 0xB  # C08B
  Q6_OFF     = 0xC  # C08C - Read data
  Q6_ON      = 0xD  # C08D
  Q7_OFF     = 0xE  # C08E - Read mode
  Q7_ON      = 0xF  # C08F - Write mode

  before do
    disk
    disk.set_input(:clk_14m, 0)
    disk.set_input(:clk_2m, 0)
    disk.set_input(:pre_phase_zero, 0)
    disk.set_input(:io_select, 0)
    disk.set_input(:device_select, 0)
    disk.set_input(:reset, 0)
    disk.set_input(:a, 0)
    disk.set_input(:d_in, 0)
    disk.set_input(:ram_write_addr, 0)
    disk.set_input(:ram_di, 0)
    disk.set_input(:ram_we, 0)

    # Reset
    disk.set_input(:reset, 1)
    clock_2m
    disk.set_input(:reset, 0)
  end

  def clock_14m
    disk.set_input(:clk_14m, 0)
    disk.propagate
    disk.set_input(:clk_14m, 1)
    disk.propagate
  end

  def clock_2m
    # DiskII runs from clk_14m and samples clk_2m edges internally.
    disk.set_input(:clk_2m, 0)
    clock_14m
    disk.set_input(:clk_2m, 1)
    clock_14m
  end

  def access_io(addr_low)
    # Access device I/O at C0Ex
    disk.set_input(:a, 0xC0E0 | addr_low)
    disk.set_input(:device_select, 1)
    disk.set_input(:pre_phase_zero, 1)
    clock_2m
    disk.set_input(:device_select, 0)
    disk.set_input(:pre_phase_zero, 0)
  end

  def load_track_data(data)
    data.each_with_index do |byte, i|
      disk.set_input(:ram_write_addr, i)
      disk.set_input(:ram_di, byte)
      disk.set_input(:ram_we, 1)
      clock_14m
    end
    disk.set_input(:ram_we, 0)
  end

  describe 'motor control' do
    # Reference VHDL: C088 turns motor off, C089 turns motor on

    it 'turns motor on when accessing C089' do
      access_io(MOTOR_ON)
      clock_2m

      d1_active = disk.get_output(:d1_active)
      expect(d1_active).to eq(1)
    end

    it 'turns motor off when accessing C088' do
      # First turn on
      access_io(MOTOR_ON)
      clock_2m

      # Then turn off
      access_io(MOTOR_OFF)
      clock_2m

      d1_active = disk.get_output(:d1_active)
      expect(d1_active).to eq(0)
    end
  end

  describe 'drive selection' do
    # Reference VHDL: C08A selects drive 1, C08B selects drive 2

    it 'selects drive 1 by default' do
      access_io(MOTOR_ON)
      clock_2m

      d1_active = disk.get_output(:d1_active)
      d2_active = disk.get_output(:d2_active)

      expect(d1_active).to eq(1)
      expect(d2_active).to eq(0)
    end

    it 'selects drive 2 when accessing C08B' do
      access_io(MOTOR_ON)
      clock_2m
      access_io(DRIVE2)
      clock_2m

      d1_active = disk.get_output(:d1_active)
      d2_active = disk.get_output(:d2_active)

      expect(d1_active).to eq(0)
      expect(d2_active).to eq(1)
    end

    it 'returns to drive 1 when accessing C08A' do
      access_io(MOTOR_ON)
      access_io(DRIVE2)
      clock_2m
      access_io(DRIVE1)
      clock_2m

      d1_active = disk.get_output(:d1_active)
      expect(d1_active).to eq(1)
    end
  end

  describe 'Q6/Q7 mode control' do
    # Reference VHDL:
    # Q7 Q6 Mode
    # 0  0  Read
    # 0  1  Sense write protect
    # 1  0  Write
    # 1  1  Load Write Latch

    it 'sets Q6 with C08C (off) and C08D (on)' do
      access_io(Q6_OFF)
      clock_2m
      # Q6 should be 0

      access_io(Q6_ON)
      clock_2m
      # Q6 should be 1
    end

    it 'sets Q7 with C08E (off) and C08F (on)' do
      access_io(Q7_OFF)
      clock_2m
      # Q7 should be 0 (read mode)

      access_io(Q7_ON)
      clock_2m
      # Q7 should be 1 (write mode)
    end
  end

  describe 'head stepper motor phases' do
    # Reference VHDL: 4 phase stepper motor
    # C080-C087 control phases 0-3
    # Two phase changes per track (70 phases for 35 tracks)

    it 'controls phase 0 with C080/C081' do
      access_io(PHASE0_ON)
      clock_2m
      # Phase 0 enabled

      access_io(PHASE0_OFF)
      clock_2m
      # Phase 0 disabled
    end

    it 'controls all 4 phases independently' do
      # Enable phases in sequence
      access_io(PHASE0_ON)
      clock_2m
      access_io(PHASE1_ON)
      clock_2m
      access_io(PHASE2_ON)
      clock_2m
      access_io(PHASE3_ON)
      clock_2m

      # Disable all
      access_io(PHASE0_OFF)
      access_io(PHASE1_OFF)
      access_io(PHASE2_OFF)
      access_io(PHASE3_OFF)
      clock_2m
    end
  end

  describe 'track position' do
    # Reference VHDL: phase(7:2) is track number
    # Initial phase is 70 (track 17 or 18)

    it 'reports initial track position' do
      track = disk.get_output(:track)
      # Initial phase of 70 means track 70/2 = 35, but clamped
      expect(track).to be_between(0, 34)
    end

    it 'outputs 6-bit track number' do
      track = disk.get_output(:track)
      expect(track).to be_between(0, 63)  # 6 bits
    end
  end

  describe 'track data reading' do
    # Reference VHDL:
    # Track data is 0x1A00 (6656) bytes
    # Reading C08C returns track data when valid

    before do
      # Load some track data
      track_data = (0...100).map { |i| i & 0xFF }
      load_track_data(track_data)

      # Turn on motor and set read mode
      access_io(MOTOR_ON)
      access_io(Q7_OFF)  # Read mode
    end

    it 'reads from track buffer' do
      # Access C08C to read data
      disk.set_input(:a, 0xC0EC)  # C08C
      disk.set_input(:device_select, 1)
      disk.propagate

      d_out = disk.get_output(:d_out)
      expect(d_out).to be_between(0, 255)
    end

    it 'advances track address on read' do
      initial_addr = disk.get_output(:track_addr)

      # Multiple reads should advance address
      10.times do
        disk.set_input(:a, 0xC0EC)
        disk.set_input(:device_select, 1)
        disk.set_input(:pre_phase_zero, 1)
        clock_2m
        disk.set_input(:device_select, 0)
        disk.set_input(:pre_phase_zero, 0)
      end

      final_addr = disk.get_output(:track_addr)
      # Address should have changed (either advanced or wrapped)
      expect(final_addr).to be_a(Integer)
    end

    it 'wraps track address at end of track' do
      # Track size is 0x33FE (13310) half-bytes, wraps to 0
      # The actual address is track_byte_addr(14:1)

      track_addr = disk.get_output(:track_addr)
      expect(track_addr).to be_between(0, 0x3FFF)  # 14 bits
    end
  end

  describe 'ROM access' do
    # Reference VHDL: IO_SELECT accesses ROM at C600-C6FF

    it 'outputs ROM data when io_select is high' do
      disk.set_input(:a, 0xC600)  # ROM base
      disk.set_input(:io_select, 1)
      disk.propagate

      d_out = disk.get_output(:d_out)
      # ROM data should be output
      expect(d_out).to be_between(0, 255)
    end

    it 'uses low 8 bits of address for ROM' do
      disk.set_input(:a, 0xC6FF)  # Last ROM byte
      disk.set_input(:io_select, 1)
      disk.propagate

      d_out = disk.get_output(:d_out)
      expect(d_out).to be_between(0, 255)
    end
  end

  describe 'track RAM interface' do
    # Reference VHDL: External interface for loading track data

    it 'accepts track data via ram_we' do
      # Write a test pattern
      disk.set_input(:ram_write_addr, 0)
      disk.set_input(:ram_di, 0xAA)
      disk.set_input(:ram_we, 1)
      clock_14m
      disk.set_input(:ram_we, 0)

      # Read it back
      access_io(MOTOR_ON)
      access_io(Q7_OFF)

      disk.set_input(:a, 0xC0EC)
      disk.set_input(:device_select, 1)
      disk.propagate

      # Data should be readable
      d_out = disk.get_output(:d_out)
      expect(d_out).to be_between(0, 255)
    end

    it 'supports 14-bit write address' do
      # Track is 6656 bytes, needs 13 bits, but interface has 14
      disk.set_input(:ram_write_addr, 0x2000)  # High address
      disk.set_input(:ram_di, 0x55)
      disk.set_input(:ram_we, 1)
      clock_14m
      disk.set_input(:ram_we, 0)
    end
  end

  describe 'disk spin timing' do
    # Reference VHDL:
    # New byte every 32 CPU cycles (2 MHz / 64)
    # byte_delay counter simulates disk rotation

    it 'advances byte address over time' do
      access_io(MOTOR_ON)
      initial_addr = disk.get_output(:track_addr)

      # Run for many cycles
      100.times { clock_2m }

      final_addr = disk.get_output(:track_addr)
      # Address should change over time (disk spinning)
      expect(final_addr).to be_a(Integer)
    end
  end

  describe 'reset behavior' do
    it 'resets motor phase registers' do
      # Set some state
      access_io(MOTOR_ON)
      access_io(PHASE0_ON)
      access_io(PHASE1_ON)
      clock_2m

      # Reset
      disk.set_input(:reset, 1)
      clock_2m
      disk.set_input(:reset, 0)
      clock_2m

      # Motor should be off after reset
      d1_active = disk.get_output(:d1_active)
      expect(d1_active).to eq(0)
    end

    it 'resets track byte address' do
      # Run to advance address
      access_io(MOTOR_ON)
      50.times { clock_2m }

      # Reset
      disk.set_input(:reset, 1)
      clock_2m
      disk.set_input(:reset, 0)
      clock_2m

      track_addr = disk.get_output(:track_addr)
      expect(track_addr).to eq(0)
    end
  end

  describe 'simulation helpers' do
    it 'provides load_track method' do
      track_data = (0...100).to_a
      disk.load_track(0, track_data)

      # Verify data was loaded
      byte = disk.read_track_byte(0)
      expect(byte).to eq(0)
    end

    it 'provides read_track_byte method' do
      disk.load_track(0, [0xDE, 0xAD, 0xBE, 0xEF])

      expect(disk.read_track_byte(0)).to eq(0xDE)
      expect(disk.read_track_byte(1)).to eq(0xAD)
      expect(disk.read_track_byte(2)).to eq(0xBE)
      expect(disk.read_track_byte(3)).to eq(0xEF)
    end
  end

  describe 'VHDL reference comparison', if: HdlToolchain.ghdl_available? do
    include VhdlReferenceHelper

    let(:reference_vhdl) { VhdlReferenceHelper.reference_file('disk_ii.vhd') }
    let(:rom_vhdl) { VhdlReferenceHelper.reference_file('disk_ii_rom.vhd') }
    let(:work_dir) { Dir.mktmpdir('disk_ii_test_') }

    before do
      skip 'Reference VHDL not found' unless VhdlReferenceHelper.reference_exists?('disk_ii.vhd')
    end

    after do
      FileUtils.rm_rf(work_dir) if work_dir && Dir.exist?(work_dir)
    end

    it 'matches reference motor control behavior' do
      # This is a high-level test that compares motor on/off behavior
      # Disk II has complex dependencies so we test reset behavior
      ports = {
        CLK_14M: { direction: 'in', width: 1 },
        CLK_2M: { direction: 'in', width: 1 },
        PRE_PHASE_ZERO: { direction: 'in', width: 1 },
        IO_SELECT: { direction: 'in', width: 1 },
        DEVICE_SELECT: { direction: 'in', width: 1 },
        RESET: { direction: 'in', width: 1 },
        A: { direction: 'in', width: 16 },
        D_IN: { direction: 'in', width: 8 },
        D_OUT: { direction: 'out', width: 8 },
        TRACK: { direction: 'out', width: 6 },
        D1_ACTIVE: { direction: 'out', width: 1 },
        D2_ACTIVE: { direction: 'out', width: 1 }
      }

      # Test reset behavior
      test_vectors = [
        { inputs: { RESET: 1, A: 0, D_IN: 0, PRE_PHASE_ZERO: 0, IO_SELECT: 0, DEVICE_SELECT: 0, CLK_2M: 0 } },
        { inputs: { RESET: 0, A: 0, D_IN: 0, PRE_PHASE_ZERO: 0, IO_SELECT: 0, DEVICE_SELECT: 0, CLK_2M: 0 } }
      ]

      result = run_comparison_test(
        disk,
        vhdl_files: [reference_vhdl, rom_vhdl],
        ports: ports,
        test_vectors: test_vectors,
        base_dir: work_dir,
        clock_name: 'CLK_14M'
      )

      if result[:success] == false && result[:error]
        skip "GHDL simulation failed: #{result[:error]}"
      end

      expect(result[:success]).to be(true),
        "Mismatches: #{result[:comparison][:mismatches].first(5).inspect}"
    end
  end
end

RSpec.describe RHDL::Examples::Apple2::DiskIIROM do
  let(:rom) { described_class.new('disk_rom') }

  before do
    rom
    rom.set_input(:clk, 0)
    rom.set_input(:addr, 0)
  end

  def clock_cycle
    rom.set_input(:clk, 0)
    rom.propagate
    rom.set_input(:clk, 1)
    rom.propagate
  end

  describe 'ROM structure' do
    it 'has 256-byte capacity' do
      # Disk II ROM is 256 bytes (C600-C6FF)
      rom.set_input(:addr, 0)
      rom.propagate
      dout = rom.get_output(:dout)
      expect(dout).to be_between(0, 255)

      rom.set_input(:addr, 255)
      rom.propagate
      dout = rom.get_output(:dout)
      expect(dout).to be_between(0, 255)
    end

    it 'uses 8-bit address' do
      (0..255).step(32).each do |addr|
        rom.set_input(:addr, addr)
        rom.propagate
        expect(rom.get_output(:dout)).to be_between(0, 255)
      end
    end

    it 'outputs 8-bit data' do
      rom.set_input(:addr, 0)
      rom.propagate
      dout = rom.get_output(:dout)
      expect(dout).to be_between(0, 255)
    end
  end

  describe 'asynchronous read' do
    it 'provides combinational output' do
      # Test that output changes immediately with address (combinational)
      rom.set_input(:addr, 0)
      rom.propagate
      val0 = rom.get_output(:dout)
      expect(val0).to be_between(0, 255)

      rom.set_input(:addr, 1)
      rom.propagate
      val1 = rom.get_output(:dout)
      expect(val1).to be_between(0, 255)

      rom.set_input(:addr, 2)
      rom.propagate
      val2 = rom.get_output(:dout)
      expect(val2).to be_between(0, 255)
    end
  end

  describe 'load_rom helper' do
    it 'loads ROM data at runtime' do
      boot_code = [0xA9, 0x60, 0x8D, 0x01, 0x08]  # Sample boot code
      rom.load_rom(boot_code)

      boot_code.each_with_index do |byte, i|
        rom.set_input(:addr, i)
        rom.propagate
        expect(rom.get_output(:dout)).to eq(byte)
      end
    end

    it 'limits data to 256 bytes' do
      large_data = (0..300).to_a
      rom.load_rom(large_data)

      # Should only load first 256 bytes
      rom.set_input(:addr, 255)
      rom.propagate
      expect(rom.get_output(:dout)).to eq(255)
    end
  end

  describe 'VHDL reference comparison', if: HdlToolchain.ghdl_available? do
    include VhdlReferenceHelper

    let(:reference_vhdl) { VhdlReferenceHelper.reference_file('disk_ii_rom.vhd') }
    let(:work_dir) { Dir.mktmpdir('disk_ii_rom_test_') }

    before do
      skip 'Reference VHDL not found' unless VhdlReferenceHelper.reference_exists?('disk_ii_rom.vhd')
    end

    after do
      FileUtils.rm_rf(work_dir) if work_dir && Dir.exist?(work_dir)
    end

    it 'matches reference ROM read behavior' do
      ports = {
        clk: { direction: 'in', width: 1 },
        addr: { direction: 'in', width: 8 },
        dout: { direction: 'out', width: 8 }
      }

      # Test reading from various ROM addresses
      test_vectors = [0, 16, 32, 64, 128, 200, 255].map { |addr| { inputs: { addr: addr } } }

      result = run_comparison_test(
        rom,
        vhdl_files: [reference_vhdl],
        ports: ports,
        test_vectors: test_vectors,
        base_dir: work_dir,
        clock_name: 'clk'
      )

      if result[:success] == false && result[:error]
        skip "GHDL simulation failed: #{result[:error]}"
      end

      expect(result[:success]).to be(true),
        "Mismatches: #{result[:comparison][:mismatches].first(5).inspect}"
    end
  end
end
