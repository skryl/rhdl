# Spec for MOS 6502S Synthesizable Components
# Tests basic functionality and Verilog generation

require 'active_support/core_ext/string/inflections'
require_relative '../../../lib/rhdl'
require_relative '../../../examples/mos6502s/datapath'
require_relative '../../../examples/mos6502s/memory'

RSpec.describe 'MOS6502S Synthesizable Components' do
  describe MOS6502S::Registers do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_registers')
      expect(verilog).to include('input  [7:0] data_in')
      expect(verilog).to include('output reg [7:0] a')
      expect(verilog).to include('always @(posedge clk')
    end

    it 'simulates correctly' do
      reg = described_class.new('test_reg')
      reg.set_input(:clk, 0)
      reg.set_input(:rst, 0)
      reg.set_input(:data_in, 0x42)
      reg.set_input(:load_a, 0)
      reg.set_input(:load_x, 0)
      reg.set_input(:load_y, 0)
      reg.propagate

      # Rising edge with load_a
      reg.set_input(:load_a, 1)
      reg.set_input(:clk, 1)
      reg.propagate

      expect(reg.read_a).to eq(0x42)
    end
  end

  describe MOS6502S::ALU do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_alu')
      expect(verilog).to include('localparam OP_ADC')
      expect(verilog).to include('localparam OP_SBC')
    end

    it 'performs ADC correctly' do
      alu = described_class.new('test_alu')
      alu.set_input(:a, 0x10)
      alu.set_input(:b, 0x05)
      alu.set_input(:c_in, 0)
      alu.set_input(:d_flag, 0)
      alu.set_input(:op, MOS6502S::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x15)
      expect(alu.get_output(:z)).to eq(0)
      expect(alu.get_output(:n)).to eq(0)
    end

    it 'performs AND correctly' do
      alu = described_class.new('test_alu')
      alu.set_input(:a, 0xFF)
      alu.set_input(:b, 0x0F)
      alu.set_input(:c_in, 0)
      alu.set_input(:d_flag, 0)
      alu.set_input(:op, MOS6502S::ALU::OP_AND)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x0F)
    end
  end

  describe MOS6502S::StatusRegister do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_status_register')
      expect(verilog).to include('localparam FLAG_N')
      expect(verilog).to include('localparam FLAG_C')
    end
  end

  describe MOS6502S::ProgramCounter do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_program_counter')
      expect(verilog).to include('output reg [15:0] pc')
    end
  end

  describe MOS6502S::InstructionDecoder do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_instruction_decoder')
      expect(verilog).to include('case (opcode)')
      # Check that opcodes are present
      expect(verilog).to include("8'h69") # ADC immediate
      expect(verilog).to include("8'hA9") # LDA immediate
    end

    it 'decodes ADC immediate correctly' do
      decoder = described_class.new('test_decoder')
      decoder.set_input(:opcode, 0x69)  # ADC immediate
      decoder.propagate

      expect(decoder.get_output(:addr_mode)).to eq(MOS6502S::InstructionDecoder::MODE_IMMEDIATE)
      expect(decoder.get_output(:alu_op)).to eq(MOS6502S::InstructionDecoder::OP_ADC)
      expect(decoder.get_output(:illegal)).to eq(0)
    end
  end

  describe MOS6502S::ControlUnit do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_control_unit')
      expect(verilog).to include('localparam STATE_FETCH')
      expect(verilog).to include('localparam STATE_EXECUTE')
    end
  end

  describe MOS6502S::AddressGenerator do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_address_generator')
      expect(verilog).to include('localparam MODE_ZERO_PAGE')
    end

    it 'computes zero page address correctly' do
      ag = described_class.new('test_ag')
      ag.set_input(:mode, MOS6502S::AddressGenerator::MODE_ZERO_PAGE)
      ag.set_input(:operand_lo, 0x80)
      ag.set_input(:operand_hi, 0)
      ag.set_input(:x_reg, 0)
      ag.set_input(:y_reg, 0)
      ag.set_input(:pc, 0)
      ag.set_input(:sp, 0)
      ag.set_input(:indirect_lo, 0)
      ag.set_input(:indirect_hi, 0)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x0080)
      expect(ag.get_output(:is_zero_page)).to eq(1)
    end
  end

  describe MOS6502S::Memory do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_memory')
    end
  end

  describe 'All components' do
    it 'can generate complete Verilog output' do
      components = [
        MOS6502S::Registers,
        MOS6502S::StackPointer,
        MOS6502S::ProgramCounter,
        MOS6502S::InstructionRegister,
        MOS6502S::AddressLatch,
        MOS6502S::DataLatch,
        MOS6502S::StatusRegister,
        MOS6502S::AddressGenerator,
        MOS6502S::IndirectAddressCalc,
        MOS6502S::ALU,
        MOS6502S::InstructionDecoder,
        MOS6502S::ControlUnit,
        MOS6502S::Memory
      ]

      components.each do |klass|
        expect(klass).to respond_to(:to_verilog)
        verilog = klass.to_verilog
        expect(verilog).to include('module mos6502s_')
        expect(verilog).to include('endmodule')
      end
    end
  end
end
