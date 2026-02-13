# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'sv32 tlb behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }
  let(:is_pipeline) { pipeline }
  let(:cpu) do
    if is_pipeline
      RHDL::Examples::RISCV::Pipeline::IRHarness.new('sv32_tlb_pipeline', backend: :jit, allow_fallback: false)
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

  def run_until(max_cycles:, message:)
    cycles = 0
    until yield
      raise "timeout waiting for #{message}" if cycles >= max_cycles

      cpu.clock_cycle
      cycles += 1
    end
  end

  def max_cycles(n)
    is_pipeline ? n * 3 : n
  end

  def pipeline_settle_nops
    is_pipeline ? [asm.nop, asm.nop] : []
  end

  it 'caches data translation until sfence.vma invalidates it' do
    root_ppn = 0x001
    l0_ppn = 0x002
    data_a_ppn = 0x003
    data_b_ppn = 0x004
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    data_a_pa = data_a_ppn << 12
    data_b_pa = data_b_ppn << 12

    write_data_word(cpu, root_pa, pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa, pte_leaf(0x000, r: true, w: true, x: true, u: false))
    write_data_word(cpu, l0_pa + 4, pte_leaf(data_a_ppn, r: true, w: true, x: false, u: false))
    write_data_word(cpu, data_a_pa, 0x1111_1111)
    write_data_word(cpu, data_b_pa, 0x2222_2222)

    program = [
      asm.lui(1, 0x80000),         # satp mode
      asm.addi(1, 1, root_ppn),    # satp root ppn
      asm.csrrw(0, 0x180, 1),      # satp
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # VA 0x1000
      asm.lw(10, 3, 0),            # first load (fills dTLB with page A)
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.lw(11, 3, 0),            # second load (should still hit page A without sfence)
      asm.nop,
      asm.nop,
      asm.sfence_vma,              # invalidate TLB
      asm.nop,
      asm.nop,
      asm.lw(12, 3, 0),            # third load should observe page B
      asm.jal(0, 0)
    ]

    cpu.load_program(program, 0)
    cpu.reset!

    run_until(max_cycles: max_cycles(180), message: 'first load to x10') { cpu.read_reg(10) == 0x1111_1111 }
    write_data_word(cpu, l0_pa + 4, pte_leaf(data_b_ppn, r: true, w: true, x: false, u: false))
    run_until(max_cycles: max_cycles(220), message: 'second load to x11') { cpu.read_reg(11) != 0 }
    run_until(max_cycles: max_cycles(280), message: 'third load to x12') { cpu.read_reg(12) != 0 }

    expect(cpu.read_reg(11)).to eq(0x1111_1111)
    expect(cpu.read_reg(12)).to eq(0x2222_2222)
  end

  it 'caches instruction translation until sfence.vma invalidates it' do
    root_ppn = 0x001
    l0_ppn = 0x002
    text_a_ppn = 0x003
    text_b_ppn = 0x004
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    text_a_pa = text_a_ppn << 12
    text_b_pa = text_b_ppn << 12

    write_data_word(cpu, root_pa, pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa, pte_leaf(0x000, r: true, w: true, x: true, u: false))
    write_data_word(cpu, l0_pa + 4, pte_leaf(text_a_ppn, r: true, w: false, x: true, u: false))

    main = [
      asm.lui(1, 0x80000),         # satp mode
      asm.addi(1, 1, root_ppn),    # satp root ppn
      asm.csrrw(0, 0x180, 1),      # satp
      *pipeline_settle_nops,
      asm.lui(3, 0x1),             # VA 0x1000
      asm.jalr(1, 3, 0),           # call 1 (fills iTLB with page A)
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.jalr(1, 3, 0),           # call 2 (should still use page A without sfence)
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.sfence_vma,              # invalidate iTLB
      asm.nop,
      asm.nop,
      asm.jalr(1, 3, 0),           # call 3 should use page B
      asm.jal(0, 0)
    ]

    text_a = [
      asm.addi(10, 10, 1),
      asm.jalr(0, 1, 0)
    ]

    text_b = [
      asm.addi(10, 10, 2),
      asm.jalr(0, 1, 0)
    ]

    cpu.load_program(main, 0)
    cpu.load_program(text_a, text_a_pa)
    cpu.load_program(text_b, text_b_pa)
    cpu.reset!

    run_until(max_cycles: max_cycles(240), message: 'first call to increment x10') { cpu.read_reg(10) == 1 }
    write_data_word(cpu, l0_pa + 4, pte_leaf(text_b_ppn, r: true, w: false, x: true, u: false))
    run_until(max_cycles: max_cycles(320), message: 'second call to increment x10') { cpu.read_reg(10) >= 2 }
    run_until(max_cycles: max_cycles(420), message: 'third call after sfence to increment x10') { cpu.read_reg(10) >= 4 }

    expect(cpu.read_reg(10)).to eq(4)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  include_examples 'sv32 tlb behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  include_examples 'sv32 tlb behavior', pipeline: true
end
