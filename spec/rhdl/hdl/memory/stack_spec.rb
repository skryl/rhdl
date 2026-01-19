require 'spec_helper'

RSpec.describe RHDL::HDL::Stack do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:stack) { RHDL::HDL::Stack.new }

  before do
    stack.set_input(:rst, 0)
    stack.set_input(:push, 0)
    stack.set_input(:pop, 0)
    stack.propagate  # Initialize outputs
  end

  describe 'simulation' do
    it 'pushes and pops values' do
      # Push 0x11
      stack.set_input(:din, 0x11)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:dout)).to eq(0x11)
      expect(stack.get_output(:empty)).to eq(0)

      # Push 0x22
      stack.set_input(:din, 0x22)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:dout)).to eq(0x22)

      # Pop - should get 0x22
      stack.set_input(:pop, 1)
      clock_cycle(stack)

      stack.set_input(:pop, 0)
      expect(stack.get_output(:dout)).to eq(0x11)
    end

    it 'indicates empty and full' do
      expect(stack.get_output(:empty)).to eq(1)
      expect(stack.get_output(:full)).to eq(0)

      # Fill the stack (16 entries)
      16.times do |i|
        stack.set_input(:din, i + 1)
        stack.set_input(:push, 1)
        clock_cycle(stack)
        stack.set_input(:push, 0)
      end

      expect(stack.get_output(:empty)).to eq(0)
      expect(stack.get_output(:full)).to eq(1)
    end

    it 'resets correctly' do
      # Push some values
      stack.set_input(:din, 0xFF)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:empty)).to eq(0)

      # Reset
      stack.set_input(:rst, 1)
      clock_cycle(stack)

      expect(stack.get_output(:empty)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::Stack.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Stack.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # clk, rst, push, pop, din, dout, empty, full, sp
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Stack.to_verilog
      expect(verilog).to include('module stack')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to match(/output.*\[7:0\].*dout/)
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::Stack.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit stack')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('input din')
      expect(firrtl).to include('output dout')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::Stack,
          base_dir: 'tmp/circt_test/stack'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Stack.new('stack') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'stack') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('stack.clk', 'stack.rst', 'stack.push', 'stack.pop', 'stack.din')
      expect(ir.outputs.keys).to include('stack.dout', 'stack.empty', 'stack.full', 'stack.sp')
      # Stack has DFFs for stack pointer
      expect(ir.dffs.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module stack')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input push')
      expect(verilog).to include('input pop')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to include('output [7:0] dout')
      expect(verilog).to include('output empty')
      expect(verilog).to include('output full')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::Stack.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:push, 0)
        behavior.set_input(:pop, 0)
        behavior.propagate

        test_cases = [
          { din: 0x11, rst: 0, push: 1, pop: 0 },  # push
          { din: 0x22, rst: 0, push: 1, pop: 0 },  # push
          { din: 0, rst: 0, push: 0, pop: 1 },     # pop
          { din: 0, rst: 0, push: 0, pop: 1 },     # pop
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:din, tc[:din])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:push, tc[:push])
          behavior.set_input(:pop, tc[:pop])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            dout: behavior.get_output(:dout),
            empty: behavior.get_output(:empty)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'stack')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:empty]).to eq(expected[:empty]),
            "Cycle #{idx}: expected empty=#{expected[:empty]}, got #{result[:results][idx][:empty]}"
        end
      end
    end
  end
end
