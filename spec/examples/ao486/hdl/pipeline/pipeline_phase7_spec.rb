# spec/examples/ao486/hdl/pipeline/pipeline_phase7_spec.rb
# RED spec for Phase 7: Exception Handling & Interrupt Support

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 7' do
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

  def read_word(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8)
  end

  def read_dword(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8) |
      ((memory[addr + 2] || 0) << 16) | ((memory[addr + 3] || 0) << 24)
  end

  def run_until_halt(max_steps = 100)
    max_steps.times do
      result = pipeline.step(memory)
      return result if result == :halt
    end
    :timeout
  end

  # Set up IVT entry: real-mode IVT is at 0x0000:0x0000, 4 bytes per vector (IP:CS)
  def setup_ivt_entry(memory, vector, ip, cs)
    base = vector * 4
    write_word(memory, base, ip)
    write_word(memory, base + 2, cs)
  end

  before do
    pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
  end

  describe 'INT instruction (software interrupt)' do
    it 'INT 0x21 pushes FLAGS/CS/IP and jumps to IVT entry' do
      # Set up IVT entry for INT 0x21
      setup_ivt_entry(memory, 0x21, 0x1000, 0x0000)

      # Set some flags so we can verify they're pushed
      pipeline.set_flag(:cf, 1)
      pipeline.set_flag(:zf, 1)
      flags_before = pipeline.build_eflags_public

      write_code(memory, 0x7C00, 0xCD, 0x21)  # INT 0x21
      esp_before = pipeline.reg(:esp)
      pipeline.step(memory)

      # Stack should contain: FLAGS, CS, return IP (pushed in this order for real mode)
      # ESP decreases by 6 (3 words)
      new_esp = pipeline.reg(:esp) & 0xFFFF
      expect(new_esp).to eq((esp_before - 6) & 0xFFFF)

      # Return IP (0x7C02) at [SP]
      expect(read_word(memory, new_esp)).to eq(0x7C02)
      # CS (0x0000) at [SP+2]
      expect(read_word(memory, new_esp + 2)).to eq(0x0000)
      # FLAGS at [SP+4]
      expect(read_word(memory, new_esp + 4)).to eq(flags_before & 0xFFFF)

      # EIP should be loaded from IVT
      expect(pipeline.reg(:eip)).to eq(0x1000)
      # IF should be cleared
      expect(pipeline.reg(:iflag)).to eq(0)
    end

    it 'INT3 (0xCC) triggers vector 3' do
      setup_ivt_entry(memory, 3, 0x2000, 0x0000)

      write_code(memory, 0x7C00, 0xCC)  # INT3
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x2000)
    end
  end

  describe 'Division by zero exception' do
    it 'DIV by zero triggers exception vector 0' do
      setup_ivt_entry(memory, 0, 0x3000, 0x0000)

      pipeline.set_reg(:eax, 0x10)
      pipeline.set_reg(:ecx, 0)  # divisor = 0

      # DIV CL (F6 F1 = mod=3, reg=6, rm=1)
      write_code(memory, 0x7C00, 0xF6, 0xF1)
      pipeline.step(memory)

      # Should have vectored to #DE handler
      expect(pipeline.reg(:eip)).to eq(0x3000)

      # Return address on stack should point to the faulting instruction
      esp = pipeline.reg(:esp) & 0xFFFF
      expect(read_word(memory, esp)).to eq(0x7C00)
    end
  end

  describe 'Invalid opcode exception' do
    it 'undefined opcode (0x0F 0xFF) triggers vector 6' do
      setup_ivt_entry(memory, C::EXCEPTION_UD, 0x4000, 0x0000)

      write_code(memory, 0x7C00, 0x0F, 0xFF)  # invalid 2-byte opcode
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x4000)

      # Return address on stack should point to faulting instruction
      esp = pipeline.reg(:esp) & 0xFFFF
      expect(read_word(memory, esp)).to eq(0x7C00)
    end
  end

  describe 'INTO instruction' do
    it 'INTO (0xCE) triggers vector 4 when OF=1' do
      setup_ivt_entry(memory, C::EXCEPTION_OF, 0x5000, 0x0000)

      pipeline.set_flag(:of, 1)
      write_code(memory, 0x7C00, 0xCE)  # INTO
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x5000)
    end

    it 'INTO (0xCE) is a no-op when OF=0' do
      pipeline.set_flag(:of, 0)
      write_code(memory, 0x7C00, 0xCE, 0xF4)  # INTO, HLT
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x7C01)  # just advances past INTO
    end
  end

  describe 'Hardware interrupt' do
    it 'accepts hardware interrupt when IF=1' do
      setup_ivt_entry(memory, 0x08, 0x6000, 0x0000)  # IRQ0 -> vector 8

      pipeline.set_flag(:if, 1)
      pipeline.raise_hw_interrupt(0x08)

      write_code(memory, 0x7C00, 0x90)  # NOP (will be interrupted)
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x6000)
      # IF should be cleared
      expect(pipeline.reg(:iflag)).to eq(0)
    end

    it 'does not accept hardware interrupt when IF=0' do
      setup_ivt_entry(memory, 0x08, 0x6000, 0x0000)

      pipeline.set_flag(:if, 0)
      pipeline.raise_hw_interrupt(0x08)

      write_code(memory, 0x7C00, 0x90)  # NOP
      pipeline.step(memory)

      # Should just execute the NOP normally
      expect(pipeline.reg(:eip)).to eq(0x7C01)
    end

    it 'accepts pending interrupt after STI' do
      setup_ivt_entry(memory, 0x08, 0x6000, 0x0000)

      pipeline.set_flag(:if, 0)
      pipeline.raise_hw_interrupt(0x08)

      write_code(memory, 0x7C00, 0xFB, 0x90, 0xF4)  # STI, NOP, HLT
      pipeline.step(memory)  # STI
      pipeline.step(memory)  # NOP — interrupt should be serviced here

      expect(pipeline.reg(:eip)).to eq(0x6000)
    end
  end

  describe 'IRET' do
    it 'IRET restores IP/CS/FLAGS from stack' do
      # Push a fake interrupt frame: FLAGS, CS, IP
      esp = pipeline.reg(:esp) & 0xFFFF
      flags_val = 0x0202  # IF=1, bit1=1 (reserved)
      return_ip = 0x7C10
      return_cs = 0x0000

      new_esp = (esp - 6) & 0xFFFF
      write_word(memory, new_esp, return_ip)      # IP
      write_word(memory, new_esp + 2, return_cs)   # CS
      write_word(memory, new_esp + 4, flags_val)   # FLAGS
      pipeline.set_reg(:esp, new_esp)

      write_code(memory, 0x7C00, 0xCF)  # IRET
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(return_ip)
      expect(pipeline.reg(:esp) & 0xFFFF).to eq(esp)
      expect(pipeline.reg(:iflag)).to eq(1)
    end
  end

  describe 'end-to-end: interrupt handler round-trip' do
    it 'INT pushes frame, handler runs, IRET returns' do
      # Set up IVT for INT 0x30
      setup_ivt_entry(memory, 0x30, 0x2000, 0x0000)

      # Main program: set AX, INT 0x30, HLT
      write_code(memory, 0x7C00,
                 0xB8, 0x00, 0x00,  # MOV AX, 0
                 0xCD, 0x30,         # INT 0x30
                 0xF4)               # HLT

      # Handler at 0x2000: INC AX, IRET
      write_code(memory, 0x2000,
                 0x40,  # INC AX
                 0xCF)  # IRET

      run_until_halt

      # AX should be 1 (incremented by handler)
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(1)
      # EIP should be at HLT+1
      expect(pipeline.reg(:eip)).to eq(0x7C06)
    end
  end
end
