# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::ZeroExtend do
  let(:ext) { RHDL::HDL::ZeroExtend.new(nil, in_width: 8, out_width: 16) }

  describe 'simulation' do
    it 'extends with zeros' do
      ext.set_input(:a, 0xFF)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0x00FF)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::ZeroExtend.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ZeroExtend.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ZeroExtend.to_verilog
      expect(verilog).to include('module zero_extend')
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ZeroExtend.new('zero_extend', in_width: 4, out_width: 8) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'zero_extend') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('zero_extend.a')
      expect(ir.outputs.keys).to include('zero_extend.y')
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module zero_extend')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [7:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0101 }, expected: { y: 0b00000101 } },
          { inputs: { a: 0b1000 }, expected: { y: 0b00001000 } },
          { inputs: { a: 0b1111 }, expected: { y: 0b00001111 } },
          { inputs: { a: 0b0000 }, expected: { y: 0b00000000 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/zero_extend')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
