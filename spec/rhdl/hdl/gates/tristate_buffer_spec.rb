require 'spec_helper'

RSpec.describe RHDL::HDL::TristateBuffer do
  describe 'simulation' do
    it 'passes input to output when enabled' do
      gate = RHDL::HDL::TristateBuffer.new

      gate.set_input(:a, 1)
      gate.set_input(:en, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end

    it 'outputs 0 when disabled (synthesizable behavior)' do
      gate = RHDL::HDL::TristateBuffer.new

      gate.set_input(:a, 1)
      gate.set_input(:en, 0)
      gate.propagate
      # Note: For synthesis compatibility, disabled outputs 0 instead of high-Z
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::TristateBuffer.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::TristateBuffer.to_verilog
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::TristateBuffer.new('tribuf') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'tribuf') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('tribuf.a', 'tribuf.en')
      expect(ir.outputs.keys).to include('tribuf.y')
      # Tristate buffer implemented as mux
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module tribuf')
      expect(verilog).to include('input a')
      expect(verilog).to include('input en')
      expect(verilog).to include('output y')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::TristateBuffer.new

        test_cases = [
          { a: 1, en: 1 },  # enabled, pass 1
          { a: 0, en: 1 },  # enabled, pass 0
          { a: 1, en: 0 },  # disabled, output 0
          { a: 0, en: 0 },  # disabled, output 0
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.set_input(:en, tc[:en])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { y: behavioral.get_output(:y) }
        end

        base_dir = File.join('tmp', 'iverilog', 'tribuf')
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
