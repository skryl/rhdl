# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502::Registers do
  let(:registers) { described_class.new('test_reg') }

  describe 'simulation' do
    before do
      registers.set_input(:clk, 0)
      registers.set_input(:rst, 0)
      registers.set_input(:data_in, 0)
      registers.set_input(:load_a, 0)
      registers.set_input(:load_x, 0)
      registers.set_input(:load_y, 0)
      registers.propagate
    end

    it 'loads value into A register on rising edge' do
      registers.set_input(:data_in, 0x42)
      registers.set_input(:load_a, 1)
      registers.set_input(:clk, 1)
      registers.propagate

      expect(registers.read_a).to eq(0x42)
    end

    it 'loads value into X register on rising edge' do
      registers.set_input(:data_in, 0x55)
      registers.set_input(:load_x, 1)
      registers.set_input(:clk, 1)
      registers.propagate

      expect(registers.read_x).to eq(0x55)
    end

    it 'loads value into Y register on rising edge' do
      registers.set_input(:data_in, 0xAA)
      registers.set_input(:load_y, 1)
      registers.set_input(:clk, 1)
      registers.propagate

      expect(registers.read_y).to eq(0xAA)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_registers')
      expect(verilog).to include('input [7:0] data_in')
      expect(verilog).to include('output reg [7:0] a')
      expect(verilog).to include('always @(posedge clk')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_registers') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mos6502_registers') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_registers.clk', 'mos6502_registers.rst')
      expect(ir.inputs.keys).to include('mos6502_registers.data_in')
      expect(ir.inputs.keys).to include('mos6502_registers.load_a', 'mos6502_registers.load_x', 'mos6502_registers.load_y')
      expect(ir.outputs.keys).to include('mos6502_registers.a', 'mos6502_registers.x', 'mos6502_registers.y')
    end

    it 'generates DFFs for A, X, Y registers' do
      # Registers has 3x 8-bit registers requiring DFFs
      expect(ir.dffs.length).to be > 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mos6502_registers')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output [7:0] a')
    end
  end
end
