require 'spec_helper'

RSpec.describe 'Combinational Gate-Level Netlist Generation' do
  describe 'Mux2' do
    let(:component) { RHDL::HDL::Mux2.new('mux2', width: 1) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mux2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux2.a', 'mux2.b', 'mux2.sel')
      expect(ir.outputs.keys).to include('mux2.y')
      # MUX2: sel ? b : a - typically 1 MUX primitive or AND/OR/NOT combo
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mux2')
      expect(verilog).to include('input sel')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0, sel: 0 }, expected: { y: 0 } },
          { inputs: { a: 0, b: 1, sel: 0 }, expected: { y: 0 } },
          { inputs: { a: 1, b: 0, sel: 0 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, sel: 1 }, expected: { y: 0 } },
          { inputs: { a: 0, b: 1, sel: 1 }, expected: { y: 1 } },
          { inputs: { a: 1, b: 0, sel: 1 }, expected: { y: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mux2')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Mux2 (4-bit)' do
    let(:component) { RHDL::HDL::Mux2.new('mux2_4bit', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mux2_4bit') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux2_4bit.a', 'mux2_4bit.b', 'mux2_4bit.sel')
      expect(ir.outputs.keys).to include('mux2_4bit.y')
      # 4-bit MUX2: 4 MUX primitives
      expect(ir.gates.length).to eq(4)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('input [3:0] b')
      expect(verilog).to include('output [3:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b1010, b: 0b0101, sel: 0 }, expected: { y: 0b1010 } },
          { inputs: { a: 0b1010, b: 0b0101, sel: 1 }, expected: { y: 0b0101 } },
          { inputs: { a: 0b1111, b: 0b0000, sel: 0 }, expected: { y: 0b1111 } },
          { inputs: { a: 0b1111, b: 0b0000, sel: 1 }, expected: { y: 0b0000 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mux2_4bit')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Mux4' do
    let(:component) { RHDL::HDL::Mux4.new('mux4', width: 1) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mux4') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mux4.a', 'mux4.b', 'mux4.c', 'mux4.d', 'mux4.sel')
      expect(ir.outputs.keys).to include('mux4.y')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mux4')
      expect(verilog).to include('input [1:0] sel')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 1, b: 0, c: 0, d: 0, sel: 0 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 1, c: 0, d: 0, sel: 1 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, c: 1, d: 0, sel: 2 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, c: 0, d: 1, sel: 3 }, expected: { y: 1 } },
          { inputs: { a: 1, b: 1, c: 1, d: 1, sel: 0 }, expected: { y: 1 } },
          { inputs: { a: 0, b: 0, c: 0, d: 0, sel: 2 }, expected: { y: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mux4')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Decoder2to4' do
    let(:component) { RHDL::HDL::Decoder2to4.new('dec2to4') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'dec2to4') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dec2to4.a', 'dec2to4.en')
      expect(ir.outputs.keys).to include('dec2to4.y0', 'dec2to4.y1', 'dec2to4.y2', 'dec2to4.y3')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module dec2to4')
      expect(verilog).to include('input [1:0] a')
      expect(verilog).to include('output y0')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, en: 1 }, expected: { y0: 1, y1: 0, y2: 0, y3: 0 } },
          { inputs: { a: 1, en: 1 }, expected: { y0: 0, y1: 1, y2: 0, y3: 0 } },
          { inputs: { a: 2, en: 1 }, expected: { y0: 0, y1: 0, y2: 1, y3: 0 } },
          { inputs: { a: 3, en: 1 }, expected: { y0: 0, y1: 0, y2: 0, y3: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/dec2to4')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Decoder3to8' do
    let(:component) { RHDL::HDL::Decoder3to8.new('dec3to8') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'dec3to8') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dec3to8.a', 'dec3to8.en')
      expect(ir.outputs.keys).to include('dec3to8.y0', 'dec3to8.y1')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
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

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/dec3to8')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Encoder4to2' do
    let(:component) { RHDL::HDL::Encoder4to2.new('enc4to2') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'enc4to2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('enc4to2.a')
      expect(ir.outputs.keys).to include('enc4to2.y')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module enc4to2')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [1:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0001 }, expected: { y: 0 } },
          { inputs: { a: 0b0010 }, expected: { y: 1 } },
          { inputs: { a: 0b0100 }, expected: { y: 2 } },
          { inputs: { a: 0b1000 }, expected: { y: 3 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/enc4to2')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'ZeroDetect' do
    let(:component) { RHDL::HDL::ZeroDetect.new('zero_detect', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'zero_detect') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('zero_detect.a')
      expect(ir.outputs.keys).to include('zero_detect.zero')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module zero_detect')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output zero')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0 }, expected: { zero: 1 } },
          { inputs: { a: 1 }, expected: { zero: 0 } },
          { inputs: { a: 5 }, expected: { zero: 0 } },
          { inputs: { a: 15 }, expected: { zero: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/zero_detect')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'SignExtend' do
    let(:component) { RHDL::HDL::SignExtend.new('sign_extend', in_width: 4, out_width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'sign_extend') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('sign_extend.a')
      expect(ir.outputs.keys).to include('sign_extend.y')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module sign_extend')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [7:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0101 }, expected: { y: 0b00000101 } },  # Positive: 5 -> 5
          { inputs: { a: 0b1000 }, expected: { y: 0b11111000 } },  # Negative: -8 -> -8
          { inputs: { a: 0b1111 }, expected: { y: 0b11111111 } },  # Negative: -1 -> -1
          { inputs: { a: 0b0000 }, expected: { y: 0b00000000 } }   # Zero: 0 -> 0
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/sign_extend')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'ZeroExtend' do
    let(:component) { RHDL::HDL::ZeroExtend.new('zero_extend', in_width: 4, out_width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'zero_extend') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('zero_extend.a')
      expect(ir.outputs.keys).to include('zero_extend.y')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module zero_extend')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [7:0] y')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0b0101 }, expected: { y: 0b00000101 } },
          { inputs: { a: 0b1000 }, expected: { y: 0b00001000 } },  # No sign extension
          { inputs: { a: 0b1111 }, expected: { y: 0b00001111 } },
          { inputs: { a: 0b0000 }, expected: { y: 0b00000000 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/zero_extend')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
