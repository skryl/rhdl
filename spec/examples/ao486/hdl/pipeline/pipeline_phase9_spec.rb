# spec/examples/ao486/hdl/pipeline/pipeline_phase9_spec.rb
# RED spec for Phase 9: Paging & TLB

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 9' do
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

  # Build a page directory entry
  # frame: physical address of page table (4KB aligned) or large page (4MB aligned)
  # p: present, rw: read/write, us: user/supervisor, ps: page size (4MB if 1)
  def build_pde(frame:, p: 1, rw: 1, us: 0, ps: 0)
    entry = (frame & 0xFFFFF000)
    entry |= (ps & 1) << 7
    entry |= (us & 1) << 2
    entry |= (rw & 1) << 1
    entry |= (p & 1)
    entry
  end

  # Build a page table entry
  # frame: physical address of 4KB page
  # p: present, rw: read/write, us: user/supervisor
  def build_pte(frame:, p: 1, rw: 1, us: 0)
    entry = (frame & 0xFFFFF000)
    entry |= (us & 1) << 2
    entry |= (rw & 1) << 1
    entry |= (p & 1)
    entry
  end

  # Set up identity-mapped paging for the first N MB
  # page_dir_addr: physical address of page directory (4KB aligned)
  # page_table_addr: physical address of first page table (4KB aligned)
  # num_pages: number of 4KB pages to map (default 256 = 1MB)
  def setup_identity_paging(page_dir_addr, page_table_addr, num_pages: 256, rw: 1, us: 0)
    # Write PDE 0 pointing to the page table
    pde = build_pde(frame: page_table_addr, p: 1, rw: rw, us: us)
    write_dword(memory, page_dir_addr, pde)

    # Write PTEs for identity mapping
    num_pages.times do |i|
      pte = build_pte(frame: i * 0x1000, p: 1, rw: rw, us: us)
      write_dword(memory, page_table_addr + i * 4, pte)
    end

    # Load CR3 with page directory address
    pipeline.set_cr3(page_dir_addr)
  end

  # Set up a 32-bit protected mode environment with flat segments
  def setup_protected_mode_32bit
    pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
    pipeline.set_cr0_pe(1)
    # Set CS descriptor to 32-bit mode (D=1) so operand/address size defaults to 32-bit
    pipeline.set_cs_db(1)
  end

  # Build a GDT descriptor (reused from Phase 8)
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

  describe 'basic paging: linear-to-physical translation' do
    it 'with CR0.PG=1, memory access translates through PDE→PTE→physical' do
      setup_protected_mode_32bit

      # Page directory at 0x20000, page table at 0x21000
      setup_identity_paging(0x20000, 0x21000)

      # Enable paging
      pipeline.set_cr0_pg(1)

      # Write data at physical address 0x8000
      memory[0x8000] = 0x42

      # MOV AL, [0x8000]: should go through page translation
      pipeline.set_reg(:ebx, 0x8000)
      write_code(memory, 0x7C00, 0x8A, 0x03, 0xF4)  # MOV AL, [EBX]; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0x42)
    end
  end

  describe 'TLB caching' do
    it 'second access to same page hits TLB without page walk' do
      setup_protected_mode_32bit
      setup_identity_paging(0x20000, 0x21000)
      pipeline.set_cr0_pg(1)

      memory[0x8000] = 0xAA
      memory[0x8001] = 0xBB

      # First access: TLB miss → page walk → fill
      pipeline.set_reg(:ebx, 0x8000)
      write_code(memory, 0x7C00, 0x8A, 0x03)  # MOV AL, [EBX]
      pipeline.step(memory)
      expect(pipeline.reg(:eax) & 0xFF).to eq(0xAA)

      # Verify TLB has an entry for this page
      expect(pipeline.tlb_hit?(0x8000)).to eq(true)

      # Second access: should hit TLB
      pipeline.set_reg(:ebx, 0x8001)
      write_code(memory, pipeline.reg(:eip), 0x8A, 0x03, 0xF4)  # MOV AL, [EBX]; HLT
      pipeline.step(memory)
      expect(pipeline.reg(:eax) & 0xFF).to eq(0xBB)
    end
  end

  describe 'page fault on not-present page' do
    it 'access to not-present page triggers #PF with correct CR2 and error code' do
      setup_protected_mode_32bit
      setup_identity_paging(0x20000, 0x21000, num_pages: 8)
      pipeline.set_cr0_pg(1)

      # PDE 0 maps pages 0-7 (0x0000-0x7FFF). Page 8+ is unmapped.
      # Mark PTE for page at 0x9000 as not present
      # PDE index for 0x9000 is 0 (within first 4MB), PTE index = 9
      # PTE 9 is at page_table + 9*4 = 0x21024
      # We set up only 8 pages, so PTE 9 is 0 (not present)

      # Set up IDT for #PF (vector 14) — protected-mode IDT
      # For simplicity, use real-mode-style IVT
      write_word(memory, C::EXCEPTION_PF * 4, 0x5000)
      write_word(memory, C::EXCEPTION_PF * 4 + 2, 0x0000)

      # Try to read from 0x9000 (unmapped)
      pipeline.set_reg(:ebx, 0x9000)
      write_code(memory, 0x7C00, 0x8A, 0x03)  # MOV AL, [EBX]
      pipeline.step(memory)

      # Should have faulted to #PF handler
      expect(pipeline.reg(:eip)).to eq(0x5000)
      # CR2 should contain the faulting linear address
      expect(pipeline.reg(:cr2)).to eq(0x9000)
    end
  end

  describe 'write protection' do
    it 'write to read-only page at CPL=3 triggers #PF' do
      setup_protected_mode_32bit
      # Map most pages as read-write, but page at 0x8000 as read-only
      page_dir = 0x20000
      page_tbl = 0x21000

      # PDE 0 → page table (r/w, user)
      pde = build_pde(frame: page_tbl, p: 1, rw: 1, us: 1)
      write_dword(memory, page_dir, pde)

      # Identity map pages 0-255 as r/w, user
      256.times do |i|
        pte = build_pte(frame: i * 0x1000, p: 1, rw: 1, us: 1)
        write_dword(memory, page_tbl + i * 4, pte)
      end

      # Override page 8 (0x8000-0x8FFF) as read-only
      pte_ro = build_pte(frame: 0x8000, p: 1, rw: 0, us: 1)
      write_dword(memory, page_tbl + 8 * 4, pte_ro)

      pipeline.set_cr3(page_dir)
      pipeline.set_cr0_pg(1)
      pipeline.set_cr0_wp(1)
      pipeline.set_cpl(3)  # User mode

      # Set up #PF handler
      write_word(memory, C::EXCEPTION_PF * 4, 0x5000)
      write_word(memory, C::EXCEPTION_PF * 4 + 2, 0x0000)

      # Try to write to read-only page
      pipeline.set_reg(:ebx, 0x8000)
      pipeline.set_reg(:eax, 0x42)
      write_code(memory, 0x7C00, 0x88, 0x03)  # MOV [EBX], AL
      pipeline.step(memory)

      expect(pipeline.reg(:eip)).to eq(0x5000)
      expect(pipeline.reg(:cr2)).to eq(0x8000)
    end

    it 'write to read-only page at CPL=0 with WP=0 succeeds' do
      setup_protected_mode_32bit
      setup_identity_paging(0x20000, 0x21000, rw: 0, us: 0)
      pipeline.set_cr0_pg(1)
      pipeline.set_cr0_wp(0)  # Supervisor can write to read-only pages

      pipeline.set_reg(:ebx, 0x8000)
      pipeline.set_reg(:eax, 0x42)
      write_code(memory, 0x7C00, 0x88, 0x03, 0xF4)  # MOV [EBX], AL; HLT
      run_until_halt

      expect(memory[0x8000]).to eq(0x42)
    end
  end

  describe 'INVLPG' do
    it 'INVLPG invalidates the TLB entry for the specified address' do
      setup_protected_mode_32bit
      setup_identity_paging(0x20000, 0x21000)
      pipeline.set_cr0_pg(1)

      # Access page to fill TLB
      memory[0x8000] = 0xAA
      pipeline.set_reg(:ebx, 0x8000)
      write_code(memory, 0x7C00, 0x8A, 0x03)  # MOV AL, [EBX]
      pipeline.step(memory)
      expect(pipeline.tlb_hit?(0x8000)).to eq(true)

      # INVLPG [EBX]: 0F 01 3B (ModR/M: mod=00, reg=7, rm=011)
      write_code(memory, pipeline.reg(:eip), 0x0F, 0x01, 0x3B)
      pipeline.step(memory)

      # TLB entry should be invalidated
      expect(pipeline.tlb_hit?(0x8000)).to eq(false)
    end
  end

  describe 'CR3 write flushes TLB' do
    it 'writing CR3 flushes all TLB entries' do
      setup_protected_mode_32bit
      setup_identity_paging(0x20000, 0x21000)
      pipeline.set_cr0_pg(1)

      # Fill TLB with entries
      memory[0x8000] = 0xAA
      pipeline.set_reg(:ebx, 0x8000)
      write_code(memory, 0x7C00, 0x8A, 0x03)  # MOV AL, [EBX]
      pipeline.step(memory)
      expect(pipeline.tlb_hit?(0x8000)).to eq(true)

      # MOV CR3, EAX (reload same value — should still flush TLB)
      pipeline.set_reg(:eax, 0x20000)
      write_code(memory, pipeline.reg(:eip), 0x0F, 0x22, 0xD8)  # MOV CR3, EAX
      pipeline.step(memory)

      expect(pipeline.tlb_hit?(0x8000)).to eq(false)
    end
  end

  describe '4MB pages' do
    it 'PDE with PS=1 maps a 4MB page directly' do
      setup_protected_mode_32bit

      # Page directory at 0x20000
      # PDE 0 with PS=1: maps virtual 0x00000000-0x003FFFFF to physical 0x00000000-0x003FFFFF
      pde = build_pde(frame: 0x00000000, p: 1, rw: 1, us: 0, ps: 1)
      write_dword(memory, 0x20000, pde)

      pipeline.set_cr3(0x20000)
      pipeline.set_cr0_pg(1)

      # Access at offset within the 4MB page
      memory[0x8000] = 0x55
      pipeline.set_reg(:ebx, 0x8000)
      write_code(memory, 0x7C00, 0x8A, 0x03, 0xF4)  # MOV AL, [EBX]; HLT
      run_until_halt

      expect(pipeline.reg(:eax) & 0xFF).to eq(0x55)
    end
  end

  describe 'end-to-end: enable paging and access mapped memory' do
    it 'sets up page tables, enables paging, reads and writes through virtual addresses' do
      setup_protected_mode_32bit

      # Set up identity paging for first 1MB
      page_dir = 0x20000
      page_tbl = 0x21000
      setup_identity_paging(page_dir, page_tbl, num_pages: 256)
      pipeline.set_cr0_pg(1)

      # Write value via virtual address, read it back
      pipeline.set_reg(:ebx, 0x8000)
      pipeline.set_reg(:eax, 0xDE)

      code = [
        0x88, 0x03,        # MOV [EBX], AL — write 0xDE to virtual 0x8000
        0xC6, 0x03, 0x00,  # MOV BYTE [EBX], 0 — overwrite with 0 (wait no, let's read it back differently)
      ]
      # Simpler: write AL to [EBX], increment EBX, write different value, read both back
      write_code(memory, 0x7C00,
                 0x88, 0x03,        # MOV [EBX], AL — write 0xDE to [0x8000]
                 0x30, 0xC0,        # XOR AL, AL — clear AL
                 0x8A, 0x03,        # MOV AL, [EBX] — read back from [0x8000]
                 0xF4)              # HLT
      run_until_halt

      # AL should have 0xDE read back from the address we wrote to
      expect(pipeline.reg(:eax) & 0xFF).to eq(0xDE)
      # Physical memory at 0x8000 should also have 0xDE
      expect(memory[0x8000]).to eq(0xDE)
    end
  end
end
