require 'spec_helper'

RSpec.describe RHDL::HDL::IncDec do
  describe 'simulation' do
    it 'increments when inc=1' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 100)
      incdec.set_input(:inc, 1)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(101)
    end

    it 'decrements when inc=0' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 100)
      incdec.set_input(:inc, 0)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(99)
    end

    it 'handles overflow on increment' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 255)
      incdec.set_input(:inc, 1)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(0)
      expect(incdec.get_output(:cout)).to eq(1)
    end

    it 'handles underflow on decrement' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 0)
      incdec.set_input(:inc, 0)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(255)
      expect(incdec.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::IncDec.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::IncDec.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, inc, result, cout
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::IncDec.to_verilog
      expect(verilog).to include('module inc_dec')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] result')
    end
  end
end
