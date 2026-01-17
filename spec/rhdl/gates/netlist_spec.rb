require 'spec_helper'

RSpec.describe 'Gate-Level Netlist Generation' do
  describe 'simple gates' do
    describe 'NotGate' do
      let(:component) { RHDL::HDL::NotGate.new('not_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'not_gate') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('not_gate.a')
        expect(ir.outputs.keys).to include('not_gate.y')
        expect(ir.gates.length).to eq(1)
        expect(ir.gates.first.type).to eq(:not)
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('module not_gate')
        expect(verilog).to include('input a')
        expect(verilog).to include('output y')
        expect(verilog).to include('not g0')
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a: 0 }, expected: { y: 1 } },
            { inputs: { a: 1 }, expected: { y: 0 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/not_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'AndGate' do
      let(:component) { RHDL::HDL::AndGate.new('and_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'and_gate') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('and_gate.a0', 'and_gate.a1')
        expect(ir.outputs.keys).to include('and_gate.y')
        expect(ir.gates.length).to eq(1)
        expect(ir.gates.first.type).to eq(:and)
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('module and_gate')
        expect(verilog).to include('input a0')
        expect(verilog).to include('input a1')
        expect(verilog).to include('output y')
        expect(verilog).to include('and g0')
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
            { inputs: { a0: 0, a1: 1 }, expected: { y: 0 } },
            { inputs: { a0: 1, a1: 0 }, expected: { y: 0 } },
            { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/and_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'OrGate' do
      let(:component) { RHDL::HDL::OrGate.new('or_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'or_gate') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('or_gate.a0', 'or_gate.a1')
        expect(ir.outputs.keys).to include('or_gate.y')
        expect(ir.gates.length).to eq(1)
        expect(ir.gates.first.type).to eq(:or)
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('or g0')
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
            { inputs: { a0: 0, a1: 1 }, expected: { y: 1 } },
            { inputs: { a0: 1, a1: 0 }, expected: { y: 1 } },
            { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/or_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'XorGate' do
      let(:component) { RHDL::HDL::XorGate.new('xor_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'xor_gate') }

      it 'generates correct IR structure' do
        expect(ir.gates.length).to eq(1)
        expect(ir.gates.first.type).to eq(:xor)
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('xor g0')
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a0: 0, a1: 0 }, expected: { y: 0 } },
            { inputs: { a0: 0, a1: 1 }, expected: { y: 1 } },
            { inputs: { a0: 1, a1: 0 }, expected: { y: 1 } },
            { inputs: { a0: 1, a1: 1 }, expected: { y: 0 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/xor_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'NandGate' do
      let(:component) { RHDL::HDL::NandGate.new('nand_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'nand_gate') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('nand_gate.a0', 'nand_gate.a1')
        expect(ir.outputs.keys).to include('nand_gate.y')
        # NAND may be implemented as AND + NOT or native NAND
        expect(ir.gates.length).to be >= 1
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('module nand_gate')
        # NAND may use nand primitive or and + not
        expect(verilog).to match(/nand g0|and g0/)
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a0: 0, a1: 0 }, expected: { y: 1 } },
            { inputs: { a0: 0, a1: 1 }, expected: { y: 1 } },
            { inputs: { a0: 1, a1: 0 }, expected: { y: 1 } },
            { inputs: { a0: 1, a1: 1 }, expected: { y: 0 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/nand_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'NorGate' do
      let(:component) { RHDL::HDL::NorGate.new('nor_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'nor_gate') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('nor_gate.a0', 'nor_gate.a1')
        expect(ir.outputs.keys).to include('nor_gate.y')
        # NOR may be implemented as OR + NOT or native NOR
        expect(ir.gates.length).to be >= 1
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('module nor_gate')
        # NOR may use nor primitive or or + not
        expect(verilog).to match(/nor g0|or g0/)
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a0: 0, a1: 0 }, expected: { y: 1 } },
            { inputs: { a0: 0, a1: 1 }, expected: { y: 0 } },
            { inputs: { a0: 1, a1: 0 }, expected: { y: 0 } },
            { inputs: { a0: 1, a1: 1 }, expected: { y: 0 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/nor_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'XnorGate' do
      let(:component) { RHDL::HDL::XnorGate.new('xnor_gate') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'xnor_gate') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('xnor_gate.a0', 'xnor_gate.a1')
        expect(ir.outputs.keys).to include('xnor_gate.y')
        # XNOR may be implemented as XOR + NOT or native XNOR
        expect(ir.gates.length).to be >= 1
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('module xnor_gate')
        # XNOR may use xnor primitive or xor + not
        expect(verilog).to match(/xnor g0|xor g0/)
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a0: 0, a1: 0 }, expected: { y: 1 } },
            { inputs: { a0: 0, a1: 1 }, expected: { y: 0 } },
            { inputs: { a0: 1, a1: 0 }, expected: { y: 0 } },
            { inputs: { a0: 1, a1: 1 }, expected: { y: 1 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/xnor_gate')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'Buffer' do
      let(:component) { RHDL::HDL::Buffer.new('buffer') }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'buffer') }

      it 'generates correct IR structure' do
        expect(ir.gates.length).to eq(1)
        expect(ir.gates.first.type).to eq(:buf)
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('buf g0')
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a: 0 }, expected: { y: 0 } },
            { inputs: { a: 1 }, expected: { y: 1 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/buffer')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end
  end

  describe 'bitwise gates' do
    describe 'BitwiseNot' do
      let(:component) { RHDL::HDL::BitwiseNot.new('bitwise_not', width: 4) }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bitwise_not') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('bitwise_not.a')
        expect(ir.outputs.keys).to include('bitwise_not.y')
        # 4-bit NOT requires 4 NOT gates
        expect(ir.gates.length).to eq(4)
        expect(ir.gates.all? { |g| g.type == :not }).to be(true)
      end

      it 'generates valid structural Verilog' do
        verilog = NetlistHelper.ir_to_structural_verilog(ir)
        expect(verilog).to include('module bitwise_not')
        expect(verilog).to include('input [3:0] a')
        expect(verilog).to include('output [3:0] y')
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a: 0b0000 }, expected: { y: 0b1111 } },
            { inputs: { a: 0b1111 }, expected: { y: 0b0000 } },
            { inputs: { a: 0b1010 }, expected: { y: 0b0101 } },
            { inputs: { a: 0b0101 }, expected: { y: 0b1010 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_not')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'BitwiseAnd' do
      let(:component) { RHDL::HDL::BitwiseAnd.new('bitwise_and', width: 4) }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bitwise_and') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('bitwise_and.a', 'bitwise_and.b')
        expect(ir.outputs.keys).to include('bitwise_and.y')
        # 4-bit AND requires 4 AND gates
        expect(ir.gates.length).to eq(4)
        expect(ir.gates.all? { |g| g.type == :and }).to be(true)
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a: 0b1111, b: 0b0000 }, expected: { y: 0b0000 } },
            { inputs: { a: 0b1111, b: 0b1111 }, expected: { y: 0b1111 } },
            { inputs: { a: 0b1010, b: 0b1100 }, expected: { y: 0b1000 } },
            { inputs: { a: 0b0101, b: 0b0011 }, expected: { y: 0b0001 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_and')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'BitwiseOr' do
      let(:component) { RHDL::HDL::BitwiseOr.new('bitwise_or', width: 4) }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bitwise_or') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('bitwise_or.a', 'bitwise_or.b')
        expect(ir.outputs.keys).to include('bitwise_or.y')
        expect(ir.gates.length).to eq(4)
        expect(ir.gates.all? { |g| g.type == :or }).to be(true)
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a: 0b0000, b: 0b0000 }, expected: { y: 0b0000 } },
            { inputs: { a: 0b1111, b: 0b0000 }, expected: { y: 0b1111 } },
            { inputs: { a: 0b1010, b: 0b0101 }, expected: { y: 0b1111 } },
            { inputs: { a: 0b0100, b: 0b0010 }, expected: { y: 0b0110 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_or')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end

    describe 'BitwiseXor' do
      let(:component) { RHDL::HDL::BitwiseXor.new('bitwise_xor', width: 4) }
      let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'bitwise_xor') }

      it 'generates correct IR structure' do
        expect(ir.inputs.keys).to include('bitwise_xor.a', 'bitwise_xor.b')
        expect(ir.outputs.keys).to include('bitwise_xor.y')
        expect(ir.gates.length).to eq(4)
        expect(ir.gates.all? { |g| g.type == :xor }).to be(true)
      end

      context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
        it 'simulates correctly' do
          vectors = [
            { inputs: { a: 0b0000, b: 0b0000 }, expected: { y: 0b0000 } },
            { inputs: { a: 0b1111, b: 0b0000 }, expected: { y: 0b1111 } },
            { inputs: { a: 0b1111, b: 0b1111 }, expected: { y: 0b0000 } },
            { inputs: { a: 0b1010, b: 0b0110 }, expected: { y: 0b1100 } }
          ]

          result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/bitwise_xor')
          expect(result[:success]).to be(true), result[:error]

          vectors.each_with_index do |vec, idx|
            expect(result[:results][idx]).to eq(vec[:expected])
          end
        end
      end
    end
  end
end
