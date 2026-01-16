require_relative 'spec_helper'
require_relative '../../../examples/mos6502/cpu'

RSpec.describe 'FIG Forth interpreter on 6502' do
  let(:cpu) { MOS6502::CPU.new }

  it 'boots and initializes the user area' do
    source_path = File.expand_path('../../../examples/mos6502/fig_forth/fig6502.asm', __dir__)
    source = File.read(source_path)

    assembler = MOS6502::Assembler.new
    origin = 0x0380
    program = assembler.assemble(source, origin)

    cpu.load_program(program, origin)

    # Stub OSI ROM routines used for terminal I/O.
    cpu.write_mem(0xBF2D, 0x60) # RTS for OUTCH
    cpu.write_mem(0xFD00, 0xA9) # LDA #$00 for INCH
    cpu.write_mem(0xFD01, 0x00)
    cpu.write_mem(0xFD02, 0x60) # RTS

    cpu.reset
    cpu.run(5_000)

    expect(cpu.halted?).to be(false)

    up_addr = 0x00B3
    up_value = cpu.read_mem(up_addr) | (cpu.read_mem(up_addr + 1) << 8)
    expect(up_value).to eq(0x1F80)
  end
end
