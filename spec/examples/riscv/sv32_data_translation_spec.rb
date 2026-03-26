# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'sv32 data translation and faults' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }
  let(:is_pipeline) { pipeline }
  let(:cpu) do
    if is_pipeline
      RHDL::Examples::RISCV::Pipeline::IRHarness.new('sv32_pipeline', backend: :jit)
    else
      RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: :jit)
    end
  end

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Sim::Native::IR::JIT_AVAILABLE
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

  def read_data_word(cpu, addr)
    if cpu.respond_to?(:read_data_word)
      cpu.read_data_word(addr)
    else
      cpu.read_data(addr)
    end
  end

  it 'translates virtual data addresses for load/store using satp page tables' do
    root_ppn = 0x001
    l0_ppn = 0x002
    data_ppn = 0x003

    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    data_pa = data_ppn << 12

    write_data_word(cpu, root_pa + (0 * 4), pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa + (0 * 4), pte_leaf(0x000, r: true, w: true, x: true))
    write_data_word(cpu, l0_pa + (1 * 4), pte_leaf(data_ppn, r: true, w: true, x: false))
    write_data_word(cpu, data_pa, 0xA5A55A5A)

    program = [
      # M-mode: switch to S-mode (translation only applies in S/U-mode)
      asm.lui(1, 0x1),             # x1 = 0x1000
      asm.addi(1, 1, -2048),       # x1 = 0x800 (MPP=S)
      asm.csrrw(0, 0x300, 1),      # mstatus.MPP = S
      asm.addi(1, 0, 0x18),        # x1 = S-mode entry point
      asm.csrrw(0, 0x341, 1),      # mepc = 0x18
      asm.mret,                    # switch to S-mode
      # S-mode code at 0x18:
      asm.lui(1, 0x80000),         # x1 = satp mode bit
      asm.addi(1, 1, root_ppn),    # x1 = satp(mode=1, ppn=root)
      asm.csrrw(0, 0x180, 1),      # satp = x1
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # x3 = 0x1000 (VA page vpn0=1)
      asm.lw(4, 3, 0),             # x4 = *(0x1000) -> PA 0x3000
      asm.addi(5, 0, 0x77),        # x5 = 0x77
      asm.sw(5, 3, 4),             # *(0x1004) -> PA 0x3004
      asm.nop
    ]

    cpu.load_program(program, 0)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 96 : 36)

    expect(cpu.read_reg(4)).to eq(0xA5A55A5A)
    expect(read_data_word(cpu, data_pa + 4)).to eq(0x77)
  end

  it 'raises load page fault with mcause=13 and mtval=faulting virtual address' do
    root_ppn = 0x001
    l0_ppn = 0x002

    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    write_data_word(cpu, root_pa + (0 * 4), pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa + (0 * 4), pte_leaf(0x000, r: true, w: true, x: true))
    # No leaf mapping for vpn0=1, so accesses to VA 0x1000 fault.

    program = [
      asm.addi(1, 0, 0x200),       # x1 = mtvec handler
      asm.csrrw(0, 0x305, 1),      # mtvec = x1
      # Switch to S-mode (translation only applies in S/U-mode)
      asm.lui(1, 0x1),             # x1 = 0x1000
      asm.addi(1, 1, -2048),       # x1 = 0x800 (MPP=S)
      asm.csrrw(0, 0x300, 1),      # mstatus.MPP = S
      asm.addi(1, 0, 0x20),        # x1 = S-mode entry point
      asm.csrrw(0, 0x341, 1),      # mepc = 0x20
      asm.mret,                    # switch to S-mode
      # S-mode code at 0x20:
      asm.lui(1, 0x80000),         # x1 = satp mode bit
      asm.addi(1, 1, root_ppn),    # x1 = satp(mode=1, ppn=root)
      asm.csrrw(0, 0x180, 1),      # satp = x1
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # x3 = VA 0x1000
      asm.lw(2, 3, 0),             # should fault (load page fault)
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0),     # x10 = mcause
      asm.csrrs(11, 0x343, 0),     # x11 = mtval
      asm.jal(0, 0)
    ]

    cpu.load_program(program, 0)
    cpu.load_program(trap_handler, 0x200)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 128 : 52)

    expect(cpu.read_reg(10)).to eq(13)
    expect(cpu.read_reg(11)).to eq(0x1000)
  end

  it 'raises store page fault with mcause=15 and mtval=faulting virtual address' do
    root_ppn = 0x001
    l0_ppn = 0x002

    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    write_data_word(cpu, root_pa + (0 * 4), pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa + (0 * 4), pte_leaf(0x000, r: true, w: true, x: true))
    # No leaf mapping for vpn0=1, so accesses to VA 0x1000 fault.

    program = [
      asm.addi(1, 0, 0x200),       # x1 = mtvec handler
      asm.csrrw(0, 0x305, 1),      # mtvec = x1
      # Switch to S-mode (translation only applies in S/U-mode)
      asm.lui(1, 0x1),             # x1 = 0x1000
      asm.addi(1, 1, -2048),       # x1 = 0x800 (MPP=S)
      asm.csrrw(0, 0x300, 1),      # mstatus.MPP = S
      asm.addi(1, 0, 0x20),        # x1 = S-mode entry point
      asm.csrrw(0, 0x341, 1),      # mepc = 0x20
      asm.mret,                    # switch to S-mode
      # S-mode code at 0x20:
      asm.lui(1, 0x80000),         # x1 = satp mode bit
      asm.addi(1, 1, root_ppn),    # x1 = satp(mode=1, ppn=root)
      asm.csrrw(0, 0x180, 1),      # satp = x1
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # x3 = VA 0x1000
      asm.addi(2, 0, 0x55),        # x2 = store data
      asm.sw(2, 3, 0),             # should fault (store page fault)
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0),     # x10 = mcause
      asm.csrrs(11, 0x343, 0),     # x11 = mtval
      asm.jal(0, 0)
    ]

    cpu.load_program(program, 0)
    cpu.load_program(trap_handler, 0x200)
    cpu.reset!
    cpu.run_cycles(is_pipeline ? 128 : 52)

    expect(cpu.read_reg(10)).to eq(15)
    expect(cpu.read_reg(11)).to eq(0x1000)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  include_examples 'sv32 data translation and faults', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  include_examples 'sv32 data translation and faults', pipeline: true
end
