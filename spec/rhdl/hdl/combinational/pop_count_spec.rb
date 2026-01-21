# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::PopCount do
  let(:pop) { RHDL::HDL::PopCount.new(nil, width: 8) }

  describe 'simulation' do
    it 'counts set bits' do
      pop.set_input(:a, 0b10101010)
      pop.propagate
      expect(pop.get_output(:count)).to eq(4)

      pop.set_input(:a, 0b11111111)
      pop.propagate
      expect(pop.get_output(:count)).to eq(8)

      pop.set_input(:a, 0b00000000)
      pop.propagate
      expect(pop.get_output(:count)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::PopCount.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::PopCount.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, count
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::PopCount.to_verilog
      expect(verilog).to include('module pop_count')
      expect(verilog).to include('input [7:0] a')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::PopCount.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit pop_count')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output count')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::PopCount,
          base_dir: 'tmp/circt_test/pop_count'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::PopCount.new('popcount', width: 8) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'popcount') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('popcount.a')
      expect(ir.outputs.keys).to include('popcount.count')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module popcount')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [3:0] count')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::PopCount.new(nil, width: 8)

        test_cases = [
          { a: 0b10101010 },  # 4 bits
          { a: 0b11111111 },  # 8 bits
          { a: 0b00000000 },  # 0 bits
          { a: 0b00000001 },  # 1 bit
          { a: 0b11110000 },  # 4 bits
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { count: behavior.get_output(:count) }
        end

        base_dir = File.join('tmp', 'iverilog', 'popcount')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:count]).to eq(expected[:count]),
            "Cycle #{idx}: expected count=#{expected[:count]}, got #{result[:results][idx][:count]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results' do
        test_cases = [
          { a: 0b10101010 },
          { a: 0b11111111 },
          { a: 0b00000000 },
          { a: 0b00000001 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::PopCount,
          'pop_count',
          test_cases,
          base_dir: 'tmp/netlist_comparison/pop_count',
          has_clock: false
        )
      end
    end
  end
end
