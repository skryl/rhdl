# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Demux2 do
  let(:demux) { RHDL::HDL::Demux2.new(nil, width: 8) }

  describe 'simulation' do
    it 'routes to output a when sel=0' do
      demux.set_input(:a, 0x42)
      demux.set_input(:sel, 0)
      demux.propagate

      expect(demux.get_output(:y0)).to eq(0x42)
      expect(demux.get_output(:y1)).to eq(0)
    end

    it 'routes to output b when sel=1' do
      demux.set_input(:a, 0x42)
      demux.set_input(:sel, 1)
      demux.propagate

      expect(demux.get_output(:y0)).to eq(0)
      expect(demux.get_output(:y1)).to eq(0x42)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Demux2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Demux2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, sel, y0, y1
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Demux2.to_verilog
      expect(verilog).to include('module demux2')
      expect(verilog).to include('input sel')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::Demux2.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit demux2')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output y0')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::Demux2,
          base_dir: 'tmp/circt_test/demux2'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist (1-bit)' do
    let(:component) { RHDL::HDL::Demux2.new('demux2', width: 1) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'demux2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('demux2.a', 'demux2.sel')
      expect(ir.outputs.keys).to include('demux2.y0', 'demux2.y1')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module demux2')
      expect(verilog).to include('input a')
      expect(verilog).to include('input sel')
      expect(verilog).to include('output y0')
      expect(verilog).to include('output y1')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::Demux2.new(nil, width: 1)

        test_cases = [
          { a: 1, sel: 0 },  # route to y0
          { a: 1, sel: 1 },  # route to y1
          { a: 0, sel: 0 },  # zero to y0
          { a: 0, sel: 1 },  # zero to y1
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.set_input(:sel, tc[:sel])
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            y0: behavior.get_output(:y0),
            y1: behavior.get_output(:y1)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'demux2')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:y0]).to eq(expected[:y0]),
            "Cycle #{idx}: expected y0=#{expected[:y0]}, got #{result[:results][idx][:y0]}"
          expect(result[:results][idx][:y1]).to eq(expected[:y1]),
            "Cycle #{idx}: expected y1=#{expected[:y1]}, got #{result[:results][idx][:y1]}"
        end
      end
    end
  end
end
