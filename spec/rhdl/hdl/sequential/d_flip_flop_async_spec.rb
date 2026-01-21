require 'spec_helper'

RSpec.describe RHDL::HDL::DFlipFlopAsync do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:dff) { RHDL::HDL::DFlipFlopAsync.new }

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

    it 'resets asynchronously on reset signal' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      # Async reset should work without clock edge
      dff.set_input(:rst, 1)
      dff.propagate
      expect(dff.get_output(:q)).to eq(0)
    end

    it 'reset takes priority over clock edge' do
      dff.set_input(:d, 1)
      dff.set_input(:rst, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::DFlipFlopAsync.behavior_defined? || RHDL::HDL::DFlipFlopAsync.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::DFlipFlopAsync.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # d, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::DFlipFlopAsync.to_verilog
      expect(verilog).to include('module d_flip_flop_async')
      expect(verilog).to include('input d')
      expect(verilog).to match(/output.*q/)
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::DFlipFlopAsync.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit d_flip_flop_async')
      expect(firrtl).to include('input d')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('output q')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::DFlipFlopAsync,
          base_dir: 'tmp/circt_test/d_flip_flop_async'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::DFlipFlopAsync.new('dff_async') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'dff_async') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dff_async.d', 'dff_async.clk', 'dff_async.rst', 'dff_async.en')
      expect(ir.outputs.keys).to include('dff_async.q', 'dff_async.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module dff_async')
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
        behavior = RHDL::HDL::DFlipFlopAsync.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)

        test_cases = [
          { d: 1, rst: 0, en: 1 },  # capture 1
          { d: 0, rst: 0, en: 1 },  # capture 0
          { d: 1, rst: 0, en: 0 },  # hold (en=0)
          { d: 0, rst: 1, en: 1 },  # async reset
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

        base_dir = File.join('tmp', 'iverilog', 'dff_async')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:q]).to eq(expected[:q]),
            "Cycle #{idx}: expected q=#{expected[:q]}, got #{result[:results][idx][:q]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results', pending: 'Flip-flop qn timing issues with Ruby/Native SimCPU' do
        test_cases = [
          { d: 1, rst: 0, en: 1 },
          { d: 0, rst: 0, en: 1 },
          { d: 1, rst: 0, en: 0 },
          { d: 0, rst: 1, en: 1 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::DFlipFlopAsync,
          'd_flip_flop_async',
          test_cases,
          base_dir: 'tmp/netlist_comparison/d_flip_flop_async',
          has_clock: true
        )
      end
    end
  end
end
