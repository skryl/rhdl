require 'spec_helper'

RSpec.describe RHDL::HDL::TFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:tff) { RHDL::HDL::TFlipFlop.new }

  before do
    tff.set_input(:rst, 0)
    tff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'toggles on T=1' do
      tff.set_input(:t, 1)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(0)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)
    end

    it 'holds on T=0' do
      tff.set_input(:t, 1)
      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)

      tff.set_input(:t, 0)
      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::TFlipFlop.behavior_defined? || RHDL::HDL::TFlipFlop.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::TFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # t, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::TFlipFlop.to_verilog
      expect(verilog).to include('module t_flip_flop')
      expect(verilog).to include('input t')
      expect(verilog).to match(/output.*q/)
    end

    context 'iverilog behavioral simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::TFlipFlop.to_verilog
        behavioral = RHDL::HDL::TFlipFlop.new
        behavioral.set_input(:rst, 0)
        behavioral.set_input(:en, 1)

        inputs = { t: 1, clk: 1, rst: 1, en: 1 }
        outputs = { q: 1, qn: 1 }

        vectors = []
        # Start with reset cycle to initialize flip-flop (avoids X propagation)
        test_cases = [
          { t: 0, rst: 1, en: 1 },  # reset (initialize to 0)
          { t: 1, rst: 0, en: 1 },  # toggle to 1
          { t: 1, rst: 0, en: 1 },  # toggle to 0
          { t: 1, rst: 0, en: 1 },  # toggle to 1
          { t: 0, rst: 0, en: 1 },  # hold
          { t: 1, rst: 0, en: 0 },  # hold (en=0)
        ]

        test_cases.each do |tc|
          behavioral.set_input(:t, tc[:t])
          behavioral.set_input(:rst, tc[:rst])
          behavioral.set_input(:en, tc[:en])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate
          vectors << {
            inputs: { t: tc[:t], rst: tc[:rst], en: tc[:en] },
            expected: { q: behavioral.get_output(:q), qn: behavioral.get_output(:qn) }
          }
        end

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 't_flip_flop',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/t_flip_flop',
          has_clock: true
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:q]).to eq(vec[:expected][:q]),
            "Vector #{idx}: expected q=#{vec[:expected][:q]}, got #{result[:results][idx][:q]}"
          expect(result[:results][idx][:qn]).to eq(vec[:expected][:qn]),
            "Vector #{idx}: expected qn=#{vec[:expected][:qn]}, got #{result[:results][idx][:qn]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::TFlipFlop.new('tff') }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'tff') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('tff.t', 'tff.clk', 'tff.rst', 'tff.en')
      expect(ir.outputs.keys).to include('tff.q', 'tff.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module tff')
      expect(verilog).to include('input t')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::TFlipFlop.new
        behavioral.set_input(:rst, 0)
        behavioral.set_input(:en, 1)

        test_cases = [
          { t: 1, rst: 0, en: 1 },  # toggle to 1
          { t: 1, rst: 0, en: 1 },  # toggle to 0
          { t: 1, rst: 0, en: 1 },  # toggle to 1
          { t: 0, rst: 0, en: 1 },  # hold
          { t: 1, rst: 1, en: 1 },  # reset
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:t, tc[:t])
          behavioral.set_input(:rst, tc[:rst])
          behavioral.set_input(:en, tc[:en])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavioral.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'tff')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:q]).to eq(expected[:q]),
            "Cycle #{idx}: expected q=#{expected[:q]}, got #{result[:results][idx][:q]}"
        end
      end
    end
  end
end
