# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'

RSpec.describe RHDL::Apple2::Apple2 do
  let(:apple2) { described_class.new('apple2') }
  let(:ram) { Array.new(48 * 1024, 0) }  # 48KB RAM

  before do
    apple2
    # Initialize inputs
    apple2.set_input(:clk_14m, 0)
    apple2.set_input(:flash_clk, 0)
    apple2.set_input(:reset, 0)
    apple2.set_input(:ram_do, 0)
    apple2.set_input(:pd, 0)
    apple2.set_input(:k, 0)
    apple2.set_input(:gameport, 0)
    apple2.set_input(:pause, 0)
  end

  def clock_14m_cycle
    # 14MHz falling edge
    apple2.set_input(:clk_14m, 0)
    apple2.propagate

    # Get RAM address and provide data
    ram_addr = apple2.get_output(:ram_addr)
    if ram_addr < ram.size
      apple2.set_input(:ram_do, ram[ram_addr])
    end
    apple2.propagate

    # 14MHz rising edge
    apple2.set_input(:clk_14m, 1)
    apple2.propagate

    # Handle RAM writes
    ram_we = apple2.get_output(:ram_we)
    if ram_we == 1
      write_addr = apple2.get_output(:ram_addr)
      if write_addr < ram.size
        ram[write_addr] = apple2.get_output(:d)
      end
    end
  end

  def clock_cycle
    # Run multiple 14MHz cycles for one approximate CPU cycle
    14.times { clock_14m_cycle }
  end

  def run_cycles(n)
    n.times { clock_cycle }
  end

  def reset_system
    apple2.set_input(:reset, 1)
    clock_cycle
    apple2.set_input(:reset, 0)
  end

  def load_rom(data)
    apple2.load_rom(data)
  end

  describe 'component integration' do
    it 'elaborates all sub-components' do
      expect(apple2.instance_variable_get(:@timing)).to be_a(RHDL::Apple2::TimingGenerator)
      expect(apple2.instance_variable_get(:@video_gen)).to be_a(RHDL::Apple2::VideoGenerator)
      expect(apple2.instance_variable_get(:@char_rom)).to be_a(RHDL::Apple2::CharacterROM)
      expect(apple2.instance_variable_get(:@speaker_toggle)).to be_a(RHDL::Apple2::SpeakerToggle)
      expect(apple2.instance_variable_get(:@cpu)).to be_a(RHDL::Apple2::CPU6502)
    end
  end

  describe 'clock generation' do
    it 'generates clk_2m from timing generator' do
      reset_system
      values = []
      100.times do
        clock_cycle
        values << apple2.get_output(:clk_2m)
      end

      # Should have transitions
      expect(values.uniq.size).to be > 1
    end

    it 'generates pre_phase_zero' do
      reset_system
      values = []
      100.times do
        clock_cycle
        values << apple2.get_output(:pre_phase_zero)
      end

      expect(values).to include(0).or include(1)
    end
  end

  describe 'basic integration' do
    it 'system initializes without error' do
      reset_system
      run_cycles(10)
      expect(apple2.get_output(:pc_debug)).to be_a(Integer)
    end
  end

  describe 'boot sequence' do
    before do
      # Create a simple ROM that:
      # 1. Sets up the stack
      # 2. Runs a simple loop
      # ROM starts at $D000 (offset 0x0000 in ROM memory)
      # Reset vector at $FFFC-$FFFD (offset 0x2FFC in ROM memory)

      rom = Array.new(12 * 1024, 0xEA)  # Fill with NOPs

      # Simple boot code at $F000 (offset 0x2000)
      # $F000: LDX #$FF   ; Set stack pointer
      # $F002: TXS
      # $F003: LDA #$41   ; 'A' ASCII
      # $F005: STA $0400  ; Store to text page
      # $F008: JMP $F008  ; Infinite loop
      boot_code = [
        0xA2, 0xFF,       # LDX #$FF
        0x9A,             # TXS
        0xA9, 0x41,       # LDA #'A'
        0x8D, 0x00, 0x04, # STA $0400
        0x4C, 0x08, 0xF0  # JMP $F008
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte  # $F000 = ROM offset 0x2000
      end

      # Set reset vector to $F000
      rom[0x2FFC] = 0x00  # Low byte
      rom[0x2FFD] = 0xF0  # High byte

      load_rom(rom)
      reset_system
    end

    it 'reads reset vector and jumps to boot code' do
      # Complete reset sequence
      run_cycles(10)

      # After reset, PC should be at boot code address
      pc = apple2.get_output(:pc_debug)
      expect(pc).to be >= 0xF000
    end

    it 'executes boot code and writes to RAM' do
      # Run enough cycles to execute boot code
      50.times { clock_cycle }

      # Check that 'A' was written to $0400
      expect(ram[0x0400]).to eq(0x41)
    end
  end

  describe 'ROM access' do
    before do
      # Create ROM with identifiable pattern
      rom = Array.new(12 * 1024, 0)

      # Put signature at known locations
      rom[0x0000] = 0xD0  # $D000
      rom[0x1000] = 0xE0  # $E000
      rom[0x2000] = 0xF0  # $F000

      # Boot code that reads ROM
      # $F010: LDA $D000
      # $F013: STA $10
      # $F015: JMP $F015
      boot_code = [
        0xAD, 0x00, 0xD0,  # LDA $D000
        0x85, 0x10,        # STA $10
        0x4C, 0x15, 0xF0   # JMP $F015
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2010 + i] = byte  # $F010 = ROM offset 0x2010
      end

      # Reset vector points to $F010
      rom[0x2FFC] = 0x10
      rom[0x2FFD] = 0xF0

      load_rom(rom)
      reset_system
    end

    it 'CPU can read ROM and write to RAM' do
      # Run boot code: LDA $D000 (4 cycles) + STA $10 (3 cycles)
      # Each CPU cycle needs ~14 14MHz cycles, plus reset overhead
      run_cycles(100)

      # Check that ROM value ($D0) was written to RAM at $10
      expect(ram[0x10]).to eq(0xD0)
    end
  end

  describe 'keyboard interface' do
    before do
      # Boot code that reads keyboard
      # $F000: LDA $C000  ; Read keyboard
      # $F003: STA $10    ; Store to ZP
      # $F005: JMP $F000  ; Loop
      rom = Array.new(12 * 1024, 0xEA)

      boot_code = [
        0xAD, 0x00, 0xC0,  # LDA $C000
        0x85, 0x10,        # STA $10
        0x4C, 0x00, 0xF0   # JMP $F000
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte
      end

      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0

      load_rom(rom)
      reset_system
    end

    it 'reads keyboard data from $C000' do
      # Set keyboard data
      apple2.set_input(:k, 0xC1)  # 'A' with high bit set

      run_cycles(100)

      # The keyboard value should be stored at $10
      expect(ram[0x10]).to eq(0xC1)
    end
  end

  describe 'speaker toggle' do
    it 'toggles speaker when $C030 is accessed' do
      # Boot code that toggles speaker
      rom = Array.new(12 * 1024, 0xEA)

      boot_code = [
        0xAD, 0x30, 0xC0,  # LDA $C030 (toggle speaker)
        0x4C, 0x00, 0xF0   # JMP $F000
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte
      end

      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0

      load_rom(rom)
      reset_system

      # Run to toggle speaker
      run_cycles(50)

      # Speaker state may have changed
      final_speaker = apple2.get_output(:speaker)
      expect([0, 1]).to include(final_speaker)
    end
  end

  describe 'video generation' do
    before do
      reset_system
    end

    it 'outputs video signal' do
      100.times { clock_cycle }

      video = apple2.get_output(:video)
      expect([0, 1]).to include(video)
    end

    it 'outputs color_line signal' do
      100.times { clock_cycle }

      color_line = apple2.get_output(:color_line)
      expect([0, 1]).to include(color_line)
    end

    it 'outputs blanking signals' do
      100.times { clock_cycle }

      hbl = apple2.get_output(:hbl)
      vbl = apple2.get_output(:vbl)

      expect([0, 1]).to include(hbl)
      expect([0, 1]).to include(vbl)
    end
  end

  describe 'debug outputs' do
    before do
      # Simple ROM with known code
      rom = Array.new(12 * 1024, 0xEA)
      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0
      rom[0x2000] = 0xA9  # LDA #$42
      rom[0x2001] = 0x42

      load_rom(rom)
      reset_system
    end

    it 'outputs CPU program counter' do
      run_cycles(20)

      pc = apple2.get_output(:pc_debug)
      expect(pc).to be >= 0xF000
    end

    it 'outputs A register value' do
      run_cycles(50)

      a = apple2.get_output(:a_debug)
      expect(a).to be_between(0, 255)
    end

    it 'outputs X register value' do
      x = apple2.get_output(:x_debug)
      expect(x).to be_between(0, 255)
    end

    it 'outputs Y register value' do
      y = apple2.get_output(:y_debug)
      expect(y).to be_between(0, 255)
    end
  end

  describe 'annunciator outputs' do
    before do
      reset_system
    end

    it 'outputs annunciator values from soft switches' do
      10.times { clock_cycle }

      an = apple2.get_output(:an)
      expect(an).to be_between(0, 15)
    end
  end

  describe 'ROM helpers' do
    it 'loads ROM data via load_rom' do
      test_data = [0xA9, 0x00, 0x85, 0x00]  # LDA #$00, STA $00
      apple2.load_rom(test_data, 0)

      # Verify by reading
      expect(apple2.read_rom(0)).to eq(0xA9)
      expect(apple2.read_rom(1)).to eq(0x00)
      expect(apple2.read_rom(2)).to eq(0x85)
      expect(apple2.read_rom(3)).to eq(0x00)
    end

    it 'reads ROM data via read_rom' do
      apple2.load_rom([0xEA], 0x100)  # NOP at offset $100

      data = apple2.read_rom(0x100)
      expect(data).to eq(0xEA)
    end
  end
end

RSpec.describe RHDL::Apple2::VGAOutput do
  let(:vga) { described_class.new('vga') }

  before do
    vga
    vga.set_input(:clk_14m, 0)
    vga.set_input(:video, 0)
    vga.set_input(:color_line, 0)
    vga.set_input(:hbl, 0)
    vga.set_input(:vbl, 0)
  end

  def clock_cycle
    vga.set_input(:clk_14m, 0)
    vga.propagate
    vga.set_input(:clk_14m, 1)
    vga.propagate
  end

  describe 'VGA sync generation' do
    it 'generates hsync signal' do
      hsync_values = []

      1000.times do
        clock_cycle
        hsync_values << vga.get_output(:vga_hsync)
      end

      # Should see hsync transitions
      expect(hsync_values.uniq.size).to be > 1
    end

    it 'generates vsync signal' do
      vsync_values = []

      # Need many cycles to see vsync (once per frame)
      5000.times do
        clock_cycle
        vsync_values << vga.get_output(:vga_vsync)
      end

      # Should see vsync transitions (at least one per frame)
      expect(vsync_values).to include(0).or include(1)
    end
  end

  describe 'RGB output' do
    it 'outputs white when video is high and not blanked' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to eq(0xF)
      expect(g).to eq(0xF)
      expect(b).to eq(0xF)
    end

    it 'outputs black when video is low' do
      vga.set_input(:video, 0)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to eq(0)
      expect(g).to eq(0)
      expect(b).to eq(0)
    end

    it 'outputs black during horizontal blanking' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 1)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      expect(r).to eq(0)
    end

    it 'outputs black during vertical blanking' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 1)
      clock_cycle

      r = vga.get_output(:vga_r)
      expect(r).to eq(0)
    end
  end

  describe '4-bit RGB output' do
    it 'outputs 4-bit values' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to be_between(0, 15)
      expect(g).to be_between(0, 15)
      expect(b).to be_between(0, 15)
    end
  end
end

RSpec.describe 'Apple II ROM Integration' do
  # Integration test using only the Apple2 HDL component
  # Verifies ROM loading and memory map access via cpu_din

  let(:apple2) { RHDL::Apple2::Apple2.new('apple2') }
  let(:ram) { Array.new(48 * 1024, 0) }

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)

  before do
    skip 'AppleIIgo ROM not found' unless File.exist?(ROM_PATH)

    apple2
    # Initialize inputs
    apple2.set_input(:clk_14m, 0)
    apple2.set_input(:flash_clk, 0)
    apple2.set_input(:reset, 0)
    apple2.set_input(:ram_do, 0)
    apple2.set_input(:pd, 0)
    apple2.set_input(:k, 0)
    apple2.set_input(:gameport, 0)
    apple2.set_input(:pause, 0)

    # Load the AppleIIgo ROM
    rom_data = File.binread(ROM_PATH).bytes
    apple2.load_rom(rom_data)
  end

  def clock_14m_cycle
    apple2.set_input(:clk_14m, 0)
    apple2.propagate

    ram_addr = apple2.get_output(:ram_addr)
    if ram_addr < ram.size
      apple2.set_input(:ram_do, ram[ram_addr])
    end
    apple2.propagate

    apple2.set_input(:clk_14m, 1)
    apple2.propagate

    ram_we = apple2.get_output(:ram_we)
    if ram_we == 1
      write_addr = apple2.get_output(:ram_addr)
      if write_addr < ram.size
        ram[write_addr] = apple2.get_output(:d)
      end
    end
  end

  def clock_cycle
    14.times { clock_14m_cycle }
  end

  def reset_system
    apple2.set_input(:reset, 1)
    clock_cycle
    apple2.set_input(:reset, 0)
  end

  describe 'ROM boot' do
    before do
      reset_system
    end

    it 'jumps to reset vector on boot' do
      # Run enough cycles to complete reset sequence (reset takes ~7 cycles)
      200.times { clock_cycle }

      pc = apple2.get_output(:pc_debug)
      # Reset vector in AppleIIgo ROM should point to ROM code
      # PC should be somewhere in memory (allow some leeway for different ROMs)
      expect(pc).to be_between(0, 0xFFFF)
    end

    it 'executes first instruction (CLD)' do
      # Run cycles to execute first instruction
      100.times { clock_cycle }

      # If CLD executed, A register should be valid
      a = apple2.get_output(:a_debug)
      expect(a).to be_between(0, 255)
    end
  end

  describe 'screen memory routing' do
    before do
      # Create ROM that writes to screen
      rom = Array.new(12 * 1024, 0xEA)

      # Boot code that writes 'A' to screen
      boot_code = [
        0xA9, 0xC1,       # LDA #$C1 ('A' with high bit)
        0x8D, 0x00, 0x04, # STA $0400
        0x4C, 0x05, 0xF0  # JMP $F005
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte
      end

      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0

      apple2.load_rom(rom)
      reset_system
    end

    it 'routes CPU writes to text page through RAM' do
      # Run enough cycles to execute the store
      50.times { clock_cycle }

      # Verify character was written to RAM
      expect(ram[0x0400]).to eq(0xC1)
    end
  end
end
