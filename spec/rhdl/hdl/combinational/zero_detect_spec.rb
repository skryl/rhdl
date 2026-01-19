# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::ZeroDetect do
  let(:det) { RHDL::HDL::ZeroDetect.new(nil, width: 8) }

  describe 'simulation' do
    it 'detects zero' do
      det.set_input(:a, 0x00)
      det.propagate

      expect(det.get_output(:zero)).to eq(1)
    end

    it 'detects non-zero' do
      det.set_input(:a, 0x01)
      det.propagate

      expect(det.get_output(:zero)).to eq(0)
    end

    it 'detects non-zero for all bits set' do
      det.set_input(:a, 0xFF)
      det.propagate

      expect(det.get_output(:zero)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::ZeroDetect.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ZeroDetect.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ZeroDetect.to_verilog
      expect(verilog).to include('module zero_detect')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output zero')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::ZeroDetect.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit zero_detect')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output zero')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::ZeroDetect,
          base_dir: 'tmp/circt_test/zero_detect'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ZeroDetect.new('zero_detect', width: 4) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'zero_detect') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('zero_detect.a')
      expect(ir.outputs.keys).to include('zero_detect.zero')
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module zero_detect')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output zero')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0 }, expected: { zero: 1 } },
          { inputs: { a: 1 }, expected: { zero: 0 } },
          { inputs: { a: 5 }, expected: { zero: 0 } },
          { inputs: { a: 15 }, expected: { zero: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/zero_detect')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
