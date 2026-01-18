require 'spec_helper'

RSpec.describe RHDL::HDL::AddSub do
  describe 'simulation' do
    it 'performs addition when sub=0' do
      addsub = RHDL::HDL::AddSub.new(nil, width: 8)

      addsub.set_input(:a, 100)
      addsub.set_input(:b, 50)
      addsub.set_input(:sub, 0)
      addsub.propagate
      expect(addsub.get_output(:result)).to eq(150)
    end

    it 'performs subtraction when sub=1' do
      addsub = RHDL::HDL::AddSub.new(nil, width: 8)

      addsub.set_input(:a, 100)
      addsub.set_input(:b, 50)
      addsub.set_input(:sub, 1)
      addsub.propagate
      expect(addsub.get_output(:result)).to eq(50)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::AddSub.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::AddSub.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(8)  # a, b, sub, result, cout, overflow, zero, negative
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::AddSub.to_verilog
      expect(verilog).to include('module add_sub')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] result')
    end

    context 'iverilog behavioral simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::AddSub.to_verilog
        behavioral = RHDL::HDL::AddSub.new(nil, width: 8)

        inputs = { a: 8, b: 8, sub: 1 }
        outputs = { result: 8, cout: 1, overflow: 1, zero: 1, negative: 1 }

        vectors = []
        test_cases = [
          { a: 100, b: 50, sub: 0 },  # 100 + 50 = 150
          { a: 100, b: 50, sub: 1 },  # 100 - 50 = 50
          { a: 200, b: 100, sub: 0 }, # 200 + 100 = 44 (overflow)
          { a: 50, b: 100, sub: 1 },  # 50 - 100 = 206 (underflow)
          { a: 0, b: 0, sub: 0 },     # zero result
          { a: 128, b: 0, sub: 0 },   # negative result (MSB set)
        ]

        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.set_input(:b, tc[:b])
          behavioral.set_input(:sub, tc[:sub])
          behavioral.propagate
          vectors << {
            inputs: tc,
            expected: {
              result: behavioral.get_output(:result),
              zero: behavioral.get_output(:zero),
              negative: behavioral.get_output(:negative)
            }
          }
        end

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 'add_sub',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/add_sub'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:result]).to eq(vec[:expected][:result]),
            "Vector #{idx}: expected result=#{vec[:expected][:result]}, got #{result[:results][idx][:result]}"
          expect(result[:results][idx][:zero]).to eq(vec[:expected][:zero]),
            "Vector #{idx}: expected zero=#{vec[:expected][:zero]}, got #{result[:results][idx][:zero]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::AddSub.new('addsub', width: 8) }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'addsub') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('addsub.a', 'addsub.b', 'addsub.sub')
      expect(ir.outputs.keys).to include('addsub.result', 'addsub.cout', 'addsub.overflow', 'addsub.zero', 'addsub.negative')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module addsub')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('input sub')
      expect(verilog).to include('output [7:0] result')
      expect(verilog).to include('output cout')
      expect(verilog).to include('output overflow')
      expect(verilog).to include('output zero')
      expect(verilog).to include('output negative')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        # Generate test vectors from behavioral simulation
        test_vectors = []
        behavioral = RHDL::HDL::AddSub.new(nil, width: 8)

        test_cases = [
          { a: 100, b: 50, sub: 0 },  # 100 + 50 = 150
          { a: 100, b: 50, sub: 1 },  # 100 - 50 = 50
          { a: 200, b: 100, sub: 0 }, # 200 + 100 = 44 (overflow)
          { a: 50, b: 100, sub: 1 },  # 50 - 100 = 206 (underflow)
          { a: 0, b: 0, sub: 0 },     # zero result
          { a: 128, b: 0, sub: 0 },   # negative result (MSB set)
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.set_input(:b, tc[:b])
          behavioral.set_input(:sub, tc[:sub])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            result: behavioral.get_output(:result),
            zero: behavioral.get_output(:zero),
            negative: behavioral.get_output(:negative)
          }
        end

        # Run structural simulation
        base_dir = File.join('tmp', 'iverilog', 'addsub')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        # Compare outputs
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
