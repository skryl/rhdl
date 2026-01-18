require 'spec_helper'

RSpec.describe RHDL::HDL::ProgramCounter do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:pc) { RHDL::HDL::ProgramCounter.new }

  before do
    pc.set_input(:rst, 0)
    pc.set_input(:en, 1)
    pc.set_input(:load, 0)
    pc.set_input(:inc, 1)
  end

  describe 'simulation' do
    it 'increments by 1 by default' do
      expect(pc.get_output(:q)).to eq(0)

      clock_cycle(pc)
      expect(pc.get_output(:q)).to eq(1)

      clock_cycle(pc)
      expect(pc.get_output(:q)).to eq(2)
    end

    it 'loads a new address' do
      pc.set_input(:load, 1)
      pc.set_input(:d, 0x1000)
      clock_cycle(pc)

      expect(pc.get_output(:q)).to eq(0x1000)
    end

    it 'increments by variable amount' do
      pc.set_input(:inc, 3)
      clock_cycle(pc)
      expect(pc.get_output(:q)).to eq(3)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::ProgramCounter.behavior_defined? || RHDL::HDL::ProgramCounter.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ProgramCounter.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # clk, rst, en, load, inc, d, q
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ProgramCounter.to_verilog
      expect(verilog).to include('module program_counter')
      expect(verilog).to include('input [15:0] d')
      expect(verilog).to match(/output.*\[15:0\].*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ProgramCounter.new('pc') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'pc') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('pc.clk', 'pc.rst', 'pc.en', 'pc.load', 'pc.d', 'pc.inc')
      expect(ir.outputs.keys).to include('pc.q')
      expect(ir.dffs.length).to eq(16)  # 16-bit program counter has 16 DFFs
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module pc')
      expect(verilog).to include('input [15:0] d')
      expect(verilog).to include('input [15:0] inc')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('input load')
      expect(verilog).to include('output [15:0] q')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::ProgramCounter.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)
        behavior.set_input(:load, 0)
        behavior.set_input(:inc, 1)

        test_cases = [
          { d: 0, rst: 0, en: 1, load: 0, inc: 1 },       # count: 0->1
          { d: 0, rst: 0, en: 1, load: 0, inc: 1 },       # count: 1->2
          { d: 0x100, rst: 0, en: 1, load: 1, inc: 1 },   # load 0x100
          { d: 0, rst: 0, en: 1, load: 0, inc: 2 },       # inc by 2: 0x100->0x102
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:load, tc[:load])
          behavior.set_input(:inc, tc[:inc])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavior.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'pc')
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
