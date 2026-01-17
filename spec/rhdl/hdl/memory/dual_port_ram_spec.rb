require 'spec_helper'

RSpec.describe RHDL::HDL::DualPortRAM do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:dpram) { RHDL::HDL::DualPortRAM.new(nil, data_width: 8, addr_width: 8) }

  it 'writes and reads from port A' do
    # Write 0xAB via port A
    dpram.set_input(:addr_a, 0x10)
    dpram.set_input(:din_a, 0xAB)
    dpram.set_input(:we_a, 1)
    clock_cycle(dpram)

    # Read back from port A
    dpram.set_input(:we_a, 0)
    dpram.propagate
    expect(dpram.get_output(:dout_a)).to eq(0xAB)
  end

  it 'writes and reads from port B' do
    # Write 0xCD via port B
    dpram.set_input(:addr_b, 0x20)
    dpram.set_input(:din_b, 0xCD)
    dpram.set_input(:we_b, 1)
    clock_cycle(dpram)

    # Read back from port B
    dpram.set_input(:we_b, 0)
    dpram.propagate
    expect(dpram.get_output(:dout_b)).to eq(0xCD)
  end

  it 'allows simultaneous read from both ports' do
    # Write values to two addresses via port A
    dpram.set_input(:addr_a, 0x10)
    dpram.set_input(:din_a, 0x11)
    dpram.set_input(:we_a, 1)
    clock_cycle(dpram)

    dpram.set_input(:addr_a, 0x20)
    dpram.set_input(:din_a, 0x22)
    clock_cycle(dpram)

    # Read both values simultaneously
    dpram.set_input(:we_a, 0)
    dpram.set_input(:we_b, 0)
    dpram.set_input(:addr_a, 0x10)
    dpram.set_input(:addr_b, 0x20)
    dpram.propagate

    expect(dpram.get_output(:dout_a)).to eq(0x11)
    expect(dpram.get_output(:dout_b)).to eq(0x22)
  end

  it 'allows port B to read what port A wrote' do
    # Write via port A
    dpram.set_input(:addr_a, 0x30)
    dpram.set_input(:din_a, 0x55)
    dpram.set_input(:we_a, 1)
    dpram.set_input(:we_b, 0)
    clock_cycle(dpram)

    # Read via port B
    dpram.set_input(:we_a, 0)
    dpram.set_input(:addr_b, 0x30)
    dpram.propagate

    expect(dpram.get_output(:dout_b)).to eq(0x55)
  end
end
