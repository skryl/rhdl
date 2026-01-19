# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::LZCount do
  let(:lzc) { RHDL::HDL::LZCount.new(nil, width: 8) }

  describe 'simulation' do
    it 'counts leading zeros' do
      lzc.set_input(:a, 0b10000000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(0)

      lzc.set_input(:a, 0b00001000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(4)

      lzc.set_input(:a, 0b00000001)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(7)

      lzc.set_input(:a, 0b00000000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(8)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::LZCount.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::LZCount.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, count, zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::LZCount.to_verilog
      expect(verilog).to include('module lz_count')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [3:0] count')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::LZCount.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit lz_count')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output count')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::LZCount,
          base_dir: 'tmp/circt_test/lz_count'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::LZCount.new('lzcount', width: 8) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'lzcount') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('lzcount.a')
      expect(ir.outputs.keys).to include('lzcount.count', 'lzcount.all_zero')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module lzcount')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [3:0] count')
      expect(verilog).to include('output all_zero')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::LZCount.new(nil, width: 8)

        test_cases = [
          { a: 0b10000000 },  # 0 leading zeros
          { a: 0b00001000 },  # 4 leading zeros
          { a: 0b00000001 },  # 7 leading zeros
          { a: 0b00000000 },  # 8 leading zeros (all zero)
          { a: 0b01000000 },  # 1 leading zero
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            count: behavior.get_output(:count),
            all_zero: behavior.get_output(:all_zero)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'lzcount')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:count]).to eq(expected[:count]),
            "Cycle #{idx}: expected count=#{expected[:count]}, got #{result[:results][idx][:count]}"
          expect(result[:results][idx][:all_zero]).to eq(expected[:all_zero]),
            "Cycle #{idx}: expected all_zero=#{expected[:all_zero]}, got #{result[:results][idx][:all_zero]}"
        end
      end
    end
  end
end
