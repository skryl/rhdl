# spec/examples/ao486/hdl/pipeline/pipeline_phase8_spec.rb
# RED spec for Phase 8: Protected Mode & Segmentation

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 8' do
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

  # Build a segment descriptor (64-bit packed value)
  # base: 32-bit, limit: 20-bit, type: 4-bit, s: 1=code/data, dpl: 0-3,
  # p: present, db: 0=16bit/1=32bit, g: granularity
  def build_descriptor(base:, limit:, type:, s: 1, dpl: 0, p: 1, db: 0, g: 0)
    desc = 0
    # Limit[15:0] at bits [15:0]
    desc |= (limit & 0xFFFF)
    # Base[23:0] at bits [39:16]
    desc |= ((base & 0xFF_FFFF) << 16)
    # Type at bits [43:40]
    desc |= ((type & 0xF) << 40)
    # S at bit [44]
    desc |= ((s & 1) << 44)
    # DPL at bits [46:45]
    desc |= ((dpl & 3) << 45)
    # P at bit [47]
    desc |= ((p & 1) << 47)
    # Limit[19:16] at bits [51:48]
    desc |= (((limit >> 16) & 0xF) << 48)
    # D/B at bit [54]
    desc |= ((db & 1) << 54)
    # G at bit [55]
    desc |= ((g & 1) << 55)
    # Base[31:24] at bits [63:56]
    desc |= (((base >> 24) & 0xFF) << 56)
    desc
  end

  # Write a 64-bit descriptor to memory (little-endian)
  def write_descriptor(memory, addr, desc)
    8.times { |i| memory[addr + i] = (desc >> (i * 8)) & 0xFF }
  end

  # Set up a minimal GDT at a given address
  # Returns: { gdt_addr:, code_sel:, data_sel: }
  def setup_gdt(memory, gdt_addr, code_base: 0, data_base: 0, dpl: 0, db: 0)
    # Entry 0: null descriptor (required)
    write_descriptor(memory, gdt_addr, 0)

    # Entry 1 (selector 0x08): code segment
    code_desc = build_descriptor(
      base: code_base, limit: 0xFFFFF, type: 0xA, # code, execute/read
      s: 1, dpl: dpl, p: 1, db: db, g: 1           # 4GB limit with G=1
    )
    write_descriptor(memory, gdt_addr + 8, code_desc)

    # Entry 2 (selector 0x10): data segment
    data_desc = build_descriptor(
      base: data_base, limit: 0xFFFFF, type: 0x2, # data, read/write
      s: 1, dpl: dpl, p: 1, db: db, g: 1
    )
    write_descriptor(memory, gdt_addr + 16, data_desc)

    # Set GDTR
    pipeline.load_gdtr(gdt_addr, 23)  # 3 entries * 8 - 1 = 23

    { gdt_addr: gdt_addr, code_sel: 0x08 | dpl, data_sel: 0x10 | dpl }
  end

  describe 'LGDT instruction' do
    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    it 'LGDT loads GDT base and limit from memory' do
      # Set up GDT pointer structure at 0x8000: limit (16-bit), base (32-bit)
      gdt_base = 0x1000
      gdt_limit = 0x17  # 3 entries * 8 - 1
      write_word(memory, 0x8000, gdt_limit)
      write_dword(memory, 0x8002, gdt_base)

      # LGDT [0x8000]: 0F 01 16 00 80 (16-bit addressing, mod=0 rm=6 disp16)
      write_code(memory, 0x7C00, 0x0F, 0x01, 0x16, 0x00, 0x80)
      pipeline.step(memory)

      expect(pipeline.reg(:gdtr_base)).to eq(gdt_base)
      expect(pipeline.reg(:gdtr_limit)).to eq(gdt_limit)
    end
  end

  describe 'LIDT instruction' do
    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    it 'LIDT loads IDT base and limit from memory' do
      idt_base = 0x2000
      idt_limit = 0xFF
      write_word(memory, 0x8000, idt_limit)
      write_dword(memory, 0x8002, idt_base)

      # LIDT [0x8000]: 0F 01 1E 00 80
      write_code(memory, 0x7C00, 0x0F, 0x01, 0x1E, 0x00, 0x80)
      pipeline.step(memory)

      expect(pipeline.reg(:idtr_base)).to eq(idt_base)
      expect(pipeline.reg(:idtr_limit)).to eq(idt_limit)
    end
  end

  describe 'enable protected mode via CR0' do
    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    it 'MOV CR0, EAX with PE=1 enables protected mode' do
      # Set up a GDT first
      setup_gdt(memory, 0x1000)

      # MOV EAX, CR0: 0F 20 C0 (read CR0 into EAX)
      write_code(memory, 0x7C00, 0x0F, 0x20, 0xC0)
      pipeline.step(memory)
      cr0_val = pipeline.reg(:eax)

      # OR EAX, 1 (set PE bit): 66 83 C8 01 (32-bit prefix + OR r/m, imm8)
      # Actually simpler: OR AL, 1 → 0C 01
      write_code(memory, pipeline.reg(:eip), 0x0C, 0x01)
      pipeline.step(memory)

      # MOV CR0, EAX: 0F 22 C0 (write EAX to CR0)
      write_code(memory, pipeline.reg(:eip), 0x0F, 0x22, 0xC0)
      pipeline.step(memory)

      expect(pipeline.reg(:cr0_pe)).to eq(1)
    end
  end

  describe 'GDT descriptor loading' do
    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    it 'loading DS with a selector reads descriptor from GDT and caches it' do
      gdt = setup_gdt(memory, 0x1000, data_base: 0x10000)

      # Enable protected mode
      pipeline.set_cr0_pe(1)

      # MOV AX, 0x10: B8 10 00
      write_code(memory, 0x7C00, 0xB8, gdt[:data_sel] & 0xFF, 0x00)
      pipeline.step(memory)

      # MOV DS, AX: 8E D8
      write_code(memory, pipeline.reg(:eip), 0x8E, 0xD8)
      pipeline.step(memory)

      # Verify DS descriptor cache has correct base
      ds_cache = pipeline.seg_cache_public(:ds)
      expect(pipeline.desc_base_public(ds_cache)).to eq(0x10000)
    end

    it 'loading a null selector into DS is allowed' do
      setup_gdt(memory, 0x1000)
      pipeline.set_cr0_pe(1)

      # MOV AX, 0: B8 00 00
      write_code(memory, 0x7C00, 0xB8, 0x00, 0x00)
      pipeline.step(memory)

      # MOV DS, AX: 8E D8
      write_code(memory, pipeline.reg(:eip), 0x8E, 0xD8)
      result = pipeline.step(memory)

      # Should succeed (null DS is allowed)
      expect(result).to eq(:ok)
    end

    it 'loading a not-present segment raises #NP' do
      # Set up GDT with a not-present descriptor
      gdt_addr = 0x1000
      write_descriptor(memory, gdt_addr, 0)  # null
      np_desc = build_descriptor(base: 0, limit: 0xFFFF, type: 0x2, s: 1, dpl: 0, p: 0)
      write_descriptor(memory, gdt_addr + 8, np_desc)
      pipeline.load_gdtr(gdt_addr, 15)
      pipeline.set_cr0_pe(1)

      # Set up IVT/IDT for #NP (vector 11)
      # For simplicity, set up real-mode-style IVT handler
      write_word(memory, C::EXCEPTION_NP * 4, 0x5000)
      write_word(memory, C::EXCEPTION_NP * 4 + 2, 0x0000)

      # MOV AX, 0x08: B8 08 00
      write_code(memory, 0x7C00, 0xB8, 0x08, 0x00)
      pipeline.step(memory)

      # MOV DS, AX: 8E D8 — should raise #NP
      write_code(memory, pipeline.reg(:eip), 0x8E, 0xD8)
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x5000)
    end
  end

  describe 'segment limit checking' do
    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    it 'access beyond segment limit raises #GP' do
      gdt_addr = 0x1000
      write_descriptor(memory, gdt_addr, 0)  # null
      # Data segment with limit of 0xFF (256 bytes)
      small_desc = build_descriptor(base: 0x10000, limit: 0xFF, type: 0x2, s: 1, dpl: 0, p: 1)
      write_descriptor(memory, gdt_addr + 8, small_desc)
      pipeline.load_gdtr(gdt_addr, 15)
      pipeline.set_cr0_pe(1)

      # Load DS with the small segment
      write_code(memory, 0x7C00, 0xB8, 0x08, 0x00)  # MOV AX, 0x08
      pipeline.step(memory)
      write_code(memory, pipeline.reg(:eip), 0x8E, 0xD8)  # MOV DS, AX
      pipeline.step(memory)

      # Set up #GP handler
      write_word(memory, C::EXCEPTION_GP * 4, 0x6000)
      write_word(memory, C::EXCEPTION_GP * 4 + 2, 0x0000)

      # Try to access address 0x200 (beyond limit 0xFF) via DS
      pipeline.set_reg(:ebx, 0x200)
      write_code(memory, pipeline.reg(:eip), 0x8A, 0x07)  # MOV AL, [BX]
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x6000)
    end
  end

  describe 'far JMP to protected-mode code' do
    before do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    end

    it 'JMP FAR with selector loads CS from GDT and jumps' do
      gdt = setup_gdt(memory, 0x1000, code_base: 0, db: 1)
      pipeline.set_cr0_pe(1)

      # Write HLT at target address
      write_code(memory, 0x8000, 0xF4)

      # JMP FAR 0x08:0x8000
      # EA 00 80 00 00 08 00 (in 16-bit mode: offset16 + selector16)
      write_code(memory, 0x7C00, 0xEA, 0x00, 0x80, 0x08, 0x00)
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x8000)
      # CS should now have selector 0x08
    end
  end

  describe 'end-to-end: real-to-protected mode transition' do
    it 'sets up GDT, enables PE, and executes in protected mode' do
      pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)

      # Set up GDT at 0x1000
      gdt_addr = 0x1000
      write_descriptor(memory, gdt_addr, 0)  # null

      # Entry 1: 32-bit code, base 0, limit 4GB
      code_desc = build_descriptor(base: 0, limit: 0xFFFFF, type: 0xA, s: 1, dpl: 0, p: 1, db: 1, g: 1)
      write_descriptor(memory, gdt_addr + 8, code_desc)

      # Entry 2: 32-bit data, base 0, limit 4GB
      data_desc = build_descriptor(base: 0, limit: 0xFFFFF, type: 0x2, s: 1, dpl: 0, p: 1, db: 1, g: 1)
      write_descriptor(memory, gdt_addr + 16, data_desc)

      # GDT pointer at 0x0F00
      write_word(memory, 0x0F00, 23)        # limit
      write_dword(memory, 0x0F02, gdt_addr)  # base

      # Boot code at 0x7C00:
      code = [
        # LGDT [0x0F00]: 0F 01 16 00 0F
        0x0F, 0x01, 0x16, 0x00, 0x0F,
        # MOV EAX, CR0: 0F 20 C0
        0x0F, 0x20, 0xC0,
        # OR AL, 1: 0C 01
        0x0C, 0x01,
        # MOV CR0, EAX: 0F 22 C0
        0x0F, 0x22, 0xC0,
        # HLT: F4 (we'll check that PE is set at this point)
        0xF4
      ]
      write_code(memory, 0x7C00, *code)

      result = run_until_halt

      expect(result).to eq(:halt)
      expect(pipeline.reg(:cr0_pe)).to eq(1)
      expect(pipeline.reg(:gdtr_base)).to eq(gdt_addr)
      expect(pipeline.reg(:gdtr_limit)).to eq(23)
    end
  end
end
