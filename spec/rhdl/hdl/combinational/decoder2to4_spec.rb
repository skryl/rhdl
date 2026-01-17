# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder2to4 do
  let(:dec) { RHDL::HDL::Decoder2to4.new }

  describe 'simulation' do
    it 'produces one-hot output' do
      dec.set_input(:en, 1)

      dec.set_input(:a, 0)
      dec.propagate
      expect(dec.get_output(:y0)).to eq(1)
      expect(dec.get_output(:y1)).to eq(0)
      expect(dec.get_output(:y2)).to eq(0)
      expect(dec.get_output(:y3)).to eq(0)

      dec.set_input(:a, 2)
      dec.propagate
      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y2)).to eq(1)
    end

    it 'outputs all zeros when disabled' do
      dec.set_input(:en, 0)
      dec.set_input(:a, 1)
      dec.propagate

      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y1)).to eq(0)
      expect(dec.get_output(:y2)).to eq(0)
      expect(dec.get_output(:y3)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Decoder2to4.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Decoder2to4.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, en, y0, y1, y2, y3
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Decoder2to4.to_verilog
      expect(verilog).to include('module decoder2to4')
      expect(verilog).to include('input [1:0] a')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Decoder2to4.new('dec2to4') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'dec2to4') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dec2to4.a', 'dec2to4.en')
      expect(ir.outputs.keys).to include('dec2to4.y0', 'dec2to4.y1', 'dec2to4.y2', 'dec2to4.y3')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module dec2to4')
      expect(verilog).to include('input [1:0] a')
      expect(verilog).to include('output y0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, en: 1 }, expected: { y0: 1, y1: 0, y2: 0, y3: 0 } },
          { inputs: { a: 1, en: 1 }, expected: { y0: 0, y1: 1, y2: 0, y3: 0 } },
          { inputs: { a: 2, en: 1 }, expected: { y0: 0, y1: 0, y2: 1, y3: 0 } },
          { inputs: { a: 3, en: 1 }, expected: { y0: 0, y1: 0, y2: 0, y3: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/dec2to4')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
