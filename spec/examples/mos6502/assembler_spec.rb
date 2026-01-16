require_relative 'spec_helper'
require_relative '../../../examples/mos6502/assembler'

RSpec.describe MOS6502::Assembler do
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
