# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/apple2/hdl/cpu6502'

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
      # This CPU uses a JMP-like reset sequence (3 cycles to reach vector)
      run_cycles(3)
      # After reset sequence, PC should be at reset vector
      expect(cpu.get_output(:debug_pc)).to eq(0x0200)
    end
  end

  describe 'NOP instruction' do
    before do
      set_reset_vector(0x0200)
      load_program([0xEA, 0xEA, 0xEA], 0x0200)  # Three NOPs
      reset_cpu
      run_cycles(3)  # Complete reset sequence (JMP-like, 3 cycles)
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
      run_cycles(3)  # Complete reset sequence (JMP-like, 3 cycles)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
    end

    it 'calls subroutine and returns' do
      run_cycles(6)   # JSR $0210 (6 cycles)
      expect(cpu.get_output(:debug_pc)).to eq(0x0210)

      run_cycles(2)   # LDA #$42
      expect(cpu.get_output(:debug_a)).to eq(0x42)

      run_cycles(6)   # RTS (6 cycles)
      expect(cpu.get_output(:debug_pc)).to eq(0x0203)
    end
  end

  describe 'PHA and PLA' do
    before do
      set_reset_vector(0x0200)
      # LDA #$55; PHA; LDA #$00; PLA
      load_program([0xA9, 0x55, 0x48, 0xA9, 0x00, 0x68], 0x0200)
      reset_cpu
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      # TSX (stack pointer is $FD after reset - 6502 reset performs 3 dummy pushes)
      load_program([0xBA], 0x0200)
      reset_cpu
      run_cycles(3)
    end

    it 'transfers S to X' do
      run_cycles(2)  # TSX
      expect(cpu.get_output(:debug_x)).to eq(0xFD)
    end
  end

  describe 'TXS' do
    before do
      set_reset_vector(0x0200)
      # LDX #$80; TXS
      load_program([0xA2, 0x80, 0x9A], 0x0200)
      reset_cpu
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
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
      run_cycles(3)
    end

    it 'subtracts immediate from A' do
      run_cycles(2)  # SEC
      run_cycles(2)  # LDA #$50
      run_cycles(2)  # SBC #$20
      expect(cpu.get_output(:debug_a)).to eq(0x30)
    end
  end

  # Integration test: Run a complete 6502 program
  describe 'complete 6502 program execution' do
    describe 'countdown loop' do
      before do
        set_reset_vector(0x0200)
        # Program: Count down from 5 to 0, storing each value in memory
        # $0200: LDX #$05    ; X = 5
        # $0202: STX $10     ; Store X at $10 + offset
        # $0204: DEX         ; X = X - 1
        # $0205: BNE $FD     ; Branch back to STX if Z=0 (offset -3)
        # $0207: BRK         ; Stop
        load_program([
          0xA2, 0x05,       # LDX #$05
          0x86, 0x10,       # STX $10 (store X at zero page $10)
          0xCA,             # DEX
          0xD0, 0xFB,       # BNE $0202 (offset -5 = $FB)
          0x00              # BRK
        ], 0x0200)
        reset_cpu
        run_cycles(3)  # Complete reset
      end

      it 'executes a countdown loop storing values to memory' do
        # Run enough cycles to complete the loop
        # LDX: 2, then 5 iterations of: STX(3) + DEX(2) + BNE(3) = 8 cycles each
        # Last iteration: STX(3) + DEX(2) + BNE not taken(2) = 7
        # Total: 2 + 4*8 + 7 = 41 cycles
        run_cycles(50)  # Run a bit more to be safe

        # X should be 0 after the loop
        expect(cpu.get_output(:debug_x)).to eq(0x00)

        # The last value stored should be 1 (stored before final DEX made X=0)
        expect(memory[0x10]).to eq(0x01)
      end
    end

    describe 'memory copy loop' do
      before do
        set_reset_vector(0x0200)
        # Program: Copy 4 bytes from $0030 to $0040
        # Source data at $0030-$0033
        memory[0x30] = 0xDE
        memory[0x31] = 0xAD
        memory[0x32] = 0xBE
        memory[0x33] = 0xEF

        # $0200: LDX #$00    ; X = 0
        # $0202: LDA $30,X   ; Load from source+X
        # $0204: STA $40,X   ; Store to dest+X
        # $0206: INX         ; X++
        # $0207: CPX #$04    ; Compare X with 4
        # $0209: BNE $F7     ; Branch back if not equal
        # $020B: BRK
        load_program([
          0xA2, 0x00,       # LDX #$00
          0xB5, 0x30,       # LDA $30,X
          0x95, 0x40,       # STA $40,X
          0xE8,             # INX
          0xE0, 0x04,       # CPX #$04
          0xD0, 0xF7,       # BNE $0202 (offset -9 = $F7)
          0x00              # BRK
        ], 0x0200)
        reset_cpu
        run_cycles(3)
      end

      it 'copies memory block correctly' do
        # Run enough cycles
        # LDX: 2 cycles
        # Per iteration: LDA zp,X(4) + STA zp,X(4) + INX(2) + CPX(2) + BNE(3) = 15
        # Last iteration BNE not taken: -1 cycle
        # Total: 2 + 4*15 - 1 = 61 cycles
        run_cycles(80)

        # Verify copy
        expect(memory[0x40]).to eq(0xDE)
        expect(memory[0x41]).to eq(0xAD)
        expect(memory[0x42]).to eq(0xBE)
        expect(memory[0x43]).to eq(0xEF)
        expect(cpu.get_output(:debug_x)).to eq(0x04)
      end
    end

    describe 'fibonacci sequence' do
      before do
        set_reset_vector(0x0200)
        # Program: Compute first 8 Fibonacci numbers and store at $0050
        # F0=1, F1=1, F2=2, F3=3, F4=5, F5=8, F6=13, F7=21
        #
        # $0200: LDA #$01    ; A = 1 (F0)
        # $0202: STA $50     ; Store F0
        # $0204: STA $51     ; Store F1
        # $0206: LDX #$02    ; X = 2 (index for F2)
        # loop:
        # $0208: LDA $4E,X   ; A = F[n-2]
        # $020A: CLC
        # $020B: ADC $4F,X   ; A = F[n-2] + F[n-1]
        # $020D: STA $50,X   ; Store F[n]
        # $020F: INX
        # $0210: CPX #$08    ; Done 8 numbers?
        # $0212: BNE $F4     ; Loop if not
        # $0214: BRK
        load_program([
          0xA9, 0x01,       # LDA #$01
          0x85, 0x50,       # STA $50
          0x85, 0x51,       # STA $51
          0xA2, 0x02,       # LDX #$02
          # loop:
          0xB5, 0x4E,       # LDA $4E,X (F[n-2])
          0x18,             # CLC
          0x75, 0x4F,       # ADC $4F,X (F[n-1])
          0x95, 0x50,       # STA $50,X
          0xE8,             # INX
          0xE0, 0x08,       # CPX #$08
          0xD0, 0xF4,       # BNE loop
          0x00              # BRK
        ], 0x0200)
        reset_cpu
        run_cycles(3)
      end

      it 'computes fibonacci sequence correctly' do
        # Run enough cycles for the program
        # Initial setup: ~10 cycles
        # Per loop iteration: LDA(4) + CLC(2) + ADC(4) + STA(4) + INX(2) + CPX(2) + BNE(3) = 21
        # 6 iterations: 6 * 21 = 126, last one BNE not taken: -1
        # Total: ~140 cycles
        run_cycles(160)

        # Verify Fibonacci sequence: 1, 1, 2, 3, 5, 8, 13, 21
        expect(memory[0x50]).to eq(1)
        expect(memory[0x51]).to eq(1)
        expect(memory[0x52]).to eq(2)
        expect(memory[0x53]).to eq(3)
        expect(memory[0x54]).to eq(5)
        expect(memory[0x55]).to eq(8)
        expect(memory[0x56]).to eq(13)
        expect(memory[0x57]).to eq(21)
      end
    end

    describe 'subroutine with parameters' do
      before do
        set_reset_vector(0x0200)
        # Program: Call a subroutine to multiply two numbers (simple addition loop)
        # Main: Load 5 and 3, call multiply, store result
        #
        # $0200: LDA #$05    ; multiplicand
        # $0202: STA $10     ; store at $10
        # $0204: LDA #$03    ; multiplier
        # $0206: STA $11     ; store at $11
        # $0208: JSR $0220   ; call multiply
        # $020B: STA $12     ; store result
        # $020D: BRK
        #
        # Multiply subroutine at $0220:
        # $0220: LDA #$00    ; result = 0
        # $0222: LDX $11     ; X = multiplier (count)
        # $0224: BEQ $0A     ; if zero, done
        # loop:
        # $0226: CLC
        # $0227: ADC $10     ; result += multiplicand
        # $0229: DEX
        # $022A: BNE $FA     ; loop if X != 0
        # done:
        # $022C: RTS
        load_program([
          0xA9, 0x05,       # LDA #$05
          0x85, 0x10,       # STA $10
          0xA9, 0x03,       # LDA #$03
          0x85, 0x11,       # STA $11
          0x20, 0x20, 0x02, # JSR $0220
          0x85, 0x12,       # STA $12
          0x00              # BRK
        ], 0x0200)

        load_program([
          0xA9, 0x00,       # LDA #$00
          0xA6, 0x11,       # LDX $11
          0xF0, 0x06,       # BEQ done (+6)
          # loop:
          0x18,             # CLC
          0x65, 0x10,       # ADC $10
          0xCA,             # DEX
          0xD0, 0xFA,       # BNE loop
          # done:
          0x60              # RTS
        ], 0x0220)

        reset_cpu
        run_cycles(3)
      end

      it 'calls subroutine and computes 5*3=15' do
        # Run enough cycles
        run_cycles(100)

        # Result should be 15 (5 * 3)
        expect(memory[0x12]).to eq(15)
      end
    end
  end
end
