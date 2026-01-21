# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/apple2/hdl/apple2_system'

# Integration test: Apple2System - CPU6502 integrated with Apple2
# Uses Apple2System which has CPU6502 and Apple2 as subcomponents
RSpec.describe 'Apple2System Integration' do
  let(:system) { RHDL::Apple2::Apple2System.new('apple2_system') }
  let(:ram) { Array.new(48 * 1024, 0) }  # 48KB RAM

  before do
    # Initialize system inputs
    system.set_input(:clk_14m, 0)
    system.set_input(:flash_clk, 0)
    system.set_input(:reset, 0)
    system.set_input(:ram_do, 0)
    system.set_input(:pd, 0)
    system.set_input(:k, 0)
    system.set_input(:gameport, 0)
    system.set_input(:pause, 0)
  end

  def load_rom(data)
    system.load_rom(data)
  end

  def load_ram(data, start_addr)
    data.each_with_index do |byte, i|
      ram[start_addr + i] = byte if start_addr + i < ram.size
    end
  end

  # Run one 14MHz clock cycle
  def clock_14m_cycle(trace: false)
    @cpu_clock_count ||= 0

    # 14MHz falling edge
    system.set_input(:clk_14m, 0)
    system.propagate

    # Get RAM address and provide data
    ram_addr = system.get_output(:ram_addr)
    if ram_addr < ram.size
      system.set_input(:ram_do, ram[ram_addr])
    end
    system.propagate

    # 14MHz rising edge
    system.set_input(:clk_14m, 1)
    system.propagate

    if trace
      pc = system.get_output(:pc_debug)
      a_reg = system.get_output(:a_debug)
      puts "  14M cycle: PC=0x#{pc.to_s(16).rjust(4,'0')} A=0x#{a_reg.to_s(16).rjust(2,'0')}"
    end

    # Handle RAM writes
    ram_we = system.get_output(:ram_we)
    if ram_we == 1
      write_addr = system.get_output(:ram_addr)
      if write_addr < ram.size
        ram[write_addr] = system.get_output(:d)
      end
    end
  end

  def clock_cycle(trace: false)
    # Run multiple 14MHz cycles for one approximate CPU cycle
    14.times { clock_14m_cycle(trace: trace) }
  end

  def run_cycles(n)
    n.times { clock_cycle }
  end

  def reset_system
    system.set_input(:reset, 1)
    clock_cycle
    system.set_input(:reset, 0)
  end

  describe 'basic integration' do
    it 'system initializes without error' do
      reset_system
      run_cycles(10)
      expect(system.get_output(:pc_debug)).to be_a(Integer)
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
      pc = system.get_output(:pc_debug)
      expect(pc).to be >= 0xF000
    end

    it 'executes boot code and writes to RAM' do
      # Run enough cycles to execute boot code
      # Enable trace for first few cycles
      15.times do |i|
        puts "=== Clock cycle #{i} ===" if i < 12
        clock_cycle(trace: i < 12)
      end
      35.times { clock_cycle }

      puts "Final A=0x#{system.get_output(:a_debug).to_s(16)}"
      puts "ram[0x0400] = 0x#{ram[0x0400].to_s(16)}"
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
      system.set_input(:k, 0xC1)  # 'A' with high bit set

      run_cycles(100)

      # The keyboard value should be stored at $10
      expect(ram[0x10]).to eq(0xC1)
    end
  end
end
