require 'spec_helper'

RSpec.describe RHDL::HDL::Subtractor do
  describe 'simulation' do
    it 'subtracts 8-bit numbers' do
      sub = RHDL::HDL::Subtractor.new(nil, width: 8)

      # 100 - 50 = 50
      sub.set_input(:a, 100)
      sub.set_input(:b, 50)
      sub.set_input(:bin, 0)
      sub.propagate
      expect(sub.get_output(:diff)).to eq(50)
      expect(sub.get_output(:bout)).to eq(0)
    end

    it 'handles borrow' do
      sub = RHDL::HDL::Subtractor.new(nil, width: 8)

      # 50 - 100 = -50 (with borrow)
      sub.set_input(:a, 50)
      sub.set_input(:b, 100)
      sub.set_input(:bin, 0)
      sub.propagate
      expect(sub.get_output(:diff)).to eq(206)  # 256 - 50
      expect(sub.get_output(:bout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Subtractor.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Subtractor.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, b, bin, diff, bout, overflow
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Subtractor.to_verilog
      expect(verilog).to include('module subtractor')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] diff')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Subtractor.new('sub', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'sub') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('sub.a', 'sub.b', 'sub.bin')
      expect(ir.outputs.keys).to include('sub.diff', 'sub.bout', 'sub.overflow')
      expect(ir.gates.length).to be > 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module sub')
      expect(verilog).to include('output [3:0] diff')
      expect(verilog).to include('output bout')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 5, b: 3, bin: 0 }, expected: { diff: 2, bout: 0, overflow: 0 } },
          { inputs: { a: 0, b: 0, bin: 0 }, expected: { diff: 0, bout: 0, overflow: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/sub')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
