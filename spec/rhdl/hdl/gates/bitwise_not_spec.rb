require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseNot do
  describe 'simulation' do
    it 'performs 8-bit NOT' do
      gate = RHDL::HDL::BitwiseNot.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b00001111)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseNot.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitwiseNot.to_verilog
      expect(verilog).to include('assign y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::BitwiseNot.new('bitwise_not', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bitwise_not') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('bitwise_not.a')
      expect(ir.outputs.keys).to include('bitwise_not.y')
      expect(ir.gates.length).to eq(4)
      expect(ir.gates.all? { |g| g.type == :not }).to be(true)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module bitwise_not')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [3:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0000 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b1111 }, expected: { y: 0b0000 } },
          { inputs: { a: 0b1010 }, expected: { y: 0b0101 } },
          { inputs: { a: 0b0101 }, expected: { y: 0b1010 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_not')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
