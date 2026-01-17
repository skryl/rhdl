# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::BitReverse do
  let(:rev) { RHDL::HDL::BitReverse.new(nil, width: 8) }

  describe 'simulation' do
    it 'reverses bit order' do
      rev.set_input(:a, 0b10110001)
      rev.propagate

      expect(rev.get_output(:y)).to eq(0b10001101)
    end

    it 'handles symmetric patterns' do
      rev.set_input(:a, 0b10000001)
      rev.propagate

      expect(rev.get_output(:y)).to eq(0b10000001)
    end

    it 'reverses all zeros' do
      rev.set_input(:a, 0b00000000)
      rev.propagate

      expect(rev.get_output(:y)).to eq(0b00000000)
    end

    it 'reverses all ones' do
      rev.set_input(:a, 0b11111111)
      rev.propagate

      expect(rev.get_output(:y)).to eq(0b11111111)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitReverse.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::BitReverse.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitReverse.to_verilog
      expect(verilog).to include('module bit_reverse')
      expect(verilog).to include('input [7:0] a')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::BitReverse.new('bitrev', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bitrev') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('bitrev.a')
      expect(ir.outputs.keys).to include('bitrev.y')
      # Bit reverse is just rewiring, may have buffer gates or none
      expect(ir.gates.length).to be >= 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module bitrev')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] y')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::BitReverse.new(nil, width: 8)

        test_cases = [
          { a: 0b10110001 },
          { a: 0b10000001 },
          { a: 0b00000000 },
          { a: 0b11111111 },
          { a: 0b00001111 },
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { y: behavioral.get_output(:y) }
        end

        base_dir = File.join('tmp', 'iverilog', 'bitrev')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:y]).to eq(expected[:y]),
            "Cycle #{idx}: expected y=#{expected[:y]}, got #{result[:results][idx][:y]}"
        end
      end
    end
  end
end
