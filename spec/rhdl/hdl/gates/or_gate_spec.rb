require 'spec_helper'

RSpec.describe RHDL::HDL::OrGate do
  describe 'simulation' do
    it 'performs OR operation' do
      gate = RHDL::HDL::OrGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::OrGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::OrGate.to_verilog
      expect(verilog).to include('assign y')
    end

    context 'iverilog behavioral simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::OrGate.to_verilog
        behavioral = RHDL::HDL::OrGate.new

        inputs = { a0: 1, a1: 1 }
        outputs = { y: 1 }

        vectors = []
        test_cases = [
          { a0: 0, a1: 0 },
          { a0: 0, a1: 1 },
          { a0: 1, a1: 0 },
          { a0: 1, a1: 1 }
        ]

        test_cases.each do |tc|
          tc.each { |k, v| behavioral.set_input(k, v) }
          behavioral.propagate
          vectors << {
            inputs: tc,
            expected: { y: behavioral.get_output(:y) }
          }
        end

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 'or_gate',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/or_gate'
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
    let(:component) { RHDL::HDL::OrGate.new('or_gate') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'or_gate') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('or_gate.a0', 'or_gate.a1')
      expect(ir.outputs.keys).to include('or_gate.y')
      expect(ir.gates.length).to eq(1)
      expect(ir.gates.first.type).to eq(:or)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('or g0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 0, a1: 1 }, expected: { y: 1 } },
          { inputs: { a0: 1, a1: 0 }, expected: { y: 1 } },
          { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/or_gate')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
