require_relative 'spec_helper'
require_relative '../../../examples/mos6502/memory'

RSpec.describe MOS6502::Memory do
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

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = MOS6502::Memory.to_verilog
      expect(verilog).to include('module mos6502_memory')
    end
  end
end
