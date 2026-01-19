# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Demux4 do
  let(:demux) { RHDL::HDL::Demux4.new(nil, width: 8) }

  describe 'simulation' do
    it 'routes to correct output' do
      demux.set_input(:a, 0xFF)

      4.times do |sel|
        demux.set_input(:sel, sel)
        demux.propagate

        4.times do |out|
          expected = (out == sel) ? 0xFF : 0
          expect(demux.get_output("y#{out}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Demux4.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Demux4.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, sel, y0, y1, y2, y3
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Demux4.to_verilog
      expect(verilog).to include('module demux4')
      expect(verilog).to include('input a')
      expect(verilog).to include('output y0')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::Demux4.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit demux4')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output y0')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::Demux4,
          base_dir: 'tmp/circt_test/demux4'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist (1-bit)' do
    let(:component) { RHDL::HDL::Demux4.new('demux4', width: 1) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'demux4') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('demux4.a', 'demux4.sel')
      expect(ir.outputs.keys).to include('demux4.y0', 'demux4.y1', 'demux4.y2', 'demux4.y3')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module demux4')
      expect(verilog).to include('input a')
      expect(verilog).to include('input [1:0] sel')
      expect(verilog).to include('output y0')
      expect(verilog).to include('output y1')
      expect(verilog).to include('output y2')
      expect(verilog).to include('output y3')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::Demux4.new(nil, width: 1)

        test_cases = []
        4.times { |sel| test_cases << { a: 1, sel: sel } }

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.set_input(:sel, tc[:sel])
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            y0: behavior.get_output(:y0),
            y1: behavior.get_output(:y1),
            y2: behavior.get_output(:y2),
            y3: behavior.get_output(:y3)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'demux4')
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
