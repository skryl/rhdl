require 'spec_helper'

RSpec.describe RHDL::HDL::JKFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:jkff) { RHDL::HDL::JKFlipFlop.new }

  before do
    jkff.set_input(:rst, 0)
    jkff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'holds state when J=0 and K=0' do
      jkff.set_input(:j, 1)
      jkff.set_input(:k, 0)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)

      jkff.set_input(:j, 0)
      jkff.set_input(:k, 0)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)  # Hold
    end

    it 'resets when J=0 and K=1' do
      jkff.set_input(:j, 1)
      jkff.set_input(:k, 0)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)

      jkff.set_input(:j, 0)
      jkff.set_input(:k, 1)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(0)
    end

    it 'sets when J=1 and K=0' do
      jkff.set_input(:j, 1)
      jkff.set_input(:k, 0)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)
      expect(jkff.get_output(:qn)).to eq(0)
    end

    it 'toggles when J=1 and K=1' do
      jkff.set_input(:j, 1)
      jkff.set_input(:k, 1)

      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)

      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(0)

      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)
    end

    it 'resets on reset signal' do
      jkff.set_input(:j, 1)
      jkff.set_input(:k, 0)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(1)

      jkff.set_input(:rst, 1)
      clock_cycle(jkff)
      expect(jkff.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::JKFlipFlop.behavior_defined? || RHDL::HDL::JKFlipFlop.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::JKFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # j, k, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::JKFlipFlop.to_verilog
      expect(verilog).to include('module jk_flip_flop')
      expect(verilog).to include('input j')
      expect(verilog).to include('input k')
      expect(verilog).to match(/output.*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::JKFlipFlop.new('jkff') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'jkff') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('jkff.j', 'jkff.k', 'jkff.clk', 'jkff.rst', 'jkff.en')
      expect(ir.outputs.keys).to include('jkff.q', 'jkff.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module jkff')
      expect(verilog).to include('input j')
      expect(verilog).to include('input k')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::JKFlipFlop.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)

        test_cases = [
          { j: 1, k: 0, rst: 0, en: 1 },  # set
          { j: 0, k: 0, rst: 0, en: 1 },  # hold
          { j: 0, k: 1, rst: 0, en: 1 },  # reset
          { j: 1, k: 1, rst: 0, en: 1 },  # toggle
          { j: 1, k: 1, rst: 0, en: 1 },  # toggle
          { j: 0, k: 0, rst: 1, en: 1 },  # reset signal
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:j, tc[:j])
          behavior.set_input(:k, tc[:k])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavior.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'jkff')
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
