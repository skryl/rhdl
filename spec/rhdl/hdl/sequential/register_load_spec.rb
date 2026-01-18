require 'spec_helper'

RSpec.describe RHDL::HDL::RegisterLoad do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:reg) { RHDL::HDL::RegisterLoad.new }

  before do
    reg.set_input(:rst, 0)
    reg.set_input(:load, 0)
  end

  describe 'simulation' do
    it 'stores 8-bit values when load is high' do
      reg.set_input(:load, 1)
      reg.set_input(:d, 0xAB)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)
    end

    it 'holds value when load is low' do
      reg.set_input(:load, 1)
      reg.set_input(:d, 0xAB)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)

      reg.set_input(:load, 0)
      reg.set_input(:d, 0xFF)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)  # Still 0xAB
    end

    it 'resets to zero' do
      reg.set_input(:load, 1)
      reg.set_input(:d, 0xFF)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xFF)

      reg.set_input(:rst, 1)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::RegisterLoad.behavior_defined? || RHDL::HDL::RegisterLoad.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::RegisterLoad.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # d, clk, rst, load, q
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::RegisterLoad.to_verilog
      expect(verilog).to include('module register_load')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::RegisterLoad.new('reg_load') }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'reg_load') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('reg_load.d', 'reg_load.clk', 'reg_load.rst', 'reg_load.load')
      expect(ir.outputs.keys).to include('reg_load.q')
      expect(ir.dffs.length).to eq(8)  # 8-bit register has 8 DFFs
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module reg_load')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input load')
      expect(verilog).to include('output [7:0] q')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::RegisterLoad.new
        behavioral.set_input(:rst, 0)
        behavioral.set_input(:load, 0)

        test_cases = [
          { d: 0xAB, rst: 0, load: 1 },  # load value
          { d: 0x55, rst: 0, load: 1 },  # load another
          { d: 0xFF, rst: 0, load: 0 },  # hold (load=0)
          { d: 0x00, rst: 1, load: 1 },  # reset
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:d, tc[:d])
          behavioral.set_input(:rst, tc[:rst])
          behavioral.set_input(:load, tc[:load])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavioral.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'reg_load')
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
