require 'spec_helper'

RSpec.describe RHDL::HDL::RAM do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:ram) { RHDL::HDL::RAM.new(nil, data_width: 8, addr_width: 8) }

  it 'writes and reads data' do
    # Write 0xAB to address 0x10
    ram.set_input(:addr, 0x10)
    ram.set_input(:din, 0xAB)
    ram.set_input(:we, 1)
    clock_cycle(ram)

    # Read back
    ram.set_input(:we, 0)
    ram.propagate
    expect(ram.get_output(:dout)).to eq(0xAB)
  end

  it 'maintains data when not writing' do
    # Write initial value
    ram.set_input(:addr, 0x20)
    ram.set_input(:din, 0x42)
    ram.set_input(:we, 1)
    clock_cycle(ram)

    # Change din but keep we=0
    ram.set_input(:we, 0)
    ram.set_input(:din, 0xFF)
    clock_cycle(ram)

    # Value should still be 0x42
    expect(ram.get_output(:dout)).to eq(0x42)
  end

  it 'supports direct memory access' do
    ram.write_mem(0x50, 0xCD)
    expect(ram.read_mem(0x50)).to eq(0xCD)
  end

  it 'loads program data' do
    program = [0xA0, 0x42, 0xF0]
    ram.load_program(program, 0x100)

    expect(ram.read_mem(0x100)).to eq(0xA0)
    expect(ram.read_mem(0x101)).to eq(0x42)
    expect(ram.read_mem(0x102)).to eq(0xF0)
  end

  it 'reads different addresses' do
    ram.write_mem(0x00, 0x11)
    ram.write_mem(0x01, 0x22)
    ram.write_mem(0x02, 0x33)

    ram.set_input(:we, 0)

    ram.set_input(:addr, 0x00)
    ram.propagate
    expect(ram.get_output(:dout)).to eq(0x11)

    ram.set_input(:addr, 0x01)
    ram.propagate
    expect(ram.get_output(:dout)).to eq(0x22)

    ram.set_input(:addr, 0x02)
    ram.propagate
    expect(ram.get_output(:dout)).to eq(0x33)
  end
end
