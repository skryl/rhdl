# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502::AddressLatch do
  let(:latch) { described_class.new('test_addr_latch') }

  describe 'simulation' do
    before do
      latch.set_input(:clk, 0)
      latch.set_input(:rst, 0)
      latch.set_input(:data_in, 0)
      latch.set_input(:load_lo, 0)
      latch.set_input(:load_hi, 0)
      latch.propagate
    end

    it 'loads low byte on load_lo signal' do
      latch.set_input(:data_in, 0x34)
      latch.set_input(:load_lo, 1)
      latch.set_input(:clk, 1)
      latch.propagate

      expect(latch.get_output(:addr) & 0xFF).to eq(0x34)
    end

    it 'loads high byte on load_hi signal' do
      latch.set_input(:data_in, 0x12)
      latch.set_input(:load_hi, 1)
      latch.set_input(:clk, 1)
      latch.propagate

      expect((latch.get_output(:addr) >> 8) & 0xFF).to eq(0x12)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_address_latch')
      expect(verilog).to include('addr')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavioral Verilog compiles and runs' do
        verilog = described_class.to_verilog

        inputs = { clk: 1, rst: 1, data_in: 8, load_lo: 1, load_hi: 1 }
        outputs = { addr: 16 }

        vectors = [
          { inputs: { clk: 0, rst: 0, data_in: 0x34, load_lo: 0, load_hi: 0 } },
          { inputs: { clk: 1, rst: 0, data_in: 0x34, load_lo: 1, load_hi: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0x12, load_lo: 0, load_hi: 1 } }
        ]

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 'mos6502_address_latch',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/mos6502_address_latch',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_address_latch') }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'mos6502_address_latch') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_address_latch.clk', 'mos6502_address_latch.rst')
      expect(ir.inputs.keys).to include('mos6502_address_latch.load_lo', 'mos6502_address_latch.load_hi')
      expect(ir.outputs.keys).to include('mos6502_address_latch.addr')
    end

    it 'generates DFFs for 16-bit address register' do
      # Address latch has 16-bit register requiring DFFs
      expect(ir.dffs.length).to be > 0
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mos6502_address_latch')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output [15:0] addr')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structural Verilog' do
        vectors = [
          { inputs: { clk: 0, rst: 0, data_in: 0x34, load_lo: 0, load_hi: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0x34, load_lo: 1, load_hi: 0 } },
          { inputs: { clk: 1, rst: 0, data_in: 0x34, load_lo: 1, load_hi: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0x12, load_lo: 0, load_hi: 1 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_address_latch')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
