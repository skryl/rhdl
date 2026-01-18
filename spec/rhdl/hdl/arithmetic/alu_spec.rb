require 'spec_helper'

RSpec.describe RHDL::HDL::ALU do
  let(:alu) { RHDL::HDL::ALU.new(nil, width: 8) }

  describe 'simulation' do
    it 'performs ADD' do
      alu.set_input(:a, 10)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
      alu.set_input(:cin, 0)
      alu.propagate

      expect(alu.get_output(:result)).to eq(15)
      expect(alu.get_output(:zero)).to eq(0)
    end

    it 'performs SUB' do
      alu.set_input(:a, 10)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_SUB)
      alu.set_input(:cin, 0)
      alu.propagate

      expect(alu.get_output(:result)).to eq(5)
    end

    it 'performs AND' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:b, 0b10101010)
      alu.set_input(:op, RHDL::HDL::ALU::OP_AND)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b10100000)
    end

    it 'performs OR' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:b, 0b00001111)
      alu.set_input(:op, RHDL::HDL::ALU::OP_OR)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b11111111)
    end

    it 'performs XOR' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:b, 0b10101010)
      alu.set_input(:op, RHDL::HDL::ALU::OP_XOR)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b01011010)
    end

    it 'performs NOT' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:op, RHDL::HDL::ALU::OP_NOT)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b00001111)
    end

    it 'performs MUL' do
      alu.set_input(:a, 10)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_MUL)
      alu.propagate

      expect(alu.get_output(:result)).to eq(50)
    end

    it 'performs DIV' do
      alu.set_input(:a, 20)
      alu.set_input(:b, 4)
      alu.set_input(:op, RHDL::HDL::ALU::OP_DIV)
      alu.propagate

      expect(alu.get_output(:result)).to eq(5)
    end

    it 'sets zero flag' do
      alu.set_input(:a, 5)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_SUB)
      alu.set_input(:cin, 0)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0)
      expect(alu.get_output(:zero)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::ALU.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ALU.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # a, b, op, cin, result, cout, zero, negative, overflow
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ALU.to_verilog
      expect(verilog).to include('module alu')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [7:0] result')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ALU.new('alu', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'alu') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('alu.a', 'alu.b', 'alu.op', 'alu.cin')
      expect(ir.outputs.keys).to include('alu.result', 'alu.cout', 'alu.zero', 'alu.negative', 'alu.overflow')
      # ALU has many gates for all operations
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module alu')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('input [3:0] op')
      expect(verilog).to include('input cin')
      expect(verilog).to include('output [7:0] result')
      expect(verilog).to include('output cout')
      expect(verilog).to include('output zero')
      expect(verilog).to include('output negative')
      expect(verilog).to include('output overflow')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::ALU.new(nil, width: 8)

        test_cases = [
          { a: 10, b: 5, op: RHDL::HDL::ALU::OP_ADD, cin: 0 },   # ADD
          { a: 10, b: 5, op: RHDL::HDL::ALU::OP_SUB, cin: 0 },   # SUB
          { a: 0b11110000, b: 0b10101010, op: RHDL::HDL::ALU::OP_AND, cin: 0 },  # AND
          { a: 0b11110000, b: 0b00001111, op: RHDL::HDL::ALU::OP_OR, cin: 0 },   # OR
          { a: 0b11110000, b: 0b10101010, op: RHDL::HDL::ALU::OP_XOR, cin: 0 },  # XOR
          { a: 5, b: 5, op: RHDL::HDL::ALU::OP_SUB, cin: 0 },    # zero flag test
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.set_input(:b, tc[:b])
          behavioral.set_input(:op, tc[:op])
          behavioral.set_input(:cin, tc[:cin])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            result: behavioral.get_output(:result),
            zero: behavioral.get_output(:zero)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'alu')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:result]).to eq(expected[:result]),
            "Cycle #{idx}: expected result=#{expected[:result]}, got #{result[:results][idx][:result]}"
          expect(result[:results][idx][:zero]).to eq(expected[:zero]),
            "Cycle #{idx}: expected zero=#{expected[:zero]}, got #{result[:results][idx][:zero]}"
        end
      end
    end
  end
end
