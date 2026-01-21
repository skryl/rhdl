# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/apple2/hdl/apple2'
require_relative '../../../examples/apple2/hdl/cpu6502'

# Integration test: CPU6502 + Apple2 - manually connected
# Based on reference design: CPU uses Q3 clock, enable = not pre_phi0
RSpec.describe 'CPU6502 + Apple2 Integration' do
  let(:cpu) { RHDL::Apple2::CPU6502.new('cpu') }
  let(:apple2) { RHDL::Apple2::Apple2.new('apple2') }
  let(:ram) { Array.new(48 * 1024, 0) }  # 48KB RAM

  before do
    # Initialize CPU inputs
    cpu.set_input(:clk, 0)
    cpu.set_input(:enable, 1)
    cpu.set_input(:reset, 0)
    cpu.set_input(:nmi_n, 1)
    cpu.set_input(:irq_n, 1)
    cpu.set_input(:so_n, 1)
    cpu.set_input(:di, 0)

    # Initialize Apple2 inputs
    apple2.set_input(:clk_14m, 0)
    apple2.set_input(:flash_clk, 0)
    apple2.set_input(:reset, 0)
    apple2.set_input(:ram_do, 0)
    apple2.set_input(:pd, 0)
    apple2.set_input(:k, 0)
    apple2.set_input(:gameport, 0)
    apple2.set_input(:pause, 0)
    apple2.set_input(:cpu_addr, 0)
    apple2.set_input(:cpu_we, 0)
    apple2.set_input(:cpu_dout, 0)
    apple2.set_input(:cpu_pc, 0)
    apple2.set_input(:cpu_opcode, 0)
  end

  def load_rom(data)
    apple2.load_rom(data)
  end

  def load_ram(data, start_addr)
    data.each_with_index do |byte, i|
      ram[start_addr + i] = byte if start_addr + i < ram.size
    end
  end

  # Track previous Q3 for edge detection
  attr_accessor :prev_q3

  # Run one 14MHz clock cycle
  def clock_14m_cycle(trace: false)
    @prev_q3 ||= 0
    @cpu_clock_count ||= 0

    # Update Apple2 with CPU outputs
    apple2.set_input(:cpu_addr, cpu.get_output(:addr))
    apple2.set_input(:cpu_we, cpu.get_output(:we))
    apple2.set_input(:cpu_dout, cpu.get_output(:do_out))
    apple2.set_input(:cpu_pc, cpu.get_output(:debug_pc))
    apple2.set_input(:cpu_opcode, cpu.get_output(:debug_opcode))

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

    # Get timing signals
    q3 = apple2.get_output(:clk_2m)
    pre_phi0 = apple2.get_output(:pre_phase_zero)

    # CPU enable: not pre_phi0 (matches reference)
    cpu.set_input(:enable, pre_phi0 == 0 ? 1 : 0)

    # Get CPU data from Apple2
    cpu_din = apple2.get_output(:cpu_din)
    cpu.set_input(:di, cpu_din)

    # Clock CPU on rising edge of Q3
    if @prev_q3 == 0 && q3 == 1
      enable = pre_phi0 == 0 ? 1 : 0
      if trace
        pc = cpu.get_output(:debug_pc)
        addr = cpu.get_output(:addr)
        a_reg = cpu.get_output(:debug_a)
        puts "  CPU_CLK #{@cpu_clock_count}: PC=0x#{pc.to_s(16).rjust(4,'0')} addr=0x#{addr.to_s(16).rjust(4,'0')} " \
             "A=0x#{a_reg.to_s(16).rjust(2,'0')} di=0x#{cpu_din.to_s(16).rjust(2,'0')} en=#{enable} pre_phi0=#{pre_phi0}"
      end

      cpu.set_input(:clk, 0)
      cpu.propagate
      cpu.set_input(:clk, 1)
      cpu.propagate
      @cpu_clock_count += 1
    end
    @prev_q3 = q3

    # Handle RAM writes
    ram_we = apple2.get_output(:ram_we)
    if ram_we == 1
      write_addr = apple2.get_output(:ram_addr)
      if write_addr < ram.size
        ram[write_addr] = apple2.get_output(:d)
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
    @prev_q3 = 0
    cpu.set_input(:reset, 1)
    apple2.set_input(:reset, 1)
    clock_cycle
    cpu.set_input(:reset, 0)
    apple2.set_input(:reset, 0)
  end

  describe 'basic integration' do
    it 'connects CPU to Apple2' do
      reset_system
      run_cycles(10)
      expect(cpu.get_output(:addr)).to be_a(Integer)
      expect(apple2.get_output(:cpu_din)).to be_a(Integer)
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
      pc = cpu.get_output(:debug_pc)
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

      puts "Final A=0x#{cpu.get_output(:debug_a).to_s(16)}"
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
      apple2.set_input(:k, 0xC1)  # 'A' with high bit set

      run_cycles(100)

      # The keyboard value should be stored at $10
      expect(ram[0x10]).to eq(0xC1)
    end
  end
end
