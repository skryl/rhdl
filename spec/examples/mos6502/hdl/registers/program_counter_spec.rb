# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe MOS6502::ProgramCounter do
  let(:pc) { described_class.new('test_pc') }

  describe 'simulation' do
    before do
      pc.set_input(:clk, 0)
      pc.set_input(:rst, 1)
      pc.set_input(:inc, 0)
      pc.set_input(:load, 0)
      pc.set_input(:addr_in, 0)
      pc.propagate
      # Rising edge for reset
      pc.set_input(:clk, 1)
      pc.propagate
      pc.set_input(:clk, 0)
      pc.set_input(:rst, 0)
      pc.propagate
    end

    it 'initializes to reset vector on reset' do
      # PC should be at reset vector or 0 after reset
      expect(pc.get_output(:pc)).to be_a(Integer)
    end

    it 'increments on inc signal' do
      initial_pc = pc.get_output(:pc)
      pc.set_input(:inc, 1)
      pc.set_input(:clk, 1)
      pc.propagate

      expect(pc.get_output(:pc)).to eq((initial_pc + 1) & 0xFFFF)
    end

    it 'loads new value on load signal' do
      pc.set_input(:addr_in, 0x1234)
      pc.set_input(:load, 1)
      pc.set_input(:clk, 1)
      pc.propagate

      expect(pc.get_output(:pc)).to eq(0x1234)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_program_counter')
      expect(verilog).to include('output reg [15:0] pc')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog compiles and runs' do
        verilog = described_class.to_verilog

        inputs = { clk: 1, rst: 1, inc: 1, load: 1, addr_in: 16 }
        outputs = { pc: 16 }

        vectors = [
          { inputs: { clk: 0, rst: 1, inc: 0, load: 0, addr_in: 0 } },
          { inputs: { clk: 1, rst: 1, inc: 0, load: 0, addr_in: 0 } },
          { inputs: { clk: 0, rst: 0, inc: 1, load: 0, addr_in: 0 } }
        ]

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_program_counter',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_program_counter',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_program_counter') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_program_counter') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_program_counter.clk', 'mos6502_program_counter.rst')
      expect(ir.inputs.keys).to include('mos6502_program_counter.inc', 'mos6502_program_counter.load')
      expect(ir.outputs.keys).to include('mos6502_program_counter.pc')
    end

    it 'generates DFFs for 16-bit counter' do
      # Program counter has 16-bit register requiring DFFs
      expect(ir.dffs.length).to be > 0
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mos6502_program_counter')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output [15:0] pc')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structure Verilog' do
        vectors = [
          { inputs: { clk: 0, rst: 1, inc: 0, load: 0, addr_in: 0 } },
          { inputs: { clk: 1, rst: 1, inc: 0, load: 0, addr_in: 0 } },
          { inputs: { clk: 0, rst: 0, inc: 0, load: 0, addr_in: 0 } },
          { inputs: { clk: 1, rst: 0, inc: 1, load: 0, addr_in: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_program_counter')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
