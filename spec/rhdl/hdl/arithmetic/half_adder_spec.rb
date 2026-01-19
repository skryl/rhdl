require 'spec_helper'

RSpec.describe RHDL::HDL::HalfAdder do
  describe 'simulation' do
    it 'adds two bits' do
      adder = RHDL::HDL::HalfAdder.new

      # 0 + 0 = 0
      adder.set_input(:a, 0)
      adder.set_input(:b, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(0)
      expect(adder.get_output(:cout)).to eq(0)

      # 1 + 0 = 1
      adder.set_input(:a, 1)
      adder.set_input(:b, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(1)
      expect(adder.get_output(:cout)).to eq(0)

      # 1 + 1 = 10
      adder.set_input(:a, 1)
      adder.set_input(:b, 1)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(0)
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::HalfAdder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::HalfAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, b, sum, cout
      expect(ir.assigns.length).to be >= 2
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::HalfAdder.to_verilog
      expect(verilog).to include('module half_adder')
      expect(verilog).to include('input a')
      expect(verilog).to include('input b')
      expect(verilog).to include('output sum')
      expect(verilog).to include('output cout')
      expect(verilog).to include('assign sum')
      expect(verilog).to include('assign cout')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::HalfAdder.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit half_adder')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('input b')
      expect(firrtl).to include('output sum')
      expect(firrtl).to include('output cout')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        test_vectors = [
          { inputs: { a: 0, b: 0 }, expected: { sum: 0, cout: 0 } },
          { inputs: { a: 0, b: 1 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 1 }, expected: { sum: 0, cout: 1 } }
        ]

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::HalfAdder,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/half_adder'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::HalfAdder.to_verilog
        behavior = RHDL::HDL::HalfAdder.new

        inputs = { a: 1, b: 1 }
        outputs = { sum: 1, cout: 1 }

        vectors = []
        test_cases = [
          { a: 0, b: 0 },
          { a: 0, b: 1 },
          { a: 1, b: 0 },
          { a: 1, b: 1 },
        ]

        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.set_input(:b, tc[:b])
          behavior.propagate
          vectors << {
            inputs: tc,
            expected: {
              sum: behavior.get_output(:sum),
              cout: behavior.get_output(:cout)
            }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'half_adder',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/half_adder'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:sum]).to eq(vec[:expected][:sum]),
            "Vector #{idx}: expected sum=#{vec[:expected][:sum]}, got #{result[:results][idx][:sum]}"
          expect(result[:results][idx][:cout]).to eq(vec[:expected][:cout]),
            "Vector #{idx}: expected cout=#{vec[:expected][:cout]}, got #{result[:results][idx][:cout]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::HalfAdder.new('half_adder') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'half_adder') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('half_adder.a', 'half_adder.b')
      expect(ir.outputs.keys).to include('half_adder.sum', 'half_adder.cout')
      expect(ir.gates.length).to eq(2)
      gate_types = ir.gates.map(&:type).sort
      expect(gate_types).to eq([:and, :xor])
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module half_adder')
      expect(verilog).to include('input a')
      expect(verilog).to include('input b')
      expect(verilog).to include('output sum')
      expect(verilog).to include('output cout')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0 }, expected: { sum: 0, cout: 0 } },
          { inputs: { a: 0, b: 1 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 1 }, expected: { sum: 0, cout: 1 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/half_adder')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
