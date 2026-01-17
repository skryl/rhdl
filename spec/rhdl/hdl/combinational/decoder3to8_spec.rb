# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder3to8 do
  let(:dec) { RHDL::HDL::Decoder3to8.new }

  describe 'simulation' do
    it 'decodes all 8 values' do
      dec.set_input(:en, 1)

      8.times do |i|
        dec.set_input(:a, i)
        dec.propagate

        8.times do |j|
          expected = (i == j) ? 1 : 0
          expect(dec.get_output("y#{j}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Decoder3to8.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Decoder3to8.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(10)  # a, en, y0-y7
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Decoder3to8.to_verilog
      expect(verilog).to include('module decoder3to8')
      expect(verilog).to include('input [2:0] a')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Decoder3to8.new('dec3to8') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'dec3to8') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dec3to8.a', 'dec3to8.en')
      expect(ir.outputs.keys).to include('dec3to8.y0', 'dec3to8.y1')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module dec3to8')
      expect(verilog).to include('input [2:0] a')
      expect(verilog).to include('output y0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, en: 1 }, expected: { y0: 1, y1: 0, y2: 0, y3: 0, y4: 0, y5: 0, y6: 0, y7: 0 } },
          { inputs: { a: 1, en: 1 }, expected: { y0: 0, y1: 1, y2: 0, y3: 0, y4: 0, y5: 0, y6: 0, y7: 0 } },
          { inputs: { a: 7, en: 1 }, expected: { y0: 0, y1: 0, y2: 0, y3: 0, y4: 0, y5: 0, y6: 0, y7: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/dec3to8')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
