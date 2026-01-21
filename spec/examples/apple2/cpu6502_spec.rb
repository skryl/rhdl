# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/apple2/hdl/cpu6502'

RSpec.describe RHDL::Apple2::CPU6502 do
  let(:cpu) { RHDL::Apple2::CPU6502.new('cpu') }

  # Memory simulation (64KB)
  let(:memory) { Array.new(65536, 0) }

  def set_reset_vector(addr)
    memory[0xFFFC] = addr & 0xFF
    memory[0xFFFD] = (addr >> 8) & 0xFF
  end

  def load_program(program, start_addr)
    program.each_with_index do |byte, i|
      memory[start_addr + i] = byte
    end
  end

  def clock_cycle
    # Falling edge - address is output
    cpu.set_input(:clk, 0)
    cpu.propagate

    # Now read address and provide data
    addr = cpu.get_output(:addr)
    cpu.set_input(:di, memory[addr] || 0)
    cpu.propagate

    # Sample WE and data BEFORE rising edge (they change after edge)
    we = cpu.get_output(:we)
    do_out = cpu.get_output(:do_out)

    # Rising edge - state transitions
    cpu.set_input(:clk, 1)
    cpu.propagate

    # Handle writes using sampled values
    if we == 1
      memory[addr] = do_out
    end
  end

  def run_cycles(n)
    n.times { clock_cycle }
  end

  def reset_cpu
    cpu.set_input(:enable, 1)
    cpu.set_input(:reset, 1)
    cpu.set_input(:nmi_n, 1)
    cpu.set_input(:irq_n, 1)
    cpu.set_input(:so_n, 1)
    clock_cycle
    cpu.set_input(:reset, 0)
  end

  describe 'initialization' do
    before do
      cpu.set_input(:enable, 1)
      cpu.set_input(:reset, 0)
      cpu.set_input(:nmi_n, 1)
      cpu.set_input(:irq_n, 1)
      cpu.set_input(:so_n, 1)
      cpu.set_input(:di, 0)
    end

    it 'creates a CPU instance' do
      expect(cpu).to be_a(RHDL::Apple2::CPU6502)
    end

    it 'has required inputs' do
      expect(cpu.inputs.keys).to include(:clk, :enable, :reset, :nmi_n, :irq_n, :so_n, :di)
    end

    it 'has required outputs' do
      expect(cpu.outputs.keys).to include(:addr, :do_out, :we)
      expect(cpu.outputs.keys).to include(:debug_a, :debug_x, :debug_y, :debug_s, :debug_pc, :debug_opcode)
    end
  end

  describe 'reset behavior' do
    before do
      set_reset_vector(0x0200)
      load_program([0xEA], 0x0200)  # NOP at $0200
      reset_cpu
    end

    it 'reads reset vector after reset' do
      # After reset, CPU should be reading from $FFFC (reset vector)
      # The address should eventually reach the reset vector location
      run_cycles(6)
      # After reset sequence, PC should be at reset vector
      expect(cpu.get_output(:debug_pc)).to eq(0x0200)
    end
  end

  describe 'NOP instruction' do
    before do
      set_reset_vector(0x0200)
      load_program([0xEA, 0xEA, 0xEA], 0x0200)  # Three NOPs
      reset_cpu
      run_cycles(6)  # Complete reset sequence
    end

    it 'executes NOP (2 cycles)' do
      initial_pc = cpu.get_output(:debug_pc)
      run_cycles(2)
      expect(cpu.get_output(:debug_pc)).to eq((initial_pc + 1) & 0xFFFF)
    end
  end

  describe 'LDA immediate' do
    before do
      set_reset_vector(0x0200)
      load_program([0xA9, 0x42], 0x0200)  # LDA #$42
      reset_cpu
      run_cycles(6)  # Complete reset sequence
    end

    it 'loads immediate value into A' do
      run_cycles(2)  # Execute LDA #$42
      expect(cpu.get_output(:debug_a)).to eq(0x42)
    end
  end

  describe 'LDX immediate' do
    before do
      set_reset_vector(0x0200)
      load_program([0xA2, 0x55], 0x0200)  # LDX #$55
      reset_cpu
      run_cycles(6)
    end

    it 'loads immediate value into X' do
      run_cycles(2)
      expect(cpu.get_output(:debug_x)).to eq(0x55)
    end
  end

  describe 'LDY immediate' do
    before do
      set_reset_vector(0x0200)
      load_program([0xA0, 0xAA], 0x0200)  # LDY #$AA
      reset_cpu
      run_cycles(6)
    end

    it 'loads immediate value into Y' do
      run_cycles(2)
      expect(cpu.get_output(:debug_y)).to eq(0xAA)
    end
  end

  describe 'STA zero page' do
    before do
      set_reset_vector(0x0200)
      # LDA #$42; STA $10
      load_program([0xA9, 0x42, 0x85, 0x10], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'stores A to zero page' do
      run_cycles(2)  # LDA #$42
      run_cycles(3)  # STA $10
      expect(memory[0x10]).to eq(0x42)
    end
  end

  describe 'STA absolute' do
    before do
      set_reset_vector(0x0200)
      # LDA #$FF; STA $0300
      load_program([0xA9, 0xFF, 0x8D, 0x00, 0x03], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'stores A to absolute address' do
      run_cycles(2)  # LDA #$FF
      run_cycles(4)  # STA $0300
      expect(memory[0x0300]).to eq(0xFF)
    end
  end

  describe 'ADC immediate' do
    before do
      set_reset_vector(0x0200)
      # CLC; LDA #$10; ADC #$20
      load_program([0x18, 0xA9, 0x10, 0x69, 0x20], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'adds immediate value to A' do
      run_cycles(2)  # CLC
      run_cycles(2)  # LDA #$10
      run_cycles(2)  # ADC #$20
      expect(cpu.get_output(:debug_a)).to eq(0x30)
    end
  end

  describe 'INC zero page' do
    before do
      set_reset_vector(0x0200)
      memory[0x10] = 0x41
      # INC $10
      load_program([0xE6, 0x10], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'increments memory location' do
      run_cycles(5)  # INC $10 (5 cycles for RMW)
      expect(memory[0x10]).to eq(0x42)
    end
  end

  describe 'INX' do
    before do
      set_reset_vector(0x0200)
      # LDX #$FE; INX
      load_program([0xA2, 0xFE, 0xE8], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'increments X' do
      run_cycles(2)  # LDX #$FE
      run_cycles(2)  # INX
      expect(cpu.get_output(:debug_x)).to eq(0xFF)
    end
  end

  describe 'INY' do
    before do
      set_reset_vector(0x0200)
      # LDY #$00; INY
      load_program([0xA0, 0x00, 0xC8], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'increments Y' do
      run_cycles(2)  # LDY #$00
      run_cycles(2)  # INY
      expect(cpu.get_output(:debug_y)).to eq(0x01)
    end
  end

  describe 'DEX' do
    before do
      set_reset_vector(0x0200)
      # LDX #$10; DEX
      load_program([0xA2, 0x10, 0xCA], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'decrements X' do
      run_cycles(2)  # LDX #$10
      run_cycles(2)  # DEX
      expect(cpu.get_output(:debug_x)).to eq(0x0F)
    end
  end

  describe 'DEY' do
    before do
      set_reset_vector(0x0200)
      # LDY #$10; DEY
      load_program([0xA0, 0x10, 0x88], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'decrements Y' do
      run_cycles(2)  # LDY #$10
      run_cycles(2)  # DEY
      expect(cpu.get_output(:debug_y)).to eq(0x0F)
    end
  end

  describe 'JMP absolute' do
    before do
      set_reset_vector(0x0200)
      # JMP $0300; at $0300: NOP
      load_program([0x4C, 0x00, 0x03], 0x0200)
      load_program([0xEA], 0x0300)
      reset_cpu
      run_cycles(6)
    end

    it 'jumps to absolute address' do
      run_cycles(3)  # JMP $0300
      expect(cpu.get_output(:debug_pc)).to eq(0x0300)
    end
  end

  describe 'BNE (branch not taken)' do
    before do
      set_reset_vector(0x0200)
      # LDA #$00; BNE $10 (branch forward 16 bytes - not taken because Z=1)
      load_program([0xA9, 0x00, 0xD0, 0x10], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'does not branch when Z=1' do
      run_cycles(2)  # LDA #$00 (sets Z flag)
      run_cycles(2)  # BNE (not taken, 2 cycles)
      expect(cpu.get_output(:debug_pc)).to eq(0x0204)
    end
  end

  describe 'BNE (branch taken, no page cross)' do
    before do
      set_reset_vector(0x0200)
      # LDA #$01; BNE $02 (branch forward 2 bytes - taken because Z=0)
      load_program([0xA9, 0x01, 0xD0, 0x02, 0xEA, 0xEA, 0xEA], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'branches when Z=0' do
      run_cycles(2)  # LDA #$01 (clears Z flag)
      run_cycles(3)  # BNE (taken, 3 cycles)
      expect(cpu.get_output(:debug_pc)).to eq(0x0206)
    end
  end

  describe 'JSR and RTS' do
    before do
      set_reset_vector(0x0200)
      # JSR $0210; NOP (at $0203)
      # at $0210: LDA #$42; RTS
      load_program([0x20, 0x10, 0x02, 0xEA], 0x0200)
      load_program([0xA9, 0x42, 0x60], 0x0210)
      reset_cpu
      run_cycles(6)
    end

    it 'calls subroutine and returns' do
      run_cycles(6)   # JSR $0210
      expect(cpu.get_output(:debug_pc)).to eq(0x0210)

      run_cycles(2)   # LDA #$42
      expect(cpu.get_output(:debug_a)).to eq(0x42)

      run_cycles(6)   # RTS
      expect(cpu.get_output(:debug_pc)).to eq(0x0203)
    end
  end

  describe 'PHA and PLA' do
    before do
      set_reset_vector(0x0200)
      # LDA #$55; PHA; LDA #$00; PLA
      load_program([0xA9, 0x55, 0x48, 0xA9, 0x00, 0x68], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'pushes and pulls accumulator' do
      run_cycles(2)  # LDA #$55
      expect(cpu.get_output(:debug_a)).to eq(0x55)

      run_cycles(3)  # PHA
      run_cycles(2)  # LDA #$00
      expect(cpu.get_output(:debug_a)).to eq(0x00)

      run_cycles(4)  # PLA
      expect(cpu.get_output(:debug_a)).to eq(0x55)
    end
  end

  describe 'TAX' do
    before do
      set_reset_vector(0x0200)
      # LDA #$77; TAX
      load_program([0xA9, 0x77, 0xAA], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'transfers A to X' do
      run_cycles(2)  # LDA #$77
      run_cycles(2)  # TAX
      expect(cpu.get_output(:debug_x)).to eq(0x77)
    end
  end

  describe 'TXA' do
    before do
      set_reset_vector(0x0200)
      # LDX #$88; TXA
      load_program([0xA2, 0x88, 0x8A], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'transfers X to A' do
      run_cycles(2)  # LDX #$88
      run_cycles(2)  # TXA
      expect(cpu.get_output(:debug_a)).to eq(0x88)
    end
  end

  describe 'TAY' do
    before do
      set_reset_vector(0x0200)
      # LDA #$99; TAY
      load_program([0xA9, 0x99, 0xA8], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'transfers A to Y' do
      run_cycles(2)  # LDA #$99
      run_cycles(2)  # TAY
      expect(cpu.get_output(:debug_y)).to eq(0x99)
    end
  end

  describe 'TYA' do
    before do
      set_reset_vector(0x0200)
      # LDY #$AA; TYA
      load_program([0xA0, 0xAA, 0x98], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'transfers Y to A' do
      run_cycles(2)  # LDY #$AA
      run_cycles(2)  # TYA
      expect(cpu.get_output(:debug_a)).to eq(0xAA)
    end
  end

  describe 'TSX' do
    before do
      set_reset_vector(0x0200)
      # TSX (stack pointer should be $FF after reset)
      load_program([0xBA], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'transfers S to X' do
      run_cycles(2)  # TSX
      expect(cpu.get_output(:debug_x)).to eq(0xFF)
    end
  end

  describe 'TXS' do
    before do
      set_reset_vector(0x0200)
      # LDX #$80; TXS
      load_program([0xA2, 0x80, 0x9A], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'transfers X to S' do
      run_cycles(2)  # LDX #$80
      run_cycles(2)  # TXS
      expect(cpu.get_output(:debug_s)).to eq(0x80)
    end
  end

  describe 'AND immediate' do
    before do
      set_reset_vector(0x0200)
      # LDA #$FF; AND #$0F
      load_program([0xA9, 0xFF, 0x29, 0x0F], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'ANDs immediate value with A' do
      run_cycles(2)  # LDA #$FF
      run_cycles(2)  # AND #$0F
      expect(cpu.get_output(:debug_a)).to eq(0x0F)
    end
  end

  describe 'ORA immediate' do
    before do
      set_reset_vector(0x0200)
      # LDA #$F0; ORA #$0F
      load_program([0xA9, 0xF0, 0x09, 0x0F], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'ORs immediate value with A' do
      run_cycles(2)  # LDA #$F0
      run_cycles(2)  # ORA #$0F
      expect(cpu.get_output(:debug_a)).to eq(0xFF)
    end
  end

  describe 'EOR immediate' do
    before do
      set_reset_vector(0x0200)
      # LDA #$FF; EOR #$AA
      load_program([0xA9, 0xFF, 0x49, 0xAA], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'XORs immediate value with A' do
      run_cycles(2)  # LDA #$FF
      run_cycles(2)  # EOR #$AA
      expect(cpu.get_output(:debug_a)).to eq(0x55)
    end
  end

  describe 'ASL accumulator' do
    before do
      set_reset_vector(0x0200)
      # LDA #$40; ASL
      load_program([0xA9, 0x40, 0x0A], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'shifts A left' do
      run_cycles(2)  # LDA #$40
      run_cycles(2)  # ASL A
      expect(cpu.get_output(:debug_a)).to eq(0x80)
    end
  end

  describe 'LSR accumulator' do
    before do
      set_reset_vector(0x0200)
      # LDA #$80; LSR
      load_program([0xA9, 0x80, 0x4A], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'shifts A right' do
      run_cycles(2)  # LDA #$80
      run_cycles(2)  # LSR A
      expect(cpu.get_output(:debug_a)).to eq(0x40)
    end
  end

  describe 'ROL accumulator' do
    before do
      set_reset_vector(0x0200)
      # SEC; LDA #$40; ROL
      load_program([0x38, 0xA9, 0x40, 0x2A], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'rotates A left through carry' do
      run_cycles(2)  # SEC
      run_cycles(2)  # LDA #$40
      run_cycles(2)  # ROL A
      expect(cpu.get_output(:debug_a)).to eq(0x81)  # $40 << 1 | C = $81
    end
  end

  describe 'ROR accumulator' do
    before do
      set_reset_vector(0x0200)
      # SEC; LDA #$02; ROR
      load_program([0x38, 0xA9, 0x02, 0x6A], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'rotates A right through carry' do
      run_cycles(2)  # SEC
      run_cycles(2)  # LDA #$02
      run_cycles(2)  # ROR A
      expect(cpu.get_output(:debug_a)).to eq(0x81)  # C << 7 | $02 >> 1 = $81
    end
  end

  describe 'CMP immediate' do
    before do
      set_reset_vector(0x0200)
      # LDA #$50; CMP #$30
      load_program([0xA9, 0x50, 0xC9, 0x30], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'compares A with immediate (A > M sets C)' do
      run_cycles(2)  # LDA #$50
      run_cycles(2)  # CMP #$30
      # A ($50) > M ($30), so C=1, Z=0, N=0
      # We can't easily check flags, but we can verify A is unchanged
      expect(cpu.get_output(:debug_a)).to eq(0x50)
    end
  end

  describe 'LDA zero page, X' do
    before do
      set_reset_vector(0x0200)
      memory[0x15] = 0x42  # Value at $10 + $05 = $15
      # LDX #$05; LDA $10,X
      load_program([0xA2, 0x05, 0xB5, 0x10], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'loads from zero page indexed by X' do
      run_cycles(2)  # LDX #$05
      run_cycles(4)  # LDA $10,X
      expect(cpu.get_output(:debug_a)).to eq(0x42)
    end
  end

  describe 'SBC immediate' do
    before do
      set_reset_vector(0x0200)
      # SEC; LDA #$50; SBC #$20
      load_program([0x38, 0xA9, 0x50, 0xE9, 0x20], 0x0200)
      reset_cpu
      run_cycles(6)
    end

    it 'subtracts immediate from A' do
      run_cycles(2)  # SEC
      run_cycles(2)  # LDA #$50
      run_cycles(2)  # SBC #$20
      expect(cpu.get_output(:debug_a)).to eq(0x30)
    end
  end
end
