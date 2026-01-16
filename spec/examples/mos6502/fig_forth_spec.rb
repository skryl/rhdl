require_relative 'spec_helper'
require_relative '../../../examples/mos6502/cpu'

RSpec.describe 'FIG Forth interpreter on 6502' do
  let(:cpu) { MOS6502::CPU.new }

  def load_fig_forth(cpu)
    source_path = File.expand_path('../../../examples/mos6502/fig_forth/fig6502.asm', __dir__)
    source = File.read(source_path)

    assembler = MOS6502::Assembler.new
    origin = 0x0380
    program = assembler.assemble(source, origin)
    cpu.load_program(program, origin)
  end

  def install_io_stubs(cpu)
    # OUTCH: store A into $0300,Y and increment output index at $F1
    outch = [0xA4, 0xF1, 0x99, 0x00, 0x03, 0xC8, 0x84, 0xF1, 0x60]
    outch.each_with_index { |byte, i| cpu.write_mem(0xBF2D + i, byte) }

    # INCH: read from $0200,Y and increment input index at $F0
    inch = [0xA4, 0xF0, 0xB9, 0x00, 0x02, 0xC8, 0x84, 0xF0, 0x60]
    inch.each_with_index { |byte, i| cpu.write_mem(0xFD00 + i, byte) }

    cpu.write_mem(0x00F0, 0x00)
    cpu.write_mem(0x00F1, 0x00)
  end

  it 'boots and initializes the user area' do
    load_fig_forth(cpu)
    install_io_stubs(cpu)

    cpu.reset
    cpu.run(5_000)

    expect(cpu.halted?).to be(false)

    up_addr = 0x00B3
    up_value = cpu.read_mem(up_addr) | (cpu.read_mem(up_addr + 1) << 8)
    expect(up_value).to eq(0x1F80)
  end

  it 'executes a Forth program and emits output' do
    load_fig_forth(cpu)
    install_io_stubs(cpu)

    input = "1 2 + .\r".bytes
    input.each_with_index { |byte, i| cpu.write_mem(0x0200 + i, byte) }

    cpu.reset

    output = ''
    50_000.times do
      cpu.step
      out_len = cpu.read_mem(0x00F1)
      if out_len.positive?
        output = (0...out_len).map { |i| cpu.read_mem(0x0300 + i) }.pack('C*')
        break if output.include?('3')
      end
    end

    expect(output).to include('3')
  end
end
