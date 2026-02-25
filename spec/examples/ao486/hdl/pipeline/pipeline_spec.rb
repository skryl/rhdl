# spec/examples/ao486/hdl/pipeline/pipeline_spec.rb
# RED spec for Pipeline integration — Phase 5 end-to-end instruction tests

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline do
  let(:pipeline) { described_class.new }

  # Helper: write bytes at an address in the memory hash
  def write_code(memory, addr, *bytes)
    bytes.each_with_index { |b, i| memory[(addr + i) & 0xFFFF_FFFF] = b & 0xFF }
  end

  # Helper: write a 16-bit little-endian value
  def write_word(memory, addr, val)
    memory[addr]     = val & 0xFF
    memory[addr + 1] = (val >> 8) & 0xFF
  end

  # Helper: write a 32-bit little-endian value
  def write_dword(memory, addr, val)
    memory[addr]     = val & 0xFF
    memory[addr + 1] = (val >> 8) & 0xFF
    memory[addr + 2] = (val >> 16) & 0xFF
    memory[addr + 3] = (val >> 24) & 0xFF
  end

  # Helper: read 32-bit LE from memory
  def read_dword(memory, addr)
    (memory[addr] || 0) |
      ((memory[addr + 1] || 0) << 8) |
      ((memory[addr + 2] || 0) << 16) |
      ((memory[addr + 3] || 0) << 24)
  end

  # Helper: read 16-bit LE from memory
  def read_word(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8)
  end

  # Default startup: CS base = 0xFFFF0000, EIP = 0xFFF0
  # Linear address = 0xFFFF0000 + 0xFFF0 = 0xFFFF_FFF0 (reset vector)
  # For testing, we'll configure to a simpler address.

  describe 'setup' do
    it 'starts in real mode with startup register values' do
      expect(pipeline.reg(:eip)).to eq(C::STARTUP_EIP)  # 0xFFF0
      expect(pipeline.reg(:eax)).to eq(C::STARTUP_EAX)
      expect(pipeline.reg(:cr0_pe)).to eq(0)
    end
  end

  # For easier testing, set CS base to 0 and EIP to a known address.
  # The pipeline should provide a way to set up initial state.
  context 'with CS base=0, EIP=0x7C00 (boot sector style)' do
    let(:memory) { {} }

    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    describe 'MOV reg, imm' do
      it 'MOV EAX, 0x12345678 (B8 + dword)' do
        # In 16-bit real mode, need 0x66 prefix for 32-bit operand
        write_code(memory, 0x7C00, 0x66, 0xB8, 0x78, 0x56, 0x34, 0x12)
        pipeline.step(memory)
        expect(pipeline.reg(:eax)).to eq(0x12345678)
        expect(pipeline.reg(:eip)).to eq(0x7C06)
      end

      it 'MOV AX, 0x0042 (B8 + word, 16-bit mode)' do
        write_code(memory, 0x7C00, 0xB8, 0x42, 0x00)
        pipeline.step(memory)
        expect(pipeline.reg(:eax)).to eq(0x0042)
        expect(pipeline.reg(:eip)).to eq(0x7C03)
      end

      it 'MOV BL, 0xFF (B3 + byte)' do
        write_code(memory, 0x7C00, 0xB3, 0xFF)
        pipeline.step(memory)
        expect(pipeline.reg(:ebx) & 0xFF).to eq(0xFF)
        expect(pipeline.reg(:eip)).to eq(0x7C02)
      end
    end

    describe 'MOV r/m, r and MOV r, r/m' do
      it 'MOV EBX, EAX via ModR/M (89 C3 = MOV r/m, r with mod=3, reg=0, rm=3)' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
        pipeline.set_reg(:eax, 0xAAAA)
        write_code(memory, 0x7C00, 0x66, 0x89, 0xC3)  # 0x66 prefix for 32-bit
        pipeline.step(memory)
        expect(pipeline.reg(:ebx)).to eq(0xAAAA)
      end
    end

    describe 'MOV memory' do
      it 'MOV [0x8000], AL (88 06 00 80 = 16-bit addr, mod=0, rm=6, disp16)' do
        pipeline.set_reg(:eax, 0x42)
        write_code(memory, 0x7C00, 0x88, 0x06, 0x00, 0x80)
        pipeline.step(memory)
        expect(memory[0x8000]).to eq(0x42)
      end

      it 'MOV AL, [0x8000] reads from memory' do
        memory[0x8000] = 0xBB
        write_code(memory, 0x7C00, 0x8A, 0x06, 0x00, 0x80)
        pipeline.step(memory)
        expect(pipeline.reg(:eax) & 0xFF).to eq(0xBB)
      end
    end

    describe 'ADD' do
      it 'ADD AX, BX (01 D8 = ADD r/m16, r16 with mod=3, reg=3, rm=0)' do
        pipeline.set_reg(:eax, 0x10)
        pipeline.set_reg(:ebx, 0x20)
        write_code(memory, 0x7C00, 0x01, 0xD8)
        pipeline.step(memory)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x30)
      end

      it 'ADD AL, 0x10 (04 10)' do
        pipeline.set_reg(:eax, 0x05)
        write_code(memory, 0x7C00, 0x04, 0x10)
        pipeline.step(memory)
        expect(pipeline.reg(:eax) & 0xFF).to eq(0x15)
      end

      it 'SUB AX, 0x01 (2D 01 00) sets ZF when result is zero' do
        pipeline.set_reg(:eax, 0x01)
        write_code(memory, 0x7C00, 0x2D, 0x01, 0x00)
        pipeline.step(memory)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0)
        expect(pipeline.reg(:zflag)).to eq(1)
      end
    end

    describe 'CMP and flags' do
      it 'CMP AX, AX (39 C0) sets ZF=1, CF=0' do
        pipeline.set_reg(:eax, 0x42)
        write_code(memory, 0x7C00, 0x39, 0xC0)
        pipeline.step(memory)
        expect(pipeline.reg(:zflag)).to eq(1)
        expect(pipeline.reg(:cflag)).to eq(0)
        # CMP does not modify destination
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x42)
      end
    end

    describe 'INC/DEC' do
      it 'INC AX (40)' do
        pipeline.set_reg(:eax, 0x0F)
        write_code(memory, 0x7C00, 0x40)
        pipeline.step(memory)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x10)
      end

      it 'DEC CX (49)' do
        pipeline.set_reg(:ecx, 0x01)
        write_code(memory, 0x7C00, 0x49)
        pipeline.step(memory)
        expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0x00)
        expect(pipeline.reg(:zflag)).to eq(1)
      end
    end

    describe 'PUSH/POP' do
      it 'PUSH AX / POP BX round-trip (16-bit mode)' do
        pipeline.set_reg(:eax, 0xBEEF)
        pipeline.set_reg(:ebx, 0)
        esp_before = pipeline.reg(:esp)

        # PUSH AX (0x50)
        write_code(memory, 0x7C00, 0x50)
        pipeline.step(memory)
        expect(pipeline.reg(:esp)).to eq((esp_before - 2) & 0xFFFF)

        # POP BX (0x5B)
        write_code(memory, pipeline.reg(:eip), 0x5B)
        pipeline.step(memory)
        expect(pipeline.reg(:ebx) & 0xFFFF).to eq(0xBEEF)
        expect(pipeline.reg(:esp)).to eq(esp_before & 0xFFFF)
      end

      it 'PUSH imm16 (68 34 12)' do
        esp_before = pipeline.reg(:esp)
        write_code(memory, 0x7C00, 0x68, 0x34, 0x12)
        pipeline.step(memory)
        expect(pipeline.reg(:esp)).to eq((esp_before - 2) & 0xFFFF)
        expect(read_word(memory, pipeline.reg(:esp))).to eq(0x1234)
      end
    end

    describe 'JMP' do
      it 'JMP short +0x10 (EB 10)' do
        write_code(memory, 0x7C00, 0xEB, 0x10)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(0x7C12) # 0x7C00 + 2 + 0x10
      end

      it 'JMP short backward -2 (EB FE) results in infinite loop' do
        write_code(memory, 0x7C00, 0xEB, 0xFE)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(0x7C00) # 0x7C00 + 2 - 2
      end
    end

    describe 'Jcc' do
      it 'JZ taken when ZF=1 (74 05)' do
        pipeline.set_flag(:zf, 1)
        write_code(memory, 0x7C00, 0x74, 0x05)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(0x7C07)
      end

      it 'JZ not taken when ZF=0 (74 05)' do
        pipeline.set_flag(:zf, 0)
        write_code(memory, 0x7C00, 0x74, 0x05)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(0x7C02)
      end
    end

    describe 'CALL/RET' do
      it 'CALL near pushes return address and jumps (E8 xx xx)' do
        esp_before = pipeline.reg(:esp)
        # CALL +0x0100 (E8 00 01) → target = 0x7C00 + 3 + 0x100 = 0x7D03
        write_code(memory, 0x7C00, 0xE8, 0x00, 0x01)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(0x7D03)
        # Return address (0x7C03) pushed on stack
        expect(read_word(memory, pipeline.reg(:esp))).to eq(0x7C03)
      end

      it 'RET near pops return address (C3)' do
        # First push a return address
        return_addr = 0x7C10
        esp = pipeline.reg(:esp)
        new_esp = (esp - 2) & 0xFFFF
        write_word(memory, new_esp, return_addr)
        pipeline.set_reg(:esp, new_esp)

        write_code(memory, 0x7C00, 0xC3)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(return_addr)
        expect(pipeline.reg(:esp)).to eq(esp & 0xFFFF)
      end
    end

    describe 'LEA' do
      it 'LEA AX, [BX+SI] (8D 00)' do
        pipeline.set_reg(:ebx, 0x100)
        pipeline.set_reg(:esi, 0x200)
        write_code(memory, 0x7C00, 0x8D, 0x00)
        pipeline.step(memory)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x300)
      end
    end

    describe 'NOP' do
      it 'NOP advances EIP by 1 (90)' do
        write_code(memory, 0x7C00, 0x90)
        pipeline.step(memory)
        expect(pipeline.reg(:eip)).to eq(0x7C01)
      end
    end

    describe 'flag manipulation' do
      it 'STC sets CF, CLC clears CF' do
        write_code(memory, 0x7C00, 0xF9)  # STC
        pipeline.step(memory)
        expect(pipeline.reg(:cflag)).to eq(1)

        write_code(memory, pipeline.reg(:eip), 0xF8)  # CLC
        pipeline.step(memory)
        expect(pipeline.reg(:cflag)).to eq(0)
      end

      it 'STD sets DF, CLD clears DF' do
        write_code(memory, 0x7C00, 0xFD)  # STD
        pipeline.step(memory)
        expect(pipeline.reg(:dflag)).to eq(1)

        write_code(memory, pipeline.reg(:eip), 0xFC)  # CLD
        pipeline.step(memory)
        expect(pipeline.reg(:dflag)).to eq(0)
      end
    end

    describe 'HLT' do
      it 'HLT returns :halt status' do
        write_code(memory, 0x7C00, 0xF4)
        result = pipeline.step(memory)
        expect(result).to eq(:halt)
      end
    end

    describe 'end-to-end: sum 1..5 loop' do
      it 'computes sum = 1+2+3+4+5 = 15' do
        # Program at 0x7C00 (16-bit real mode):
        #   MOV AX, 0        ; B8 00 00
        #   MOV CX, 5        ; B9 05 00
        # loop:
        #   ADD AX, CX       ; 01 C8
        #   DEC CX           ; 49
        #   JNZ loop          ; 75 FB (-5: back to ADD)
        #   HLT              ; F4
        code = [
          0xB8, 0x00, 0x00,   # MOV AX, 0
          0xB9, 0x05, 0x00,   # MOV CX, 5
          0x01, 0xC8,         # ADD AX, CX
          0x49,               # DEC CX
          0x75, 0xFB,         # JNZ -5 (back to ADD AX, CX)
          0xF4                # HLT
        ]
        write_code(memory, 0x7C00, *code)

        # Execute up to 50 steps (should complete in ~17 steps)
        50.times do
          result = pipeline.step(memory)
          break if result == :halt
        end

        expect(pipeline.reg(:eax) & 0xFFFF).to eq(15)
        expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0)
      end
    end

    describe 'end-to-end: store to memory' do
      it 'loads, adds, stores result to memory' do
        # Program: Load values from memory, add them, store result
        #   MOV AL, [0x8000]   ; A0 00 80
        #   ADD AL, [0x8001]   ; 02 06 01 80
        #   MOV [0x8002], AL   ; A2 02 80
        #   HLT                ; F4
        code = [
          0xA0, 0x00, 0x80,       # MOV AL, [0x8000]
          0x02, 0x06, 0x01, 0x80, # ADD AL, [0x8001]
          0xA2, 0x02, 0x80,       # MOV [0x8002], AL
          0xF4                    # HLT
        ]
        write_code(memory, 0x7C00, *code)
        memory[0x8000] = 10
        memory[0x8001] = 25

        20.times do
          result = pipeline.step(memory)
          break if result == :halt
        end

        expect(memory[0x8002]).to eq(35)
      end
    end
  end
end
