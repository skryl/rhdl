# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'linux privilege boot compatibility' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }
  let(:pipeline_mode) { pipeline }

  def run_program(cpu, program, pipeline:, extra_cycles: 0)
    cpu.load_program(program, 0)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 36 : 14) + extra_cycles)
  end

  def pipeline_settle_nops
    pipeline_mode ? [asm.nop, asm.nop] : []
  end

  def write_data_word(cpu, addr, value)
    if cpu.respond_to?(:write_data_word)
      cpu.write_data_word(addr, value)
    else
      cpu.write_data(addr, value)
    end
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

  it 'hands off with mret and services delegated supervisor ecall via sret' do
    main_program = [
      asm.addi(1, 0, 0x300),      # stvec = 0x300
      asm.csrrw(0, 0x105, 1),
      asm.addi(1, 0, 0x200),      # medeleg: delegate S-mode ecall (code 9)
      asm.csrrw(0, 0x302, 1),
      asm.lui(1, 0x1),
      asm.addi(1, 1, -2048),      # mstatus.MPP = S
      asm.csrrw(0, 0x300, 1),
      asm.addi(1, 0, 0x40),       # mepc = 0x40 (enter supervisor payload)
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.ecall,                  # runs in S-mode, trapped to stvec with scause=9
      asm.addi(12, 0, 0x66),      # executes after sret
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x142, 0),    # scause
      asm.csrrs(11, 0x141, 0),    # sepc
      asm.addi(11, 11, 4),        # resume after ecall
      asm.csrrw(0, 0x141, 11),
      asm.sret
    ]

    cpu.load_program(trap_handler, 0x300)
    run_program(cpu, main_program, pipeline: pipeline, extra_cycles: pipeline ? 50 : 22)

    expect(cpu.read_reg(10)).to eq(9)
    expect(cpu.read_reg(11)).to eq(0x44)
    expect(cpu.read_reg(12)).to eq(0x66)
  end

  it 'enables sv32 in supervisor code after handoff and translates kernel virtual loads' do
    root_ppn = 0x001
    l0_ppn = 0x002
    data_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    data_pa = data_ppn << 12
    satp_value = 0x8000_0000 | root_ppn

    write_data_word(cpu, root_pa, pte_pointer(l0_ppn))
    write_data_word(cpu, l0_pa, pte_leaf(0x000, r: true, w: true, x: true))
    write_data_word(cpu, l0_pa + 4, pte_leaf(data_ppn, r: true, w: true, x: false))
    write_data_word(cpu, data_pa, 0xC0DE_1234)

    main_program = [
      asm.lui(1, 0x1),
      asm.addi(1, 1, -2048),      # mstatus.MPP = S
      asm.csrrw(0, 0x300, 1),
      asm.addi(1, 0, 0x40),       # mepc = 0x40
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.lui(2, 0x80000),        # satp.mode = Sv32
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),     # satp
      asm.sfence_vma,
      *pipeline_settle_nops,
      asm.lui(3, 0x1),            # VA 0x1000 -> PA 0x3000
      asm.lw(13, 3, 0),
      asm.csrrs(12, 0x180, 0),    # satp readback
      asm.nop
    ]

    run_program(cpu, main_program, pipeline: pipeline, extra_cycles: pipeline ? 120 : 48)

    expect(cpu.read_reg(13)).to eq(0xC0DE_1234)
    expect(cpu.read_reg(12)).to eq(satp_value)
  end
end

RSpec.describe 'RISC-V Linux privilege boot compatibility', timeout: 30 do
  backends = {
    jit: RHDL::Codegen::IR::IR_JIT_AVAILABLE,
    interpreter: RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
  }
  backends[:compiler] = RHDL::Codegen::IR::IR_COMPILER_AVAILABLE if ENV['RHDL_LINUX_INCLUDE_COMPILER'] == '1'

  backends.each do |backend, available|
    context "single-cycle on #{backend}" do
      let(:cpu) { RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: backend, allow_fallback: false) }

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'linux privilege boot compatibility', pipeline: false
    end

    context "pipeline on #{backend}" do
      let(:cpu) do
        RHDL::Examples::RISCV::Pipeline::IRHarness.new(
          "linux_privilege_pipeline_#{backend}",
          mem_size: 65_536,
          backend: backend,
          allow_fallback: false
        )
      end

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'linux privilege boot compatibility', pipeline: true
    end
  end
end
