require 'rspec'
require_relative '../examples/mos6502/cpu'

RSpec.describe MOS6502 do
  describe MOS6502::ALU do
    let(:alu) { MOS6502::ALU.new }

    before do
      alu.set_input(:c_in, 0)
      alu.set_input(:d_flag, 0)
    end

    describe 'ADC' do
      it 'adds two numbers' do
        alu.set_input(:a, 0x10)
        alu.set_input(:b, 0x20)
        alu.set_input(:op, MOS6502::ALU::OP_ADC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x30)
        expect(alu.get_output(:z)).to eq(0)
        expect(alu.get_output(:n)).to eq(0)
        expect(alu.get_output(:c)).to eq(0)
      end

      it 'adds with carry in' do
        alu.set_input(:a, 0x10)
        alu.set_input(:b, 0x20)
        alu.set_input(:c_in, 1)
        alu.set_input(:op, MOS6502::ALU::OP_ADC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x31)
      end

      it 'sets carry on overflow' do
        alu.set_input(:a, 0xFF)
        alu.set_input(:b, 0x01)
        alu.set_input(:op, MOS6502::ALU::OP_ADC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x00)
        expect(alu.get_output(:c)).to eq(1)
        expect(alu.get_output(:z)).to eq(1)
      end
    end

    describe 'SBC' do
      it 'subtracts two numbers with borrow clear' do
        alu.set_input(:a, 0x30)
        alu.set_input(:b, 0x10)
        alu.set_input(:c_in, 1)  # Carry set means no borrow
        alu.set_input(:op, MOS6502::ALU::OP_SBC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x20)
        expect(alu.get_output(:c)).to eq(1)
      end
    end

    describe 'Logic operations' do
      it 'performs AND' do
        alu.set_input(:a, 0xF0)
        alu.set_input(:b, 0x0F)
        alu.set_input(:op, MOS6502::ALU::OP_AND)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x00)
        expect(alu.get_output(:z)).to eq(1)
      end

      it 'performs ORA' do
        alu.set_input(:a, 0xF0)
        alu.set_input(:b, 0x0F)
        alu.set_input(:op, MOS6502::ALU::OP_ORA)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0xFF)
        expect(alu.get_output(:n)).to eq(1)
      end
    end

    describe 'Shift operations' do
      it 'performs ASL' do
        alu.set_input(:a, 0x81)
        alu.set_input(:op, MOS6502::ALU::OP_ASL)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x02)
        expect(alu.get_output(:c)).to eq(1)
      end

      it 'performs LSR' do
        alu.set_input(:a, 0x81)
        alu.set_input(:op, MOS6502::ALU::OP_LSR)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x40)
        expect(alu.get_output(:c)).to eq(1)
      end
    end

    describe 'Compare' do
      it 'compares equal values' do
        alu.set_input(:a, 0x42)
        alu.set_input(:b, 0x42)
        alu.set_input(:op, MOS6502::ALU::OP_CMP)
        alu.propagate

        expect(alu.get_output(:z)).to eq(1)
        expect(alu.get_output(:c)).to eq(1)
      end
    end
  end

  describe MOS6502::Assembler do
    let(:asm) { MOS6502::Assembler.new }

    it 'assembles simple instructions' do
      source = <<~'ASM'
        LDA #$42
        NOP
        RTS
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xA9, 0x42, 0xEA, 0x60])
    end

    it 'assembles zero page addressing' do
      source = <<~'ASM'
        LDA $10
        STA $20
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xA5, 0x10, 0x85, 0x20])
    end

    it 'assembles absolute addressing' do
      source = <<~'ASM'
        LDA $1234
        STA $5678
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xAD, 0x34, 0x12, 0x8D, 0x78, 0x56])
    end

    it 'handles labels' do
      source = <<~'ASM'
        START:
          LDA #$00
          BEQ END
          INX
        END:
          RTS
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xA9, 0x00, 0xF0, 0x01, 0xE8, 0x60])
    end
  end

  describe MOS6502::Memory do
    let(:mem) { MOS6502::Memory.new }

    it 'reads and writes RAM' do
      mem.write(0x0000, 0x42)
      expect(mem.read(0x0000)).to eq(0x42)
    end

    it 'loads programs' do
      program = [0xA9, 0x42, 0x60]
      mem.load_program(program, 0x8000)

      expect(mem.read(0x8000)).to eq(0xA9)
      expect(mem.read(0x8001)).to eq(0x42)
      expect(mem.read(0x8002)).to eq(0x60)
    end

    it 'sets vectors' do
      mem.set_reset_vector(0x8000)
      expect(mem.read(0xFFFC)).to eq(0x00)
      expect(mem.read(0xFFFD)).to eq(0x80)
    end
  end

  describe MOS6502::CPU do
    let(:cpu) { MOS6502::CPU.new }

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
end
