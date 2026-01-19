require 'spec_helper'

RSpec.describe RHDL::HDL::XorGate do
  describe 'simulation' do
    it 'performs XOR operation' do
      gate = RHDL::HDL::XorGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::XorGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::XorGate.to_verilog
      expect(verilog).to include('assign y')
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::XorGate.to_verilog
        behavior = RHDL::HDL::XorGate.new

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
          module_name: 'xor_gate',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/xor_gate'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:y]).to eq(vec[:expected][:y]),
            "Vector #{idx}: expected y=#{vec[:expected][:y]}, got #{result[:results][idx][:y]}"
        end
      end
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::XorGate.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit xor_gate')
      expect(firrtl).to include('input a0')
      expect(firrtl).to include('output y')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        test_vectors = [
          { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 0, a1: 1 }, expected: { y: 1 } },
          { inputs: { a0: 1, a1: 0 }, expected: { y: 1 } },
          { inputs: { a0: 1, a1: 1 }, expected: { y: 0 } }
        ]

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::XorGate,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/xor_gate'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::XorGate.new('xor_gate') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'xor_gate') }

    it 'generates correct IR structure' do
      expect(ir.gates.length).to eq(1)
      expect(ir.gates.first.type).to eq(:xor)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('xor g0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 0, a1: 1 }, expected: { y: 1 } },
          { inputs: { a0: 1, a1: 0 }, expected: { y: 1 } },
          { inputs: { a0: 1, a1: 1 }, expected: { y: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/xor_gate')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
