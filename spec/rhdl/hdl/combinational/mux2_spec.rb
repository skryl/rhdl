# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux2 do
  let(:mux) { RHDL::HDL::Mux2.new(nil, width: 8) }

  describe 'simulation' do
    it 'selects input a when sel=0' do
      mux.set_input(:a, 0x11)
      mux.set_input(:b, 0x22)
      mux.set_input(:sel, 0)
      mux.propagate

      expect(mux.get_output(:y)).to eq(0x11)
    end

    it 'selects input b when sel=1' do
      mux.set_input(:a, 0x11)
      mux.set_input(:b, 0x22)
      mux.set_input(:sel, 1)
      mux.propagate

      expect(mux.get_output(:y)).to eq(0x22)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Mux2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Mux2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, b, sel, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Mux2.to_verilog
      expect(verilog).to include('module mux2')
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist (1-bit)' do
    let(:component) { RHDL::HDL::Mux2.new('mux2', width: 1) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mux2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux2.a', 'mux2.b', 'mux2.sel')
      expect(ir.outputs.keys).to include('mux2.y')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mux2')
      expect(verilog).to include('input sel')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0, sel: 0 }, expected: { y: 0 } },
          { inputs: { a: 0, b: 1, sel: 0 }, expected: { y: 0 } },
          { inputs: { a: 1, b: 0, sel: 0 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, sel: 1 }, expected: { y: 0 } },
          { inputs: { a: 0, b: 1, sel: 1 }, expected: { y: 1 } },
          { inputs: { a: 1, b: 0, sel: 1 }, expected: { y: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mux2')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'gate-level netlist (4-bit)' do
    let(:component) { RHDL::HDL::Mux2.new('mux2_4bit', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mux2_4bit') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux2_4bit.a', 'mux2_4bit.b', 'mux2_4bit.sel')
      expect(ir.outputs.keys).to include('mux2_4bit.y')
      expect(ir.gates.length).to eq(4)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('input [3:0] b')
      expect(verilog).to include('output [3:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b1010, b: 0b0101, sel: 0 }, expected: { y: 0b1010 } },
          { inputs: { a: 0b1010, b: 0b0101, sel: 1 }, expected: { y: 0b0101 } },
          { inputs: { a: 0b1111, b: 0b0000, sel: 0 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b1111, b: 0b0000, sel: 1 }, expected: { y: 0b0000 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mux2_4bit')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
