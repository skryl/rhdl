require_relative 'spec_helper'
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

      it 'sets overflow flag for signed overflow' do
        alu.set_input(:a, 0x7F)  # +127
        alu.set_input(:b, 0x01)  # +1
        alu.set_input(:op, MOS6502::ALU::OP_ADC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x80)  # -128 in signed
        expect(alu.get_output(:v)).to eq(1)
        expect(alu.get_output(:n)).to eq(1)
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

      it 'subtracts with borrow' do
        alu.set_input(:a, 0x30)
        alu.set_input(:b, 0x10)
        alu.set_input(:c_in, 0)  # Carry clear means borrow
        alu.set_input(:op, MOS6502::ALU::OP_SBC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x1F)
      end

      it 'clears carry on borrow' do
        alu.set_input(:a, 0x10)
        alu.set_input(:b, 0x20)
        alu.set_input(:c_in, 1)
        alu.set_input(:op, MOS6502::ALU::OP_SBC)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0xF0)
        expect(alu.get_output(:c)).to eq(0)
        expect(alu.get_output(:n)).to eq(1)
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

      it 'performs EOR' do
        alu.set_input(:a, 0xFF)
        alu.set_input(:b, 0xF0)
        alu.set_input(:op, MOS6502::ALU::OP_EOR)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x0F)
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
        expect(alu.get_output(:n)).to eq(0)
      end

      it 'performs ROL with carry' do
        alu.set_input(:a, 0x80)
        alu.set_input(:c_in, 1)
        alu.set_input(:op, MOS6502::ALU::OP_ROL)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x01)
        expect(alu.get_output(:c)).to eq(1)
      end

      it 'performs ROR with carry' do
        alu.set_input(:a, 0x01)
        alu.set_input(:c_in, 1)
        alu.set_input(:op, MOS6502::ALU::OP_ROR)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0x80)
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
        expect(alu.get_output(:n)).to eq(0)
      end

      it 'compares A > M' do
        alu.set_input(:a, 0x50)
        alu.set_input(:b, 0x40)
        alu.set_input(:op, MOS6502::ALU::OP_CMP)
        alu.propagate

        expect(alu.get_output(:z)).to eq(0)
        expect(alu.get_output(:c)).to eq(1)
        expect(alu.get_output(:n)).to eq(0)
      end

      it 'compares A < M' do
        alu.set_input(:a, 0x40)
        alu.set_input(:b, 0x50)
        alu.set_input(:op, MOS6502::ALU::OP_CMP)
        alu.propagate

        expect(alu.get_output(:z)).to eq(0)
        expect(alu.get_output(:c)).to eq(0)
        expect(alu.get_output(:n)).to eq(1)
      end
    end
  end

  describe MOS6502::Assembler do
    let(:asm) { MOS6502::Assembler.new }

    it 'assembles simple instructions' do
      source = <<~ASM
        LDA #$42
        NOP
        RTS
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xA9, 0x42, 0xEA, 0x60])
    end

    it 'assembles zero page addressing' do
      source = <<~ASM
        LDA $10
        STA $20
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xA5, 0x10, 0x85, 0x20])
    end

    it 'assembles absolute addressing' do
      source = <<~ASM
        LDA $1234
        STA $5678
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xAD, 0x34, 0x12, 0x8D, 0x78, 0x56])
    end

    it 'assembles indexed addressing' do
      source = <<~ASM
        LDA $10,X
        STA $1234,Y
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xB5, 0x10, 0x99, 0x34, 0x12])
    end

    it 'handles labels' do
      source = <<~ASM
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

    it 'handles indirect addressing' do
      source = <<~ASM
        LDA ($10,X)
        LDA ($20),Y
        JMP ($FFFE)
      ASM

      bytes = asm.assemble(source, 0x8000)
      expect(bytes).to eq([0xA1, 0x10, 0xB1, 0x20, 0x6C, 0xFE, 0xFF])
    end
  end

  describe MOS6502::StatusRegister do
    let(:sr) { MOS6502::StatusRegister.new }

    before do
      # Initialize with clock low
      sr.set_input(:clk, 0)
      sr.set_input(:rst, 0)
      sr.set_input(:load_all, 0)
      sr.set_input(:load_flags, 0)
      sr.set_input(:load_n, 0)
      sr.set_input(:load_z, 0)
      sr.set_input(:load_c, 0)
      sr.set_input(:load_v, 0)
      sr.set_input(:load_i, 0)
      sr.set_input(:load_d, 0)
      sr.set_input(:load_b, 0)
    end

    def clock_pulse
      sr.set_input(:clk, 0)
      sr.propagate
      sr.set_input(:clk, 1)
      sr.propagate
    end

    it 'starts with I flag set' do
      sr.propagate
      expect(sr.get_output(:i)).to eq(1)
    end

    it 'sets individual flags' do
      sr.set_input(:c_in, 1)
      sr.set_input(:load_c, 1)
      clock_pulse

      expect(sr.get_output(:c)).to eq(1)
    end

    it 'clears individual flags' do
      sr.set_input(:c_in, 1)
      sr.set_input(:load_c, 1)
      clock_pulse

      sr.set_input(:c_in, 0)
      sr.set_input(:load_c, 1)
      clock_pulse

      expect(sr.get_output(:c)).to eq(0)
    end

    it 'loads all flags at once' do
      sr.set_input(:data_in, 0xFF)
      sr.set_input(:load_all, 1)
      clock_pulse

      # B flag should be cleared, unused bit 5 should be set
      expect(sr.get_output(:p) & 0xEF).to eq(0xEF)
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

    describe 'Load/Store instructions' do
      it 'executes LDA immediate' do
        cpu.assemble_and_load("LDA #$42")
        cpu.reset
        cpu.step

        expect(cpu.a).to eq(0x42)
        expect(cpu.flag_z).to eq(0)
        expect(cpu.flag_n).to eq(0)
      end

      it 'executes LDA with zero value' do
        cpu.assemble_and_load("LDA #$00")
        cpu.reset
        cpu.step

        expect(cpu.a).to eq(0x00)
        expect(cpu.flag_z).to eq(1)
      end

      it 'executes LDA with negative value' do
        cpu.assemble_and_load("LDA #$80")
        cpu.reset
        cpu.step

        expect(cpu.a).to eq(0x80)
        expect(cpu.flag_n).to eq(1)
      end

      it 'executes LDX and LDY' do
        cpu.assemble_and_load(<<~ASM)
          LDX #$10
          LDY #$20
        ASM
        cpu.reset
        cpu.step
        cpu.step

        expect(cpu.x).to eq(0x10)
        expect(cpu.y).to eq(0x20)
      end

      it 'executes STA zero page' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$42
          STA $10
        ASM
        cpu.reset
        cpu.step
        cpu.step

        expect(cpu.read_mem(0x10)).to eq(0x42)
      end
    end

    describe 'Register transfer instructions' do
      it 'executes TAX' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$42
          TAX
        ASM
        cpu.reset
        cpu.step
        cpu.step

        expect(cpu.x).to eq(0x42)
      end

      it 'executes TXA' do
        cpu.assemble_and_load(<<~ASM)
          LDX #$42
          TXA
        ASM
        cpu.reset
        cpu.step
        cpu.step

        expect(cpu.a).to eq(0x42)
      end

      it 'executes TAY and TYA' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$42
          TAY
          LDA #$00
          TYA
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.a).to eq(0x42)
        expect(cpu.y).to eq(0x42)
      end
    end

    describe 'Arithmetic instructions' do
      it 'executes ADC' do
        cpu.assemble_and_load(<<~ASM)
          CLC
          LDA #$10
          ADC #$20
        ASM
        cpu.reset
        3.times { cpu.step }

        expect(cpu.a).to eq(0x30)
      end

      it 'executes SBC' do
        cpu.assemble_and_load(<<~ASM)
          SEC
          LDA #$30
          SBC #$10
        ASM
        cpu.reset
        3.times { cpu.step }

        expect(cpu.a).to eq(0x20)
      end

      it 'executes INC and DEC' do
        cpu.write_mem(0x10, 0x42)
        cpu.assemble_and_load(<<~ASM)
          INC $10
          DEC $10
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.read_mem(0x10)).to eq(0x42)
      end

      it 'executes INX, INY, DEX, DEY' do
        cpu.assemble_and_load(<<~ASM)
          LDX #$10
          LDY #$20
          INX
          INY
          DEX
          DEY
        ASM
        cpu.reset
        6.times { cpu.step }

        expect(cpu.x).to eq(0x10)
        expect(cpu.y).to eq(0x20)
      end
    end

    describe 'Logic instructions' do
      it 'executes AND' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$FF
          AND #$0F
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x0F)
      end

      it 'executes ORA' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$F0
          ORA #$0F
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0xFF)
      end

      it 'executes EOR' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$FF
          EOR #$F0
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x0F)
      end
    end

    describe 'Shift instructions' do
      it 'executes ASL accumulator' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$81
          ASL A
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x02)
        expect(cpu.flag_c).to eq(1)
      end

      it 'executes LSR accumulator' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$81
          LSR A
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x40)
        expect(cpu.flag_c).to eq(1)
      end

      it 'executes ROL and ROR' do
        cpu.assemble_and_load(<<~ASM)
          SEC
          LDA #$80
          ROL A
          ROR A
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.a).to eq(0x80)
      end
    end

    describe 'Compare instructions' do
      it 'executes CMP with equal values' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$42
          CMP #$42
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.flag_z).to eq(1)
        expect(cpu.flag_c).to eq(1)
      end

      it 'executes CMP with A > M' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$50
          CMP #$40
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.flag_z).to eq(0)
        expect(cpu.flag_c).to eq(1)
        expect(cpu.flag_n).to eq(0)
      end

      it 'executes CMP with A < M' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$40
          CMP #$50
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.flag_z).to eq(0)
        expect(cpu.flag_c).to eq(0)
      end

      it 'executes CPX and CPY' do
        cpu.assemble_and_load(<<~ASM)
          LDX #$42
          CPX #$42
          LDY #$42
          CPY #$42
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.flag_z).to eq(1)
      end
    end

    describe 'Branch instructions' do
      it 'executes BEQ when Z=1' do
        cpu.assemble_and_load(<<~ASM)
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
        cpu.assemble_and_load(<<~ASM)
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

      it 'executes BNE when Z=0' do
        cpu.assemble_and_load(<<~ASM)
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

      it 'executes BMI when N=1' do
        cpu.assemble_and_load(<<~ASM)
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

      it 'executes BPL when N=0' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$01
          BPL SKIP
          LDA #$42
        SKIP:
          NOP
        ASM
        cpu.reset
        3.times { cpu.step }

        expect(cpu.a).to eq(0x01)
      end

      it 'executes BCC when C=0' do
        cpu.assemble_and_load(<<~ASM)
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

      it 'executes BCS when C=1' do
        cpu.assemble_and_load(<<~ASM)
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
    end

    describe 'Flag instructions' do
      it 'executes CLC and SEC' do
        cpu.assemble_and_load(<<~ASM)
          SEC
          CLC
        ASM
        cpu.reset
        cpu.step
        expect(cpu.flag_c).to eq(1)
        cpu.step
        expect(cpu.flag_c).to eq(0)
      end

      it 'executes CLD and SED' do
        cpu.assemble_and_load(<<~ASM)
          SED
          CLD
        ASM
        cpu.reset
        cpu.step
        expect(cpu.flag_d).to eq(1)
        cpu.step
        expect(cpu.flag_d).to eq(0)
      end

      it 'executes CLI and SEI' do
        cpu.assemble_and_load(<<~ASM)
          CLI
          SEI
        ASM
        cpu.reset
        cpu.step
        expect(cpu.flag_i).to eq(0)
        cpu.step
        expect(cpu.flag_i).to eq(1)
      end

      it 'executes CLV' do
        # Set V flag via ADC overflow then clear it
        cpu.assemble_and_load(<<~ASM)
          CLC
          LDA #$7F
          ADC #$01
          CLV
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.flag_v).to eq(0)
      end
    end

    describe 'Stack instructions' do
      it 'executes PHA and PLA' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$42
          PHA
          LDA #$00
          PLA
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.a).to eq(0x42)
      end

      it 'executes PHP and PLP' do
        cpu.assemble_and_load(<<~ASM)
          SEC
          PHP
          CLC
          PLP
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.flag_c).to eq(1)
      end

      it 'executes TXS and TSX' do
        cpu.assemble_and_load(<<~ASM)
          LDX #$80
          TXS
          LDX #$00
          TSX
        ASM
        cpu.reset
        4.times { cpu.step }

        expect(cpu.sp).to eq(0x80)
        expect(cpu.x).to eq(0x80)
      end
    end

    describe 'Jump instructions' do
      it 'executes JMP absolute' do
        cpu.assemble_and_load(<<~ASM)
          JMP SKIP
          LDA #$42
        SKIP:
          LDA #$00
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x00)
      end
    end

    describe 'Addressing modes' do
      it 'executes zero page X indexed' do
        cpu.write_mem(0x15, 0x42)
        cpu.assemble_and_load(<<~ASM)
          LDX #$05
          LDA $10,X
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x42)
      end

      it 'executes absolute X indexed' do
        cpu.write_mem(0x1005, 0x42)
        cpu.assemble_and_load(<<~ASM)
          LDX #$05
          LDA $1000,X
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x42)
      end

      it 'executes absolute Y indexed' do
        cpu.write_mem(0x1005, 0x42)
        cpu.assemble_and_load(<<~ASM)
          LDY #$05
          LDA $1000,Y
        ASM
        cpu.reset
        2.times { cpu.step }

        expect(cpu.a).to eq(0x42)
      end
    end

    describe 'Complete programs' do
      it 'counts from 0 to 5' do
        cpu.assemble_and_load(<<~ASM)
          LDA #$00
        LOOP:
          CLC
          ADC #$01
          CMP #$05
          BNE LOOP
        ASM
        cpu.reset
        20.times { cpu.step }

        expect(cpu.a).to eq(0x05)
      end

      it 'copies memory' do
        # Set up source data
        cpu.write_mem(0x00, 0x11)
        cpu.write_mem(0x01, 0x22)
        cpu.write_mem(0x02, 0x33)

        cpu.assemble_and_load(<<~ASM)
          LDX #$00
        LOOP:
          LDA $00,X
          STA $10,X
          INX
          CPX #$03
          BNE LOOP
        ASM
        cpu.reset
        20.times { cpu.step }

        expect(cpu.read_mem(0x10)).to eq(0x11)
        expect(cpu.read_mem(0x11)).to eq(0x22)
        expect(cpu.read_mem(0x12)).to eq(0x33)
      end

      it 'calculates sum of array' do
        # Array of values at $00-$03
        cpu.write_mem(0x00, 10)
        cpu.write_mem(0x01, 20)
        cpu.write_mem(0x02, 30)
        cpu.write_mem(0x03, 40)

        cpu.assemble_and_load(<<~ASM)
          LDA #$00      ; sum = 0
          LDX #$00      ; index = 0
        LOOP:
          CLC
          ADC $00,X     ; sum += array[index]
          INX
          CPX #$04      ; done when index = 4
          BNE LOOP
          STA $10       ; store result
        ASM
        cpu.reset
        30.times { cpu.step }

        expect(cpu.read_mem(0x10)).to eq(100)
      end
    end
  end
end
