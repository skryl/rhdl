# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux8 do
  let(:mux) { RHDL::HDL::Mux8.new(nil, width: 8) }

  describe 'simulation' do
    it 'selects from 8 inputs' do
      8.times { |i| mux.set_input("in#{i}".to_sym, (i + 1) * 10) }

      mux.set_input(:sel, 5)
      mux.propagate
      expect(mux.get_output(:y)).to eq(60)

      mux.set_input(:sel, 7)
      mux.propagate
      expect(mux.get_output(:y)).to eq(80)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Mux8.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Mux8.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(10)  # in0-in7, sel, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Mux8.to_verilog
      expect(verilog).to include('module mux8')
      expect(verilog).to include('input in0')
      expect(verilog).to include('output y')
    end
  end

  describe 'gate-level netlist (1-bit)' do
    let(:component) { RHDL::HDL::Mux8.new('mux8', width: 1) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mux8') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux8.in0', 'mux8.in1', 'mux8.in2', 'mux8.in3')
      expect(ir.inputs.keys).to include('mux8.in4', 'mux8.in5', 'mux8.in6', 'mux8.in7', 'mux8.sel')
      expect(ir.outputs.keys).to include('mux8.y')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mux8')
      expect(verilog).to include('input in0')
      expect(verilog).to include('input [2:0] sel')
      expect(verilog).to include('output y')
    end
  end
end
