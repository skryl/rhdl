# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502::DataLatch do
  let(:latch) { described_class.new('test_data_latch') }

  describe 'simulation' do
    before do
      latch.set_input(:clk, 0)
      latch.set_input(:rst, 0)
      latch.set_input(:data_in, 0)
      latch.set_input(:load, 0)
      latch.propagate
    end

    it 'loads data on load signal' do
      latch.set_input(:data_in, 0x42)
      latch.set_input(:load, 1)
      latch.set_input(:clk, 1)
      latch.propagate

      expect(latch.get_output(:data)).to eq(0x42)
    end

    it 'holds data when load is low' do
      # First load a value
      latch.set_input(:data_in, 0x42)
      latch.set_input(:load, 1)
      latch.set_input(:clk, 1)
      latch.propagate

      # Change input but don't load
      latch.set_input(:clk, 0)
      latch.set_input(:load, 0)
      latch.set_input(:data_in, 0xFF)
      latch.propagate
      latch.set_input(:clk, 1)
      latch.propagate

      expect(latch.get_output(:data)).to eq(0x42)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_data_latch')
      expect(verilog).to include('data')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavioral Verilog compiles and runs' do
        verilog = described_class.to_verilog

        inputs = { clk: 1, rst: 1, data_in: 8, load: 1 }
        outputs = { data: 8 }

        vectors = [
          { inputs: { clk: 0, rst: 0, data_in: 0x42, load: 0 } },
          { inputs: { clk: 1, rst: 0, data_in: 0x42, load: 1 } },
          { inputs: { clk: 0, rst: 0, data_in: 0xFF, load: 0 } }
        ]

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 'mos6502_data_latch',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/mos6502_data_latch',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_data_latch') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mos6502_data_latch') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_data_latch.clk', 'mos6502_data_latch.rst')
      expect(ir.inputs.keys).to include('mos6502_data_latch.load')
      expect(ir.outputs.keys).to include('mos6502_data_latch.data')
    end

    it 'generates DFFs for 8-bit data register' do
      # Data latch has 8-bit register requiring DFFs
      expect(ir.dffs.length).to be > 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mos6502_data_latch')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output [7:0] data')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structural Verilog' do
        vectors = [
          { inputs: { clk: 0, rst: 0, data_in: 0x42, load: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0x42, load: 1 } },
          { inputs: { clk: 1, rst: 0, data_in: 0x42, load: 1 } },
          { inputs: { clk: 0, rst: 0, data_in: 0xFF, load: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_data_latch')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
