require 'spec_helper'

RSpec.describe RHDL::HDL::ROM do
  let(:contents) { [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77] }
  let(:rom) { RHDL::HDL::ROM.new(nil, data_width: 8, addr_width: 8, contents: contents) }

  it 'reads stored data' do
    rom.set_input(:en, 1)
    rom.set_input(:addr, 0)
    rom.propagate
    expect(rom.get_output(:dout)).to eq(0x00)

    rom.set_input(:addr, 3)
    rom.propagate
    expect(rom.get_output(:dout)).to eq(0x33)

    rom.set_input(:addr, 7)
    rom.propagate
    expect(rom.get_output(:dout)).to eq(0x77)
  end

  it 'outputs zero when disabled' do
    rom.set_input(:en, 0)
    rom.set_input(:addr, 3)
    rom.propagate
    expect(rom.get_output(:dout)).to eq(0)
  end

  it 'returns zero for uninitialized addresses' do
    rom.set_input(:en, 1)
    rom.set_input(:addr, 100)
    rom.propagate
    expect(rom.get_output(:dout)).to eq(0)
  end
end
