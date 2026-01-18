# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux4 do
  let(:mux) { RHDL::HDL::Mux4.new(nil, width: 8) }

  before do
    mux.set_input(:a, 0x10)
    mux.set_input(:b, 0x20)
    mux.set_input(:c, 0x30)
    mux.set_input(:d, 0x40)
  end

  describe 'simulation' do
    it 'selects correct input based on sel' do
      mux.set_input(:sel, 0)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x10)

      mux.set_input(:sel, 1)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x20)

      mux.set_input(:sel, 2)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x30)

      mux.set_input(:sel, 3)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x40)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Mux4.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Mux4.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, b, c, d, sel, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Mux4.to_verilog
      expect(verilog).to include('module mux4')
      expect(verilog).to include('input [1:0] sel')
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::Mux4.to_verilog
        behavior = RHDL::HDL::Mux4.new(nil, width: 1)

        inputs = { a: 1, b: 1, c: 1, d: 1, sel: 2 }
        outputs = { y: 1 }

        vectors = []
        test_cases = [
          { a: 1, b: 0, c: 0, d: 0, sel: 0 },
          { a: 0, b: 1, c: 0, d: 0, sel: 1 },
          { a: 0, b: 0, c: 1, d: 0, sel: 2 },
          { a: 0, b: 0, c: 0, d: 1, sel: 3 },
          { a: 1, b: 1, c: 1, d: 1, sel: 0 },
          { a: 1, b: 1, c: 1, d: 1, sel: 1 },
          { a: 1, b: 1, c: 1, d: 1, sel: 2 },
          { a: 1, b: 1, c: 1, d: 1, sel: 3 },
          { a: 0, b: 0, c: 0, d: 0, sel: 2 }
        ]

        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.set_input(:b, tc[:b])
          behavior.set_input(:c, tc[:c])
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:sel, tc[:sel])
          behavior.propagate
          vectors << {
            inputs: tc,
            expected: { y: behavior.get_output(:y) }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mux4',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mux4'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:y]).to eq(vec[:expected][:y]),
            "Vector #{idx}: expected y=#{vec[:expected][:y]}, got #{result[:results][idx][:y]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Mux4.new('mux4', width: 1) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mux4') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux4.a', 'mux4.b', 'mux4.c', 'mux4.d', 'mux4.sel')
      expect(ir.outputs.keys).to include('mux4.y')
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mux4')
      expect(verilog).to include('input [1:0] sel')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 1, b: 0, c: 0, d: 0, sel: 0 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 1, c: 0, d: 0, sel: 1 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, c: 1, d: 0, sel: 2 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, c: 0, d: 1, sel: 3 }, expected: { y: 1 } },
          { inputs: { a: 1, b: 1, c: 1, d: 1, sel: 0 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, c: 0, d: 0, sel: 2 }, expected: { y: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mux4')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
