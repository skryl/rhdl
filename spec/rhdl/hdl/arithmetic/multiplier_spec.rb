require 'spec_helper'

RSpec.describe RHDL::HDL::Multiplier do
  describe 'simulation' do
    it 'multiplies 8-bit numbers' do
      mult = RHDL::HDL::Multiplier.new(nil, width: 8)

      mult.set_input(:a, 10)
      mult.set_input(:b, 20)
      mult.propagate
      expect(mult.get_output(:product)).to eq(200)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Multiplier.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Multiplier.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, b, product
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Multiplier.to_verilog
      expect(verilog).to include('module multiplier')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [15:0] product')
      expect(verilog).to include('assign product')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::Multiplier.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit multiplier')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('input b')
      expect(firrtl).to include('output product')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::Multiplier,
          base_dir: 'tmp/circt_test/multiplier'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Multiplier.new('mult', width: 8) }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mult') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mult.a', 'mult.b')
      expect(ir.outputs.keys).to include('mult.product')
      # Multiplier has many gates for array multiplication
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mult')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [15:0] product')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::Multiplier.new(nil, width: 8)

        test_cases = [
          { a: 10, b: 20 },   # 200
          { a: 15, b: 15 },   # 225
          { a: 0, b: 100 },   # 0
          { a: 255, b: 2 },   # 510
          { a: 1, b: 1 },     # 1
          { a: 16, b: 16 },   # 256
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.set_input(:b, tc[:b])
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { product: behavior.get_output(:product) }
        end

        base_dir = File.join('tmp', 'iverilog', 'mult')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:product]).to eq(expected[:product]),
            "Cycle #{idx}: expected product=#{expected[:product]}, got #{result[:results][idx][:product]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results' do
        test_cases = [
          { a: 10, b: 20 },
          { a: 15, b: 15 },
          { a: 0, b: 100 },
          { a: 3, b: 7 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::Multiplier,
          'multiplier',
          test_cases,
          base_dir: 'tmp/netlist_comparison/multiplier',
          has_clock: false
        )
      end
    end
  end
end
