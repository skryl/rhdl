require 'spec_helper'

RSpec.describe 'Arithmetic Gate-Level Netlist Generation' do
  describe 'HalfAdder' do
    let(:component) { RHDL::HDL::HalfAdder.new('half_adder') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'half_adder') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('half_adder.a', 'half_adder.b')
      expect(ir.outputs.keys).to include('half_adder.sum', 'half_adder.cout')
      # Half adder: XOR for sum, AND for carry
      expect(ir.gates.length).to eq(2)
      gate_types = ir.gates.map(&:type).sort
      expect(gate_types).to eq([:and, :xor])
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module half_adder')
      expect(verilog).to include('input a')
      expect(verilog).to include('input b')
      expect(verilog).to include('output sum')
      expect(verilog).to include('output cout')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0 }, expected: { sum: 0, cout: 0 } },
          { inputs: { a: 0, b: 1 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 1 }, expected: { sum: 0, cout: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/half_adder')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'FullAdder' do
    let(:component) { RHDL::HDL::FullAdder.new('full_adder') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'full_adder') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('full_adder.a', 'full_adder.b', 'full_adder.cin')
      expect(ir.outputs.keys).to include('full_adder.sum', 'full_adder.cout')
      # Full adder: 2 XOR, 2 AND, 1 OR gates
      expect(ir.gates.length).to eq(5)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module full_adder')
      expect(verilog).to include('input cin')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0, cin: 0 }, expected: { sum: 0, cout: 0 } },
          { inputs: { a: 0, b: 0, cin: 1 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 0, b: 1, cin: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 0, b: 1, cin: 1 }, expected: { sum: 0, cout: 1 } },
          { inputs: { a: 1, b: 0, cin: 0 }, expected: { sum: 1, cout: 0 } },
          { inputs: { a: 1, b: 0, cin: 1 }, expected: { sum: 0, cout: 1 } },
          { inputs: { a: 1, b: 1, cin: 0 }, expected: { sum: 0, cout: 1 } },
          { inputs: { a: 1, b: 1, cin: 1 }, expected: { sum: 1, cout: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/full_adder')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'RippleCarryAdder' do
    let(:component) { RHDL::HDL::RippleCarryAdder.new('rca', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'rca') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('rca.a', 'rca.b', 'rca.cin')
      expect(ir.outputs.keys).to include('rca.sum', 'rca.cout', 'rca.overflow')
      # 4-bit RCA gates
      expect(ir.gates.length).to be > 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module rca')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('input [3:0] b')
      expect(verilog).to include('output [3:0] sum')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 0, b: 0, cin: 0 }, expected: { sum: 0, cout: 0, overflow: 0 } },
          { inputs: { a: 1, b: 1, cin: 0 }, expected: { sum: 2, cout: 0, overflow: 0 } },
          { inputs: { a: 5, b: 3, cin: 0 }, expected: { sum: 8, cout: 0, overflow: 0 } },
          { inputs: { a: 15, b: 1, cin: 0 }, expected: { sum: 0, cout: 1, overflow: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/rca')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Subtractor' do
    let(:component) { RHDL::HDL::Subtractor.new('sub', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'sub') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('sub.a', 'sub.b', 'sub.bin')
      expect(ir.outputs.keys).to include('sub.diff', 'sub.bout', 'sub.overflow')
      # Subtractor uses adder with inverted b
      expect(ir.gates.length).to be > 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module sub')
      expect(verilog).to include('output [3:0] diff')
      expect(verilog).to include('output bout')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 5, b: 3, bin: 0 }, expected: { diff: 2, bout: 0, overflow: 0 } },
          { inputs: { a: 8, b: 4, bin: 0 }, expected: { diff: 4, bout: 0, overflow: 0 } },
          { inputs: { a: 0, b: 0, bin: 0 }, expected: { diff: 0, bout: 0, overflow: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/sub')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'Comparator' do
    let(:component) { RHDL::HDL::Comparator.new('cmp', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'cmp') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('cmp.a', 'cmp.b')
      expect(ir.outputs.keys).to include('cmp.eq', 'cmp.lt', 'cmp.gt')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module cmp')
      expect(verilog).to include('output eq')
      expect(verilog).to include('output lt')
      expect(verilog).to include('output gt')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 5, b: 5 }, expected: { eq: 1, lt: 0, gt: 0 } },
          { inputs: { a: 3, b: 7 }, expected: { eq: 0, lt: 1, gt: 0 } },
          { inputs: { a: 10, b: 4 }, expected: { eq: 0, lt: 0, gt: 1 } },
          { inputs: { a: 0, b: 0 }, expected: { eq: 1, lt: 0, gt: 0 } },
          { inputs: { a: 15, b: 0 }, expected: { eq: 0, lt: 0, gt: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/cmp')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end

  describe 'IncDec' do
    let(:component) { RHDL::HDL::IncDec.new('incdec', width: 4) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'incdec') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('incdec.a', 'incdec.inc')
      expect(ir.outputs.keys).to include('incdec.result', 'incdec.cout')
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module incdec')
      expect(verilog).to include('input inc')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates correctly' do
        vectors = [
          { inputs: { a: 5, inc: 1 }, expected: { result: 6, cout: 0 } },    # Increment
          { inputs: { a: 5, inc: 0 }, expected: { result: 4, cout: 0 } },    # Decrement
          { inputs: { a: 0, inc: 1 }, expected: { result: 1, cout: 0 } },    # 0 + 1
          { inputs: { a: 15, inc: 1 }, expected: { result: 0, cout: 1 } }    # 15 + 1 (wrap)
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/incdec')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected])
        end
      end
    end
  end
end
