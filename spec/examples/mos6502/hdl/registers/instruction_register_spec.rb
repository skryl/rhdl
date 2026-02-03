# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe MOS6502::InstructionRegister do
  let(:ir) { described_class.new('test_ir') }

  describe 'simulation' do
    before do
      ir.set_input(:clk, 0)
      ir.set_input(:rst, 0)
      ir.set_input(:data_in, 0)
      ir.set_input(:load_opcode, 0)
      ir.set_input(:load_operand_lo, 0)
      ir.set_input(:load_operand_hi, 0)
      ir.propagate
    end

    it 'loads opcode on load_opcode signal' do
      ir.set_input(:data_in, 0xA9)  # LDA immediate
      ir.set_input(:load_opcode, 1)
      ir.set_input(:clk, 1)
      ir.propagate

      expect(ir.get_output(:opcode)).to eq(0xA9)
    end

    it 'loads operand_lo on load_operand_lo signal' do
      ir.set_input(:data_in, 0x42)
      ir.set_input(:load_operand_lo, 1)
      ir.set_input(:clk, 1)
      ir.propagate

      expect(ir.get_output(:operand_lo)).to eq(0x42)
    end

    it 'loads operand_hi on load_operand_hi signal' do
      ir.set_input(:data_in, 0x80)
      ir.set_input(:load_operand_hi, 1)
      ir.set_input(:clk, 1)
      ir.propagate

      expect(ir.get_output(:operand_hi)).to eq(0x80)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_instruction_register')
      expect(verilog).to include('opcode')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog compiles and runs' do
        verilog = described_class.to_verilog

        inputs = { clk: 1, rst: 1, data_in: 8, load_opcode: 1, load_operand_lo: 1, load_operand_hi: 1 }
        outputs = { opcode: 8, operand_lo: 8, operand_hi: 8 }

        vectors = [
          { inputs: { clk: 0, rst: 0, data_in: 0xA9, load_opcode: 0, load_operand_lo: 0, load_operand_hi: 0 } },
          { inputs: { clk: 1, rst: 0, data_in: 0xA9, load_opcode: 1, load_operand_lo: 0, load_operand_hi: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0x42, load_opcode: 0, load_operand_lo: 1, load_operand_hi: 0 } }
        ]

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_instruction_register',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_instruction_register',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_instruction_register') }
    let(:netlist_ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_instruction_register') }

    it 'generates correct IR structure' do
      expect(netlist_ir.inputs.keys).to include('mos6502_instruction_register.clk', 'mos6502_instruction_register.rst')
      expect(netlist_ir.inputs.keys).to include('mos6502_instruction_register.load_opcode')
      expect(netlist_ir.outputs.keys).to include('mos6502_instruction_register.opcode')
    end

    it 'generates DFFs for opcode and operand registers' do
      # Instruction register has registers requiring DFFs
      expect(netlist_ir.dffs.length).to be > 0
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(netlist_ir)
      expect(verilog).to include('module mos6502_instruction_register')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output [7:0] opcode')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structure Verilog' do
        vectors = [
          { inputs: { clk: 0, rst: 0, data_in: 0xA9, load_opcode: 0, load_operand_lo: 0, load_operand_hi: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0xA9, load_opcode: 1, load_operand_lo: 0, load_operand_hi: 0 } },
          { inputs: { clk: 1, rst: 0, data_in: 0xA9, load_opcode: 1, load_operand_lo: 0, load_operand_hi: 0 } },
          { inputs: { clk: 0, rst: 0, data_in: 0x42, load_opcode: 0, load_operand_lo: 1, load_operand_hi: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(netlist_ir, vectors, base_dir: 'tmp/netlist_test/mos6502_instruction_register')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
