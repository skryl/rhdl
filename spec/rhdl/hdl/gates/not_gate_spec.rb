require 'spec_helper'

RSpec.describe RHDL::HDL::NotGate do
  let(:gate) { RHDL::HDL::NotGate.new }

  describe 'simulation' do
    it 'inverts the input' do
      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::NotGate.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::NotGate.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)
      expect(ir.assigns.length).to be >= 1
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::NotGate.to_verilog
      expect(verilog).to include('module not_gate')
      expect(verilog).to include('input a')
      expect(verilog).to include('output y')
      expect(verilog).to include('assign y')
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::NotGate.to_verilog
        behavior = RHDL::HDL::NotGate.new

        inputs = { a: 1 }
        outputs = { y: 1 }

        vectors = []
        test_cases = [
          { a: 0 },
          { a: 1 }
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
          module_name: 'not_gate',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/not_gate'
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
    let(:component) { RHDL::HDL::NotGate.new('not_gate') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'not_gate') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('not_gate.a')
      expect(ir.outputs.keys).to include('not_gate.y')
      expect(ir.gates.length).to eq(1)
      expect(ir.gates.first.type).to eq(:not)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module not_gate')
      expect(verilog).to include('input a')
      expect(verilog).to include('output y')
      expect(verilog).to include('not g0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0 }, expected: { y: 1 } },
          { inputs: { a: 1 }, expected: { y: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/not_gate')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
