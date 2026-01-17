require 'spec_helper'

RSpec.describe RHDL::HDL::StackPointer do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:sp) { RHDL::HDL::StackPointer.new }

  before do
    sp.set_input(:rst, 0)
    sp.set_input(:push, 0)
    sp.set_input(:pop, 0)
  end

  describe 'simulation' do
    it 'initializes to the specified value' do
      sp.propagate  # Initial propagate to set output wires
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)  # SP at max means empty
      expect(sp.get_output(:full)).to eq(0)
    end

    it 'decrements on push' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)
      expect(sp.get_output(:empty)).to eq(0)
    end

    it 'increments on pop' do
      # First push to decrement
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)

      # Now pop to increment
      sp.set_input(:push, 0)
      sp.set_input(:pop, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end

    it 'indicates full when SP is 0' do
      # Push until SP reaches 0 (255 pushes from 0xFF)
      # For efficiency, we test after just enough pushes to verify the flag logic
      # Push once to get to 0xFE first
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)
      expect(sp.get_output(:full)).to eq(0)

      # Push 254 more times to reach 0
      254.times { clock_cycle(sp) }
      expect(sp.get_output(:q)).to eq(0x00)
      expect(sp.get_output(:full)).to eq(1)
    end

    it 'wraps around on underflow' do
      # Push until SP reaches 0, then push once more to wrap
      sp.set_input(:push, 1)
      # Push 255 times to reach 0
      255.times { clock_cycle(sp) }
      expect(sp.get_output(:q)).to eq(0x00)

      # One more push wraps around to 0xFF
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
    end

    it 'resets to initial value' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)

      sp.set_input(:push, 0)
      sp.set_input(:rst, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::StackPointer.behavior_defined? || RHDL::HDL::StackPointer.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::StackPointer.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # clk, rst, push, pop, q, empty, full
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::StackPointer.to_verilog
      expect(verilog).to include('module stack_pointer')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::StackPointer.new('sp') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'sp') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('sp.clk', 'sp.rst', 'sp.push', 'sp.pop')
      expect(ir.outputs.keys).to include('sp.q', 'sp.empty', 'sp.full')
      expect(ir.dffs.length).to eq(8)  # 8-bit stack pointer has 8 DFFs
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module sp')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input push')
      expect(verilog).to include('input pop')
      expect(verilog).to include('output [7:0] q')
      expect(verilog).to include('output empty')
      expect(verilog).to include('output full')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::StackPointer.new
        behavioral.set_input(:rst, 0)
        behavioral.set_input(:push, 0)
        behavioral.set_input(:pop, 0)

        test_cases = [
          { rst: 0, push: 1, pop: 0 },  # push: 0xFF -> 0xFE
          { rst: 0, push: 1, pop: 0 },  # push: 0xFE -> 0xFD
          { rst: 0, push: 0, pop: 1 },  # pop:  0xFD -> 0xFE
          { rst: 0, push: 0, pop: 1 },  # pop:  0xFE -> 0xFF
          { rst: 1, push: 0, pop: 0 },  # reset: -> 0xFF
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:rst, tc[:rst])
          behavioral.set_input(:push, tc[:push])
          behavioral.set_input(:pop, tc[:pop])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavioral.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'sp')
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
