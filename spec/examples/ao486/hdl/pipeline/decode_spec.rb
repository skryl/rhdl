require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/pipeline/decode'

RSpec.describe RHDL::Examples::AO486::Decode do
  C = RHDL::Examples::AO486::Constants unless defined?(C)
  let(:dec) { RHDL::Examples::AO486::Decode.new }

  # Helper: feed instruction bytes and decode
  def decode_bytes(d, *bytes)
    d.set_input(:fetch_valid, bytes.length)
    # Pack bytes into 64-bit fetch word (little-endian: byte0 = bits[7:0])
    fetch_val = 0
    bytes.each_with_index { |b, i| fetch_val |= (b << (i * 8)) }
    d.set_input(:fetch, fetch_val)
    d.set_input(:operand_32bit, 0)  # real mode: 16-bit default
    d.set_input(:address_32bit, 0)  # real mode: 16-bit default
    d.propagate
  end

  describe 'NOP (0x90)' do
    it 'decodes NOP as XCHG EAX,EAX with consumed=1' do
      decode_bytes(dec, 0x90)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_XCHG)
      expect(dec.get_output(:dec_consumed)).to eq(1)
      expect(dec.get_output(:dec_ready)).to eq(1)
    end
  end

  describe 'HLT (0xF4)' do
    it 'decodes HLT with consumed=1' do
      decode_bytes(dec, 0xF4)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_HLT)
      expect(dec.get_output(:dec_consumed)).to eq(1)
      expect(dec.get_output(:dec_ready)).to eq(1)
    end
  end

  describe 'MOV reg, imm (0xB0-0xBF)' do
    it 'decodes MOV AL, 0x42 (8-bit)' do
      decode_bytes(dec, 0xB0, 0x42)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_MOV)
      expect(dec.get_output(:dec_consumed)).to eq(2)
      expect(dec.get_output(:dec_is_8bit)).to eq(1)
      expect(dec.get_output(:dec_ready)).to eq(1)
    end

    it 'decodes MOV AX, 0x1234 (16-bit in real mode)' do
      decode_bytes(dec, 0xB8, 0x34, 0x12)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_MOV)
      expect(dec.get_output(:dec_consumed)).to eq(3)
      expect(dec.get_output(:dec_is_8bit)).to eq(0)
    end
  end

  describe 'arithmetic group (0x00-0x3F)' do
    it 'decodes ADD AL, imm8 (0x04)' do
      decode_bytes(dec, 0x04, 0x10)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_ADD)
      expect(dec.get_output(:dec_consumed)).to eq(2)
      expect(dec.get_output(:dec_is_8bit)).to eq(1)
    end

    it 'decodes SUB AX, imm16 (0x2D)' do
      decode_bytes(dec, 0x2D, 0x34, 0x12)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_SUB)
      expect(dec.get_output(:dec_consumed)).to eq(3)
      expect(dec.get_output(:dec_is_8bit)).to eq(0)
    end

    it 'decodes CMP r/m, r with ModR/M (0x39 0xC0 = CMP EAX, EAX)' do
      decode_bytes(dec, 0x39, 0xC0)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_CMP)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end
  end

  describe 'immediate group (0x80-0x83)' do
    it 'decodes ADD r/m8, imm8 (0x80 /0)' do
      decode_bytes(dec, 0x80, 0xC0, 0x10)  # ADD AL, 0x10
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_ADD)
      expect(dec.get_output(:dec_consumed)).to eq(3)
    end

    it 'decodes SUB r/m16, sign-ext-imm8 (0x83 /5)' do
      decode_bytes(dec, 0x83, 0xE8, 0x10)  # SUB AX, 0x10
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_SUB)
      expect(dec.get_output(:dec_consumed)).to eq(3)
    end
  end

  describe 'INC/DEC register (0x40-0x4F)' do
    it 'decodes INC AX (0x40)' do
      decode_bytes(dec, 0x40)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_INC_DEC)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes DEC CX (0x49)' do
      decode_bytes(dec, 0x49)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_INC_DEC)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end
  end

  describe 'PUSH/POP register (0x50-0x5F)' do
    it 'decodes PUSH AX (0x50)' do
      decode_bytes(dec, 0x50)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_PUSH)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes POP BX (0x5B)' do
      decode_bytes(dec, 0x5B)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_POP)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end
  end

  describe 'control flow' do
    it 'decodes JMP short (0xEB disp8)' do
      decode_bytes(dec, 0xEB, 0xFE)  # JMP $-2
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_JMP)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end

    it 'decodes JMP near (0xE9 disp16 in real mode)' do
      decode_bytes(dec, 0xE9, 0x00, 0x10)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_JMP)
      expect(dec.get_output(:dec_consumed)).to eq(3)
    end

    it 'decodes CALL near (0xE8 disp16 in real mode)' do
      decode_bytes(dec, 0xE8, 0x00, 0x10)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_CALL)
      expect(dec.get_output(:dec_consumed)).to eq(3)
    end

    it 'decodes RET near (0xC3)' do
      decode_bytes(dec, 0xC3)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_RET_near)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes Jcc short (0x74 = JE)' do
      decode_bytes(dec, 0x74, 0x10)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_Jcc)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end
  end

  describe 'interrupt/flags' do
    it 'decodes INT 0x21 (0xCD 0x21)' do
      decode_bytes(dec, 0xCD, 0x21)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_INT_INTO)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end

    it 'decodes INT3 (0xCC)' do
      decode_bytes(dec, 0xCC)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_INT_INTO)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes IRET (0xCF)' do
      decode_bytes(dec, 0xCF)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_IRET)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes CLI (0xFA)' do
      decode_bytes(dec, 0xFA)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_CLI)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes STI (0xFB)' do
      decode_bytes(dec, 0xFB)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_STI)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes CLD (0xFC)' do
      decode_bytes(dec, 0xFC)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_CLD)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes STD (0xFD)' do
      decode_bytes(dec, 0xFD)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_STD)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes CLC (0xF8)' do
      decode_bytes(dec, 0xF8)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_CLC)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end

    it 'decodes STC (0xF9)' do
      decode_bytes(dec, 0xF9)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_STC)
      expect(dec.get_output(:dec_consumed)).to eq(1)
    end
  end

  describe 'prefix handling' do
    it 'decodes operand-size prefix (0x66) toggling to 32-bit' do
      # 0x66 B8 78 56 34 12 = MOV EAX, 0x12345678
      decode_bytes(dec, 0x66, 0xB8, 0x78, 0x56, 0x34, 0x12)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_MOV)
      expect(dec.get_output(:dec_consumed)).to eq(6)
      expect(dec.get_output(:dec_operand_32bit)).to eq(1)
    end

    it 'decodes segment override prefix' do
      # 0x26 A1 00 10 = MOV AX, ES:[0x1000]
      decode_bytes(dec, 0x26, 0xA1, 0x00, 0x10)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_MOV)
      expect(dec.get_output(:dec_prefix_group_2_seg)).to eq(C::SEGMENT_ES)
    end
  end

  describe 'MOV ModR/M forms' do
    it 'decodes MOV r/m16, r16 (0x89 0xC8 = MOV AX, CX)' do
      decode_bytes(dec, 0x89, 0xC8)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_MOV)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end
  end

  describe 'TEST instructions' do
    it 'decodes TEST AL, imm8 (0xA8)' do
      decode_bytes(dec, 0xA8, 0xFF)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_TEST)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end
  end

  describe 'shifts' do
    it 'decodes SHL/SAL with CL (0xD3 0xE0 = SHL AX, CL)' do
      decode_bytes(dec, 0xD3, 0xE0)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_Shift)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end
  end

  describe 'LEA' do
    it 'decodes LEA r16, m (0x8D)' do
      # LEA AX, [BX+SI] = 0x8D 0x00 (16-bit addr, MOD=00 R/M=000)
      decode_bytes(dec, 0x8D, 0x00)
      expect(dec.get_output(:dec_cmd)).to eq(C::CMD_LEA)
      expect(dec.get_output(:dec_consumed)).to eq(2)
    end
  end

  describe 'not ready when insufficient bytes' do
    it 'reports not ready when fetch_valid < required' do
      # MOV AX, imm16 needs 3 bytes but only 1 available
      dec.set_input(:fetch_valid, 1)
      dec.set_input(:fetch, 0xB8)
      dec.set_input(:operand_32bit, 0)
      dec.set_input(:address_32bit, 0)
      dec.propagate
      expect(dec.get_output(:dec_ready)).to eq(0)
    end
  end
end
