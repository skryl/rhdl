# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::CPU::InstructionDecoder do
  let(:decoder) { RHDL::HDL::CPU::InstructionDecoder.new }

  describe 'simulation' do
    it 'decodes NOP instruction' do
      decoder.set_input(:instruction, 0x00)
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:alu_op)).to eq(0)
      expect(decoder.get_output(:reg_write)).to eq(0)
      expect(decoder.get_output(:mem_read)).to eq(0)
      expect(decoder.get_output(:mem_write)).to eq(0)
      expect(decoder.get_output(:halt)).to eq(0)
    end

    it 'decodes LDA instruction' do
      decoder.set_input(:instruction, 0x15)  # LDA 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:reg_write)).to eq(1)
      expect(decoder.get_output(:mem_read)).to eq(1)
      expect(decoder.get_output(:mem_write)).to eq(0)
    end

    it 'decodes STA instruction' do
      decoder.set_input(:instruction, 0x25)  # STA 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:reg_write)).to eq(0)
      expect(decoder.get_output(:mem_read)).to eq(0)
      expect(decoder.get_output(:mem_write)).to eq(1)
    end

    it 'decodes ADD instruction' do
      decoder.set_input(:instruction, 0x35)  # ADD 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:alu_op)).to eq(0)  # ADD
      expect(decoder.get_output(:reg_write)).to eq(1)
      expect(decoder.get_output(:mem_read)).to eq(1)
    end

    it 'decodes SUB instruction' do
      decoder.set_input(:instruction, 0x45)  # SUB 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:alu_op)).to eq(1)  # SUB
      expect(decoder.get_output(:reg_write)).to eq(1)
      expect(decoder.get_output(:mem_read)).to eq(1)
    end

    it 'decodes LDI instruction' do
      decoder.set_input(:instruction, 0xA0)  # LDI
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:alu_src)).to eq(1)  # Immediate
      expect(decoder.get_output(:reg_write)).to eq(1)
      expect(decoder.get_output(:instr_length)).to eq(2)
    end

    it 'decodes JMP instruction' do
      decoder.set_input(:instruction, 0xB5)  # JMP 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:jump)).to eq(1)
      expect(decoder.get_output(:pc_src)).to eq(1)
    end

    it 'decodes JZ instruction when zero flag set' do
      decoder.set_input(:instruction, 0x85)  # JZ 5
      decoder.set_input(:zero_flag, 1)
      decoder.propagate

      expect(decoder.get_output(:branch)).to eq(1)
      expect(decoder.get_output(:pc_src)).to eq(1)  # Take branch
    end

    it 'decodes JZ instruction when zero flag clear' do
      decoder.set_input(:instruction, 0x85)  # JZ 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:branch)).to eq(1)
      expect(decoder.get_output(:pc_src)).to eq(0)  # Don't take branch
    end

    it 'decodes HLT instruction' do
      decoder.set_input(:instruction, 0xF0)  # HLT
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:halt)).to eq(1)
    end

    it 'decodes CALL instruction' do
      decoder.set_input(:instruction, 0xC5)  # CALL 5
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:call)).to eq(1)
      expect(decoder.get_output(:pc_src)).to eq(1)
    end

    it 'decodes RET instruction' do
      decoder.set_input(:instruction, 0xD0)  # RET
      decoder.set_input(:zero_flag, 0)
      decoder.propagate

      expect(decoder.get_output(:ret)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::CPU::InstructionDecoder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::CPU::InstructionDecoder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      # 2 inputs (instruction, zero_flag) + 15 outputs
      expect(ir.ports.length).to eq(17)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::CPU::InstructionDecoder.to_verilog
      expect(verilog).to include('module cpu_instruction_decoder')
      expect(verilog).to include('input [7:0] instruction')
      expect(verilog).to include('input zero_flag')
      expect(verilog).to include('output [3:0] alu_op')
      expect(verilog).to include('output halt')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::CPU::InstructionDecoder.new('decoder') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'decoder') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('decoder.instruction', 'decoder.zero_flag')
      expect(ir.outputs.keys).to include('decoder.alu_op', 'decoder.halt', 'decoder.reg_write', 'decoder.is_lda')
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module decoder')
      expect(verilog).to include('input [7:0] instruction')
      expect(verilog).to include('output halt')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'simulates HLT instruction correctly' do
        vectors = [
          { inputs: { instruction: 0xF0, zero_flag: 0 }, expected: { halt: 1 } },
          { inputs: { instruction: 0x00, zero_flag: 0 }, expected: { halt: 0 } },
          { inputs: { instruction: 0xA0, zero_flag: 0 }, expected: { halt: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors,
          base_dir: 'tmp/netlist_test/decoder')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx][:halt]).to eq(vec[:expected][:halt])
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results' do
        test_cases = [
          { instruction: 0x00, zero_flag: 0 },  # NOP
          { instruction: 0x15, zero_flag: 0 },  # LDA
          { instruction: 0x25, zero_flag: 0 },  # STA
          { instruction: 0x35, zero_flag: 0 },  # ADD
          { instruction: 0x45, zero_flag: 0 },  # SUB
          { instruction: 0x85, zero_flag: 1 },  # JZ (taken)
          { instruction: 0x85, zero_flag: 0 },  # JZ (not taken)
          { instruction: 0xF0, zero_flag: 0 }   # HLT
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::CPU::InstructionDecoder,
          'instruction_decoder',
          test_cases,
          base_dir: 'tmp/netlist_comparison/instruction_decoder',
          has_clock: false
        )
      end
    end
  end
end
