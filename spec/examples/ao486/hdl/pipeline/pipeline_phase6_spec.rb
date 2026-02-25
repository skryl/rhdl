# spec/examples/ao486/hdl/pipeline/pipeline_phase6_spec.rb
# RED spec for Phase 6: Microcode & Complex Instructions

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 6' do
  let(:pipeline) { described_class.new }
  let(:memory) { {} }

  def write_code(memory, addr, *bytes)
    bytes.each_with_index { |b, i| memory[(addr + i) & 0xFFFF_FFFF] = b & 0xFF }
  end

  def write_word(memory, addr, val)
    memory[addr]     = val & 0xFF
    memory[addr + 1] = (val >> 8) & 0xFF
  end

  def write_dword(memory, addr, val)
    memory[addr]     = val & 0xFF
    memory[addr + 1] = (val >> 8) & 0xFF
    memory[addr + 2] = (val >> 16) & 0xFF
    memory[addr + 3] = (val >> 24) & 0xFF
  end

  def read_dword(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8) |
      ((memory[addr + 2] || 0) << 16) | ((memory[addr + 3] || 0) << 24)
  end

  def read_word(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8)
  end

  def run_until_halt(max_steps = 100)
    max_steps.times do
      result = pipeline.step(memory)
      return result if result == :halt
    end
    :timeout
  end

  before do
    pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
  end

  describe 'PUSHA/POPA' do
    it 'PUSHA pushes all 8 GPRs in order' do
      pipeline.set_reg(:eax, 0x1111)
      pipeline.set_reg(:ecx, 0x2222)
      pipeline.set_reg(:edx, 0x3333)
      pipeline.set_reg(:ebx, 0x4444)
      # ESP will be the value BEFORE the push
      pipeline.set_reg(:ebp, 0x6666)
      pipeline.set_reg(:esi, 0x7777)
      pipeline.set_reg(:edi, 0x8888)

      esp_before = pipeline.reg(:esp)
      write_code(memory, 0x7C00, 0x60)  # PUSHA
      pipeline.step(memory)

      # 16-bit mode: pushes AX, CX, DX, BX, SP(original), BP, SI, DI
      # ESP decreases by 16 (8 words)
      expect(pipeline.reg(:esp) & 0xFFFF).to eq((esp_before - 16) & 0xFFFF)

      base = pipeline.reg(:esp) & 0xFFFF
      expect(read_word(memory, base + 14)).to eq(0x1111) # AX (pushed first, at highest address)
      expect(read_word(memory, base + 12)).to eq(0x2222) # CX
      expect(read_word(memory, base + 10)).to eq(0x3333) # DX
      expect(read_word(memory, base + 8)).to  eq(0x4444) # BX
      expect(read_word(memory, base + 6)).to  eq(esp_before & 0xFFFF) # original SP
      expect(read_word(memory, base + 4)).to  eq(0x6666) # BP
      expect(read_word(memory, base + 2)).to  eq(0x7777) # SI
      expect(read_word(memory, base + 0)).to  eq(0x8888) # DI (pushed last, at lowest address)
    end

    it 'POPA restores all GPRs (skipping SP)' do
      pipeline.set_reg(:eax, 0x1111)
      pipeline.set_reg(:ecx, 0x2222)
      pipeline.set_reg(:edx, 0x3333)
      pipeline.set_reg(:ebx, 0x4444)
      pipeline.set_reg(:ebp, 0x6666)
      pipeline.set_reg(:esi, 0x7777)
      pipeline.set_reg(:edi, 0x8888)

      write_code(memory, 0x7C00, 0x60, 0x61, 0xF4) # PUSHA, POPA, HLT

      # Zero out registers
      pipeline.step(memory)  # PUSHA
      pipeline.set_reg(:eax, 0)
      pipeline.set_reg(:ecx, 0)
      pipeline.set_reg(:edx, 0)
      pipeline.set_reg(:ebx, 0)
      pipeline.set_reg(:ebp, 0)
      pipeline.set_reg(:esi, 0)
      pipeline.set_reg(:edi, 0)

      pipeline.step(memory)  # POPA

      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x1111)
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0x2222)
      expect(pipeline.reg(:edx) & 0xFFFF).to eq(0x3333)
      expect(pipeline.reg(:ebx) & 0xFFFF).to eq(0x4444)
      # SP is skipped (not restored from stack)
      expect(pipeline.reg(:ebp) & 0xFFFF).to eq(0x6666)
      expect(pipeline.reg(:esi) & 0xFFFF).to eq(0x7777)
      expect(pipeline.reg(:edi) & 0xFFFF).to eq(0x8888)
    end
  end

  describe 'String operations' do
    it 'REP MOVSB copies N bytes' do
      # Set up: copy 5 bytes from 0x8000 to 0x9000
      pipeline.set_reg(:esi, 0x8000)
      pipeline.set_reg(:edi, 0x9000)
      pipeline.set_reg(:ecx, 5)
      pipeline.set_flag(:df, 0)  # forward direction

      # Source data
      5.times { |i| memory[0x8000 + i] = 0x41 + i }  # 'A', 'B', 'C', 'D', 'E'

      write_code(memory, 0x7C00, 0xF3, 0xA4, 0xF4)  # REP MOVSB, HLT
      run_until_halt

      5.times { |i| expect(memory[0x9000 + i]).to eq(0x41 + i) }
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0)
      expect(pipeline.reg(:esi) & 0xFFFF).to eq(0x8005)
      expect(pipeline.reg(:edi) & 0xFFFF).to eq(0x9005)
    end

    it 'STOSB fills memory with AL' do
      pipeline.set_reg(:eax, 0x42)  # AL = 0x42
      pipeline.set_reg(:edi, 0x9000)
      pipeline.set_reg(:ecx, 3)
      pipeline.set_flag(:df, 0)

      write_code(memory, 0x7C00, 0xF3, 0xAA, 0xF4)  # REP STOSB, HLT
      run_until_halt

      3.times { |i| expect(memory[0x9000 + i]).to eq(0x42) }
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0)
    end

    it 'LODSB loads bytes into AL' do
      memory[0x8000] = 0xAA
      memory[0x8001] = 0xBB
      pipeline.set_reg(:esi, 0x8000)
      pipeline.set_flag(:df, 0)

      write_code(memory, 0x7C00, 0xAC, 0xF4)  # LODSB, HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0xAA)
      expect(pipeline.reg(:esi) & 0xFFFF).to eq(0x8001)
    end

    it 'REP MOVSB with DF=1 copies backward' do
      pipeline.set_reg(:esi, 0x8004)
      pipeline.set_reg(:edi, 0x9004)
      pipeline.set_reg(:ecx, 5)
      pipeline.set_flag(:df, 1)  # backward direction

      5.times { |i| memory[0x8000 + i] = 0x41 + i }

      write_code(memory, 0x7C00, 0xF3, 0xA4, 0xF4)  # REP MOVSB, HLT
      run_until_halt

      5.times { |i| expect(memory[0x9000 + i]).to eq(0x41 + i) }
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0)
    end

    it 'CMPSB compares memory blocks' do
      # Set up two identical blocks except byte 2
      5.times { |i| memory[0x8000 + i] = 0x41 + i }
      5.times { |i| memory[0x9000 + i] = 0x41 + i }
      memory[0x9002] = 0xFF  # difference at offset 2

      pipeline.set_reg(:esi, 0x8000)
      pipeline.set_reg(:edi, 0x9000)
      pipeline.set_reg(:ecx, 5)
      pipeline.set_flag(:df, 0)

      write_code(memory, 0x7C00, 0xF3, 0xA6, 0xF4)  # REPE CMPSB, HLT
      run_until_halt

      # Should stop after 3 comparisons (first mismatch at offset 2)
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(2)
      expect(pipeline.reg(:zflag)).to eq(0)  # last comparison was unequal
    end

    it 'SCASB scans for byte in AL' do
      pipeline.set_reg(:eax, 0x43)  # looking for 'C'
      pipeline.set_reg(:edi, 0x9000)
      pipeline.set_reg(:ecx, 5)
      pipeline.set_flag(:df, 0)

      5.times { |i| memory[0x9000 + i] = 0x41 + i }  # A, B, C, D, E

      write_code(memory, 0x7C00, 0xF2, 0xAE, 0xF4)  # REPNE SCASB, HLT
      run_until_halt

      # Should stop after finding 'C' at offset 2 (3 comparisons)
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(2)
      expect(pipeline.reg(:zflag)).to eq(1)  # found it
    end
  end

  describe 'ENTER/LEAVE' do
    it 'ENTER 0x10, 0 creates basic stack frame' do
      esp_before = pipeline.reg(:esp)
      ebp_before = pipeline.reg(:ebp)

      # ENTER 0x10, 0: push BP, BP=SP, SP=SP-0x10
      write_code(memory, 0x7C00, 0xC8, 0x10, 0x00, 0x00, 0xF4)  # ENTER 16, 0; HLT
      pipeline.step(memory)

      new_bp = pipeline.reg(:ebp) & 0xFFFF
      new_sp = pipeline.reg(:esp) & 0xFFFF

      # BP was pushed, then BP = SP (after push)
      expect(new_bp).to eq((esp_before - 2) & 0xFFFF)
      # SP = BP - 0x10
      expect(new_sp).to eq((new_bp - 0x10) & 0xFFFF)
      # Old BP was pushed
      expect(read_word(memory, new_bp)).to eq(ebp_before & 0xFFFF)
    end

    it 'LEAVE restores BP and SP' do
      # Set up a stack frame first
      pipeline.set_reg(:ebp, 0x6FF0)
      pipeline.set_reg(:esp, 0x6FD0)
      # Push old BP value at [0x6FF0]
      write_word(memory, 0x6FF0, 0x7000)

      write_code(memory, 0x7C00, 0xC9, 0xF4)  # LEAVE, HLT
      pipeline.step(memory)

      # LEAVE: SP = BP, POP BP
      expect(pipeline.reg(:esp) & 0xFFFF).to eq(0x6FF2)  # BP + 2 (after pop)
      expect(pipeline.reg(:ebp) & 0xFFFF).to eq(0x7000)  # restored old BP
    end
  end

  describe 'I/O' do
    it 'OUT DX, AL writes to I/O port callback' do
      io_log = []
      pipeline.on_io_write { |port, value, size| io_log << { port: port, value: value, size: size } }

      pipeline.set_reg(:edx, 0x3F8)  # COM1 port
      pipeline.set_reg(:eax, 0x41)   # 'A'

      write_code(memory, 0x7C00, 0xEE, 0xF4)  # OUT DX, AL; HLT
      pipeline.step(memory)

      expect(io_log.length).to eq(1)
      expect(io_log[0][:port]).to eq(0x3F8)
      expect(io_log[0][:value]).to eq(0x41)
      expect(io_log[0][:size]).to eq(1)
    end

    it 'IN AL, DX reads from I/O port callback' do
      pipeline.on_io_read { |port, size| 0xBB }

      pipeline.set_reg(:edx, 0x60)  # keyboard port

      write_code(memory, 0x7C00, 0xEC, 0xF4)  # IN AL, DX; HLT
      pipeline.step(memory)

      expect(pipeline.reg(:eax) & 0xFF).to eq(0xBB)
    end

    it 'OUT imm8, AL writes to immediate port' do
      io_log = []
      pipeline.on_io_write { |port, value, size| io_log << { port: port, value: value, size: size } }

      pipeline.set_reg(:eax, 0x20)  # EOI

      write_code(memory, 0x7C00, 0xE6, 0x20, 0xF4)  # OUT 0x20, AL; HLT
      pipeline.step(memory)

      expect(io_log.length).to eq(1)
      expect(io_log[0][:port]).to eq(0x20)
      expect(io_log[0][:value]).to eq(0x20)
    end
  end

  describe 'XCHG ModR/M' do
    it 'XCHG AX, BX (87 D8)' do
      pipeline.set_reg(:eax, 0x1111)
      pipeline.set_reg(:ebx, 0x2222)

      write_code(memory, 0x7C00, 0x87, 0xD8, 0xF4)  # XCHG BX, AX (mod=3, reg=3, rm=0); HLT
      pipeline.step(memory)

      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x2222)
      expect(pipeline.reg(:ebx) & 0xFFFF).to eq(0x1111)
    end
  end

  describe 'XLAT' do
    it 'translates AL through table at BX' do
      pipeline.set_reg(:ebx, 0x8000)
      pipeline.set_reg(:eax, 0x05)  # AL = index
      memory[0x8005] = 0x42  # table[5] = 0x42

      write_code(memory, 0x7C00, 0xD7, 0xF4)  # XLAT, HLT
      pipeline.step(memory)

      expect(pipeline.reg(:eax) & 0xFF).to eq(0x42)
    end
  end

  describe 'end-to-end: REP MOVSB block copy program' do
    it 'copies a string and verifies it' do
      # Program: set up pointers, copy 5 bytes, halt
      code = [
        0xBE, 0x00, 0x80,  # MOV SI, 0x8000
        0xBF, 0x00, 0x90,  # MOV DI, 0x9000
        0xB9, 0x05, 0x00,  # MOV CX, 5
        0xFC,               # CLD
        0xF3, 0xA4,         # REP MOVSB
        0xF4                # HLT
      ]
      write_code(memory, 0x7C00, *code)
      "Hello".bytes.each_with_index { |b, i| memory[0x8000 + i] = b }

      run_until_halt

      result = 5.times.map { |i| memory[0x9000 + i] }.pack('C*')
      expect(result).to eq("Hello")
    end
  end
end
