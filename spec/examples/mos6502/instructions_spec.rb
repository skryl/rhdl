require_relative 'spec_helper'
require_relative '../../../examples/mos6502/hdl/harness'

RSpec.describe 'MOS6502 Instructions' do
  let(:cpu) { MOS6502::Harness.new }

  # ============================================
  # LOAD INSTRUCTIONS
  # ============================================
  describe 'Load instructions' do
    describe 'LDA' do
      it 'LDA immediate' do
        cpu.assemble_and_load('LDA #$42')
        cpu.reset
        cpu.step
        expect(cpu.a).to eq(0x42)
      end

      it 'LDA zero page' do
        cpu.write_mem(0x10, 0x55)
        cpu.assemble_and_load('LDA $10')
        cpu.reset
        cpu.step
        expect(cpu.a).to eq(0x55)
      end

      it 'LDA zero page,X' do
        cpu.write_mem(0x15, 0x77)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDA $10,X
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x77)
      end

      it 'LDA absolute' do
        cpu.write_mem(0x1234, 0x88)
        cpu.assemble_and_load('LDA $1234')
        cpu.reset
        cpu.step
        expect(cpu.a).to eq(0x88)
      end

      it 'LDA absolute,X' do
        cpu.write_mem(0x1239, 0x99)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDA $1234,X
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x99)
      end

      it 'LDA absolute,Y' do
        cpu.write_mem(0x123A, 0xAA)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$06
          LDA $1234,Y
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xAA)
      end

      it 'LDA (indirect,X)' do
        # Pointer at $15-$16 points to $2000
        cpu.write_mem(0x15, 0x00)
        cpu.write_mem(0x16, 0x20)
        cpu.write_mem(0x2000, 0xBB)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDA ($10,X)
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xBB)
      end

      it 'LDA (indirect),Y' do
        # Pointer at $10-$11 points to $2000
        cpu.write_mem(0x10, 0x00)
        cpu.write_mem(0x11, 0x20)
        cpu.write_mem(0x2005, 0xCC)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$05
          LDA ($10),Y
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xCC)
      end

      it 'sets Z flag when loading zero' do
        cpu.assemble_and_load('LDA #$00')
        cpu.reset
        cpu.step
        expect(cpu.flag_z).to eq(1)
        expect(cpu.flag_n).to eq(0)
      end

      it 'sets N flag when loading negative' do
        cpu.assemble_and_load('LDA #$80')
        cpu.reset
        cpu.step
        expect(cpu.flag_n).to eq(1)
        expect(cpu.flag_z).to eq(0)
      end
    end

    describe 'LDX' do
      it 'LDX immediate' do
        cpu.assemble_and_load('LDX #$42')
        cpu.reset
        cpu.step
        expect(cpu.x).to eq(0x42)
      end

      it 'LDX zero page' do
        cpu.write_mem(0x10, 0x55)
        cpu.assemble_and_load('LDX $10')
        cpu.reset
        cpu.step
        expect(cpu.x).to eq(0x55)
      end

      it 'LDX zero page,Y' do
        cpu.write_mem(0x15, 0x77)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$05
          LDX $10,Y
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.x).to eq(0x77)
      end

      it 'LDX absolute' do
        cpu.write_mem(0x1234, 0x88)
        cpu.assemble_and_load('LDX $1234')
        cpu.reset
        cpu.step
        expect(cpu.x).to eq(0x88)
      end

      it 'LDX absolute,Y' do
        cpu.write_mem(0x123A, 0x99)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$06
          LDX $1234,Y
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.x).to eq(0x99)
      end
    end

    describe 'LDY' do
      it 'LDY immediate' do
        cpu.assemble_and_load('LDY #$42')
        cpu.reset
        cpu.step
        expect(cpu.y).to eq(0x42)
      end

      it 'LDY zero page' do
        cpu.write_mem(0x10, 0x55)
        cpu.assemble_and_load('LDY $10')
        cpu.reset
        cpu.step
        expect(cpu.y).to eq(0x55)
      end

      it 'LDY zero page,X' do
        cpu.write_mem(0x15, 0x77)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDY $10,X
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.y).to eq(0x77)
      end

      it 'LDY absolute' do
        cpu.write_mem(0x1234, 0x88)
        cpu.assemble_and_load('LDY $1234')
        cpu.reset
        cpu.step
        expect(cpu.y).to eq(0x88)
      end

      it 'LDY absolute,X' do
        cpu.write_mem(0x1239, 0x99)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDY $1234,X
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.y).to eq(0x99)
      end
    end
  end

  # ============================================
  # STORE INSTRUCTIONS
  # ============================================
  describe 'Store instructions' do
    describe 'STA' do
      it 'STA zero page' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$42
          STA $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x10)).to eq(0x42)
      end

      it 'STA zero page,X' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDA #$55
          STA $10,X
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x15)).to eq(0x55)
      end

      it 'STA absolute' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$77
          STA $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x1234)).to eq(0x77)
      end

      it 'STA absolute,X' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDA #$88
          STA $1234,X
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x1239)).to eq(0x88)
      end

      it 'STA absolute,Y' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$06
          LDA #$99
          STA $1234,Y
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x123A)).to eq(0x99)
      end

      it 'STA (indirect,X)' do
        cpu.write_mem(0x15, 0x00)
        cpu.write_mem(0x16, 0x20)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDA #$AA
          STA ($10,X)
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x2000)).to eq(0xAA)
      end

      it 'STA (indirect),Y' do
        cpu.write_mem(0x10, 0x00)
        cpu.write_mem(0x11, 0x20)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$05
          LDA #$BB
          STA ($10),Y
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x2005)).to eq(0xBB)
      end
    end

    describe 'STX' do
      it 'STX zero page' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$42
          STX $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x10)).to eq(0x42)
      end

      it 'STX zero page,Y' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$05
          LDX #$55
          STX $10,Y
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x15)).to eq(0x55)
      end

      it 'STX absolute' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$77
          STX $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x1234)).to eq(0x77)
      end
    end

    describe 'STY' do
      it 'STY zero page' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$42
          STY $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x10)).to eq(0x42)
      end

      it 'STY zero page,X' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          LDY #$55
          STY $10,X
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.read_mem(0x15)).to eq(0x55)
      end

      it 'STY absolute' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$77
          STY $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x1234)).to eq(0x77)
      end
    end
  end

  # ============================================
  # REGISTER TRANSFER INSTRUCTIONS
  # ============================================
  describe 'Register transfer instructions' do
    it 'TAX transfers A to X' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$42
        TAX
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.x).to eq(0x42)
    end

    it 'TXA transfers X to A' do
      cpu.assemble_and_load(<<~'ASM')
        LDX #$55
        TXA
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.a).to eq(0x55)
    end

    it 'TAY transfers A to Y' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$77
        TAY
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.y).to eq(0x77)
    end

    it 'TYA transfers Y to A' do
      cpu.assemble_and_load(<<~'ASM')
        LDY #$88
        TYA
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.a).to eq(0x88)
    end

    it 'TSX transfers S to X' do
      cpu.assemble_and_load('TSX')
      cpu.reset
      cpu.step
      expect(cpu.x).to eq(cpu.sp)
    end

    it 'TXS transfers X to S' do
      cpu.assemble_and_load(<<~'ASM')
        LDX #$80
        TXS
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.sp).to eq(0x80)
    end

    it 'TXS does not affect flags' do
      cpu.assemble_and_load(<<~'ASM')
        LDX #$00
        LDA #$01
        TXS
      ASM
      cpu.reset
      3.times { cpu.step }
      # Z flag should still be 0 from LDA #$01
      expect(cpu.flag_z).to eq(0)
    end
  end

  # ============================================
  # ARITHMETIC INSTRUCTIONS
  # ============================================
  describe 'Arithmetic instructions' do
    describe 'ADC' do
      it 'ADC immediate' do
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$10
          ADC #$20
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x30)
      end

      it 'ADC with carry in' do
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$10
          ADC #$20
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x31)
      end

      it 'ADC sets carry on overflow' do
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$FF
          ADC #$01
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x00)
        expect(cpu.flag_c).to eq(1)
        expect(cpu.flag_z).to eq(1)
      end

      it 'ADC zero page' do
        cpu.write_mem(0x10, 0x20)
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$10
          ADC $10
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x30)
      end

      it 'ADC absolute' do
        cpu.write_mem(0x1234, 0x20)
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$10
          ADC $1234
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x30)
      end
    end

    describe 'SBC' do
      it 'SBC immediate' do
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$30
          SBC #$10
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x20)
        expect(cpu.flag_c).to eq(1)  # No borrow
      end

      it 'SBC with borrow' do
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$30
          SBC #$10
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x1F)  # 0x30 - 0x10 - 1 = 0x1F
      end

      it 'SBC sets carry on no borrow' do
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$50
          SBC #$30
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x20)
        expect(cpu.flag_c).to eq(1)
      end

      it 'SBC clears carry on borrow' do
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$10
          SBC #$30
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0xE0)  # Wrapped around
        expect(cpu.flag_c).to eq(0)  # Borrow occurred
      end

      it 'SBC zero page' do
        cpu.write_mem(0x10, 0x10)
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$30
          SBC $10
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x20)
      end
    end

    describe 'INC/DEC register' do
      it 'INX increments X' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          INX
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.x).to eq(0x06)
      end

      it 'INX wraps from $FF to $00' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$FF
          INX
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.x).to eq(0x00)
        expect(cpu.flag_z).to eq(1)
      end

      it 'DEX decrements X' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          DEX
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.x).to eq(0x04)
      end

      it 'DEX wraps from $00 to $FF' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$00
          DEX
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.x).to eq(0xFF)
        expect(cpu.flag_n).to eq(1)
      end

      it 'INY increments Y' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$05
          INY
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.y).to eq(0x06)
      end

      it 'DEY decrements Y' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$05
          DEY
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.y).to eq(0x04)
      end
    end

    describe 'INC/DEC memory' do
      it 'INC zero page' do
        cpu.write_mem(0x10, 0x05)
        cpu.assemble_and_load('INC $10')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x10)).to eq(0x06)
      end

      it 'INC zero page,X' do
        cpu.write_mem(0x15, 0x05)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          INC $10,X
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x15)).to eq(0x06)
      end

      it 'INC absolute' do
        cpu.write_mem(0x1234, 0x05)
        cpu.assemble_and_load('INC $1234')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x1234)).to eq(0x06)
      end

      it 'DEC zero page' do
        cpu.write_mem(0x10, 0x05)
        cpu.assemble_and_load('DEC $10')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x10)).to eq(0x04)
      end

      it 'DEC zero page,X' do
        cpu.write_mem(0x15, 0x05)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$05
          DEC $10,X
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x15)).to eq(0x04)
      end

      it 'DEC absolute' do
        cpu.write_mem(0x1234, 0x05)
        cpu.assemble_and_load('DEC $1234')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x1234)).to eq(0x04)
      end
    end
  end

  # ============================================
  # LOGIC INSTRUCTIONS
  # ============================================
  describe 'Logic instructions' do
    describe 'AND' do
      it 'AND immediate' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$FF
          AND #$0F
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x0F)
      end

      it 'AND zero page' do
        cpu.write_mem(0x10, 0x0F)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$FF
          AND $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x0F)
      end

      it 'AND sets Z flag on zero result' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$F0
          AND #$0F
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x00)
        expect(cpu.flag_z).to eq(1)
      end
    end

    describe 'ORA' do
      it 'ORA immediate' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$F0
          ORA #$0F
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xFF)
        expect(cpu.flag_n).to eq(1)
      end

      it 'ORA zero page' do
        cpu.write_mem(0x10, 0x0F)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$F0
          ORA $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xFF)
      end

      it 'ORA absolute' do
        cpu.write_mem(0x1234, 0x55)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$AA
          ORA $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xFF)
      end
    end

    describe 'EOR' do
      it 'EOR immediate' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$FF
          EOR #$0F
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0xF0)
      end

      it 'EOR zero page' do
        cpu.write_mem(0x10, 0xFF)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$AA
          EOR $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x55)
      end

      it 'EOR with same value produces zero' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$55
          EOR #$55
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x00)
        expect(cpu.flag_z).to eq(1)
      end
    end

    describe 'BIT' do
      it 'BIT zero page sets Z when AND is zero' do
        cpu.write_mem(0x10, 0xF0)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$0F
          BIT $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(1)
        expect(cpu.a).to eq(0x0F)  # A unchanged
      end

      it 'BIT copies bit 7 to N flag' do
        cpu.write_mem(0x10, 0x80)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$FF
          BIT $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_n).to eq(1)
      end

      it 'BIT copies bit 6 to V flag' do
        cpu.write_mem(0x10, 0x40)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$FF
          BIT $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_v).to eq(1)
      end

      it 'BIT absolute' do
        cpu.write_mem(0x1234, 0xC0)  # Bits 7 and 6 set
        cpu.assemble_and_load(<<~'ASM')
          LDA #$FF
          BIT $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_n).to eq(1)
        expect(cpu.flag_v).to eq(1)
        expect(cpu.flag_z).to eq(0)
      end
    end
  end

  # ============================================
  # COMPARE INSTRUCTIONS
  # ============================================
  describe 'Compare instructions' do
    describe 'CMP' do
      it 'CMP sets Z when equal' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$42
          CMP #$42
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(1)
        expect(cpu.flag_c).to eq(1)
      end

      it 'CMP sets C when A >= M' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$50
          CMP #$30
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(0)
        expect(cpu.flag_c).to eq(1)
      end

      it 'CMP clears C when A < M' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$30
          CMP #$50
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(0)
        expect(cpu.flag_c).to eq(0)
      end

      it 'CMP zero page' do
        cpu.write_mem(0x10, 0x42)
        cpu.assemble_and_load(<<~'ASM')
          LDA #$42
          CMP $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(1)
      end
    end

    describe 'CPX' do
      it 'CPX immediate' do
        cpu.assemble_and_load(<<~'ASM')
          LDX #$42
          CPX #$42
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(1)
        expect(cpu.flag_c).to eq(1)
      end

      it 'CPX zero page' do
        cpu.write_mem(0x10, 0x30)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$50
          CPX $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_c).to eq(1)
      end

      it 'CPX absolute' do
        cpu.write_mem(0x1234, 0x50)
        cpu.assemble_and_load(<<~'ASM')
          LDX #$30
          CPX $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_c).to eq(0)
      end
    end

    describe 'CPY' do
      it 'CPY immediate' do
        cpu.assemble_and_load(<<~'ASM')
          LDY #$42
          CPY #$42
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_z).to eq(1)
        expect(cpu.flag_c).to eq(1)
      end

      it 'CPY zero page' do
        cpu.write_mem(0x10, 0x30)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$50
          CPY $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_c).to eq(1)
      end

      it 'CPY absolute' do
        cpu.write_mem(0x1234, 0x50)
        cpu.assemble_and_load(<<~'ASM')
          LDY #$30
          CPY $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.flag_c).to eq(0)
      end
    end
  end

  # ============================================
  # SHIFT/ROTATE INSTRUCTIONS
  # ============================================
  describe 'Shift/Rotate instructions' do
    describe 'ASL' do
      it 'ASL accumulator' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$81
          ASL A
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x02)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ASL zero page' do
        cpu.write_mem(0x10, 0x40)
        cpu.assemble_and_load('ASL $10')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x10)).to eq(0x80)
        expect(cpu.flag_n).to eq(1)
      end

      it 'ASL absolute' do
        cpu.write_mem(0x1234, 0x40)
        cpu.assemble_and_load('ASL $1234')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x1234)).to eq(0x80)
      end
    end

    describe 'LSR' do
      it 'LSR accumulator' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$81
          LSR A
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x40)
        expect(cpu.flag_c).to eq(1)
      end

      it 'LSR zero page' do
        cpu.write_mem(0x10, 0x02)
        cpu.assemble_and_load('LSR $10')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x10)).to eq(0x01)
      end

      it 'LSR absolute' do
        cpu.write_mem(0x1234, 0x02)
        cpu.assemble_and_load('LSR $1234')
        cpu.reset
        cpu.step
        expect(cpu.read_mem(0x1234)).to eq(0x01)
      end

      it 'LSR clears N flag' do
        cpu.assemble_and_load(<<~'ASM')
          LDA #$80
          LSR A
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.a).to eq(0x40)
        expect(cpu.flag_n).to eq(0)
      end
    end

    describe 'ROL' do
      it 'ROL accumulator with carry clear' do
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$81
          ROL A
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x02)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ROL accumulator with carry set' do
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$81
          ROL A
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x03)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ROL zero page' do
        cpu.write_mem(0x10, 0x80)
        cpu.assemble_and_load(<<~'ASM')
          CLC
          ROL $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x10)).to eq(0x00)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ROL absolute' do
        cpu.write_mem(0x1234, 0x40)
        cpu.assemble_and_load(<<~'ASM')
          SEC
          ROL $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x1234)).to eq(0x81)
      end
    end

    describe 'ROR' do
      it 'ROR accumulator with carry clear' do
        cpu.assemble_and_load(<<~'ASM')
          CLC
          LDA #$81
          ROR A
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0x40)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ROR accumulator with carry set' do
        cpu.assemble_and_load(<<~'ASM')
          SEC
          LDA #$81
          ROR A
        ASM
        cpu.reset
        3.times { cpu.step }
        expect(cpu.a).to eq(0xC0)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ROR zero page' do
        cpu.write_mem(0x10, 0x01)
        cpu.assemble_and_load(<<~'ASM')
          CLC
          ROR $10
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x10)).to eq(0x00)
        expect(cpu.flag_c).to eq(1)
      end

      it 'ROR absolute' do
        cpu.write_mem(0x1234, 0x02)
        cpu.assemble_and_load(<<~'ASM')
          SEC
          ROR $1234
        ASM
        cpu.reset
        2.times { cpu.step }
        expect(cpu.read_mem(0x1234)).to eq(0x81)
      end
    end
  end

  # ============================================
  # BRANCH INSTRUCTIONS
  # ============================================
  describe 'Branch instructions' do
    it 'BEQ branches when Z=1' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$00
        BEQ SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x00)
    end

    it 'BEQ does not branch when Z=0' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$01
        BEQ SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x42)
    end

    it 'BNE branches when Z=0' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$01
        BNE SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x01)
    end

    it 'BNE does not branch when Z=1' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$00
        BNE SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x42)
    end

    it 'BPL branches when N=0' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$7F
        BPL SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x7F)
    end

    it 'BMI branches when N=1' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$80
        BMI SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x80)
    end

    it 'BCC branches when C=0' do
      cpu.assemble_and_load(<<~'ASM')
        CLC
        BCC SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x00)
    end

    it 'BCS branches when C=1' do
      cpu.assemble_and_load(<<~'ASM')
        SEC
        BCS SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x00)
    end

    it 'BVC branches when V=0' do
      cpu.assemble_and_load(<<~'ASM')
        CLV
        BVC SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      3.times { cpu.step }
      expect(cpu.a).to eq(0x00)
    end

    it 'BVS branches when V=1' do
      # Cause overflow: 127 + 1 overflows in signed arithmetic
      cpu.assemble_and_load(<<~'ASM')
        CLC
        LDA #$7F
        ADC #$01
        BVS SKIP
        LDA #$42
      SKIP:
        NOP
      ASM
      cpu.reset
      5.times { cpu.step }
      expect(cpu.a).to eq(0x80)  # Result of overflow
    end
  end

  # ============================================
  # JUMP INSTRUCTIONS
  # ============================================
  describe 'Jump instructions' do
    it 'JMP absolute' do
      cpu.assemble_and_load(<<~'ASM')
        JMP SKIP
        LDA #$42
      SKIP:
        LDA #$55
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.a).to eq(0x55)
    end

    it 'JMP indirect' do
      # Set up indirect pointer at $1000 pointing to $0210
      cpu.write_mem(0x1000, 0x10)
      cpu.write_mem(0x1001, 0x02)
      cpu.assemble_and_load(<<~'ASM')
        JMP ($1000)
      ASM
      cpu.reset
      cpu.step
      expect(cpu.pc).to eq(0x0210)
    end

    it 'JSR and RTS' do
      cpu.assemble_and_load(<<~'ASM')
        JSR SUB
        LDA #$42
        BRK
      SUB:
        LDA #$55
        RTS
      ASM
      cpu.reset
      50.times do
        cpu.step
        break if cpu.halted?
      end
      expect(cpu.a).to eq(0x42)
    end

    it 'nested JSR and RTS' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$00
        STA $10
        JSR OUTER
        LDA $10
        BRK
      OUTER:
        INC $10
        JSR INNER
        INC $10
        RTS
      INNER:
        INC $10
        RTS
      ASM
      cpu.reset
      50.times do
        cpu.step
        break if cpu.halted?
      end
      expect(cpu.read_mem(0x10)).to eq(3)
    end
  end

  # ============================================
  # STACK INSTRUCTIONS
  # ============================================
  describe 'Stack instructions' do
    it 'PHA pushes A to stack' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$42
        PHA
      ASM
      cpu.reset
      sp_before = cpu.sp
      2.times { cpu.step }
      expect(cpu.sp).to eq((sp_before - 1) & 0xFF)
      expect(cpu.read_mem(0x0100 + sp_before)).to eq(0x42)
    end

    it 'PLA pulls from stack to A' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$42
        PHA
        LDA #$00
        PLA
      ASM
      cpu.reset
      4.times { cpu.step }
      expect(cpu.a).to eq(0x42)
    end

    it 'PLA sets Z flag when pulling zero' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$00
        PHA
        LDA #$42
        PLA
      ASM
      cpu.reset
      4.times { cpu.step }
      expect(cpu.a).to eq(0x00)
      expect(cpu.flag_z).to eq(1)
    end

    it 'PLA sets N flag when pulling negative' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$80
        PHA
        LDA #$00
        PLA
      ASM
      cpu.reset
      4.times { cpu.step }
      expect(cpu.a).to eq(0x80)
      expect(cpu.flag_n).to eq(1)
    end

    it 'PHP pushes status register' do
      cpu.assemble_and_load(<<~'ASM')
        SEC
        PHP
      ASM
      cpu.reset
      sp_before = cpu.sp
      2.times { cpu.step }
      status = cpu.read_mem(0x0100 + sp_before)
      expect(status & 0x01).to eq(1)  # Carry should be set
    end

    it 'PLP pulls status register' do
      cpu.assemble_and_load(<<~'ASM')
        SEC
        PHP
        CLC
        PLP
      ASM
      cpu.reset
      4.times { cpu.step }
      expect(cpu.flag_c).to eq(1)
    end
  end

  # ============================================
  # FLAG INSTRUCTIONS
  # ============================================
  describe 'Flag instructions' do
    it 'CLC clears carry' do
      cpu.assemble_and_load(<<~'ASM')
        SEC
        CLC
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.flag_c).to eq(0)
    end

    it 'SEC sets carry' do
      cpu.assemble_and_load(<<~'ASM')
        CLC
        SEC
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.flag_c).to eq(1)
    end

    it 'CLI clears interrupt disable' do
      cpu.assemble_and_load(<<~'ASM')
        SEI
        CLI
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.flag_i).to eq(0)
    end

    it 'SEI sets interrupt disable' do
      cpu.assemble_and_load(<<~'ASM')
        CLI
        SEI
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.flag_i).to eq(1)
    end

    it 'CLV clears overflow' do
      # First cause overflow, then clear it
      cpu.assemble_and_load(<<~'ASM')
        CLC
        LDA #$7F
        ADC #$01
        CLV
      ASM
      cpu.reset
      4.times { cpu.step }
      expect(cpu.flag_v).to eq(0)
    end

    it 'CLD clears decimal mode' do
      cpu.assemble_and_load(<<~'ASM')
        SED
        CLD
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.flag_d).to eq(0)
    end

    it 'SED sets decimal mode' do
      cpu.assemble_and_load(<<~'ASM')
        CLD
        SED
      ASM
      cpu.reset
      2.times { cpu.step }
      expect(cpu.flag_d).to eq(1)
    end
  end

  # ============================================
  # NOP INSTRUCTION
  # ============================================
  describe 'NOP instruction' do
    it 'NOP does nothing' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$42
        NOP
        NOP
        NOP
      ASM
      cpu.reset
      4.times { cpu.step }
      expect(cpu.a).to eq(0x42)
    end
  end

  # ============================================
  # BRK INSTRUCTION
  # ============================================
  describe 'BRK instruction' do
    it 'BRK halts the CPU' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$42
        BRK
        LDA #$55
      ASM
      cpu.reset
      10.times do
        cpu.step
        break if cpu.halted?
      end
      expect(cpu.halted?).to be true
      expect(cpu.a).to eq(0x42)
    end
  end
end
