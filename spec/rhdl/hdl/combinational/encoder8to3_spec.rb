# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Encoder8to3 do
  let(:enc) { RHDL::HDL::Encoder8to3.new }

  describe 'simulation' do
    it 'encodes 8-bit one-hot to 3-bit binary' do
      # Bit 5 is set (0b00100000)
      enc.set_input(:a, 0b00100000)
      enc.propagate

      expect(enc.get_output(:y)).to eq(5)
      expect(enc.get_output(:valid)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Encoder8to3.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Encoder8to3.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, y, valid
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Encoder8to3.to_verilog
      expect(verilog).to include('module encoder8to3')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [2:0] y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Encoder8to3.new('enc8to3') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'enc8to3') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('enc8to3.a')
      expect(ir.outputs.keys).to include('enc8to3.y', 'enc8to3.valid')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module enc8to3')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [2:0] y')
      expect(verilog).to include('output valid')
    end
  end
end
