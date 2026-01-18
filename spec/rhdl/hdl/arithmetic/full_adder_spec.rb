require 'spec_helper'

RSpec.describe RHDL::HDL::FullAdder do
  describe 'simulation' do
    it 'adds two bits with carry in' do
      adder = RHDL::HDL::FullAdder.new

      # 1 + 1 + 1 = 11
      adder.set_input(:a, 1)
      adder.set_input(:b, 1)
      adder.set_input(:cin, 1)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(1)
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::FullAdder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::FullAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # a, b, cin, sum, cout
      expect(ir.assigns.length).to be >= 2
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::FullAdder.to_verilog
      expect(verilog).to include('module full_adder')
      expect(verilog).to include('input a')
      expect(verilog).to include('input b')
      expect(verilog).to include('input cin')
      expect(verilog).to include('output sum')
      expect(verilog).to include('output cout')
      expect(verilog).to include('assign sum')
      expect(verilog).to include('assign cout')
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::FullAdder.to_verilog
        behavior = RHDL::HDL::FullAdder.new

        inputs = { a: 1, b: 1, cin: 1 }
        outputs = { sum: 1, cout: 1 }

        vectors = []
        test_cases = [
          { a: 0, b: 0, cin: 0 },
          { a: 0, b: 0, cin: 1 },
          { a: 0, b: 1, cin: 0 },
          { a: 0, b: 1, cin: 1 },
          { a: 1, b: 0, cin: 0 },
          { a: 1, b: 0, cin: 1 },
          { a: 1, b: 1, cin: 0 },
          { a: 1, b: 1, cin: 1 },
        ]

        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.set_input(:b, tc[:b])
          behavior.set_input(:cin, tc[:cin])
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
          module_name: 'full_adder',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/full_adder'
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
    let(:component) { RHDL::HDL::FullAdder.new('full_adder') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'full_adder') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('full_adder.a', 'full_adder.b', 'full_adder.cin')
      expect(ir.outputs.keys).to include('full_adder.sum', 'full_adder.cout')
      expect(ir.gates.length).to eq(5)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module full_adder')
      expect(verilog).to include('input cin')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0, cin: 0 }, expected: { sum: 0, cout: 0 } },
          { inputs: { a: 0, b: 0, cin: 1 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 0, b: 1, cin: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 0, b: 1, cin: 1 }, expected: { sum: 0, cout: 1 } },
          { inputs: { a: 1, b: 0, cin: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 0, cin: 1 }, expected: { sum: 0, cout: 1 } },
          { inputs: { a: 1, b: 1, cin: 0 }, expected: { sum: 0, cout: 1 } },
          { inputs: { a: 1, b: 1, cin: 1 }, expected: { sum: 1, cout: 1 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/full_adder')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
