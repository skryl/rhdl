require 'spec_helper'

RSpec.describe RHDL::HDL::XnorGate do
  describe 'simulation' do
    it 'performs XNOR operation' do
      gate = RHDL::HDL::XnorGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::XnorGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::XnorGate.to_verilog
      expect(verilog).to include('assign y')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::XnorGate.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit xnor_gate')
      expect(firrtl).to include('input a0')
      expect(firrtl).to include('output y')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        test_vectors = [
          { inputs: { a0: 0, a1: 0 }, expected: { y: 1 } },
          { inputs: { a0: 0, a1: 1 }, expected: { y: 0 } },
          { inputs: { a0: 1, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
        ]

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::XnorGate,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/xnor_gate'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::XnorGate.new('xnor_gate') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'xnor_gate') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('xnor_gate.a0', 'xnor_gate.a1')
      expect(ir.outputs.keys).to include('xnor_gate.y')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module xnor_gate')
      expect(verilog).to match(/xnor g0|xor g0/)
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a0: 0, a1: 0 }, expected: { y: 1 } },
          { inputs: { a0: 0, a1: 1 }, expected: { y: 0 } },
          { inputs: { a0: 1, a1: 0 }, expected: { y: 0 } },
          { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/xnor_gate')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results' do
        test_cases = [
          { a0: 0, a1: 0 },
          { a0: 0, a1: 1 },
          { a0: 1, a1: 0 },
          { a0: 1, a1: 1 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::XnorGate,
          'xnor_gate',
          test_cases,
          base_dir: 'tmp/netlist_comparison/xnor_gate',
          has_clock: false
        )
      end
    end
  end
end
