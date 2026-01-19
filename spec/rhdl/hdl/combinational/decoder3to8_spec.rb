# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder3to8 do
  let(:dec) { RHDL::HDL::Decoder3to8.new }

  describe 'simulation' do
    it 'decodes all 8 values' do
      dec.set_input(:en, 1)

      8.times do |i|
        dec.set_input(:a, i)
        dec.propagate

        8.times do |j|
          expected = (i == j) ? 1 : 0
          expect(dec.get_output("y#{j}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Decoder3to8.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Decoder3to8.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(10)  # a, en, y0-y7
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Decoder3to8.to_verilog
      expect(verilog).to include('module decoder3to8')
      expect(verilog).to include('input [2:0] a')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::Decoder3to8.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit decoder3to8')
      expect(firrtl).to include('input a')
      expect(firrtl).to include('output y0')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::Decoder3to8,
          base_dir: 'tmp/circt_test/decoder3to8'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'iverilog behavior simulation', if: HdlToolchain.iverilog_available? do
      it 'matches RHDL simulation' do
        verilog = RHDL::HDL::Decoder3to8.to_verilog
        behavior = RHDL::HDL::Decoder3to8.new

        inputs = { a: 3, en: 1 }
        outputs = { y0: 1, y1: 1, y2: 1, y3: 1, y4: 1, y5: 1, y6: 1, y7: 1 }

        vectors = []
        # Test all 8 address values with enable=1
        8.times do |i|
          test_cases = [{ a: i, en: 1 }]
          test_cases.each do |tc|
            behavior.set_input(:a, tc[:a])
            behavior.set_input(:en, tc[:en])
            behavior.propagate
            vectors << {
              inputs: tc,
              expected: {
                y0: behavior.get_output(:y0),
                y1: behavior.get_output(:y1),
                y2: behavior.get_output(:y2),
                y3: behavior.get_output(:y3),
                y4: behavior.get_output(:y4),
                y5: behavior.get_output(:y5),
                y6: behavior.get_output(:y6),
                y7: behavior.get_output(:y7)
              }
            }
          end
        end
        # Test with enable=0
        [0, 4, 7].each do |i|
          behavior.set_input(:a, i)
          behavior.set_input(:en, 0)
          behavior.propagate
          vectors << {
            inputs: { a: i, en: 0 },
            expected: {
              y0: behavior.get_output(:y0),
              y1: behavior.get_output(:y1),
              y2: behavior.get_output(:y2),
              y3: behavior.get_output(:y3),
              y4: behavior.get_output(:y4),
              y5: behavior.get_output(:y5),
              y6: behavior.get_output(:y6),
              y7: behavior.get_output(:y7)
            }
          }
        end

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'decoder3to8',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/decoder3to8'
        )

        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          %i[y0 y1 y2 y3 y4 y5 y6 y7].each do |out|
            expect(result[:results][idx][out]).to eq(vec[:expected][out]),
              "Vector #{idx}: expected #{out}=#{vec[:expected][out]}, got #{result[:results][idx][out]}"
          end
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Decoder3to8.new('dec3to8') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'dec3to8') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dec3to8.a', 'dec3to8.en')
      expect(ir.outputs.keys).to include('dec3to8.y0', 'dec3to8.y1')
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module dec3to8')
      expect(verilog).to include('input [2:0] a')
      expect(verilog).to include('output y0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, en: 1 }, expected: { y0: 1, y1: 0, y2: 0, y3: 0, y4: 0, y5: 0, y6: 0, y7: 0 } },
          { inputs: { a: 1, en: 1 }, expected: { y0: 0, y1: 1, y2: 0, y3: 0, y4: 0, y5: 0, y6: 0, y7: 0 } },
          { inputs: { a: 7, en: 1 }, expected: { y0: 0, y1: 0, y2: 0, y3: 0, y4: 0, y5: 0, y6: 0, y7: 1 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/dec3to8')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
