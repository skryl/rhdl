# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::SignExtend do
  let(:ext) { RHDL::HDL::SignExtend.new(nil, in_width: 8, out_width: 16) }

  describe 'simulation' do
    it 'extends positive values with zeros' do
      ext.set_input(:a, 0x7F)  # Positive (MSB = 0)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0x007F)
    end

    it 'extends negative values with ones' do
      ext.set_input(:a, 0x80)  # Negative (MSB = 1)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0xFF80)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::SignExtend.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::SignExtend.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::SignExtend.to_verilog
      expect(verilog).to include('module sign_extend')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [15:0] y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::SignExtend.new('sign_extend', in_width: 4, out_width: 8) }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'sign_extend') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('sign_extend.a')
      expect(ir.outputs.keys).to include('sign_extend.y')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module sign_extend')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [7:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0101 }, expected: { y: 0b00000101 } },
          { inputs: { a: 0b1000 }, expected: { y: 0b11111000 } },
          { inputs: { a: 0b1111 }, expected: { y: 0b11111111 } },
          { inputs: { a: 0b0000 }, expected: { y: 0b00000000 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/sign_extend')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
