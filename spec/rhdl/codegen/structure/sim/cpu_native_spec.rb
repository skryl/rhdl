# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe RHDL::Codegen::Structure::SimCPUNative, if: RHDL::Codegen::Structure::NATIVE_SIM_AVAILABLE do
  # Helper to create a simple IR JSON
  def make_ir_json(name: 'test', net_count: 0, gates: [], dffs: [], inputs: {}, outputs: {}, schedule: [])
    {
      name: name,
      net_count: net_count,
      gates: gates,
      dffs: dffs,
      inputs: inputs,
      outputs: outputs,
      schedule: schedule
    }.to_json
  end

  describe 'initialization' do
    it 'creates a simulator from JSON' do
      json = make_ir_json(net_count: 2, inputs: { 'a' => [0] }, outputs: { 'out' => [1] })
      sim = described_class.new(json, 64)
      expect(sim).not_to be_nil
      expect(sim.native?).to be true
    end

    it 'reports correct statistics' do
      json = make_ir_json(
        net_count: 3,
        gates: [{ type: 'and', inputs: [0, 1], output: 2, value: nil }],
        inputs: { 'a' => [0], 'b' => [1] },
        outputs: { 'out' => [2] },
        schedule: [0]
      )
      sim = described_class.new(json, 64)
      stats = sim.stats
      expect(stats[:net_count]).to eq(3)
      expect(stats[:gate_count]).to eq(1)
      expect(stats[:lanes]).to eq(64)
    end
  end

  describe 'basic gates' do
    describe 'AND gate' do
      let(:json) do
        make_ir_json(
          net_count: 3,
          gates: [{ type: 'and', inputs: [0, 1], output: 2, value: nil }],
          inputs: { 'a' => [0], 'b' => [1] },
          outputs: { 'out' => [2] },
          schedule: [0]
        )
      end
      let(:sim) { described_class.new(json, 64) }

      it 'computes 0 AND 0 = 0' do
        sim.poke('a', 0)
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
      let(:json) do
        make_ir_json(
          net_count: 3,
          gates: [{ type: 'or', inputs: [0, 1], output: 2, value: nil }],
          inputs: { 'a' => [0], 'b' => [1] },
          outputs: { 'out' => [2] },
          schedule: [0]
        )
      end
      let(:sim) { described_class.new(json, 64) }

      it 'computes lane-wise OR' do
        sim.poke('a', 0b1010)
        sim.poke('b', 0b1100)
        sim.evaluate
        expect(sim.peek('out')).to eq(0b1110)
      end
    end

    describe 'XOR gate' do
      let(:json) do
        make_ir_json(
          net_count: 3,
          gates: [{ type: 'xor', inputs: [0, 1], output: 2, value: nil }],
          inputs: { 'a' => [0], 'b' => [1] },
          outputs: { 'out' => [2] },
          schedule: [0]
        )
      end
      let(:sim) { described_class.new(json, 64) }

      it 'computes lane-wise XOR' do
        sim.poke('a', 0b1010)
        sim.poke('b', 0b1100)
        sim.evaluate
        expect(sim.peek('out')).to eq(0b0110)
      end
    end

    describe 'NOT gate' do
      let(:json) do
        make_ir_json(
          net_count: 2,
          gates: [{ type: 'not', inputs: [0], output: 1, value: nil }],
          inputs: { 'a' => [0] },
          outputs: { 'out' => [1] },
          schedule: [0]
        )
      end
      let(:sim) { described_class.new(json, 64) }

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
    end

    describe 'MUX gate' do
      let(:json) do
        make_ir_json(
          net_count: 4,
          gates: [{ type: 'mux', inputs: [0, 1, 2], output: 3, value: nil }],
          inputs: { 'a' => [0], 'b' => [1], 'sel' => [2] },
          outputs: { 'out' => [3] },
          schedule: [0]
        )
      end
      let(:sim) { described_class.new(json, 64) }

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
    end

    describe 'BUF gate' do
      let(:json) do
        make_ir_json(
          net_count: 2,
          gates: [{ type: 'buf', inputs: [0], output: 1, value: nil }],
          inputs: { 'a' => [0] },
          outputs: { 'out' => [1] },
          schedule: [0]
        )
      end
      let(:sim) { described_class.new(json, 64) }

      it 'passes through the input' do
        sim.poke('a', 0xDEADBEEF)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xDEADBEEF)
      end
    end

    describe 'CONST gate' do
      it 'outputs 0 for const 0' do
        json = make_ir_json(
          net_count: 1,
          gates: [{ type: 'const', inputs: [], output: 0, value: 0 }],
          inputs: {},
          outputs: { 'out' => [0] },
          schedule: [0]
        )
        sim = described_class.new(json, 64)
        sim.evaluate
        expect(sim.peek('out')).to eq(0)
      end

      it 'outputs all 1s for const 1' do
        json = make_ir_json(
          net_count: 1,
          gates: [{ type: 'const', inputs: [], output: 0, value: 1 }],
          inputs: {},
          outputs: { 'out' => [0] },
          schedule: [0]
        )
        sim = described_class.new(json, 64)
        sim.evaluate
        expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)
      end
    end
  end

  describe 'DFF behavior' do
    describe 'basic DFF' do
      let(:json) do
        make_ir_json(
          net_count: 2,
          dffs: [{ d: 0, q: 1, rst: nil, en: nil, async_reset: false }],
          inputs: { 'd' => [0] },
          outputs: { 'q' => [1] },
          schedule: []
        )
      end
      let(:sim) { described_class.new(json, 64) }

      it 'captures d on tick' do
        sim.poke('d', 0xAAAA)
        sim.tick
        expect(sim.peek('q')).to eq(0xAAAA)

        sim.poke('d', 0x5555)
        expect(sim.peek('q')).to eq(0xAAAA)

        sim.tick
        expect(sim.peek('q')).to eq(0x5555)
      end
    end

    describe 'DFF with enable' do
      let(:json) do
        make_ir_json(
          net_count: 3,
          dffs: [{ d: 0, q: 2, rst: nil, en: 1, async_reset: false }],
          inputs: { 'd' => [0], 'en' => [1] },
          outputs: { 'q' => [2] },
          schedule: []
        )
      end
      let(:sim) { described_class.new(json, 64) }

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
    end

    describe 'DFF with reset' do
      let(:json) do
        make_ir_json(
          net_count: 3,
          dffs: [{ d: 0, q: 2, rst: 1, en: nil, async_reset: false }],
          inputs: { 'd' => [0], 'rst' => [1] },
          outputs: { 'q' => [2] },
          schedule: []
        )
      end
      let(:sim) { described_class.new(json, 64) }

      it 'resets to 0 when reset is high' do
        sim.poke('d', 0xFFFFFFFFFFFFFFFF)
        sim.poke('rst', 0)
        sim.tick
        expect(sim.peek('q')).to eq(0xFFFFFFFFFFFFFFFF)

        sim.poke('rst', 0xFFFFFFFFFFFFFFFF)
        sim.tick
        expect(sim.peek('q')).to eq(0)
      end
    end
  end

  describe 'reset' do
    let(:json) do
      make_ir_json(
        net_count: 2,
        gates: [{ type: 'buf', inputs: [0], output: 1, value: nil }],
        inputs: { 'a' => [0] },
        outputs: { 'out' => [1] },
        schedule: [0]
      )
    end
    let(:sim) { described_class.new(json, 64) }

    it 'clears all nets' do
      sim.poke('a', 0xDEADBEEF)
      sim.evaluate
      expect(sim.peek('out')).to eq(0xDEADBEEF)

      sim.reset
      expect(sim.peek('out')).to eq(0)
    end
  end

  describe 'integration with HDL components' do
    it 'simulates a NOT gate from HDL' do
      component = RHDL::HDL::NotGate.new('not1')
      ir = RHDL::Codegen::Structure::Lower.from_components([component], name: 'not_test')
      sim = described_class.new(ir.to_json, 64)

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
      sim = described_class.new(ir.to_json, 64)

      sim.poke('and1.a0', 0xFFFFFFFFFFFFFFFF)
      sim.poke('and1.a1', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('and1.y')).to eq(0xFFFFFFFFFFFFFFFF)

      sim.poke('and1.a0', 0xFFFFFFFFFFFFFFFF)
      sim.poke('and1.a1', 0)
      sim.evaluate
      expect(sim.peek('and1.y')).to eq(0)
    end
  end

  describe 'equivalence with Ruby SimCPU' do
    it 'produces same results for combinational logic' do
      component = RHDL::HDL::NotGate.new('not1')
      ir = RHDL::Codegen::Structure::Lower.from_components([component], name: 'not_test')

      ruby_sim = RHDL::Codegen::Structure::SimCPU.new(ir, lanes: 64)
      native_sim = described_class.new(ir.to_json, 64)

      [0, 0xFFFFFFFFFFFFFFFF, 0xAAAA, 0x5555, 0xDEADBEEF].each do |val|
        ruby_sim.poke('not1.a', val)
        ruby_sim.evaluate
        ruby_result = ruby_sim.peek('not1.y')

        native_sim.poke('not1.a', val)
        native_sim.evaluate
        native_result = native_sim.peek('not1.y')

        expect(native_result).to eq(ruby_result), "Mismatch for input #{val.to_s(16)}"
      end
    end

    it 'produces same results for sequential logic' do
      # Simple DFF through IR
      ir = RHDL::Codegen::Structure::IR.new(name: 'dff_test')
      2.times { ir.new_net }
      ir.add_input('d', [0])
      ir.add_output('q', [1])
      ir.add_dff(d: 0, q: 1)

      ruby_sim = RHDL::Codegen::Structure::SimCPU.new(ir, lanes: 64)
      native_sim = described_class.new(ir.to_json, 64)

      [0xAAAA, 0x5555, 0xDEADBEEF, 0].each do |val|
        ruby_sim.poke('d', val)
        ruby_sim.tick
        ruby_result = ruby_sim.peek('q')

        native_sim.poke('d', val)
        native_sim.tick
        native_result = native_sim.peek('q')

        expect(native_result).to eq(ruby_result), "Mismatch after tick with input #{val.to_s(16)}"
      end
    end
  end
end

RSpec.describe RHDL::Codegen::Structure::SimCPUNativeWrapper do
  let(:ir) do
    ir = RHDL::Codegen::Structure::IR.new(name: 'test')
    3.times { ir.new_net }
    ir.add_input('a', [0])
    ir.add_input('b', [1])
    ir.add_output('out', [2])
    ir.add_gate(type: :and, inputs: [0, 1], output: 2)
    ir.set_schedule([0])
    ir
  end

  describe 'when native is available', if: RHDL::Codegen::Structure::NATIVE_SIM_AVAILABLE do
    let(:sim) { described_class.new(ir, lanes: 64) }

    it 'uses native implementation' do
      expect(sim.native?).to be true
    end

    it 'computes correct results' do
      sim.poke('a', 0xFFFFFFFFFFFFFFFF)
      sim.poke('b', 0xFFFFFFFFFFFFFFFF)
      sim.evaluate
      expect(sim.peek('out')).to eq(0xFFFFFFFFFFFFFFFF)
    end
  end

  describe 'fallback behavior' do
    # This tests the fallback path - we can't easily test this when native is available
    # but we can at least test the wrapper interface
    let(:sim) { described_class.new(ir, lanes: 64) }

    it 'provides stats' do
      stats = sim.stats
      expect(stats[:net_count]).to eq(3)
      expect(stats[:gate_count]).to eq(1)
    end

    it 'has correct IR reference' do
      expect(sim.ir).to eq(ir)
    end

    it 'has correct lanes' do
      expect(sim.lanes).to eq(64)
    end
  end
end
