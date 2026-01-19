require 'spec_helper'

RSpec.describe RHDL::HDL::DFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:dff) { RHDL::HDL::DFlipFlop.new }

  before do
    dff.set_input(:rst, 0)
    dff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'captures input on rising edge' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)
      expect(dff.get_output(:qn)).to eq(0)
    end

    it 'holds value when enable is low' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      dff.set_input(:en, 0)
      dff.set_input(:d, 0)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)  # Still 1
    end

    it 'resets on reset signal' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      dff.set_input(:rst, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::DFlipFlop.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::DFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # d, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::DFlipFlop.to_verilog
      expect(verilog).to include('module d_flip_flop')
      expect(verilog).to include('input d')
      expect(verilog).to include('output q')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::DFlipFlop.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit d_flip_flop')
      expect(firrtl).to include('input d')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('output q')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        behavior = RHDL::HDL::DFlipFlop.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)

        test_vectors = []
        test_cases = [
          { d: 1, rst: 0, en: 1 },
          { d: 0, rst: 0, en: 1 },
          { d: 1, rst: 0, en: 0 },
          { d: 0, rst: 1, en: 1 },
        ]

        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate
          test_vectors << {
            inputs: { d: tc[:d], clk: 0, rst: tc[:rst], en: tc[:en] },
            expected: { q: behavior.get_output(:q), qn: behavior.get_output(:qn) }
          }
        end

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::DFlipFlop,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/d_flip_flop',
          has_clock: true
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::DFlipFlop.to_verilog
        behavior = RHDL::HDL::DFlipFlop.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)

        inputs = { d: 1, clk: 1, rst: 1, en: 1 }
        outputs = { q: 1, qn: 1 }

        vectors = []
        test_cases = [
          { d: 1, rst: 0, en: 1 },
          { d: 0, rst: 0, en: 1 },
          { d: 1, rst: 0, en: 0 },
          { d: 0, rst: 1, en: 1 },
        ]

        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate
          vectors << {
            inputs: { d: tc[:d], clk: 0, rst: tc[:rst], en: tc[:en] },
            expected: { q: behavior.get_output(:q), qn: behavior.get_output(:qn) }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'd_flip_flop',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/d_flip_flop',
          has_clock: true
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:q]).to eq(vec[:expected][:q]),
            "Vector #{idx}: expected q=#{vec[:expected][:q]}, got #{result[:results][idx][:q]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::DFlipFlop.new('dff') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'dff') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dff.d', 'dff.clk', 'dff.rst', 'dff.en')
      expect(ir.outputs.keys).to include('dff.q', 'dff.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module dff')
      expect(verilog).to include('input d')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::DFlipFlop.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)

        test_cases = [
          { d: 1, rst: 0, en: 1 },  # capture 1
          { d: 0, rst: 0, en: 1 },  # capture 0
          { d: 1, rst: 0, en: 0 },  # hold (en=0)
          { d: 0, rst: 1, en: 1 },  # reset
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavior.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'dff')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:q]).to eq(expected[:q]),
            "Cycle #{idx}: expected q=#{expected[:q]}, got #{result[:results][idx][:q]}"
        end
      end
    end
  end
end
