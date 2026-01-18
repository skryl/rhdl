require 'spec_helper'

RSpec.describe RHDL::HDL::AndGate do
  describe 'simulation' do
    it 'performs AND operation' do
      gate = RHDL::HDL::AndGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)
    end

    # Note: N-input gates removed in favor of synthesizable 2-input gates
    # For more inputs, chain multiple 2-input gates
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::AndGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::AndGate.to_verilog
      expect(verilog).to include('module and_gate')
      expect(verilog).to include('assign y')
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::AndGate.to_verilog
        behavior = RHDL::HDL::AndGate.new

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
          tc.each { |k, v| behavior.set_input(k, v) }
          behavior.propagate
          vectors << {
            inputs: tc,
            expected: { y: behavior.get_output(:y) }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'and_gate',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/and_gate'
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
    let(:component) { RHDL::HDL::AndGate.new('and_gate') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'and_gate') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('and_gate.a0', 'and_gate.a1')
      expect(ir.outputs.keys).to include('and_gate.y')
      expect(ir.gates.length).to eq(1)
      expect(ir.gates.first.type).to eq(:and)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module and_gate')
      expect(verilog).to include('input a0')
      expect(verilog).to include('input a1')
      expect(verilog).to include('output y')
      expect(verilog).to include('and g0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 0, a1: 1 }, expected: { y: 0 } },
          { inputs: { a0: 1, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/and_gate')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
