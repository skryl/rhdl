require 'spec_helper'

RSpec.describe RHDL::HDL::Buffer do
  let(:gate) { RHDL::HDL::Buffer.new }

  describe 'simulation' do
    it 'passes input to output' do
      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Buffer.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Buffer.to_verilog
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Buffer.new('buffer') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'buffer') }

    it 'generates correct IR structure' do
      expect(ir.gates.length).to eq(1)
      expect(ir.gates.first.type).to eq(:buf)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('buf g0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0 }, expected: { y: 0 } },
          { inputs: { a: 1 }, expected: { y: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/buffer')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
