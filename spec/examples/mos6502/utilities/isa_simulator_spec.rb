# frozen_string_literal: true

require 'rspec'
require_relative '../../../../lib/rhdl'
require_relative '../../../../examples/mos6502/utilities/isa_simulator'
require_relative '../../../../examples/mos6502/utilities/assembler'

RSpec.describe MOS6502::ISASimulator do
  let(:sim) { MOS6502::ISASimulator.new }
  let(:asm) { MOS6502::Assembler.new }

  def assemble_and_load(source, addr = 0x8000)
    bytes = asm.assemble(source, addr)
    sim.load_program(bytes, addr)
    sim.reset
    bytes
  end

  describe 'initialization' do
    it 'initializes with default values' do
      expect(sim.a).to eq(0)
      expect(sim.x).to eq(0)
      expect(sim.y).to eq(0)
      expect(sim.sp).to eq(0xFD)
      expect(sim.halted?).to be false
    end

    it 'has interrupt flag set after reset' do
      expect(sim.flag_i).to eq(1)
    end
  end

  describe 'load instructions' do
    describe 'LDA' do
      it 'LDA immediate' do
        assemble_and_load('LDA #$42')
        sim.step
        expect(sim.a).to eq(0x42)
      end

      it 'LDA zero page' do
        sim.write(0x10, 0x55)
        assemble_and_load('LDA $10')
        sim.step
        expect(sim.a).to eq(0x55)
      end

      it 'LDA zero page,X' do
        sim.write(0x15, 0x77)
        assemble_and_load(<<~'ASM')
          LDX #$05
          LDA $10,X
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0x77)
      end

      it 'LDA absolute' do
        sim.write(0x1234, 0x88)
        assemble_and_load('LDA $1234')
        sim.step
        expect(sim.a).to eq(0x88)
      end

      it 'LDA absolute,X' do
        sim.write(0x1239, 0x99)
        assemble_and_load(<<~'ASM')
          LDX #$05
          LDA $1234,X
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0x99)
      end

      it 'LDA absolute,Y' do
        sim.write(0x123A, 0xAA)
        assemble_and_load(<<~'ASM')
          LDY #$06
          LDA $1234,Y
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0xAA)
      end

      it 'LDA (indirect,X)' do
        sim.write(0x15, 0x00)
        sim.write(0x16, 0x20)
        sim.write(0x2000, 0xBB)
        assemble_and_load(<<~'ASM')
          LDX #$05
          LDA ($10,X)
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0xBB)
      end

      it 'LDA (indirect),Y' do
        sim.write(0x10, 0x00)
        sim.write(0x11, 0x20)
        sim.write(0x2005, 0xCC)
        assemble_and_load(<<~'ASM')
          LDY #$05
          LDA ($10),Y
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0xCC)
      end

      it 'sets Z flag when loading zero' do
        assemble_and_load('LDA #$00')
        sim.step
        expect(sim.flag_z).to eq(1)
      end

      it 'sets N flag when loading negative' do
        assemble_and_load('LDA #$80')
        sim.step
        expect(sim.flag_n).to eq(1)
      end
    end

    describe 'LDX' do
      it 'LDX immediate' do
        assemble_and_load('LDX #$42')
        sim.step
        expect(sim.x).to eq(0x42)
      end

      it 'LDX zero page' do
        sim.write(0x10, 0x55)
        assemble_and_load('LDX $10')
        sim.step
        expect(sim.x).to eq(0x55)
      end

      it 'LDX zero page,Y' do
        sim.write(0x15, 0x77)
        assemble_and_load(<<~'ASM')
          LDY #$05
          LDX $10,Y
        ASM
        2.times { sim.step }
        expect(sim.x).to eq(0x77)
      end
    end

    describe 'LDY' do
      it 'LDY immediate' do
        assemble_and_load('LDY #$42')
        sim.step
        expect(sim.y).to eq(0x42)
      end

      it 'LDY zero page' do
        sim.write(0x10, 0x55)
        assemble_and_load('LDY $10')
        sim.step
        expect(sim.y).to eq(0x55)
      end
    end
  end

  describe 'store instructions' do
    describe 'STA' do
      it 'STA zero page' do
        assemble_and_load(<<~'ASM')
          LDA #$42
          STA $10
        ASM
        2.times { sim.step }
        expect(sim.read(0x10)).to eq(0x42)
      end

      it 'STA absolute' do
        assemble_and_load(<<~'ASM')
          LDA #$55
          STA $1234
        ASM
        2.times { sim.step }
        expect(sim.read(0x1234)).to eq(0x55)
      end
    end

    describe 'STX' do
      it 'STX zero page' do
        assemble_and_load(<<~'ASM')
          LDX #$42
          STX $10
        ASM
        2.times { sim.step }
        expect(sim.read(0x10)).to eq(0x42)
      end
    end

    describe 'STY' do
      it 'STY zero page' do
        assemble_and_load(<<~'ASM')
          LDY #$42
          STY $10
        ASM
        2.times { sim.step }
        expect(sim.read(0x10)).to eq(0x42)
      end
    end
  end

  describe 'transfer instructions' do
    it 'TAX' do
      assemble_and_load(<<~'ASM')
        LDA #$42
        TAX
      ASM
      2.times { sim.step }
      expect(sim.x).to eq(0x42)
    end

    it 'TXA' do
      assemble_and_load(<<~'ASM')
        LDX #$42
        TXA
      ASM
      2.times { sim.step }
      expect(sim.a).to eq(0x42)
    end

    it 'TAY' do
      assemble_and_load(<<~'ASM')
        LDA #$42
        TAY
      ASM
      2.times { sim.step }
      expect(sim.y).to eq(0x42)
    end

    it 'TYA' do
      assemble_and_load(<<~'ASM')
        LDY #$42
        TYA
      ASM
      2.times { sim.step }
      expect(sim.a).to eq(0x42)
    end

    it 'TSX' do
      assemble_and_load('TSX')
      sim.step
      expect(sim.x).to eq(0xFD)  # Initial SP value
    end

    it 'TXS' do
      assemble_and_load(<<~'ASM')
        LDX #$FF
        TXS
      ASM
      2.times { sim.step }
      expect(sim.sp).to eq(0xFF)
    end
  end

  describe 'arithmetic instructions' do
    describe 'ADC' do
      it 'adds without carry' do
        assemble_and_load(<<~'ASM')
          CLC
          LDA #$10
          ADC #$20
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0x30)
        expect(sim.flag_c).to eq(0)
      end

      it 'adds with carry in' do
        assemble_and_load(<<~'ASM')
          SEC
          LDA #$10
          ADC #$20
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0x31)
      end

      it 'sets carry on overflow' do
        assemble_and_load(<<~'ASM')
          CLC
          LDA #$FF
          ADC #$01
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0x00)
        expect(sim.flag_c).to eq(1)
        expect(sim.flag_z).to eq(1)
      end

      it 'sets overflow flag correctly' do
        assemble_and_load(<<~'ASM')
          CLC
          LDA #$7F
          ADC #$01
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0x80)
        expect(sim.flag_v).to eq(1)
        expect(sim.flag_n).to eq(1)
      end
    end

    describe 'SBC' do
      it 'subtracts with borrow' do
        assemble_and_load(<<~'ASM')
          SEC
          LDA #$30
          SBC #$10
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0x20)
        expect(sim.flag_c).to eq(1)
      end

      it 'subtracts with borrow in' do
        assemble_and_load(<<~'ASM')
          CLC
          LDA #$30
          SBC #$10
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0x1F)
      end

      it 'clears carry on underflow' do
        assemble_and_load(<<~'ASM')
          SEC
          LDA #$00
          SBC #$01
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0xFF)
        expect(sim.flag_c).to eq(0)
      end
    end
  end

  describe 'logical instructions' do
    describe 'AND' do
      it 'performs logical AND' do
        assemble_and_load(<<~'ASM')
          LDA #$FF
          AND #$0F
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0x0F)
      end
    end

    describe 'ORA' do
      it 'performs logical OR' do
        assemble_and_load(<<~'ASM')
          LDA #$F0
          ORA #$0F
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0xFF)
      end
    end

    describe 'EOR' do
      it 'performs logical XOR' do
        assemble_and_load(<<~'ASM')
          LDA #$FF
          EOR #$0F
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0xF0)
      end
    end
  end

  describe 'compare instructions' do
    describe 'CMP' do
      it 'sets carry when A >= M' do
        assemble_and_load(<<~'ASM')
          LDA #$50
          CMP #$40
        ASM
        2.times { sim.step }
        expect(sim.flag_c).to eq(1)
        expect(sim.flag_z).to eq(0)
      end

      it 'sets zero when A == M' do
        assemble_and_load(<<~'ASM')
          LDA #$50
          CMP #$50
        ASM
        2.times { sim.step }
        expect(sim.flag_c).to eq(1)
        expect(sim.flag_z).to eq(1)
      end

      it 'clears carry when A < M' do
        assemble_and_load(<<~'ASM')
          LDA #$40
          CMP #$50
        ASM
        2.times { sim.step }
        expect(sim.flag_c).to eq(0)
      end
    end

    describe 'CPX' do
      it 'compares X register' do
        assemble_and_load(<<~'ASM')
          LDX #$50
          CPX #$50
        ASM
        2.times { sim.step }
        expect(sim.flag_z).to eq(1)
        expect(sim.flag_c).to eq(1)
      end
    end

    describe 'CPY' do
      it 'compares Y register' do
        assemble_and_load(<<~'ASM')
          LDY #$50
          CPY #$50
        ASM
        2.times { sim.step }
        expect(sim.flag_z).to eq(1)
        expect(sim.flag_c).to eq(1)
      end
    end
  end

  describe 'increment/decrement instructions' do
    describe 'INX' do
      it 'increments X' do
        assemble_and_load(<<~'ASM')
          LDX #$10
          INX
        ASM
        2.times { sim.step }
        expect(sim.x).to eq(0x11)
      end

      it 'wraps from FF to 00' do
        assemble_and_load(<<~'ASM')
          LDX #$FF
          INX
        ASM
        2.times { sim.step }
        expect(sim.x).to eq(0x00)
        expect(sim.flag_z).to eq(1)
      end
    end

    describe 'DEX' do
      it 'decrements X' do
        assemble_and_load(<<~'ASM')
          LDX #$10
          DEX
        ASM
        2.times { sim.step }
        expect(sim.x).to eq(0x0F)
      end

      it 'wraps from 00 to FF' do
        assemble_and_load(<<~'ASM')
          LDX #$00
          DEX
        ASM
        2.times { sim.step }
        expect(sim.x).to eq(0xFF)
        expect(sim.flag_n).to eq(1)
      end
    end

    describe 'INY' do
      it 'increments Y' do
        assemble_and_load(<<~'ASM')
          LDY #$10
          INY
        ASM
        2.times { sim.step }
        expect(sim.y).to eq(0x11)
      end
    end

    describe 'DEY' do
      it 'decrements Y' do
        assemble_and_load(<<~'ASM')
          LDY #$10
          DEY
        ASM
        2.times { sim.step }
        expect(sim.y).to eq(0x0F)
      end
    end

    describe 'INC' do
      it 'increments memory' do
        sim.write(0x10, 0x42)
        assemble_and_load('INC $10')
        sim.step
        expect(sim.read(0x10)).to eq(0x43)
      end
    end

    describe 'DEC' do
      it 'decrements memory' do
        sim.write(0x10, 0x42)
        assemble_and_load('DEC $10')
        sim.step
        expect(sim.read(0x10)).to eq(0x41)
      end
    end
  end

  describe 'shift/rotate instructions' do
    describe 'ASL' do
      it 'shifts accumulator left' do
        assemble_and_load(<<~'ASM')
          LDA #$55
          ASL A
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0xAA)
        expect(sim.flag_c).to eq(0)
      end

      it 'sets carry from bit 7' do
        assemble_and_load(<<~'ASM')
          LDA #$80
          ASL A
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0x00)
        expect(sim.flag_c).to eq(1)
        expect(sim.flag_z).to eq(1)
      end
    end

    describe 'LSR' do
      it 'shifts accumulator right' do
        assemble_and_load(<<~'ASM')
          LDA #$AA
          LSR A
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0x55)
        expect(sim.flag_c).to eq(0)
      end

      it 'sets carry from bit 0' do
        assemble_and_load(<<~'ASM')
          LDA #$01
          LSR A
        ASM
        2.times { sim.step }
        expect(sim.a).to eq(0x00)
        expect(sim.flag_c).to eq(1)
        expect(sim.flag_z).to eq(1)
      end
    end

    describe 'ROL' do
      it 'rotates left through carry' do
        assemble_and_load(<<~'ASM')
          SEC
          LDA #$55
          ROL A
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0xAB)
        expect(sim.flag_c).to eq(0)
      end
    end

    describe 'ROR' do
      it 'rotates right through carry' do
        assemble_and_load(<<~'ASM')
          SEC
          LDA #$AA
          ROR A
        ASM
        3.times { sim.step }
        expect(sim.a).to eq(0xD5)
        expect(sim.flag_c).to eq(0)
      end
    end
  end

  describe 'branch instructions' do
    it 'BEQ branches when zero' do
      assemble_and_load(<<~'ASM')
        LDA #$00
        BEQ skip
        LDA #$FF
      skip:
        NOP
      ASM
      3.times { sim.step }
      expect(sim.a).to eq(0x00)
    end

    it 'BNE branches when not zero' do
      assemble_and_load(<<~'ASM')
        LDA #$01
        BNE skip
        LDA #$FF
      skip:
        NOP
      ASM
      3.times { sim.step }
      expect(sim.a).to eq(0x01)
    end

    it 'BCS branches when carry set' do
      assemble_and_load(<<~'ASM')
        SEC
        BCS skip
        LDA #$FF
      skip:
        NOP
      ASM
      3.times { sim.step }
      expect(sim.a).to eq(0x00)
    end

    it 'BCC branches when carry clear' do
      assemble_and_load(<<~'ASM')
        CLC
        BCC skip
        LDA #$FF
      skip:
        NOP
      ASM
      3.times { sim.step }
      expect(sim.a).to eq(0x00)
    end

    it 'BMI branches when negative' do
      assemble_and_load(<<~'ASM')
        LDA #$80
        BMI skip
        LDA #$FF
      skip:
        NOP
      ASM
      3.times { sim.step }
      expect(sim.a).to eq(0x80)
    end

    it 'BPL branches when positive' do
      assemble_and_load(<<~'ASM')
        LDA #$01
        BPL skip
        LDA #$FF
      skip:
        NOP
      ASM
      3.times { sim.step }
      expect(sim.a).to eq(0x01)
    end
  end

  describe 'jump instructions' do
    it 'JMP absolute' do
      assemble_and_load(<<~'ASM')
        JMP skip
        LDA #$FF
      skip:
        LDA #$42
      ASM
      2.times { sim.step }
      expect(sim.a).to eq(0x42)
    end

    it 'JSR and RTS' do
      assemble_and_load(<<~'ASM')
        JSR sub
        LDA #$42
        JMP done
      sub:
        LDX #$FF
        RTS
      done:
        NOP
      ASM
      5.times { sim.step }
      expect(sim.x).to eq(0xFF)
      expect(sim.a).to eq(0x42)
    end
  end

  describe 'stack instructions' do
    it 'PHA and PLA' do
      assemble_and_load(<<~'ASM')
        LDA #$42
        PHA
        LDA #$00
        PLA
      ASM
      4.times { sim.step }
      expect(sim.a).to eq(0x42)
    end

    it 'PHP and PLP' do
      assemble_and_load(<<~'ASM')
        SEC
        PHP
        CLC
        PLP
      ASM
      4.times { sim.step }
      expect(sim.flag_c).to eq(1)
    end
  end

  describe 'flag instructions' do
    it 'CLC clears carry' do
      assemble_and_load(<<~'ASM')
        SEC
        CLC
      ASM
      2.times { sim.step }
      expect(sim.flag_c).to eq(0)
    end

    it 'SEC sets carry' do
      assemble_and_load(<<~'ASM')
        CLC
        SEC
      ASM
      2.times { sim.step }
      expect(sim.flag_c).to eq(1)
    end

    it 'CLD clears decimal' do
      assemble_and_load(<<~'ASM')
        SED
        CLD
      ASM
      2.times { sim.step }
      expect(sim.flag_d).to eq(0)
    end

    it 'SED sets decimal' do
      assemble_and_load(<<~'ASM')
        CLD
        SED
      ASM
      2.times { sim.step }
      expect(sim.flag_d).to eq(1)
    end

    it 'CLI clears interrupt' do
      assemble_and_load(<<~'ASM')
        SEI
        CLI
      ASM
      2.times { sim.step }
      expect(sim.flag_i).to eq(0)
    end

    it 'SEI sets interrupt' do
      assemble_and_load(<<~'ASM')
        CLI
        SEI
      ASM
      2.times { sim.step }
      expect(sim.flag_i).to eq(1)
    end

    it 'CLV clears overflow' do
      # Set V flag via ADC overflow then clear it
      assemble_and_load(<<~'ASM')
        CLC
        LDA #$7F
        ADC #$01
        CLV
      ASM
      4.times { sim.step }
      expect(sim.flag_v).to eq(0)
    end
  end

  describe 'BIT instruction' do
    it 'sets Z based on A AND M' do
      sim.write(0x10, 0xF0)
      assemble_and_load(<<~'ASM')
        LDA #$0F
        BIT $10
      ASM
      2.times { sim.step }
      expect(sim.flag_z).to eq(1)
    end

    it 'sets N from bit 7 of memory' do
      sim.write(0x10, 0x80)
      assemble_and_load(<<~'ASM')
        LDA #$FF
        BIT $10
      ASM
      2.times { sim.step }
      expect(sim.flag_n).to eq(1)
    end

    it 'sets V from bit 6 of memory' do
      sim.write(0x10, 0x40)
      assemble_and_load(<<~'ASM')
        LDA #$FF
        BIT $10
      ASM
      2.times { sim.step }
      expect(sim.flag_v).to eq(1)
    end
  end

  describe 'algorithms' do
    it 'computes factorial of 5' do
      assemble_and_load(<<~'ASM')
        LDA #$05     ; n = 5
        STA $10      ; store n
        LDA #$01     ; result = 1
        STA $11
      loop:
        LDA $10      ; load n
        BEQ done     ; if n == 0, done
        ; multiply result by n (simple loop addition)
        LDX $10      ; x = n
        LDA #$00     ; product = 0
        STA $12
      mult:
        CLC
        LDA $12
        ADC $11      ; add result
        STA $12
        DEX
        BNE mult
        LDA $12
        STA $11      ; result = product
        DEC $10      ; n--
        JMP loop
      done:
        NOP
      ASM
      sim.run(200)
      # 5! = 120
      expect(sim.read(0x11)).to eq(120)
    end

    it 'computes fibonacci(10)' do
      # Compute fib(10) = 55
      assemble_and_load(<<~'ASM')
        LDA #$00     ; fib(0) = 0
        STA $10
        LDA #$01     ; fib(1) = 1
        STA $11
        LDX #$09     ; counter = 9 (we compute 9 more terms)
      loop:
        CLC
        LDA $10
        ADC $11      ; fib(n) = fib(n-1) + fib(n-2)
        STA $12      ; temp = new value
        LDA $11
        STA $10      ; shift values
        LDA $12
        STA $11
        DEX
        BNE loop
        NOP
      ASM
      sim.run(200)
      expect(sim.read(0x11)).to eq(55)
    end
  end

  describe 'run methods' do
    it 'step returns cycles' do
      assemble_and_load('LDA #$42')
      cycles = sim.step
      expect(cycles).to be > 0
    end

    it 'run executes multiple instructions' do
      assemble_and_load(<<~'ASM')
        LDA #$01
        LDA #$02
        LDA #$03
        LDA #$04
      ASM
      count = sim.run(4)
      expect(count).to eq(4)
      expect(sim.a).to eq(0x04)
    end

    it 'run_cycles executes for approximate cycles' do
      assemble_and_load(<<~'ASM')
        LDA #$01
        LDA #$02
        LDA #$03
        LDA #$04
        LDA #$05
      ASM
      cycles = sim.run_cycles(10)
      expect(cycles).to be >= 10
    end
  end

  describe 'indirect JMP bug' do
    it 'replicates 6502 page boundary bug' do
      # When JMP ($xxFF), the high byte comes from $xx00 not $xx00+1
      sim.write(0x20FF, 0x00)
      sim.write(0x2000, 0x80)  # Bug: high byte from $2000, not $2100
      sim.write(0x2100, 0xFF)  # This would be used on correct behavior

      assemble_and_load('JMP ($20FF)')
      sim.step
      # Due to bug, jumps to $8000, not $FF00
      expect(sim.pc).to eq(0x8000)
    end
  end

  describe 'cycle counting' do
    it 'counts cycles for instructions' do
      assemble_and_load('LDA #$42')
      start_cycles = sim.cycles
      sim.step
      expect(sim.cycles - start_cycles).to eq(2)
    end

    it 'adds page crossing cycle for indexed addressing' do
      sim.write(0x1100, 0x42)  # Target is at $1000 + $FF + 1 = $1100 (crosses page)
      assemble_and_load(<<~'ASM')
        LDX #$FF
        LDA $1001,X
      ASM
      sim.step  # LDX: 2 cycles
      start_cycles = sim.cycles
      sim.step  # LDA abs,X with page cross: 4 base + 1 page cross = 5 cycles
      cycles_taken = sim.cycles - start_cycles
      expect(cycles_taken).to eq(5)
    end
  end
end
