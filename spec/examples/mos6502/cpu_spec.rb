require_relative 'spec_helper'
require_relative '../../../examples/mos6502/cpu_harness'

RSpec.describe MOS6502::CPUHarness do
  let(:cpu) { MOS6502::CPUHarness.new }

  describe 'Load instructions' do
    it 'executes LDA immediate' do
      cpu.assemble_and_load('LDA #$42')
      cpu.reset
      cpu.step

      expect(cpu.a).to eq(0x42)
    end

    it 'executes LDA with zero value' do
      cpu.assemble_and_load('LDA #$00')
      cpu.reset
      cpu.step

      expect(cpu.a).to eq(0x00)
      expect(cpu.flag_z).to eq(1)
    end

    it 'executes LDA with negative value' do
      cpu.assemble_and_load('LDA #$80')
      cpu.reset
      cpu.step

      expect(cpu.a).to eq(0x80)
      expect(cpu.flag_n).to eq(1)
    end

    it 'executes LDX and LDY' do
      cpu.assemble_and_load(<<~'ASM')
        LDX #$10
        LDY #$20
      ASM
      cpu.reset
      cpu.step
      cpu.step

      expect(cpu.x).to eq(0x10)
      expect(cpu.y).to eq(0x20)
    end
  end

  describe 'Register transfers' do
    it 'executes TAX' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$42
        TAX
      ASM
      cpu.reset
      cpu.step
      cpu.step

      expect(cpu.x).to eq(0x42)
    end
  end

  describe 'Arithmetic instructions' do
    it 'executes ADC' do
      cpu.assemble_and_load(<<~'ASM')
        CLC
        LDA #$10
        ADC #$20
      ASM
      cpu.reset
      3.times { cpu.step }

      expect(cpu.a).to eq(0x30)
    end
  end

  describe 'Logic instructions' do
    it 'executes AND' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$FF
        AND #$0F
      ASM
      cpu.reset
      2.times { cpu.step }

      expect(cpu.a).to eq(0x0F)
    end
  end

  describe 'Shift instructions' do
    it 'executes ASL accumulator' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$81
        ASL A
      ASM
      cpu.reset
      2.times { cpu.step }

      expect(cpu.a).to eq(0x02)
      expect(cpu.flag_c).to eq(1)
    end
  end

  describe 'Branch instructions' do
    it 'executes BEQ when Z=1' do
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

    it 'does not branch BEQ when Z=0' do
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
  end

  describe 'Flag instructions' do
    it 'executes CLC and SEC' do
      cpu.assemble_and_load(<<~'ASM')
        SEC
        CLC
      ASM
      cpu.reset
      cpu.step
      expect(cpu.flag_c).to eq(1)
      cpu.step
      expect(cpu.flag_c).to eq(0)
    end
  end

  describe 'Complete programs' do
    it 'counts from 0 to 5' do
      cpu.assemble_and_load(<<~'ASM')
        LDA #$00
      LOOP:
        CLC
        ADC #$01
        CMP #$05
        BNE LOOP
      ASM
      cpu.reset
      50.times { cpu.step }

      expect(cpu.a).to eq(0x05)
    end

    it 'copies memory' do
      # Set up source data
      cpu.write_mem(0x00, 0x11)
      cpu.write_mem(0x01, 0x22)
      cpu.write_mem(0x02, 0x33)

      cpu.assemble_and_load(<<~'ASM')
        LDX #$00
      LOOP:
        LDA $00,X
        STA $10,X
        INX
        CPX #$03
        BNE LOOP
      ASM
      cpu.reset
      50.times { cpu.step }

      expect(cpu.read_mem(0x10)).to eq(0x11)
      expect(cpu.read_mem(0x11)).to eq(0x22)
      expect(cpu.read_mem(0x12)).to eq(0x33)
    end
  end
end
