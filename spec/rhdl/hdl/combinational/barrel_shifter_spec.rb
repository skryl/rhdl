# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::BarrelShifter do
  let(:shifter) { RHDL::HDL::BarrelShifter.new }

  describe 'simulation' do
    it 'shifts left' do
      shifter.set_input(:a, 0b00001111)
      shifter.set_input(:shift, 2)
      shifter.set_input(:dir, 0)  # left
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 0)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b00111100)
    end

    it 'shifts right logical' do
      shifter.set_input(:a, 0b11110000)
      shifter.set_input(:shift, 2)
      shifter.set_input(:dir, 1)  # right
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 0)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b00111100)
    end

    it 'shifts right arithmetic (sign extends)' do
      shifter.set_input(:a, 0b10000000)  # -128 in signed 8-bit
      shifter.set_input(:shift, 2)
      shifter.set_input(:dir, 1)  # right
      shifter.set_input(:arith, 1)
      shifter.set_input(:rotate, 0)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b11100000)
    end

    it 'rotates left' do
      shifter.set_input(:a, 0b10000001)
      shifter.set_input(:shift, 1)
      shifter.set_input(:dir, 0)  # left
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 1)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b00000011)
    end

    it 'rotates right' do
      shifter.set_input(:a, 0b10000001)
      shifter.set_input(:shift, 1)
      shifter.set_input(:dir, 1)  # right
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 1)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b11000000)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BarrelShifter.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::BarrelShifter.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, shift, dir, arith, rotate, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BarrelShifter.to_verilog
      expect(verilog).to include('module barrel_shifter')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] y')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::BarrelShifter.new('bshifter') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bshifter') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('bshifter.a', 'bshifter.shift', 'bshifter.dir', 'bshifter.arith', 'bshifter.rotate')
      expect(ir.outputs.keys).to include('bshifter.y')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module bshifter')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [2:0] shift')
      expect(verilog).to include('input dir')
      expect(verilog).to include('input arith')
      expect(verilog).to include('input rotate')
      expect(verilog).to include('output [7:0] y')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::BarrelShifter.new

        test_cases = [
          { a: 0b00001111, shift: 2, dir: 0, arith: 0, rotate: 0 },  # shift left
          { a: 0b11110000, shift: 2, dir: 1, arith: 0, rotate: 0 },  # shift right
          { a: 0b10000000, shift: 2, dir: 1, arith: 1, rotate: 0 },  # arith right
          { a: 0b10000001, shift: 1, dir: 0, arith: 0, rotate: 1 },  # rotate left
          { a: 0b10000001, shift: 1, dir: 1, arith: 0, rotate: 1 },  # rotate right
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:a, tc[:a])
          behavioral.set_input(:shift, tc[:shift])
          behavioral.set_input(:dir, tc[:dir])
          behavioral.set_input(:arith, tc[:arith])
          behavioral.set_input(:rotate, tc[:rotate])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { y: behavioral.get_output(:y) }
        end

        base_dir = File.join('tmp', 'iverilog', 'bshifter')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:y]).to eq(expected[:y]),
            "Cycle #{idx}: expected y=#{expected[:y]}, got #{result[:results][idx][:y]}"
        end
      end
    end
  end
end
