require 'spec_helper'

RSpec.describe RHDL::HDL::Comparator do
  let(:cmp) { RHDL::HDL::Comparator.new(nil, width: 8) }

  describe 'simulation' do
    it 'compares equal values' do
      cmp.set_input(:a, 42)
      cmp.set_input(:b, 42)
      cmp.set_input(:signed_cmp, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(1)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares greater than' do
      cmp.set_input(:a, 50)
      cmp.set_input(:b, 30)
      cmp.set_input(:signed_cmp, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(1)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares less than' do
      cmp.set_input(:a, 20)
      cmp.set_input(:b, 40)
      cmp.set_input(:signed_cmp, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(1)
    end

    it 'handles signed comparison with negative numbers' do
      # -1 (0xFF) vs 1 - signed comparison should show -1 < 1
      cmp.set_input(:a, 0xFF)  # -1 in signed
      cmp.set_input(:b, 1)
      cmp.set_input(:signed_cmp, 1)
      cmp.propagate

      expect(cmp.get_output(:lt)).to eq(1)
      expect(cmp.get_output(:gt)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Comparator.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Comparator.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(8)  # a, b, signed_cmp, eq, gt, lt, gte, lte
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Comparator.to_verilog
      expect(verilog).to include('module comparator')
      expect(verilog).to include('input [7:0] a')
    end

    context 'iverilog behavioral simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::Comparator.to_verilog
        behavioral = RHDL::HDL::Comparator.new(nil, width: 8)

        inputs = { a: 8, b: 8, signed_cmp: 1 }
        outputs = { eq: 1, gt: 1, lt: 1, gte: 1, lte: 1 }

        vectors = []
        test_cases = [
          { a: 42, b: 42, signed_cmp: 0 },   # equal
          { a: 50, b: 30, signed_cmp: 0 },   # greater
          { a: 20, b: 40, signed_cmp: 0 },   # less
          { a: 0, b: 0, signed_cmp: 0 },     # zero equal
          { a: 255, b: 1, signed_cmp: 0 },   # unsigned max > 1
          { a: 255, b: 1, signed_cmp: 1 },   # signed -1 < 1
          { a: 128, b: 127, signed_cmp: 0 }, # unsigned 128 > 127
          { a: 128, b: 127, signed_cmp: 1 }, # signed -128 < 127
        ]

        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.set_input(:b, tc[:b])
          behavioral.set_input(:signed_cmp, tc[:signed_cmp])
          behavioral.propagate
          vectors << {
            inputs: tc,
            expected: {
              eq: behavioral.get_output(:eq),
              gt: behavioral.get_output(:gt),
              lt: behavioral.get_output(:lt),
              gte: behavioral.get_output(:gte),
              lte: behavioral.get_output(:lte)
            }
          }
        end

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 'comparator',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/comparator'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:eq]).to eq(vec[:expected][:eq]),
            "Vector #{idx}: expected eq=#{vec[:expected][:eq]}, got #{result[:results][idx][:eq]}"
          expect(result[:results][idx][:gt]).to eq(vec[:expected][:gt]),
            "Vector #{idx}: expected gt=#{vec[:expected][:gt]}, got #{result[:results][idx][:gt]}"
          expect(result[:results][idx][:lt]).to eq(vec[:expected][:lt]),
            "Vector #{idx}: expected lt=#{vec[:expected][:lt]}, got #{result[:results][idx][:lt]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Comparator.new('cmp', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'cmp') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('cmp.a', 'cmp.b', 'cmp.signed_cmp')
      expect(ir.outputs.keys).to include('cmp.eq', 'cmp.lt', 'cmp.gt', 'cmp.gte', 'cmp.lte')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module cmp')
      expect(verilog).to include('output eq')
      expect(verilog).to include('output lt')
      expect(verilog).to include('output gt')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 5, b: 5, signed_cmp: 0 }, expected: { eq: 1, lt: 0, gt: 0, gte: 1, lte: 1 } },
          { inputs: { a: 3, b: 7, signed_cmp: 0 }, expected: { eq: 0, lt: 1, gt: 0, gte: 0, lte: 1 } },
          { inputs: { a: 10, b: 4, signed_cmp: 0 }, expected: { eq: 0, lt: 0, gt: 1, gte: 1, lte: 0 } },
          { inputs: { a: 0, b: 0, signed_cmp: 0 }, expected: { eq: 1, lt: 0, gt: 0, gte: 1, lte: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/cmp')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
