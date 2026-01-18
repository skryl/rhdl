require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseXor do
  describe 'simulation' do
    it 'performs 8-bit XOR' do
      gate = RHDL::HDL::BitwiseXor.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.set_input(:b, 0b10101010)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b01011010)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseXor.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitwiseXor.to_verilog
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::BitwiseXor.new('bitwise_xor', width: 4) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'bitwise_xor') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('bitwise_xor.a', 'bitwise_xor.b')
      expect(ir.outputs.keys).to include('bitwise_xor.y')
      expect(ir.gates.length).to eq(4)
      expect(ir.gates.all? { |g| g.type == :xor }).to be(true)
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0000, b: 0b0000 }, expected: { y: 0b0000 } },
          { inputs: { a: 0b1111, b: 0b0000 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b1111, b: 0b1111 }, expected: { y: 0b0000 } },
          { inputs: { a: 0b1010, b: 0b0110 }, expected: { y: 0b1100 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_xor')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
