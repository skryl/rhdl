# spec/examples/ao486/hdl/pipeline/pipeline_phase11_spec.rb
# RED spec for Phase 11: Integration & Runner

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 11' do
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

  def run_until_halt(max_steps = 500)
    max_steps.times do
      result = pipeline.step(memory)
      return result if result == :halt
    end
    :timeout
  end

  describe '.COM program execution in real mode' do
    it 'executes a simple program that adds numbers and halts' do
      # Simulated .COM: loaded at CS:0100h (real mode, CS=0)
      # Program: MOV AX, 10; ADD AX, 20; HLT
      pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

      com_bytes = [
        0xB8, 0x0A, 0x00,  # MOV AX, 10
        0x05, 0x14, 0x00,  # ADD AX, 20
        0xF4                # HLT
      ]
      write_code(memory, 0x0100, *com_bytes)

      result = run_until_halt
      expect(result).to eq(:halt)
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(30)
    end

    it 'executes a program with subroutine call and return' do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

      # Main: MOV AX, 5; CALL 0x0120; HLT
      # Sub at 0x0120: ADD AX, 3; RET
      write_code(memory, 0x0100,
                 0xB8, 0x05, 0x00,   # MOV AX, 5
                 0xE8, 0x1A, 0x00,   # CALL 0x0120 (rel16 = 0x001A from 0x0106)
                 0xF4)                # HLT

      write_code(memory, 0x0120,
                 0x05, 0x03, 0x00,   # ADD AX, 3
                 0xC3)               # RET

      result = run_until_halt
      expect(result).to eq(:halt)
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(8)
    end

    it 'executes a program that uses INT with stub handler' do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

      # Set up a stub INT 0x21 handler that sets AH=0 (success) and returns
      write_word(memory, 0x21 * 4, 0x2000)       # IP = 0x2000
      write_word(memory, 0x21 * 4 + 2, 0x0000)   # CS = 0x0000

      # Handler: MOV AH, 0; IRET
      write_code(memory, 0x2000,
                 0xB4, 0x00,   # MOV AH, 0
                 0xCF)         # IRET

      # Program: MOV AH, 0x09; INT 0x21; HLT
      write_code(memory, 0x0100,
                 0xB4, 0x09,   # MOV AH, 9
                 0xCD, 0x21,   # INT 0x21
                 0xF4)         # HLT

      result = run_until_halt
      expect(result).to eq(:halt)
      # AH should be 0 (set by handler)
      expect((pipeline.reg(:eax) >> 8) & 0xFF).to eq(0)
    end
  end

  describe 'protected-mode boot sequence' do
    def build_descriptor(base:, limit:, type:, s: 1, dpl: 0, p: 1, db: 0, g: 0)
      desc = 0
      desc |= (limit & 0xFFFF)
      desc |= ((base & 0xFF_FFFF) << 16)
      desc |= ((type & 0xF) << 40)
      desc |= ((s & 1) << 44)
      desc |= ((dpl & 3) << 45)
      desc |= ((p & 1) << 47)
      desc |= (((limit >> 16) & 0xF) << 48)
      desc |= ((db & 1) << 54)
      desc |= ((g & 1) << 55)
      desc |= (((base >> 24) & 0xFF) << 56)
      desc
    end

    def write_descriptor(memory, addr, desc)
      8.times { |i| memory[addr + i] = (desc >> (i * 8)) & 0xFF }
    end

    it 'boots from real mode to protected mode and runs 32-bit code' do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
      io_log = []
      pipeline.on_io_write { |port, value, size| io_log << { port: port, value: value } }

      # ---- GDT at 0x1000 ----
      gdt_addr = 0x1000
      # Entry 0: null
      write_descriptor(memory, gdt_addr, 0)
      # Entry 1 (0x08): 32-bit code, base 0, limit 4GB
      write_descriptor(memory, gdt_addr + 8,
        build_descriptor(base: 0, limit: 0xFFFFF, type: 0xA, s: 1, dpl: 0, p: 1, db: 1, g: 1))
      # Entry 2 (0x10): 32-bit data, base 0, limit 4GB
      write_descriptor(memory, gdt_addr + 16,
        build_descriptor(base: 0, limit: 0xFFFFF, type: 0x2, s: 1, dpl: 0, p: 1, db: 1, g: 1))

      # ---- GDT pointer at 0x0F00 ----
      write_word(memory, 0x0F00, 23)         # limit
      write_dword(memory, 0x0F02, gdt_addr)  # base

      # ---- Boot code at 0x7C00 (real mode, 16-bit) ----
      boot = [
        # LGDT [0x0F00]
        0x0F, 0x01, 0x16, 0x00, 0x0F,
        # MOV EAX, CR0
        0x0F, 0x20, 0xC0,
        # OR AL, 1 (set PE)
        0x0C, 0x01,
        # MOV CR0, EAX
        0x0F, 0x22, 0xC0,
        # JMP FAR 0x08:0x8000 (jump to 32-bit code)
        0xEA, 0x00, 0x80, 0x08, 0x00,
      ]
      write_code(memory, 0x7C00, *boot)

      # ---- 32-bit protected-mode code at 0x8000 ----
      # Load DS with data segment selector (0x10)
      # MOV EAX, 0x10: B8 10 00 00 00
      # MOV DS, AX: 8E D8
      # MOV AL, 'H': B0 48
      # OUT 0xE9, AL: E6 E9  (debug port — common bochs/qemu debug output port)
      # MOV AL, 'i': B0 69
      # OUT 0xE9, AL: E6 E9
      # HLT: F4
      pm_code = [
        0xB8, 0x10, 0x00, 0x00, 0x00,  # MOV EAX, 0x10
        0x8E, 0xD8,                      # MOV DS, AX
        0xB0, 0x48,                      # MOV AL, 'H'
        0xE6, 0xE9,                      # OUT 0xE9, AL
        0xB0, 0x69,                      # MOV AL, 'i'
        0xE6, 0xE9,                      # OUT 0xE9, AL
        0xF4                             # HLT
      ]
      write_code(memory, 0x8000, *pm_code)

      result = run_until_halt
      expect(result).to eq(:halt)
      expect(pipeline.reg(:cr0_pe)).to eq(1)

      # Verify I/O output
      chars = io_log.select { |e| e[:port] == 0xE9 }.map { |e| e[:value].chr }.join
      expect(chars).to eq('Hi')
    end
  end

  describe 'Harness integration' do
    it 'Harness wraps Pipeline for .COM execution' do
      require_relative '../../../../../examples/ao486/hdl/harness'
      harness = RHDL::Examples::AO486::Harness.new

      # Load a simple .COM program
      com = [0xB8, 0x2A, 0x00, 0xF4]  # MOV AX, 42; HLT
      harness.load_com(com)

      result = harness.run(max_steps: 100)
      expect(result).to eq(:halt)
      expect(harness.reg(:eax) & 0xFFFF).to eq(42)
    end

    it 'Harness tracks cycle count' do
      require_relative '../../../../../examples/ao486/hdl/harness'
      harness = RHDL::Examples::AO486::Harness.new
      com = [0x90, 0x90, 0xF4]  # NOP; NOP; HLT
      harness.load_com(com)
      harness.run(max_steps: 100)
      expect(harness.clock_count).to be >= 3
    end

    it 'Harness provides I/O callbacks' do
      require_relative '../../../../../examples/ao486/hdl/harness'
      harness = RHDL::Examples::AO486::Harness.new
      output = []
      harness.on_io_write { |port, value, size| output << value }

      com = [
        0xB0, 0x41,   # MOV AL, 'A'
        0xE6, 0xE9,   # OUT 0xE9, AL
        0xF4           # HLT
      ]
      harness.load_com(com)
      harness.run(max_steps: 100)

      expect(output).to include(0x41)
    end
  end
end
