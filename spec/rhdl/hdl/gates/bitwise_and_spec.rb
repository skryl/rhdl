require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseAnd do
  describe 'simulation' do
    it 'performs 8-bit AND' do
      gate = RHDL::HDL::BitwiseAnd.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.set_input(:b, 0b10101010)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b10100000)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseAnd.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog with correct width' do
      verilog = RHDL::HDL::BitwiseAnd.to_verilog
      expect(verilog).to include('[7:0]')  # 8-bit signals
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::BitwiseAnd.new('bitwise_and', width: 4) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'bitwise_and') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('bitwise_and.a', 'bitwise_and.b')
      expect(ir.outputs.keys).to include('bitwise_and.y')
      expect(ir.gates.length).to eq(4)
      expect(ir.gates.all? { |g| g.type == :and }).to be(true)
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b1111, b: 0b0000 }, expected: { y: 0b0000 } },
          { inputs: { a: 0b1111, b: 0b1111 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b1010, b: 0b1100 }, expected: { y: 0b1000 } },
          { inputs: { a: 0b0101, b: 0b0011 }, expected: { y: 0b0001 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_and')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
