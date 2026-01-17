require 'spec_helper'

RSpec.describe RHDL::HDL::ShiftRegister do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:sr) { RHDL::HDL::ShiftRegister.new }

  before do
    sr.set_input(:rst, 0)
    sr.set_input(:en, 1)
    sr.set_input(:load, 0)
    sr.set_input(:dir, 1)  # Shift left
    sr.set_input(:d_in, 0)
  end

  describe 'simulation' do
    it 'shifts left' do
      sr.set_input(:load, 1)
      sr.set_input(:d, 0b00001111)
      clock_cycle(sr)
      sr.set_input(:load, 0)

      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b00011110)

      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b00111100)
    end

    it 'shifts right' do
      sr.set_input(:load, 1)
      sr.set_input(:d, 0b11110000)
      clock_cycle(sr)
      sr.set_input(:load, 0)

      sr.set_input(:dir, 0)  # Shift right
      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b01111000)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::ShiftRegister.behavior_defined? || RHDL::HDL::ShiftRegister.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ShiftRegister.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # d, d_in, clk, rst, en, load, dir, q, d_out
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ShiftRegister.to_verilog
      expect(verilog).to include('module shift_register')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ShiftRegister.new('shift_reg') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'shift_reg') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('shift_reg.d', 'shift_reg.d_in', 'shift_reg.clk', 'shift_reg.rst', 'shift_reg.en', 'shift_reg.load', 'shift_reg.dir')
      expect(ir.outputs.keys).to include('shift_reg.q', 'shift_reg.d_out')
      expect(ir.dffs.length).to eq(8)  # 8-bit shift register has 8 DFFs
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module shift_reg')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to include('input d_in')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [7:0] q')
      expect(verilog).to include('output d_out')
    end
  end
end
