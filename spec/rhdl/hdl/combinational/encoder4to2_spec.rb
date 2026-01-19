# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Encoder4to2 do
  let(:enc) { RHDL::HDL::Encoder4to2.new }

  describe 'simulation' do
    it 'encodes one-hot input' do
      # Input :a is a 4-bit value where bit 2 is set (0b0100)
      enc.set_input(:a, 0b0100)
      enc.propagate

      expect(enc.get_output(:y)).to eq(2)
      expect(enc.get_output(:valid)).to eq(1)
    end

    it 'indicates invalid when no input' do
      enc.set_input(:a, 0b0000)
      enc.propagate

      expect(enc.get_output(:valid)).to eq(0)
    end

    it 'prioritizes higher input' do
      # Bits 0, 1, and 3 are set - highest is bit 3
      enc.set_input(:a, 0b1011)
      enc.propagate

      expect(enc.get_output(:y)).to eq(3)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Encoder4to2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Encoder4to2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, y, valid
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Encoder4to2.to_verilog
      expect(verilog).to include('module encoder4to2')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [1:0] y')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::Encoder4to2.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit encoder4to2')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output y')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? && HdlToolchain.iverilog_available? do
      it 'CIRCT-generated Verilog matches RHDL Verilog behavior' do
        behavior = RHDL::HDL::Encoder4to2.new

        test_vectors = []
        test_cases = [
          { a: 0b0000 },  # no input - invalid
          { a: 0b0001 },  # bit 0 set - y=0
          { a: 0b0010 },  # bit 1 set - y=1
          { a: 0b0100 },  # bit 2 set - y=2
          { a: 0b1000 },  # bit 3 set - y=3
          { a: 0b0011 },  # bits 0,1 set - priority gives y=1
          { a: 0b0101 },  # bits 0,2 set - priority gives y=2
          { a: 0b1010 },  # bits 1,3 set - priority gives y=3
          { a: 0b1111 },  # all bits set - priority gives y=3
          { a: 0b0111 },  # bits 0,1,2 set - priority gives y=2
          { a: 0b1011 }   # bits 0,1,3 set - priority gives y=3
        ]

        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.propagate
          test_vectors << {
            inputs: tc,
            expected: {
              y: behavior.get_output(:y),
              valid: behavior.get_output(:valid)
            }
          }
        end

        result = CirctHelper.validate_circt_export(
          RHDL::HDL::Encoder4to2,
          test_vectors: test_vectors,
          base_dir: 'tmp/circt_test/encoder4to2'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::Encoder4to2.to_verilog
        behavior = RHDL::HDL::Encoder4to2.new

        inputs = { a: 4 }
        outputs = { y: 2, valid: 1 }

        vectors = []
        test_cases = [
          { a: 0b0000 },  # no input - invalid
          { a: 0b0001 },  # bit 0 set - y=0
          { a: 0b0010 },  # bit 1 set - y=1
          { a: 0b0100 },  # bit 2 set - y=2
          { a: 0b1000 },  # bit 3 set - y=3
          { a: 0b0011 },  # bits 0,1 set - priority gives y=1
          { a: 0b0101 },  # bits 0,2 set - priority gives y=2
          { a: 0b1010 },  # bits 1,3 set - priority gives y=3
          { a: 0b1111 },  # all bits set - priority gives y=3
          { a: 0b0111 },  # bits 0,1,2 set - priority gives y=2
          { a: 0b1011 }   # bits 0,1,3 set - priority gives y=3
        ]

        test_cases.each do |tc|
          behavior.set_input(:a, tc[:a])
          behavior.propagate
          vectors << {
            inputs: tc,
            expected: {
              y: behavior.get_output(:y),
              valid: behavior.get_output(:valid)
            }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'encoder4to2',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/encoder4to2'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:y]).to eq(vec[:expected][:y]),
            "Vector #{idx}: expected y=#{vec[:expected][:y]}, got #{result[:results][idx][:y]}"
          expect(result[:results][idx][:valid]).to eq(vec[:expected][:valid]),
            "Vector #{idx}: expected valid=#{vec[:expected][:valid]}, got #{result[:results][idx][:valid]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Encoder4to2.new('enc4to2') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'enc4to2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('enc4to2.a')
      expect(ir.outputs.keys).to include('enc4to2.y', 'enc4to2.valid')
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module enc4to2')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [1:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0001 }, expected: { y: 0, valid: 1 } },
          { inputs: { a: 0b0010 }, expected: { y: 1, valid: 1 } },
          { inputs: { a: 0b0100 }, expected: { y: 2, valid: 1 } },
          { inputs: { a: 0b1000 }, expected: { y: 3, valid: 1 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/enc4to2')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
