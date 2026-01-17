require 'spec_helper'

RSpec.describe RHDL::HDL::Subtractor do
  describe 'simulation' do
    it 'subtracts 8-bit numbers' do
      sub = RHDL::HDL::Subtractor.new(nil, width: 8)

      # 100 - 50 = 50
      sub.set_input(:a, 100)
      sub.set_input(:b, 50)
      sub.set_input(:bin, 0)
      sub.propagate
      expect(sub.get_output(:diff)).to eq(50)
      expect(sub.get_output(:bout)).to eq(0)
    end

    it 'handles borrow' do
      sub = RHDL::HDL::Subtractor.new(nil, width: 8)

      # 50 - 100 = -50 (with borrow)
      sub.set_input(:a, 50)
      sub.set_input(:b, 100)
      sub.set_input(:bin, 0)
      sub.propagate
      expect(sub.get_output(:diff)).to eq(206)  # 256 - 50
      expect(sub.get_output(:bout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Subtractor.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Subtractor.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, b, bin, diff, bout, overflow
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Subtractor.to_verilog
      expect(verilog).to include('module subtractor')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] diff')
    end
  end
end
