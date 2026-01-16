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
    # OUTCH: store A into $0300 using output index at $02FF
    outch = [0xAC, 0xFF, 0x02, 0x99, 0x00, 0x03, 0xC8, 0x8C, 0xFF, 0x02, 0x60]
    outch.each_with_index { |byte, i| cpu.write_mem(0xBF2D + i, byte) }

    # INCH: read from $0200 using input index at $02FE
    inch = [0xAC, 0xFE, 0x02, 0xB9, 0x00, 0x02, 0xC8, 0x8C, 0xFE, 0x02, 0x60]
    inch.each_with_index { |byte, i| cpu.write_mem(0xFD00 + i, byte) }

    cpu.write_mem(0x02FE, 0x00)
    cpu.write_mem(0x02FF, 0x00)
  end

  it 'boots and initializes the user area' do
    load_fig_forth(cpu)
    install_io_stubs(cpu)

    cpu.reset
    cpu.run(5_000)

    up_addr = 0x00B3
    up_value = cpu.read_mem(up_addr) | (cpu.read_mem(up_addr + 1) << 8)
    expect(up_value).to eq(0x1F80)
  end

  it 'executes a Forth threaded program' do
    load_fig_forth(cpu)
    install_io_stubs(cpu)

    source_path = File.expand_path('../../../examples/mos6502/fig_forth/fig6502.asm', __dir__)
    source = File.read(source_path)
    assembler = MOS6502::Assembler.new
    assembler.assemble(source, 0x0380)
    labels = assembler.instance_variable_get(:@labels)

    cpu.reset

    thread_addr = 0x0200
    target_addr = 0x3000

    write_word = lambda do |addr, value|
      cpu.write_mem(addr, value & 0xFF)
      cpu.write_mem(addr + 1, (value >> 8) & 0xFF)
    end

    write_word.call(thread_addr, labels.fetch('LIT'))
    write_word.call(thread_addr + 2, 1)
    write_word.call(thread_addr + 4, labels.fetch('LIT'))
    write_word.call(thread_addr + 6, 2)
    write_word.call(thread_addr + 8, labels.fetch('PLUS'))
    write_word.call(thread_addr + 10, labels.fetch('LIT'))
    write_word.call(thread_addr + 12, target_addr)
    write_word.call(thread_addr + 14, labels.fetch('STORE'))
    write_word.call(thread_addr + 16, labels.fetch('BRAN'))
    write_word.call(thread_addr + 18, 0)

    cpu.write_mem(0x00AE, thread_addr & 0xFF)
    cpu.write_mem(0x00AF, (thread_addr >> 8) & 0xFF)
    cpu.write_mem(0x00B0, 0x6C)
    cpu.x = 0x9E
    cpu.y = 0x00
    cpu.pc = labels.fetch('NEXT')

    cpu.run(1_000)

    expect(cpu.read_mem(target_addr)).to eq(3)
  end
end
