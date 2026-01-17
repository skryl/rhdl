# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502S::Registers do
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
      expect(verilog).to include('module mos6502s_registers')
      expect(verilog).to include('input [7:0] data_in')
      expect(verilog).to include('output reg [7:0] a')
      expect(verilog).to include('always @(posedge clk')
    end
  end
end
