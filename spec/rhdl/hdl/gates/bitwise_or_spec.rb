require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseOr do
  describe 'simulation' do
    it 'performs 8-bit OR' do
      gate = RHDL::HDL::BitwiseOr.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.set_input(:b, 0b00001111)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b11111111)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseOr.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitwiseOr.to_verilog
      expect(verilog).to include('assign y')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::BitwiseOr.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit bitwise_or')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('input b')
      expect(firrtl).to include('output y')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        test_vectors = [
          { inputs: { a: 0b11110000, b: 0b00001111 }, expected: { y: 0b11111111 } },
          { inputs: { a: 0b00000000, b: 0b00000000 }, expected: { y: 0b00000000 } },
          { inputs: { a: 0b10101010, b: 0b01010101 }, expected: { y: 0b11111111 } }
        ]

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::BitwiseOr,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/bitwise_or'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::BitwiseOr.new('bitwise_or', width: 4) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'bitwise_or') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('bitwise_or.a', 'bitwise_or.b')
      expect(ir.outputs.keys).to include('bitwise_or.y')
      expect(ir.gates.length).to eq(4)
      expect(ir.gates.all? { |g| g.type == :or }).to be(true)
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0000, b: 0b0000 }, expected: { y: 0b0000 } },
          { inputs: { a: 0b1111, b: 0b0000 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b1010, b: 0b0101 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b0100, b: 0b0010 }, expected: { y: 0b0110 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_or')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
