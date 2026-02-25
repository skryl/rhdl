# spec/examples/ao486/hdl/pipeline/pipeline_phase10_spec.rb
# RED spec for Phase 10: Complete Instruction Set

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 10' do
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

  def run_until_halt(max_steps = 200)
    max_steps.times do
      result = pipeline.step(memory)
      return result if result == :halt
    end
    :timeout
  end

  before do
    pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
  end

  describe 'CPUID' do
    it 'CPUID leaf 0 returns vendor string GenuineIntel' do
      pipeline.set_reg(:eax, 0)  # leaf 0
      write_code(memory, 0x7C00, 0x0F, 0xA2, 0xF4)  # CPUID; HLT
      run_until_halt

      # EAX = max leaf, EBX:EDX:ECX = "GenuineIntel"
      expect(pipeline.reg(:eax)).to be > 0
      ebx = pipeline.reg(:ebx)
      edx = pipeline.reg(:edx)
      ecx = pipeline.reg(:ecx)
      vendor = [ebx, edx, ecx].pack('V3')
      expect(vendor).to eq('GenuineIntel')
    end

    it 'CPUID leaf 1 returns family/model/stepping' do
      pipeline.set_reg(:eax, 1)  # leaf 1
      write_code(memory, 0x7C00, 0x0F, 0xA2, 0xF4)  # CPUID; HLT
      run_until_halt

      # EAX should contain family/model/stepping
      eax = pipeline.reg(:eax)
      expect(eax).to eq(C::CPUID_MODEL_FAMILY_STEPPING)
    end
  end

  describe 'BOUND' do
    it 'BOUND within range is a no-op' do
      # Set up bounds array at 0x8000: lower=5, upper=20
      write_word(memory, 0x8000, 5)
      write_word(memory, 0x8002, 20)

      pipeline.set_reg(:eax, 10)  # value in range
      pipeline.set_reg(:ebx, 0x8000)

      # BOUND AX, [BX]: 62 07
      write_code(memory, 0x7C00, 0x62, 0x07, 0xF4)  # BOUND AX, [BX]; HLT
      run_until_halt

      # Should pass through without exception
      expect(pipeline.reg(:eip)).to eq(0x7C03)
    end

    it 'BOUND out-of-range triggers #BR (vector 5)' do
      write_word(memory, 0x8000, 5)
      write_word(memory, 0x8002, 20)

      pipeline.set_reg(:eax, 25)  # value out of range (> upper)
      pipeline.set_reg(:ebx, 0x8000)

      # Set up IVT for #BR
      write_word(memory, C::EXCEPTION_BR * 4, 0x5000)
      write_word(memory, C::EXCEPTION_BR * 4 + 2, 0x0000)

      write_code(memory, 0x7C00, 0x62, 0x07)  # BOUND AX, [BX]
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x5000)
    end
  end

  describe 'BSF/BSR' do
    it 'BSF finds first set bit from LSB' do
      pipeline.set_reg(:eax, 0b0100_1000)  # bit 3 and 6 set

      # BSF BX, AX: 0F BC D8 (mod=3, reg=3, rm=0)
      write_code(memory, 0x7C00, 0x0F, 0xBC, 0xD8, 0xF4)  # BSF BX, AX; HLT
      run_until_halt

      expect(pipeline.reg(:ebx) & 0xFFFF).to eq(3)  # lowest set bit
      expect(pipeline.reg(:zflag)).to eq(0)  # ZF=0 because source != 0
    end

    it 'BSF sets ZF if source is zero' do
      pipeline.set_reg(:eax, 0)

      write_code(memory, 0x7C00, 0x0F, 0xBC, 0xD8, 0xF4)  # BSF BX, AX; HLT
      run_until_halt

      expect(pipeline.reg(:zflag)).to eq(1)
    end

    it 'BSR finds first set bit from MSB' do
      pipeline.set_reg(:eax, 0b0100_1000)  # bit 3 and 6 set

      # BSR BX, AX: 0F BD D8
      write_code(memory, 0x7C00, 0x0F, 0xBD, 0xD8, 0xF4)  # BSR BX, AX; HLT
      run_until_halt

      expect(pipeline.reg(:ebx) & 0xFFFF).to eq(6)  # highest set bit
      expect(pipeline.reg(:zflag)).to eq(0)
    end
  end

  describe 'BT/BTS/BTR/BTC' do
    it 'BT tests a bit and sets CF' do
      pipeline.set_reg(:eax, 0b1010_0000)  # bits 5 and 7

      # BT AX, 5: 0F BA E0 05 (mod=3, reg=4, rm=0, imm8=5)
      write_code(memory, 0x7C00, 0x0F, 0xBA, 0xE0, 0x05, 0xF4)  # BT AX, 5; HLT
      run_until_halt

      expect(pipeline.reg(:cflag)).to eq(1)  # bit 5 is set
    end

    it 'BTS tests and sets a bit' do
      pipeline.set_reg(:eax, 0b0000_0000)

      # BTS AX, 3: 0F BA E8 03 (reg=5)
      write_code(memory, 0x7C00, 0x0F, 0xBA, 0xE8, 0x03, 0xF4)  # BTS AX, 3; HLT
      run_until_halt

      expect(pipeline.reg(:cflag)).to eq(0)   # bit 3 was 0
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0b0000_1000)  # bit 3 now set
    end

    it 'BTR tests and resets a bit' do
      pipeline.set_reg(:eax, 0b0000_1000)  # bit 3 set

      # BTR AX, 3: 0F BA F0 03 (reg=6)
      write_code(memory, 0x7C00, 0x0F, 0xBA, 0xF0, 0x03, 0xF4)  # BTR AX, 3; HLT
      run_until_halt

      expect(pipeline.reg(:cflag)).to eq(1)   # bit 3 was 1
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0)  # bit 3 now cleared
    end

    it 'BTC tests and complements a bit' do
      pipeline.set_reg(:eax, 0b0000_1000)  # bit 3 set

      # BTC AX, 3: 0F BA F8 03 (reg=7)
      write_code(memory, 0x7C00, 0x0F, 0xBA, 0xF8, 0x03, 0xF4)  # BTC AX, 3; HLT
      run_until_halt

      expect(pipeline.reg(:cflag)).to eq(1)   # bit 3 was 1
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0)  # bit 3 complemented (1→0)
    end
  end

  describe 'SETcc' do
    it 'SETZ sets byte to 1 when ZF=1' do
      pipeline.set_flag(:zf, 1)

      # SETZ AL: 0F 94 C0 (mod=3, rm=0)
      write_code(memory, 0x7C00, 0x0F, 0x94, 0xC0, 0xF4)  # SETZ AL; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(1)
    end

    it 'SETNZ sets byte to 0 when ZF=1' do
      pipeline.set_flag(:zf, 1)

      # SETNZ AL: 0F 95 C0
      write_code(memory, 0x7C00, 0x0F, 0x95, 0xC0, 0xF4)  # SETNZ AL; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0)
    end
  end

  describe 'BSWAP' do
    it 'BSWAP reverses byte order of 32-bit register' do
      pipeline.set_reg(:eax, 0x12345678)

      # BSWAP EAX: 0F C8
      write_code(memory, 0x7C00, 0x0F, 0xC8, 0xF4)  # BSWAP EAX; HLT
      run_until_halt

      expect(pipeline.reg(:eax)).to eq(0x78563412)
    end
  end

  describe 'LOOP/JCXZ' do
    it 'LOOP decrements CX and jumps while CX != 0' do
      pipeline.set_reg(:ecx, 3)
      pipeline.set_reg(:eax, 0)

      # Loop body: INC AX (40), LOOP -3 (E2 FD)
      write_code(memory, 0x7C00,
                 0x40,        # INC AX
                 0xE2, 0xFD,  # LOOP -3 (back to INC)
                 0xF4)        # HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFFFF).to eq(3)
      expect(pipeline.reg(:ecx) & 0xFFFF).to eq(0)
    end

    it 'JCXZ jumps when CX is 0' do
      pipeline.set_reg(:ecx, 0)

      # JCXZ +3: E3 03; NOP; NOP; NOP; HLT
      write_code(memory, 0x7C00,
                 0xE3, 0x03,  # JCXZ +3 (skip 3 NOPs)
                 0x90, 0x90, 0x90,  # 3 NOPs (skipped)
                 0xF4)        # HLT
      run_until_halt

      expect(pipeline.reg(:eip)).to eq(0x7C06)
    end

    it 'JCXZ does not jump when CX is nonzero' do
      pipeline.set_reg(:ecx, 1)

      write_code(memory, 0x7C00,
                 0xE3, 0x01,  # JCXZ +1
                 0xF4,        # HLT (not skipped)
                 0x90)        # NOP
      run_until_halt

      expect(pipeline.reg(:eip)).to eq(0x7C03)  # stopped at HLT after JCXZ
    end
  end

  describe 'BCD adjust instructions' do
    it 'AAA adjusts after BCD addition' do
      # AL=0x0F (result of 9+6), AH=0
      pipeline.set_reg(:eax, 0x000F)

      write_code(memory, 0x7C00, 0x37, 0xF4)  # AAA; HLT
      run_until_halt

      # Should adjust: AL=5, AH=1 (carry into AH)
      expect(pipeline.reg(:eax) & 0xFF).to eq(0x05)
      expect((pipeline.reg(:eax) >> 8) & 0xFF).to eq(0x01)
    end

    it 'DAA adjusts AL after packed BCD addition' do
      # 0x19 + 0x28 = 0x41 (wrong BCD), should be 0x47
      pipeline.set_reg(:eax, 0x41)
      pipeline.set_flag(:af, 1)  # lower nibble overflowed

      write_code(memory, 0x7C00, 0x27, 0xF4)  # DAA; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0x47)
    end
  end

  describe 'SALC' do
    it 'SALC sets AL=FF when CF=1' do
      pipeline.set_flag(:cf, 1)
      pipeline.set_reg(:eax, 0)

      write_code(memory, 0x7C00, 0xD6, 0xF4)  # SALC; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0xFF)
    end

    it 'SALC sets AL=00 when CF=0' do
      pipeline.set_flag(:cf, 0)
      pipeline.set_reg(:eax, 0xFF)

      write_code(memory, 0x7C00, 0xD6, 0xF4)  # SALC; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0x00)
    end
  end

  describe 'FPU exception' do
    it 'FPU instruction with CR0.EM=1 triggers #NM (vector 7)' do
      # Enable EM bit in CR0
      pipeline.set_cr0_em(1)

      write_word(memory, C::EXCEPTION_NM * 4, 0x5000)
      write_word(memory, C::EXCEPTION_NM * 4 + 2, 0x0000)

      # Any x87 instruction, e.g. FNINIT (DB E3)
      write_code(memory, 0x7C00, 0xDB, 0xE3)
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x5000)
    end
  end

  describe 'SHLD/SHRD' do
    it 'SHLD shifts left with fill from register' do
      pipeline.set_reg(:eax, 0x1234)
      pipeline.set_reg(:ebx, 0x5678)

      # SHLD AX, BX, 4: 0F A4 D8 04
      write_code(memory, 0x7C00, 0x0F, 0xA4, 0xD8, 0x04, 0xF4)  # SHLD AX, BX, 4; HLT
      run_until_halt

      # AX shifted left 4, filled with top 4 bits of BX
      # AX=0x1234, shift left 4 = 0x2340, fill with top 4 of 0x5678 (0x5) = 0x2345
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x2345)
    end
  end

  describe 'end-to-end: bit manipulation program' do
    it 'uses BSF/BTS to find and set bits' do
      pipeline.set_reg(:eax, 0b10100000)  # bits 5, 7

      code = [
        0x0F, 0xBC, 0xD8,  # BSF BX, AX → BX=5
        0x0F, 0xBA, 0xE8, 0x02,  # BTS AX, 2 → set bit 2
        0xF4  # HLT
      ]
      write_code(memory, 0x7C00, *code)
      run_until_halt

      expect(pipeline.reg(:ebx) & 0xFFFF).to eq(5)
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0b10100100)  # bit 2 also set
    end
  end
end
