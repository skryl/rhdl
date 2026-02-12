# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'sv32 permission checks' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }
  let(:is_pipeline) { pipeline }
  let(:cpu) do
    if is_pipeline
      RHDL::Examples::RISCV::Pipeline::IRHarness.new('sv32_perm_pipeline', backend: :jit, allow_fallback: false)
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

  def pte_leaf(leaf_ppn, r:, w:, x:, u:)
    ((leaf_ppn & 0xFFFFF) << 10) |
      ((u ? 1 : 0) << 4) |
      ((x ? 1 : 0) << 3) |
      ((w ? 1 : 0) << 2) |
      ((r ? 1 : 0) << 1) |
      0x1
  end

  def write_data_word(cpu, addr, value)
    if cpu.respond_to?(:write_data_word)
      cpu.write_data_word(addr, value)
    else
      cpu.write_data(addr, value)
    end
  end

  def pipeline_settle_nops
    is_pipeline ? [asm.nop, asm.nop] : []
  end

  it 'faults instruction fetch in supervisor mode when target page has U=1' do
    root_ppn = 0x001
    l0_ppn = 0x002
    user_text_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    user_text_pa = user_text_ppn << 12

    write_data_word(cpu, root_pa, pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa, pte_leaf(0x000, r: true, w: false, x: true, u: false))
    write_data_word(cpu, l0_pa + 4, pte_leaf(user_text_ppn, r: true, w: false, x: true, u: true))

    main_program = [
      asm.addi(1, 0, 0x300),       # mtvec
      asm.csrrw(0, 0x305, 1),
      asm.lui(1, 0x1),             # x1 = 0x1000
      asm.addi(1, 1, -2048),       # x1 = 0x800 (mstatus.MPP = S)
      asm.csrrw(0, 0x300, 1),
      asm.addi(1, 0, 0x20),        # mepc = 0x20
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,                     # 0x1C
      asm.lui(2, 0x80000),         # 0x20: satp mode
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),      # satp
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # VA 0x1000 (U=1 exec page)
      asm.jalr(0, 3, 0),
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0),     # mcause
      asm.csrrs(11, 0x343, 0),     # mtval
      asm.jal(0, 0)
    ]

    user_page_program = [
      asm.addi(12, 0, 99),         # must not execute in S-mode
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(trap_handler, 0x300)
    cpu.load_program(user_page_program, user_text_pa)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 180 : 80)

    expect(cpu.read_reg(10)).to eq(12)
    expect(cpu.read_reg(11)).to eq(0x1000)
    expect(cpu.read_reg(12)).to eq(0)
  end

  it 'faults supervisor load from U=1 page when SUM=0 and allows it when SUM=1' do
    root_ppn = 0x001
    l0_ppn = 0x002
    user_data_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    user_data_pa = user_data_ppn << 12
    write_data_word(cpu, root_pa, pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa, pte_leaf(0x000, r: true, w: true, x: true, u: false))
    write_data_word(cpu, l0_pa + 4, pte_leaf(user_data_ppn, r: true, w: true, x: false, u: true))
    write_data_word(cpu, user_data_pa, 0x1122_3344)

    # SUM=0 run (expect load page fault).
    sum0_program = [
      asm.addi(1, 0, 0x300),       # mtvec
      asm.csrrw(0, 0x305, 1),
      asm.lui(1, 0x1),             # x1 = 0x1000
      asm.addi(1, 1, -2048),       # x1 = 0x800 (MPP=S, SUM=0)
      asm.csrrw(0, 0x300, 1),
      asm.addi(1, 0, 0x20),        # mepc
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,                     # 0x1C
      asm.lui(2, 0x80000),         # 0x20: satp setup
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # VA 0x1000 (U=1 data page)
      asm.lw(4, 3, 0),             # should fault with SUM=0
      asm.nop
    ]
    trap_handler = [
      asm.csrrs(10, 0x342, 0),
      asm.csrrs(11, 0x343, 0),
      asm.jal(0, 0)
    ]

    cpu.load_program(sum0_program, 0)
    cpu.load_program(trap_handler, 0x300)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 180 : 80)

    expect(cpu.read_reg(10)).to eq(13)
    expect(cpu.read_reg(11)).to eq(0x1000)
    expect(cpu.read_reg(4)).to eq(0)

    # SUM=1 run (expect load success).
    cpu.reset!
    sum1_program = [
      asm.lui(1, 0x41),            # x1 = 0x41000
      asm.addi(1, 1, -2048),       # x1 = 0x40800 (SUM=1, MPP=S)
      asm.csrrw(0, 0x300, 1),      # mstatus
      asm.addi(1, 0, 0x20),        # mepc
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,                     # 0x18
      asm.nop,                     # 0x1C
      asm.lui(2, 0x80000),         # 0x20
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),
      *pipeline_settle_nops,
      asm.lui(3, 0x1),
      asm.lw(4, 3, 0),
      asm.nop
    ]

    cpu.load_program(sum1_program, 0)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 180 : 80)

    expect(cpu.read_reg(4)).to eq(0x1122_3344)
  end

  it 'allows load from execute-only page when MXR=1' do
    root_ppn = 0x001
    l0_ppn = 0x002
    exec_data_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    exec_data_pa = exec_data_ppn << 12
    write_data_word(cpu, root_pa, pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa, pte_leaf(0x000, r: true, w: true, x: true, u: false))
    write_data_word(cpu, l0_pa + 4, pte_leaf(exec_data_ppn, r: false, w: false, x: true, u: false))
    write_data_word(cpu, exec_data_pa, 0x5566_7788)

    program = [
      asm.lui(1, 0x81),            # x1 = 0x81000
      asm.addi(1, 1, -2048),       # x1 = 0x80800 (MXR=1, MPP=S)
      asm.csrrw(0, 0x300, 1),      # mstatus
      asm.addi(1, 0, 0x20),        # mepc
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,                     # 0x18
      asm.nop,                     # 0x1C
      asm.lui(2, 0x80000),         # 0x20: satp setup
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # VA 0x1000 (X-only page)
      asm.lw(4, 3, 0),
      asm.nop
    ]

    cpu.load_program(program, 0)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 180 : 80)

    expect(cpu.read_reg(4)).to eq(0x5566_7788)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  include_examples 'sv32 permission checks', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  include_examples 'sv32 permission checks', pipeline: true
end
