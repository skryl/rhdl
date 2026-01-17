# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Encoder4to2 do
  let(:enc) { RHDL::HDL::Encoder4to2.new }

  describe 'simulation' do
    it 'encodes one-hot input' do
      # Input :a is a 4-bit value where bit 2 is set (0b0100)
      enc.set_input(:a, 0b0100)
      enc.propagate

      expect(enc.get_output(:y)).to eq(2)
      expect(enc.get_output(:valid)).to eq(1)
    end

    it 'indicates invalid when no input' do
      enc.set_input(:a, 0b0000)
      enc.propagate

      expect(enc.get_output(:valid)).to eq(0)
    end

    it 'prioritizes higher input' do
      # Bits 0, 1, and 3 are set - highest is bit 3
      enc.set_input(:a, 0b1011)
      enc.propagate

      expect(enc.get_output(:y)).to eq(3)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Encoder4to2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Encoder4to2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, y, valid
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Encoder4to2.to_verilog
      expect(verilog).to include('module encoder4to2')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [1:0] y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Encoder4to2.new('enc4to2') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'enc4to2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('enc4to2.a')
      expect(ir.outputs.keys).to include('enc4to2.y', 'enc4to2.valid')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module enc4to2')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [1:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0001 }, expected: { y: 0, valid: 1 } },
          { inputs: { a: 0b0010 }, expected: { y: 1, valid: 1 } },
          { inputs: { a: 0b0100 }, expected: { y: 2, valid: 1 } },
          { inputs: { a: 0b1000 }, expected: { y: 3, valid: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/enc4to2')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
