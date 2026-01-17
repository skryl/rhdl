require 'spec_helper'

RSpec.describe RHDL::HDL::IncDec do
  describe 'simulation' do
    it 'increments when inc=1' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 100)
      incdec.set_input(:inc, 1)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(101)
    end

    it 'decrements when inc=0' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 100)
      incdec.set_input(:inc, 0)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(99)
    end

    it 'handles overflow on increment' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 255)
      incdec.set_input(:inc, 1)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(0)
      expect(incdec.get_output(:cout)).to eq(1)
    end

    it 'handles underflow on decrement' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 0)
      incdec.set_input(:inc, 0)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(255)
      expect(incdec.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::IncDec.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::IncDec.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, inc, result, cout
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::IncDec.to_verilog
      expect(verilog).to include('module inc_dec')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] result')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::IncDec.new('incdec', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'incdec') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('incdec.a', 'incdec.inc')
      expect(ir.outputs.keys).to include('incdec.result', 'incdec.cout')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module incdec')
      expect(verilog).to include('input inc')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 5, inc: 1 }, expected: { result: 6, cout: 0 } },
          { inputs: { a: 5, inc: 0 }, expected: { result: 4, cout: 0 } },
          { inputs: { a: 0, inc: 1 }, expected: { result: 1, cout: 0 } },
          { inputs: { a: 0, inc: 0 }, expected: { result: 15, cout: 1 } },
          { inputs: { a: 15, inc: 1 }, expected: { result: 0, cout: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/incdec')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
