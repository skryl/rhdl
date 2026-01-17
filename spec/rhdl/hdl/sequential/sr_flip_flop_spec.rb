require 'spec_helper'

RSpec.describe RHDL::HDL::SRFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:srff) { RHDL::HDL::SRFlipFlop.new }

  before do
    srff.set_input(:rst, 0)
    srff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'holds state when S=0 and R=0' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:s, 0)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)  # Hold
    end

    it 'resets when S=0 and R=1' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:s, 0)
      srff.set_input(:r, 1)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(0)
      expect(srff.get_output(:qn)).to eq(1)
    end

    it 'sets when S=1 and R=0' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)
      expect(srff.get_output(:qn)).to eq(0)
    end

    it 'handles invalid state S=1 R=1 by defaulting to 0' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:s, 1)
      srff.set_input(:r, 1)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(0)  # Invalid defaults to 0
    end

    it 'resets on reset signal' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:rst, 1)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::SRFlipFlop.behavior_defined? || RHDL::HDL::SRFlipFlop.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::SRFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # s, r, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::SRFlipFlop.to_verilog
      expect(verilog).to include('module sr_flip_flop')
      expect(verilog).to include('input s')
      expect(verilog).to include('input r')
      expect(verilog).to match(/output.*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::SRFlipFlop.new('srff') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'srff') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('srff.s', 'srff.r', 'srff.clk', 'srff.rst', 'srff.en')
      expect(ir.outputs.keys).to include('srff.q', 'srff.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module srff')
      expect(verilog).to include('input s')
      expect(verilog).to include('input r')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::SRFlipFlop.new
        behavioral.set_input(:rst, 0)
        behavioral.set_input(:en, 1)

        test_cases = [
          { s: 1, r: 0, rst: 0, en: 1 },  # set
          { s: 0, r: 0, rst: 0, en: 1 },  # hold
          { s: 0, r: 1, rst: 0, en: 1 },  # reset (K)
          { s: 1, r: 0, rst: 0, en: 1 },  # set again
          { s: 0, r: 0, rst: 1, en: 1 },  # reset signal
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:s, tc[:s])
          behavioral.set_input(:r, tc[:r])
          behavioral.set_input(:rst, tc[:rst])
          behavioral.set_input(:en, tc[:en])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavioral.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'srff')
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
