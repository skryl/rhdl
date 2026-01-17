require 'spec_helper'

RSpec.describe RHDL::HDL::Divider do
  describe 'simulation' do
    it 'divides 8-bit numbers' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 10)
      div.propagate
      expect(div.get_output(:quotient)).to eq(10)
      expect(div.get_output(:remainder)).to eq(0)
      expect(div.get_output(:div_by_zero)).to eq(0)
    end

    it 'computes remainder' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 30)
      div.propagate
      expect(div.get_output(:quotient)).to eq(3)
      expect(div.get_output(:remainder)).to eq(10)
    end

    it 'handles division by zero' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 0)
      div.propagate
      expect(div.get_output(:div_by_zero)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Divider.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Divider.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # dividend, divisor, quotient, remainder, div_by_zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Divider.to_verilog
      expect(verilog).to include('module divider')
      expect(verilog).to include('input [7:0] dividend')
      expect(verilog).to include('output [7:0] quotient')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Divider.new('div', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'div') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('div.dividend', 'div.divisor')
      expect(ir.outputs.keys).to include('div.quotient', 'div.remainder', 'div.div_by_zero')
      # Divider has many gates for restoring division
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module div')
      expect(verilog).to include('input [7:0] dividend')
      expect(verilog).to include('input [7:0] divisor')
      expect(verilog).to include('output [7:0] quotient')
      expect(verilog).to include('output [7:0] remainder')
      expect(verilog).to include('output div_by_zero')
    end
  end
end
