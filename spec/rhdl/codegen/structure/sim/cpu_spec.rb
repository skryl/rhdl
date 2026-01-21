# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe RHDL::Codegen::Structure::SimCPU do
  let(:ir) { RHDL::Codegen::Structure::IR.new(name: 'test') }
  let(:sim) { described_class.new(ir, lanes: 64) }

  describe 'initialization' do
    it 'creates a simulator with default lanes' do
      sim = described_class.new(ir)
      expect(sim.lanes).to eq(64)
    end

    it 'creates a simulator with custom lanes' do
      sim = described_class.new(ir, lanes: 32)
      expect(sim.lanes).to eq(32)
    end

    it 'stores the IR' do
      expect(sim.ir).to eq(ir)
    end
  end

  describe 'basic gates' do
    describe 'AND gate' do
      before do
        # Create nets: 0=a, 1=b, 2=out
        3.times { ir.new_net }
        ir.add_input('a', [0])
        ir.add_input('b', [1])
        ir.add_output('out', [2])
        ir.add_gate(type: :and, inputs: [0, 1], output: 2)
        ir.set_schedule([0])
      end

      it 'computes 0 AND 0 = 0' do
        sim.poke('a', 0)
        sim.poke('b', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'computes 1 AND 0 = 0' do
        sim.poke('a', 0xFFFFFFFFFFFFFFFF)
        sim.poke('b', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'computes 1 AND 1 = 1' do
        sim.poke('a', 0xFFFFFFFFFFFFFFFF)
        sim.poke('b', 0xFFFFFFFFFFFFFFFF)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)
      end

      it 'computes lane-wise AND' do
        sim.poke('a', 0b1010)
        sim.poke('b', 0b1100)
        sim.evaluate
        expect(sim.peek('out')).to eq(0b1000)
      end
    end

    describe 'OR gate' do
      before do
        3.times { ir.new_net }
        ir.add_input('a', [0])
        ir.add_input('b', [1])
        ir.add_output('out', [2])
        ir.add_gate(type: :or, inputs: [0, 1], output: 2)
        ir.set_schedule([0])
      end

      it 'computes 0 OR 0 = 0' do
        sim.poke('a', 0)
        sim.poke('b', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'computes 1 OR 0 = 1' do
        sim.poke('a', 0xFFFFFFFFFFFFFFFF)
        sim.poke('b', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)
      end

      it 'computes lane-wise OR' do
        sim.poke('a', 0b1010)
        sim.poke('b', 0b1100)
        sim.evaluate
        expect(sim.peek('out')).to eq(0b1110)
      end
    end

    describe 'XOR gate' do
      before do
        3.times { ir.new_net }
        ir.add_input('a', [0])
        ir.add_input('b', [1])
        ir.add_output('out', [2])
        ir.add_gate(type: :xor, inputs: [0, 1], output: 2)
        ir.set_schedule([0])
      end

      it 'computes 0 XOR 0 = 0' do
        sim.poke('a', 0)
        sim.poke('b', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'computes 1 XOR 1 = 0' do
        sim.poke('a', 0xFFFFFFFFFFFFFFFF)
        sim.poke('b', 0xFFFFFFFFFFFFFFFF)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'computes lane-wise XOR' do
        sim.poke('a', 0b1010)
        sim.poke('b', 0b1100)
        sim.evaluate
        expect(sim.peek('out')).to eq(0b0110)
      end
    end

    describe 'NOT gate' do
      before do
        2.times { ir.new_net }
        ir.add_input('a', [0])
        ir.add_output('out', [1])
        ir.add_gate(type: :not, inputs: [0], output: 1)
        ir.set_schedule([0])
      end

      it 'computes NOT 0 = 1' do
        sim.poke('a', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)
      end

      it 'computes NOT 1 = 0' do
        sim.poke('a', 0xFFFFFFFFFFFFFFFF)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'computes lane-wise NOT' do
        sim.poke('a', 0b1010)
        sim.evaluate
        expect(sim.peek('out') & 0xF).to eq(0b0101)
      end
    end

    describe 'MUX gate' do
      before do
        4.times { ir.new_net }
        ir.add_input('a', [0])
        ir.add_input('b', [1])
        ir.add_input('sel', [2])
        ir.add_output('out', [3])
        ir.add_gate(type: :mux, inputs: [0, 1, 2], output: 3)
        ir.set_schedule([0])
      end

      it 'selects a when sel=0' do
        sim.poke('a', 0xAAAA)
        sim.poke('b', 0x5555)
        sim.poke('sel', 0)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xAAAA)
      end

      it 'selects b when sel=1' do
        sim.poke('a', 0xAAAA)
        sim.poke('b', 0x5555)
        sim.poke('sel', 0xFFFFFFFFFFFFFFFF)
        sim.evaluate
        expect(sim.peek('out')).to eq(0x5555)
      end

      it 'lane-wise mux selection' do
        sim.poke('a', 0xF0F0)
        sim.poke('b', 0x0F0F)
        sim.poke('sel', 0xFF00)
        sim.evaluate
        expect(sim.peek('out') & 0xFFFF).to eq(0x0FF0)
      end
    end

    describe 'BUF gate' do
      before do
        2.times { ir.new_net }
        ir.add_input('a', [0])
        ir.add_output('out', [1])
        ir.add_gate(type: :buf, inputs: [0], output: 1)
        ir.set_schedule([0])
      end

      it 'passes through the input' do
        sim.poke('a', 0xDEADBEEF)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xDEADBEEF)
      end
    end

    describe 'CONST gate' do
      it 'outputs 0 for const 0' do
        2.times { ir.new_net }
        ir.add_output('out', [1])
        ir.add_gate(type: :const, inputs: [], output: 1, value: 0)
        ir.set_schedule([0])
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'outputs all 1s for const 1' do
        2.times { ir.new_net }
        ir.add_output('out', [1])
        ir.add_gate(type: :const, inputs: [], output: 1, value: 1)
        ir.set_schedule([0])
        sim.evaluate
        expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)
      end
    end
  end

  describe 'multi-bit buses' do
    before do
      # 8-bit bus: inputs a[0:7], b[0:7], output out[0:7]
      # Simple bit-wise AND
      24.times { ir.new_net }
      ir.add_input('a', (0..7).to_a)
      ir.add_input('b', (8..15).to_a)
      ir.add_output('out', (16..23).to_a)
      8.times do |i|
        ir.add_gate(type: :and, inputs: [i, i + 8], output: i + 16)
      end
      ir.set_schedule((0..7).to_a)
    end

    it 'handles multi-bit poke with array values' do
      # Lane 0: a=0xFF, b=0x0F -> out=0x0F
      # Values are lane-indexed: [lane0_val, lane1_val, ...]
      sim.poke('a', [0xFF])
      sim.poke('b', [0x0F])
      sim.evaluate
      result = sim.peek('out')
      expect(result).to be_a(Array)
      expect(result.length).to eq(8)
    end
  end

  describe 'DFF behavior' do
    describe 'basic DFF' do
      before do
        2.times { ir.new_net }
        ir.add_input('d', [0])
        ir.add_output('q', [1])
        ir.add_dff(d: 0, q: 1)
      end

      it 'holds value after tick' do
        sim.poke('d', 0xFFFFFFFFFFFFFFFF)
        sim.tick
        expect(sim.peek('q')).to eq(0xFFFFFFFFFFFFFFFF)
      end

      it 'captures d on tick' do
        sim.poke('d', 0xAAAA)
        sim.tick
        sim.poke('d', 0x5555)
        expect(sim.peek('q')).to eq(0xAAAA)
        sim.tick
        expect(sim.peek('q')).to eq(0x5555)
      end
    end

    describe 'DFF with enable' do
      before do
        3.times { ir.new_net }
        ir.add_input('d', [0])
        ir.add_input('en', [1])
        ir.add_output('q', [2])
        ir.add_dff(d: 0, q: 2, en: 1)
      end

      it 'updates when enabled' do
        sim.poke('d', 0xAAAA)
        sim.poke('en', 0xFFFFFFFFFFFFFFFF)
        sim.tick
        expect(sim.peek('q')).to eq(0xAAAA)
      end

      it 'holds value when disabled' do
        sim.poke('d', 0xAAAA)
        sim.poke('en', 0xFFFFFFFFFFFFFFFF)
        sim.tick
        sim.poke('d', 0x5555)
        sim.poke('en', 0)
        sim.tick
        expect(sim.peek('q')).to eq(0xAAAA)
      end

      it 'lane-wise enable' do
        sim.poke('d', 0xFFFF)
        sim.poke('en', 0x00FF)
        sim.tick
        expect(sim.peek('q') & 0xFFFF).to eq(0x00FF)
      end
    end

    describe 'DFF with reset' do
      before do
        3.times { ir.new_net }
        ir.add_input('d', [0])
        ir.add_input('rst', [1])
        ir.add_output('q', [2])
        ir.add_dff(d: 0, q: 2, rst: 1)
      end

      it 'resets to 0 when reset is high' do
        sim.poke('d', 0xFFFFFFFFFFFFFFFF)
        sim.poke('rst', 0)
        sim.tick
        expect(sim.peek('q')).to eq(0xFFFFFFFFFFFFFFFF)

        sim.poke('rst', 0xFFFFFFFFFFFFFFFF)
        sim.tick
        expect(sim.peek('q')).to eq(0)
      end

      it 'lane-wise reset' do
        sim.poke('d', 0xFFFF)
        sim.poke('rst', 0x00FF)
        sim.tick
        expect(sim.peek('q') & 0xFFFF).to eq(0xFF00)
      end
    end
  end

  describe 'reset' do
    before do
      2.times { ir.new_net }
      ir.add_input('a', [0])
      ir.add_output('out', [1])
      ir.add_gate(type: :buf, inputs: [0], output: 1)
      ir.set_schedule([0])
    end

    it 'clears all nets' do
      sim.poke('a', 0xDEADBEEF)
      sim.evaluate
      expect(sim.peek('out')).to eq(0xDEADBEEF)

      sim.reset
      expect(sim.peek('out')).to eq(0)
    end
  end

  describe 'lane masking' do
    let(:sim) { described_class.new(ir, lanes: 8) }

    before do
      2.times { ir.new_net }
      ir.add_input('a', [0])
      ir.add_output('out', [1])
      ir.add_gate(type: :not, inputs: [0], output: 1)
      ir.set_schedule([0])
    end

    it 'masks output to lane count' do
      sim.poke('a', 0)
      sim.evaluate
      expect(sim.peek('out')).to eq(0xFF)
    end

    it 'masks input to lane count' do
      sim.poke('a', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('out')).to eq(0)
    end
  end

  describe 'combinational chains' do
    before do
      # a -> NOT -> AND -> out
      #       b ---^
      4.times { ir.new_net }
      ir.add_input('a', [0])
      ir.add_input('b', [1])
      ir.add_output('out', [3])
      ir.add_gate(type: :not, inputs: [0], output: 2)
      ir.add_gate(type: :and, inputs: [2, 1], output: 3)
      ir.set_schedule([0, 1])
    end

    it 'evaluates in correct order' do
      sim.poke('a', 0)
      sim.poke('b', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)

      sim.poke('a', 0xFFFFFFFFFFFFFFFF)
      sim.poke('b', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('out')).to eq(0)
    end
  end

  describe 'integration with HDL components' do
    it 'simulates a NOT gate from HDL' do
      component = RHDL::HDL::NotGate.new('not1')
      ir = RHDL::Codegen::Structure::Lower.from_components([component], name: 'not_test')
      sim = described_class.new(ir, lanes: 64)

      sim.poke('not1.a', 0)
      sim.evaluate
      expect(sim.peek('not1.y')).to eq(0xFFFFFFFFFFFFFFFF)

      sim.poke('not1.a', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('not1.y')).to eq(0)
    end

    it 'simulates an AND gate from HDL' do
      component = RHDL::HDL::AndGate.new('and1')
      ir = RHDL::Codegen::Structure::Lower.from_components([component], name: 'and_test')
      sim = described_class.new(ir, lanes: 64)

      # AND gate uses a0 and a1 as inputs (n-ary gate pattern)
      sim.poke('and1.a0', 0xFFFFFFFFFFFFFFFF)
      sim.poke('and1.a1', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('and1.y')).to eq(0xFFFFFFFFFFFFFFFF)

      sim.poke('and1.a0', 0xFFFFFFFFFFFFFFFF)
      sim.poke('and1.a1', 0)
      sim.evaluate
      expect(sim.peek('and1.y')).to eq(0)
    end

    it 'simulates a D flip-flop from HDL' do
      component = RHDL::HDL::DFlipFlop.new('dff1')
      ir = RHDL::Codegen::Structure::Lower.from_components([component], name: 'dff_test')
      sim = described_class.new(ir, lanes: 64)

      # DFF needs d, clk, rst=0, en=1 to capture
      sim.poke('dff1.d', 0xFFFFFFFFFFFFFFFF)
      sim.poke('dff1.clk', 0xFFFFFFFFFFFFFFFF)
      sim.poke('dff1.rst', 0)
      sim.poke('dff1.en', 0xFFFFFFFFFFFFFFFF)
      sim.tick
      expect(sim.peek('dff1.q')).to eq(0xFFFFFFFFFFFFFFFF)
    end
  end
end
