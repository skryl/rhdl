require 'spec_helper'

RSpec.describe RHDL::HDL::ROM do
  let(:contents) { [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77] }
  let(:rom) { RHDL::HDL::ROM.new(nil, data_width: 8, addr_width: 8, contents: contents) }

  describe 'simulation' do
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

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::ROM.behavior_defined?).to be_truthy
    end

    # Note: Memory components use internal state arrays which are not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::ROM.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # en, addr, dout
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::ROM.to_verilog
      expect(verilog).to include('module rom')
      expect(verilog).to include('input [7:0] addr')
      expect(verilog).to include('output [7:0] dout')
    end
  end
end
