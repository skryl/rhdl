# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'sv32 instruction translation and faults' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }
  let(:is_pipeline) { pipeline }
  let(:cpu) do
    if is_pipeline
      RHDL::Examples::RISCV::Pipeline::IRHarness.new('sv32_if_pipeline', backend: :jit, allow_fallback: false)
    else
      RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: :jit, allow_fallback: false)
    end
  end

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  def pte_pointer(next_level_ppn)
    ((next_level_ppn & 0xFFFFF) << 10) | 0x1
  end

  def pte_leaf(leaf_ppn, r:, w:, x:)
    ((leaf_ppn & 0xFFFFF) << 10) |
      ((x ? 1 : 0) << 3) |
      ((w ? 1 : 0) << 2) |
      ((r ? 1 : 0) << 1) |
      0x1
  end

  def pipeline_settle_nops
    is_pipeline ? [asm.nop, asm.nop] : []
  end

  def write_data_word(cpu, addr, value)
    if cpu.respond_to?(:write_data_word)
      cpu.write_data_word(addr, value)
    else
      cpu.write_data(addr, value)
    end
  end

  it 'translates instruction fetches via satp page tables' do
    root_ppn = 0x001
    l0_ppn = 0x002
    text_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    text_pa = text_ppn << 12

    # vpn0=0 maps initial bootstrap page identity; vpn0=1 maps to text_pa.
    write_data_word(cpu, root_pa + (0 * 4), pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa + (0 * 4), pte_leaf(0x000, r: true, w: false, x: true))
    write_data_word(cpu, l0_pa + (1 * 4), pte_leaf(text_ppn, r: true, w: false, x: true))

    main_program = [
      asm.lui(1, 0x80000),         # x1 = satp mode bit
      asm.addi(1, 1, root_ppn),    # x1 = satp(mode=1, ppn=root)
      asm.csrrw(0, 0x180, 1),      # satp = x1
      *pipeline_settle_nops,
      asm.lui(2, 0x1),             # x2 = VA 0x1000
      asm.jalr(0, 2, 0),           # fetch from mapped VA page 1
      asm.nop
    ]

    translated_page_program = [
      asm.addi(10, 0, 42),         # x10 = 42 if translated fetch works
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(translated_page_program, text_pa)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 96 : 40)

    expect(cpu.read_reg(10)).to eq(42)
  end

  it 'raises instruction page fault with mcause=12 and mtval=faulting virtual pc' do
    root_ppn = 0x001
    l0_ppn = 0x002
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12

    # Map only vpn0=0 (bootstrap + trap handler); leave vpn0=1 unmapped.
    write_data_word(cpu, root_pa + (0 * 4), pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa + (0 * 4), pte_leaf(0x000, r: true, w: false, x: true))

    main_program = [
      asm.addi(1, 0, 0x200),       # x1 = mtvec handler
      asm.csrrw(0, 0x305, 1),      # mtvec = x1
      asm.lui(1, 0x80000),         # x1 = satp mode bit
      asm.addi(1, 1, root_ppn),    # x1 = satp(mode=1, ppn=root)
      asm.csrrw(0, 0x180, 1),      # satp = x1
      *pipeline_settle_nops,
      asm.lui(2, 0x1),             # x2 = VA 0x1000
      asm.jalr(0, 2, 0),           # next fetch faults on instruction page
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0),     # x10 = mcause
      asm.csrrs(11, 0x343, 0),     # x11 = mtval
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(trap_handler, 0x200)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 112 : 48)

    expect(cpu.read_reg(10)).to eq(12)
    expect(cpu.read_reg(11)).to eq(0x1000)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  include_examples 'sv32 instruction translation and faults', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  include_examples 'sv32 instruction translation and faults', pipeline: true
end
