require 'spec_helper'

RSpec.describe RHDL::HDL::ShiftRegister do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:sr) { RHDL::HDL::ShiftRegister.new }

  before do
    sr.set_input(:rst, 0)
    sr.set_input(:en, 1)
    sr.set_input(:load, 0)
    sr.set_input(:dir, 1)  # Shift left
    sr.set_input(:d_in, 0)
  end

  describe 'simulation' do
    it 'shifts left' do
      sr.set_input(:load, 1)
      sr.set_input(:d, 0b00001111)
      clock_cycle(sr)
      sr.set_input(:load, 0)

      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b00011110)

      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b00111100)
    end

    it 'shifts right' do
      sr.set_input(:load, 1)
      sr.set_input(:d, 0b11110000)
      clock_cycle(sr)
      sr.set_input(:load, 0)

      sr.set_input(:dir, 0)  # Shift right
      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b01111000)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::ShiftRegister.behavior_defined? || RHDL::HDL::ShiftRegister.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ShiftRegister.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # d, d_in, clk, rst, en, load, dir, q, d_out
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ShiftRegister.to_verilog
      expect(verilog).to include('module shift_register')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::ShiftRegister.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit shift_register')
      expect(firrtl).to include('input d')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('output q')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        behavior = RHDL::HDL::ShiftRegister.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)
        behavior.set_input(:d_in, 0)

        test_vectors = []
        # Start with reset cycle to initialize shift register (avoids X propagation)
        test_cases = [
          { d: 0, d_in: 0, rst: 1, en: 1, load: 0, dir: 1 },           # reset (initialize to 0)
          { d: 0b00001111, d_in: 0, rst: 0, en: 1, load: 1, dir: 1 },  # load
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },           # shift left
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },           # shift left
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 0 },           # shift right
          { d: 0, d_in: 1, rst: 0, en: 1, load: 0, dir: 1 },           # shift left with d_in=1
        ]

        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:d_in, tc[:d_in])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:load, tc[:load])
          behavior.set_input(:dir, tc[:dir])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate
          test_vectors << {
            inputs: { d: tc[:d], d_in: tc[:d_in], rst: tc[:rst], en: tc[:en], load: tc[:load], dir: tc[:dir] },
            expected: { q: behavior.get_output(:q), d_out: behavior.get_output(:d_out) }
          }
        end

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::ShiftRegister,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/shift_register',
          has_clock: true
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::ShiftRegister.to_verilog
        behavior = RHDL::HDL::ShiftRegister.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)
        behavior.set_input(:d_in, 0)

        inputs = { d_in: 1, clk: 1, rst: 1, en: 1, dir: 1, load: 1, d: 8 }
        outputs = { q: 8, d_out: 1 }

        vectors = []
        # Start with reset cycle to initialize shift register (avoids X propagation)
        test_cases = [
          { d: 0, d_in: 0, rst: 1, en: 1, load: 0, dir: 1 },           # reset (initialize to 0)
          { d: 0b00001111, d_in: 0, rst: 0, en: 1, load: 1, dir: 1 },  # load
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },           # shift left
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },           # shift left
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 0 },           # shift right
          { d: 0, d_in: 1, rst: 0, en: 1, load: 0, dir: 1 },           # shift left with d_in=1
        ]

        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:d_in, tc[:d_in])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:load, tc[:load])
          behavior.set_input(:dir, tc[:dir])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate
          vectors << {
            inputs: { d: tc[:d], d_in: tc[:d_in], rst: tc[:rst], en: tc[:en], load: tc[:load], dir: tc[:dir] },
            expected: { q: behavior.get_output(:q), d_out: behavior.get_output(:d_out) }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'shift_register',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/shift_register',
          has_clock: true
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:q]).to eq(vec[:expected][:q]),
            "Vector #{idx}: expected q=#{vec[:expected][:q]}, got #{result[:results][idx][:q]}"
          expect(result[:results][idx][:d_out]).to eq(vec[:expected][:d_out]),
            "Vector #{idx}: expected d_out=#{vec[:expected][:d_out]}, got #{result[:results][idx][:d_out]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ShiftRegister.new('shift_reg') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'shift_reg') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('shift_reg.d', 'shift_reg.d_in', 'shift_reg.clk', 'shift_reg.rst', 'shift_reg.en', 'shift_reg.load', 'shift_reg.dir')
      expect(ir.outputs.keys).to include('shift_reg.q', 'shift_reg.d_out')
      expect(ir.dffs.length).to eq(8)  # 8-bit shift register has 8 DFFs
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module shift_reg')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to include('input d_in')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [7:0] q')
      expect(verilog).to include('output d_out')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::ShiftRegister.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:en, 1)
        behavior.set_input(:d_in, 0)

        test_cases = [
          { d: 0b00001111, d_in: 0, rst: 0, en: 1, load: 1, dir: 1 },  # load
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },           # shift left
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },           # shift left
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 0 },           # shift right
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:d, tc[:d])
          behavior.set_input(:d_in, tc[:d_in])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:en, tc[:en])
          behavior.set_input(:load, tc[:load])
          behavior.set_input(:dir, tc[:dir])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavior.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'shift_reg')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:q]).to eq(expected[:q]),
            "Cycle #{idx}: expected q=#{expected[:q]}, got #{result[:results][idx][:q]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results', pending: 'Sequential timing mismatch between Ruby/Native SimCPU and Verilog' do
        test_cases = [
          { d: 0b00001111, d_in: 0, rst: 0, en: 1, load: 1, dir: 1 },
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 1 },
          { d: 0, d_in: 0, rst: 0, en: 1, load: 0, dir: 0 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::ShiftRegister,
          'shift_register',
          test_cases,
          base_dir: 'tmp/netlist_comparison/shift_register',
          has_clock: true
        )
      end
    end
  end
end
