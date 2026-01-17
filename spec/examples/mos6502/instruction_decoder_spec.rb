# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe MOS6502::InstructionDecoder do
  let(:decoder) { described_class.new('test_decoder') }

  describe 'simulation' do
    it 'decodes ADC immediate (0x69)' do
      decoder.set_input(:opcode, 0x69)
      decoder.propagate

      expect(decoder.get_output(:addr_mode)).to eq(MOS6502::InstructionDecoder::MODE_IMMEDIATE)
      expect(decoder.get_output(:alu_op)).to eq(MOS6502::InstructionDecoder::OP_ADC)
      expect(decoder.get_output(:illegal)).to eq(0)
    end

    it 'decodes LDA zero page (0xA5)' do
      decoder.set_input(:opcode, 0xA5)
      decoder.propagate

      expect(decoder.get_output(:addr_mode)).to eq(MOS6502::InstructionDecoder::MODE_ZERO_PAGE)
      expect(decoder.get_output(:instr_type)).to eq(MOS6502::InstructionDecoder::TYPE_LOAD)
    end

    it 'decodes STA absolute (0x8D)' do
      decoder.set_input(:opcode, 0x8D)
      decoder.propagate

      expect(decoder.get_output(:addr_mode)).to eq(MOS6502::InstructionDecoder::MODE_ABSOLUTE)
      expect(decoder.get_output(:instr_type)).to eq(MOS6502::InstructionDecoder::TYPE_STORE)
    end

    it 'decodes BEQ (0xF0)' do
      decoder.set_input(:opcode, 0xF0)
      decoder.propagate

      expect(decoder.get_output(:addr_mode)).to eq(MOS6502::InstructionDecoder::MODE_RELATIVE)
      expect(decoder.get_output(:instr_type)).to eq(MOS6502::InstructionDecoder::TYPE_BRANCH)
    end

    it 'decodes JMP absolute (0x4C)' do
      decoder.set_input(:opcode, 0x4C)
      decoder.propagate

      expect(decoder.get_output(:addr_mode)).to eq(MOS6502::InstructionDecoder::MODE_ABSOLUTE)
      expect(decoder.get_output(:instr_type)).to eq(MOS6502::InstructionDecoder::TYPE_JUMP)
    end

    it 'identifies illegal opcodes' do
      decoder.set_input(:opcode, 0x02)  # Illegal opcode
      decoder.propagate

      expect(decoder.get_output(:illegal)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_instruction_decoder')
      expect(verilog).to include('input [7:0] opcode')
      expect(verilog).to include('output')
      expect(verilog).to include('addr_mode')
    end

    it 'generates a complete decoder module' do
      verilog = described_class.to_verilog
      expect(verilog.length).to be > 1000  # Complex decoder
      expect(verilog).to include('endmodule')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_instruction_decoder') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mos6502_instruction_decoder') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_instruction_decoder.opcode')
      expect(ir.outputs.keys).to include('mos6502_instruction_decoder.addr_mode')
      expect(ir.outputs.keys).to include('mos6502_instruction_decoder.alu_op')
      expect(ir.outputs.keys).to include('mos6502_instruction_decoder.instr_type')
    end

    it 'generates gates for combinational logic' do
      # Decoder is purely combinational ROM-like structure
      expect(ir.gates.length).to be > 50
      expect(ir.dffs.length).to eq(0)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mos6502_instruction_decoder')
      expect(verilog).to include('input [7:0] opcode')
      expect(verilog).to include('output [3:0] addr_mode')
    end
  end
end
