require 'spec_helper'

RSpec.describe RHDL::HDL::RippleCarryAdder do
  describe 'simulation' do
    it 'adds 8-bit numbers' do
      adder = RHDL::HDL::RippleCarryAdder.new(nil, width: 8)

      # 100 + 50 = 150
      adder.set_input(:a, 100)
      adder.set_input(:b, 50)
      adder.set_input(:cin, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(150)
      expect(adder.get_output(:cout)).to eq(0)

      # 200 + 100 = 300 (overflow)
      adder.set_input(:a, 200)
      adder.set_input(:b, 100)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(44)  # 300 & 0xFF
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::RippleCarryAdder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::RippleCarryAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, b, cin, sum, cout, overflow
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::RippleCarryAdder.to_verilog
      expect(verilog).to include('module ripple_carry_adder')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [7:0] sum')
      expect(verilog).to include('assign sum')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::RippleCarryAdder.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit ripple_carry_adder')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('input b')
      expect(firrtl).to include('output sum')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::RippleCarryAdder,
          base_dir: 'tmp/circt_test/ripple_carry_adder'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::RippleCarryAdder.new('rca', width: 4) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'rca') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('rca.a', 'rca.b', 'rca.cin')
      expect(ir.outputs.keys).to include('rca.sum', 'rca.cout', 'rca.overflow')
      expect(ir.gates.length).to be > 0
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module rca')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('input [3:0] b')
      expect(verilog).to include('output [3:0] sum')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0, cin: 0 }, expected: { sum: 0, cout: 0, overflow: 0 } },
          { inputs: { a: 1, b: 1, cin: 0 }, expected: { sum: 2, cout: 0, overflow: 0 } },
          { inputs: { a: 15, b: 1, cin: 0 }, expected: { sum: 0, cout: 1, overflow: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/rca')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
