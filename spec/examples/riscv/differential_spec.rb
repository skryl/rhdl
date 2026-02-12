# Differential tests for single-cycle vs pipelined RV32I CPUs
# Ensures both implementations produce the same architectural state

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe 'RISC-V single-cycle vs pipelined equivalence', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  def build_single
    RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: :jit, allow_fallback: false)
  end

  def build_pipeline
    RHDL::Examples::RISCV::Pipeline::IRHarness.new('pipeline_equiv', backend: :jit, allow_fallback: false)
  end

  def run_single(program, extra_cycles: 0)
    cpu = build_single
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + extra_cycles)
    cpu
  end

  def run_pipeline(program, extra_cycles: 0)
    cpu = build_pipeline
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + 5 + extra_cycles)
    cpu
  end

  def compare_state(program, mem_addrs: [], extra_cycles: 8)
    padded_program = program + Array.new(8, asm.nop)
    single = run_single(padded_program, extra_cycles: extra_cycles)
    pipeline = run_pipeline(padded_program, extra_cycles: extra_cycles)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end

    mem_addrs.each do |addr|
      expect(pipeline.read_data(addr)).to eq(single.read_data_word(addr)), "memory mismatch at 0x#{addr.to_s(16)}"
    end
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

  it 'matches on mixed arithmetic and immediate program' do
    program = [
      asm.lui(1, 0x12345),
      asm.auipc(2, 1),
      asm.addi(3, 0, 127),
      asm.slli(4, 3, 2),
      asm.srli(5, 4, 1),
      asm.addi(6, 0, -1),
      asm.srai(7, 6, 4),
      asm.xori(8, 3, 0xFF),
      asm.ori(9, 8, 0x01),
      asm.andi(10, 9, 0x0F),
      asm.add(11, 4, 5),
      asm.sub(12, 11, 3),
      asm.sll(13, 3, 10),
      asm.srl(14, 13, 10),
      asm.sra(15, 6, 10),
      asm.slt(16, 6, 3),
      asm.sltu(17, 6, 3),
      asm.slti(18, 6, 0),
      asm.sltiu(19, 6, 1)
    ]

    compare_state(program)
  end

  it 'matches on byte/halfword/word memory operations' do
    program = [
      asm.addi(1, 0, 0x300),
      asm.addi(2, 0, 0xAB),
      asm.sb(2, 1, 0),
      asm.lb(3, 1, 0),
      asm.lbu(4, 1, 0),
      asm.addi(5, 0, -1),
      asm.sh(5, 1, 2),
      asm.lh(6, 1, 2),
      asm.lhu(7, 1, 2),
      asm.addi(8, 0, 0x55),
      asm.sw(8, 1, 4),
      asm.lw(9, 1, 4)
    ]

    compare_state(program, mem_addrs: [0x300, 0x304])
  end

  it 'matches on branch and jump control flow' do
    program = [
      asm.addi(1, 0, 5),
      asm.addi(2, 0, 5),
      asm.beq(1, 2, 8),
      asm.addi(10, 0, 1),
      asm.addi(10, 10, 2),
      asm.addi(2, 0, 3),
      asm.bne(1, 2, 8),
      asm.addi(10, 10, 4),
      asm.addi(10, 10, 8),
      asm.addi(3, 0, -1),
      asm.addi(4, 0, 1),
      asm.blt(3, 4, 8),
      asm.addi(10, 10, 16),
      asm.addi(10, 10, 32),
      asm.bge(4, 3, 8),
      asm.addi(10, 10, 64),
      asm.addi(10, 10, 128),
      asm.addi(5, 0, 1),
      asm.addi(6, 0, -1),
      asm.bltu(5, 6, 8),
      asm.addi(10, 10, 256),
      asm.addi(10, 10, 512),
      asm.bgeu(6, 5, 8),
      asm.addi(10, 10, 1024),
      asm.addi(10, 10, 128),
      asm.jal(7, 8),
      asm.addi(10, 10, 512),
      asm.addi(11, 0, 120),
      asm.jalr(8, 11, 0),
      asm.addi(10, 10, 256),
      asm.addi(10, 10, 64)
    ]

    compare_state(program, extra_cycles: 16)
  end

  it 'matches on immediate and shift edge values' do
    program = [
      asm.addi(1, 0, 2047),
      asm.addi(2, 0, -2048),
      asm.add(3, 1, 2),
      asm.addi(4, 0, 40),
      asm.sll(5, 1, 4),       # shift amount uses rs2[4:0] = 8
      asm.srl(6, 5, 4),
      asm.lui(7, 0xFFFFF),
      asm.sra(8, 7, 4),
      asm.slti(9, 2, -2047),
      asm.sltiu(10, 2, 1)
    ]

    compare_state(program)
  end

  it 'matches on M-extension multiply/divide behavior' do
    program = [
      asm.addi(1, 0, -20),
      asm.addi(2, 0, 3),
      asm.addi(3, 0, 7),
      asm.addi(4, 0, 0),
      asm.addi(5, 0, -1),
      asm.lui(6, 0x80000),
      asm.mul(10, 1, 2),
      asm.mulh(11, 1, 2),
      asm.mulhsu(12, 1, 2),
      asm.mulhu(13, 5, 2),
      asm.div(14, 1, 2),
      asm.divu(15, 3, 2),
      asm.rem(16, 1, 2),
      asm.remu(17, 3, 2),
      asm.div(18, 3, 4),   # divide by zero
      asm.rem(19, 3, 4),   # remainder by zero
      asm.div(20, 6, 5),   # signed overflow: 0x80000000 / -1
      asm.rem(21, 6, 5)    # signed overflow remainder
    ]

    compare_state(program, extra_cycles: 12)
  end

  it 'matches on CSR Zicsr read/modify/write behavior' do
    program = [
      asm.addi(1, 0, 0x40),
      asm.csrrw(2, 0x305, 1),        # mtvec <- x1, x2 <- old mtvec
      asm.csrrs(3, 0x305, 0),        # x3 <- mtvec
      asm.addi(4, 0, 0b1010),
      asm.csrrw(0, 0x300, 4),        # mstatus <- x4
      asm.csrrsi(5, 0x300, 0b0101),  # x5 <- old, set bits
      asm.csrrci(6, 0x300, 0b0011),  # x6 <- old, clear bits
      asm.csrrs(7, 0x300, 0)         # x7 <- mstatus
    ]

    compare_state(program, extra_cycles: 10)
  end

  it 'matches on xv6-oriented SYSTEM compatibility (WFI/SFENCE.VMA + mip/sip)' do
    program = [
      asm.addi(1, 0, 7),
      asm.wfi,
      asm.addi(1, 1, 5),
      asm.fence_i,
      asm.sfence_vma,
      asm.lui(3, 1),              # x3 = 0x1000
      asm.addi(3, 3, -1912),      # x3 = 0x888
      asm.csrrw(0, 0x303, 3),     # mideleg = 0x888
      asm.nop,
      asm.csrrs(4, 0x344, 0),     # x4 = mip
      asm.csrrs(5, 0x144, 0)      # x5 = sip
    ]

    padded_program = program + Array.new(8, asm.nop)
    single = build_single
    single.load_program(padded_program)
    single.reset!
    single.set_interrupts(software: 1, timer: 1, external: 1)
    single.run_cycles(padded_program.length + 14)

    pipeline = build_pipeline
    pipeline.load_program(padded_program)
    pipeline.reset!
    pipeline.set_interrupts(software: 1, timer: 1, external: 1)
    pipeline.run_cycles(padded_program.length + 22)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
  end

  it 'matches on Sv32 data translation for mapped load/store accesses' do
    root_ppn = 0x001
    l0_ppn = 0x002
    data_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    data_pa = data_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_leaf_boot = ((0x000 & 0xFFFFF) << 10) | 0xF
    pte_leaf_rw = ((data_ppn & 0xFFFFF) << 10) | 0x7

    program = [
      asm.lui(1, 0x80000),
      asm.addi(1, 1, root_ppn),
      asm.csrrw(0, 0x180, 1),  # satp
      asm.nop,
      asm.nop,
      asm.lui(3, 0x1),         # VA 0x1000
      asm.lw(4, 3, 0),
      asm.addi(5, 0, 0x77),
      asm.sw(5, 3, 4),
      asm.nop
    ]

    single = build_single
    write_data_word(single, root_pa, pte_pointer)
    write_data_word(single, l0_pa, pte_leaf_boot)
    write_data_word(single, l0_pa + 4, pte_leaf_rw)
    write_data_word(single, data_pa, 0xA5A55A5A)
    single.load_program(program, 0)
    single.reset!
    single.run_cycles(28)

    pipeline = build_pipeline
    write_data_word(pipeline, root_pa, pte_pointer)
    write_data_word(pipeline, l0_pa, pte_leaf_boot)
    write_data_word(pipeline, l0_pa + 4, pte_leaf_rw)
    write_data_word(pipeline, data_pa, 0xA5A55A5A)
    pipeline.load_program(program, 0)
    pipeline.reset!
    pipeline.run_cycles(72)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
    expect(read_data_word(pipeline, data_pa + 4)).to eq(read_data_word(single, data_pa + 4))
  end

  it 'matches on Sv32 load page-fault trap cause and tval' do
    root_ppn = 0x001
    l0_ppn = 0x002
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_leaf_boot = ((0x000 & 0xFFFFF) << 10) | 0xF

    main_program = [
      asm.addi(1, 0, 0x200),   # mtvec
      asm.csrrw(0, 0x305, 1),
      asm.lui(1, 0x80000),
      asm.addi(1, 1, root_ppn),
      asm.csrrw(0, 0x180, 1),  # satp
      asm.nop,
      asm.nop,
      asm.lui(3, 0x1),         # VA 0x1000 (unmapped at level 0)
      asm.lw(2, 3, 0),
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0), # mcause
      asm.csrrs(11, 0x343, 0), # mtval
      asm.jal(0, 0)
    ]

    single = build_single
    write_data_word(single, root_pa, pte_pointer)
    write_data_word(single, l0_pa, pte_leaf_boot)
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(44)

    pipeline = build_pipeline
    write_data_word(pipeline, root_pa, pte_pointer)
    write_data_word(pipeline, l0_pa, pte_leaf_boot)
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(96)

    expect(single.read_reg(10)).to eq(13)
    expect(single.read_reg(11)).to eq(0x1000)
    expect(pipeline.read_reg(10)).to eq(single.read_reg(10))
    expect(pipeline.read_reg(11)).to eq(single.read_reg(11))
  end

  it 'matches on Sv32 instruction translation for mapped fetches' do
    root_ppn = 0x001
    l0_ppn = 0x002
    text_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    text_pa = text_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_leaf_boot_x = ((0x000 & 0xFFFFF) << 10) | 0xB
    pte_leaf_text_x = ((text_ppn & 0xFFFFF) << 10) | 0xB

    main_program = [
      asm.lui(1, 0x80000),
      asm.addi(1, 1, root_ppn),
      asm.csrrw(0, 0x180, 1),   # satp
      asm.nop,
      asm.nop,
      asm.lui(2, 0x1),          # VA 0x1000
      asm.jalr(0, 2, 0),
      asm.nop
    ]

    translated_page_program = [
      asm.addi(10, 0, 42),
      asm.jal(0, 0)
    ]

    single = build_single
    write_data_word(single, root_pa, pte_pointer)
    write_data_word(single, l0_pa, pte_leaf_boot_x)
    write_data_word(single, l0_pa + 4, pte_leaf_text_x)
    single.load_program(main_program, 0)
    single.load_program(translated_page_program, text_pa)
    single.reset!
    single.run_cycles(40)

    pipeline = build_pipeline
    write_data_word(pipeline, root_pa, pte_pointer)
    write_data_word(pipeline, l0_pa, pte_leaf_boot_x)
    write_data_word(pipeline, l0_pa + 4, pte_leaf_text_x)
    pipeline.load_program(main_program, 0)
    pipeline.load_program(translated_page_program, text_pa)
    pipeline.reset!
    pipeline.run_cycles(104)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
  end

  it 'matches on Sv32 instruction page-fault trap cause and tval' do
    root_ppn = 0x001
    l0_ppn = 0x002
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_leaf_boot_x = ((0x000 & 0xFFFFF) << 10) | 0xB

    main_program = [
      asm.addi(1, 0, 0x200),    # mtvec
      asm.csrrw(0, 0x305, 1),
      asm.lui(1, 0x80000),
      asm.addi(1, 1, root_ppn),
      asm.csrrw(0, 0x180, 1),   # satp
      asm.nop,
      asm.nop,
      asm.lui(2, 0x1),          # VA 0x1000 (unmapped)
      asm.jalr(0, 2, 0),
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0),  # mcause
      asm.csrrs(11, 0x343, 0),  # mtval
      asm.jal(0, 0)
    ]

    single = build_single
    write_data_word(single, root_pa, pte_pointer)
    write_data_word(single, l0_pa, pte_leaf_boot_x)
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(52)

    pipeline = build_pipeline
    write_data_word(pipeline, root_pa, pte_pointer)
    write_data_word(pipeline, l0_pa, pte_leaf_boot_x)
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(120)

    expect(single.read_reg(10)).to eq(12)
    expect(single.read_reg(11)).to eq(0x1000)
    expect(pipeline.read_reg(10)).to eq(single.read_reg(10))
    expect(pipeline.read_reg(11)).to eq(single.read_reg(11))
  end

  it 'matches on Sv32 S-mode instruction U-bit permission fault behavior' do
    root_ppn = 0x001
    l0_ppn = 0x002
    user_text_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    user_text_pa = user_text_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_leaf_boot_x = ((0x000 & 0xFFFFF) << 10) | 0xB
    pte_leaf_user_x = ((user_text_ppn & 0xFFFFF) << 10) | 0x1B

    main_program = [
      asm.addi(1, 0, 0x300),      # mtvec
      asm.csrrw(0, 0x305, 1),
      asm.lui(1, 0x1),            # x1 = 0x1000
      asm.addi(1, 1, -2048),      # x1 = 0x800 (MPP=S)
      asm.csrrw(0, 0x300, 1),     # mstatus
      asm.addi(1, 0, 0x20),       # mepc
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,                    # 0x20 next
      asm.lui(2, 0x80000),        # satp mode
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),
      asm.nop,
      asm.nop,
      asm.lui(3, 0x1),            # VA 0x1000 on U=1 X page
      asm.jalr(0, 3, 0),
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x342, 0),    # mcause
      asm.csrrs(11, 0x343, 0),    # mtval
      asm.jal(0, 0)
    ]

    user_program = [
      asm.addi(12, 0, 99),
      asm.jal(0, 0)
    ]

    single = build_single
    write_data_word(single, root_pa, pte_pointer)
    write_data_word(single, l0_pa, pte_leaf_boot_x)
    write_data_word(single, l0_pa + 4, pte_leaf_user_x)
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x300)
    single.load_program(user_program, user_text_pa)
    single.reset!
    single.run_cycles(88)

    pipeline = build_pipeline
    write_data_word(pipeline, root_pa, pte_pointer)
    write_data_word(pipeline, l0_pa, pte_leaf_boot_x)
    write_data_word(pipeline, l0_pa + 4, pte_leaf_user_x)
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x300)
    pipeline.load_program(user_program, user_text_pa)
    pipeline.reset!
    pipeline.run_cycles(196)

    expect(single.read_reg(10)).to eq(12)
    expect(single.read_reg(11)).to eq(0x1000)
    expect(single.read_reg(12)).to eq(0)
    expect(pipeline.read_reg(10)).to eq(single.read_reg(10))
    expect(pipeline.read_reg(11)).to eq(single.read_reg(11))
    expect(pipeline.read_reg(12)).to eq(single.read_reg(12))
  end

  it 'matches on Sv32 S-mode MXR behavior for loads from execute-only pages' do
    root_ppn = 0x001
    l0_ppn = 0x002
    data_ppn = 0x003
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    data_pa = data_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_leaf_boot = ((0x000 & 0xFFFFF) << 10) | 0xF
    pte_leaf_x_only = ((data_ppn & 0xFFFFF) << 10) | 0x9

    program = [
      asm.lui(1, 0x81),           # x1 = 0x81000
      asm.addi(1, 1, -2048),      # x1 = 0x80800 (MXR=1, MPP=S)
      asm.csrrw(0, 0x300, 1),     # mstatus
      asm.addi(1, 0, 0x20),       # mepc
      asm.csrrw(0, 0x341, 1),
      asm.mret,
      asm.nop,
      asm.nop,
      asm.lui(2, 0x80000),        # satp mode
      asm.addi(2, 2, root_ppn),
      asm.csrrw(0, 0x180, 2),
      asm.nop,
      asm.nop,
      asm.lui(3, 0x1),            # VA 0x1000
      asm.lw(4, 3, 0),
      asm.nop
    ]

    single = build_single
    write_data_word(single, root_pa, pte_pointer)
    write_data_word(single, l0_pa, pte_leaf_boot)
    write_data_word(single, l0_pa + 4, pte_leaf_x_only)
    write_data_word(single, data_pa, 0x5566_7788)
    single.load_program(program, 0)
    single.reset!
    single.run_cycles(88)

    pipeline = build_pipeline
    write_data_word(pipeline, root_pa, pte_pointer)
    write_data_word(pipeline, l0_pa, pte_leaf_boot)
    write_data_word(pipeline, l0_pa + 4, pte_leaf_x_only)
    write_data_word(pipeline, data_pa, 0x5566_7788)
    pipeline.load_program(program, 0)
    pipeline.reset!
    pipeline.run_cycles(196)

    expect(single.read_reg(4)).to eq(0x5566_7788)
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
  end

  it 'matches on Sv32 dTLB cache persistence and sfence.vma invalidation' do
    root_ppn = 0x001
    l0_ppn = 0x002
    data_a_ppn = 0x003
    data_b_ppn = 0x004
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    data_a_pa = data_a_ppn << 12
    data_b_pa = data_b_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_boot = ((0x000 & 0xFFFFF) << 10) | 0xF
    pte_data_a = ((data_a_ppn & 0xFFFFF) << 10) | 0x7
    pte_data_b = ((data_b_ppn & 0xFFFFF) << 10) | 0x7
    program = [
      asm.lui(1, 0x80000),
      asm.addi(1, 1, root_ppn),
      asm.csrrw(0, 0x180, 1),
      asm.nop,
      asm.nop,
      asm.lui(3, 0x1),
      asm.lw(10, 3, 0),
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.lw(11, 3, 0),
      asm.nop,
      asm.nop,
      asm.sfence_vma,
      asm.nop,
      asm.nop,
      asm.lw(12, 3, 0),
      asm.jal(0, 0)
    ]

    run_case = lambda do |cpu, pipeline_mode:|
      max_scale = pipeline_mode ? 3 : 1
      write_data_word(cpu, root_pa, pte_pointer)
      write_data_word(cpu, l0_pa, pte_boot)
      write_data_word(cpu, l0_pa + 4, pte_data_a)
      write_data_word(cpu, data_a_pa, 0x1111_1111)
      write_data_word(cpu, data_b_pa, 0x2222_2222)
      cpu.load_program(program, 0)
      cpu.reset!

      cycles = 0
      until cpu.read_reg(10) == 0x1111_1111
        raise 'timeout waiting for x10 first load' if cycles >= 180 * max_scale
        cpu.clock_cycle
        cycles += 1
      end
      write_data_word(cpu, l0_pa + 4, pte_data_b)

      cycles = 0
      until cpu.read_reg(11) != 0
        raise 'timeout waiting for x11 second load' if cycles >= 220 * max_scale
        cpu.clock_cycle
        cycles += 1
      end

      cycles = 0
      until cpu.read_reg(12) != 0
        raise 'timeout waiting for x12 third load' if cycles >= 280 * max_scale
        cpu.clock_cycle
        cycles += 1
      end

      [cpu.read_reg(10), cpu.read_reg(11), cpu.read_reg(12)]
    end

    single = build_single
    pipeline = build_pipeline
    single_regs = run_case.call(single, pipeline_mode: false)
    pipeline_regs = run_case.call(pipeline, pipeline_mode: true)

    expect(single_regs).to eq([0x1111_1111, 0x1111_1111, 0x2222_2222])
    expect(pipeline_regs).to eq(single_regs)
  end

  it 'matches on Sv32 iTLB cache persistence and sfence.vma invalidation' do
    root_ppn = 0x001
    l0_ppn = 0x002
    text_a_ppn = 0x003
    text_b_ppn = 0x004
    root_pa = root_ppn << 12
    l0_pa = l0_ppn << 12
    text_a_pa = text_a_ppn << 12
    text_b_pa = text_b_ppn << 12
    pte_pointer = ((l0_ppn & 0xFFFFF) << 10) | 0x1
    pte_boot_x = ((0x000 & 0xFFFFF) << 10) | 0xF
    pte_text_a = ((text_a_ppn & 0xFFFFF) << 10) | 0xB
    pte_text_b = ((text_b_ppn & 0xFFFFF) << 10) | 0xB
    main = [
      asm.lui(1, 0x80000),
      asm.addi(1, 1, root_ppn),
      asm.csrrw(0, 0x180, 1),
      asm.nop,
      asm.nop,
      asm.lui(3, 0x1),
      asm.jalr(1, 3, 0),
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.jalr(1, 3, 0),
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop,
      asm.sfence_vma,
      asm.nop,
      asm.nop,
      asm.jalr(1, 3, 0),
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

    run_case = lambda do |cpu, pipeline_mode:|
      max_scale = pipeline_mode ? 3 : 1
      write_data_word(cpu, root_pa, pte_pointer)
      write_data_word(cpu, l0_pa, pte_boot_x)
      write_data_word(cpu, l0_pa + 4, pte_text_a)
      cpu.load_program(main, 0)
      cpu.load_program(text_a, text_a_pa)
      cpu.load_program(text_b, text_b_pa)
      cpu.reset!

      cycles = 0
      until cpu.read_reg(10) == 1
        raise 'timeout waiting for first call' if cycles >= 240 * max_scale
        cpu.clock_cycle
        cycles += 1
      end
      write_data_word(cpu, l0_pa + 4, pte_text_b)

      cycles = 0
      until cpu.read_reg(10) >= 2
        raise 'timeout waiting for second call' if cycles >= 320 * max_scale
        cpu.clock_cycle
        cycles += 1
      end

      cycles = 0
      until cpu.read_reg(10) >= 4
        raise 'timeout waiting for third call' if cycles >= 420 * max_scale
        cpu.clock_cycle
        cycles += 1
      end

      cpu.read_reg(10)
    end

    single = build_single
    pipeline = build_pipeline
    single_x10 = run_case.call(single, pipeline_mode: false)
    pipeline_x10 = run_case.call(pipeline, pipeline_mode: true)

    expect(single_x10).to eq(4)
    expect(pipeline_x10).to eq(single_x10)
  end

  it 'matches on ECALL trap and MRET return behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      asm.addi(2, 0, 7),
      asm.ecall,                 # trap
      asm.addi(2, 2, 1),         # executes after mret
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(4, 0x342, 0),    # x4 = mcause
      asm.csrrs(3, 0x341, 0),    # x3 = mepc
      asm.csrrs(5, 0x343, 0),    # x5 = mtval
      asm.addi(3, 3, 4),
      asm.csrrw(0, 0x341, 3),    # mepc += 4
      asm.mret
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(14)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(48)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
  end

  it 'matches on EBREAK trap and MRET return behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      asm.addi(2, 0, 9),
      asm.ebreak,                # trap
      asm.addi(2, 2, 2),         # executes after mret
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(4, 0x342, 0),    # x4 = mcause
      asm.csrrs(3, 0x341, 0),    # x3 = mepc
      asm.csrrs(5, 0x343, 0),    # x5 = mtval
      asm.addi(3, 3, 4),
      asm.csrrw(0, 0x341, 3),    # mepc += 4
      asm.mret
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(14)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(48)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
  end

  it 'matches on mstatus trap-stack updates for ECALL/MRET' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      asm.addi(1, 0, 0x8),       # mstatus.MIE = 1
      asm.csrrw(0, 0x300, 1),
      asm.nop,
      asm.nop,
      asm.ecall,
      asm.csrrs(10, 0x300, 0),
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x300, 0),    # mstatus during trap
      asm.csrrs(3, 0x341, 0),    # mepc
      asm.addi(3, 3, 4),
      asm.csrrw(0, 0x341, 3),
      asm.mret
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(22)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(58)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
    expect(single.read_reg(2)).to eq(0x1880)
    expect(single.read_reg(10)).to eq(0x88)
  end

  it 'matches on illegal SYSTEM trap and MRET return behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      0x10600073,                # unknown SYSTEM funct12 => illegal instruction
      asm.addi(2, 0, 1),
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(4, 0x342, 0),    # x4 = mcause
      asm.csrrs(3, 0x341, 0),    # x3 = mepc
      asm.csrrs(5, 0x343, 0),    # x5 = mtval
      asm.addi(3, 3, 4),
      asm.csrrw(0, 0x341, 3),    # mepc += 4
      asm.mret
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(20)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(56)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
    expect(single.read_reg(2)).to eq(1)
    expect(single.read_reg(3)).to eq(20)
    expect(single.read_reg(4)).to eq(2)
    expect(single.read_reg(5)).to eq(0x10600073)
  end

  it 'matches on delegated ECALL trap to stvec and SRET return behavior' do
    main_program = [
      asm.addi(1, 0, 0x300),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x105, 1),    # stvec = x1
      asm.lui(1, 0x1),           # x1 = 0x1000
      asm.addi(1, 1, -2048),     # x1 = 0x800 (delegate code 11)
      asm.csrrw(0, 0x302, 1),    # medeleg = x1
      asm.addi(2, 0, 5),
      asm.ecall,
      asm.addi(2, 2, 1),
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(4, 0x142, 0),    # scause
      asm.csrrs(3, 0x141, 0),    # sepc
      asm.addi(3, 3, 4),
      asm.csrrw(0, 0x141, 3),
      asm.sret
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x300)
    single.reset!
    single.run_cycles(24)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x300)
    pipeline.reset!
    pipeline.run_cycles(66)

    expect(single.read_reg(2)).to eq(6)
    expect(single.read_reg(4)).to eq(11)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
    expect(pipeline.read_reg(3)).to eq(single.read_reg(3))
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
  end

  it 'matches on delegated illegal SYSTEM trap to stvec with stval' do
    illegal_inst = 0x10600073
    main_program = [
      asm.addi(1, 0, 0x300),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x105, 1),    # stvec = x1
      asm.addi(1, 0, 0x4),       # delegate code 2 (illegal instruction)
      asm.csrrw(0, 0x302, 1),    # medeleg = x1
      asm.addi(2, 0, 9),
      illegal_inst,
      asm.addi(2, 2, 1),
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(4, 0x142, 0),    # scause
      asm.csrrs(3, 0x141, 0),    # sepc
      asm.csrrs(5, 0x143, 0),    # stval
      asm.addi(3, 3, 4),
      asm.csrrw(0, 0x141, 3),
      asm.sret
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x300)
    single.reset!
    single.run_cycles(28)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x300)
    pipeline.reset!
    pipeline.run_cycles(72)

    expect(single.read_reg(2)).to eq(10)
    expect(single.read_reg(4)).to eq(2)
    expect(single.read_reg(5)).to eq(illegal_inst)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
    expect(pipeline.read_reg(3)).to eq(single.read_reg(3))
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
    expect(pipeline.read_reg(5)).to eq(single.read_reg(5))
  end

  it 'matches on delegated machine timer interrupt trap behavior' do
    main_program = [
      asm.addi(1, 0, 0x300),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x105, 1),    # stvec = x1
      asm.addi(1, 0, 0x80),      # MTIP bit
      asm.csrrw(0, 0x303, 1),    # mideleg = MTIP
      asm.csrrw(0, 0x104, 1),    # sie = MTIE
      asm.addi(1, 0, 0x2),       # sstatus.SIE = 1
      asm.csrrw(0, 0x100, 1),
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x142, 0),    # scause
      asm.csrrs(4, 0x100, 0),    # sstatus in handler
      asm.jal(0, 0)
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x300)
    single.reset!
    single.run_cycles(12)
    single.set_interrupts(timer: 1)
    single.run_cycles(10)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x300)
    pipeline.reset!
    pipeline.run_cycles(34)
    pipeline.set_interrupts(timer: 1)
    pipeline.run_cycles(28)

    expect(single.read_reg(2)).to eq(0x80000007)
    expect(single.read_reg(4)).to eq(0x120)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
  end

  it 'matches on machine timer interrupt trap behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      asm.addi(1, 0, 0x80),      # mie.MTIE = 1
      asm.csrrw(0, 0x304, 1),
      asm.addi(1, 0, 0x8),       # mstatus.MIE = 1
      asm.csrrw(0, 0x300, 1),
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x342, 0),    # mcause
      asm.csrrs(4, 0x300, 0),    # mstatus in handler
      asm.jal(0, 0)
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(10)
    single.set_interrupts(timer: 1)
    single.run_cycles(8)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(24)
    pipeline.set_interrupts(timer: 1)
    pipeline.run_cycles(24)

    expect(single.read_reg(2)).to eq(0x80000007)
    expect(single.read_reg(4)).to eq(0x1880)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
  end

  it 'matches on CLINT-driven machine timer interrupt trap behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      asm.lui(5, 0x2004),        # x5 = 0x02004000 (mtimecmp)
      asm.addi(6, 0, 40),
      asm.sw(6, 5, 0),           # mtimecmp low
      asm.sw(0, 5, 4),           # mtimecmp high
      asm.addi(1, 0, 0x80),      # mie.MTIE = 1
      asm.csrrw(0, 0x304, 1),
      asm.addi(1, 0, 0x8),       # mstatus.MIE = 1
      asm.csrrw(0, 0x300, 1),
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x342, 0),    # mcause
      asm.csrrs(4, 0x300, 0),    # mstatus in handler
      asm.jal(0, 0)
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(50)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(70)

    expect(single.read_reg(2)).to eq(0x80000007)
    expect(single.read_reg(4)).to eq(0x1880)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
  end

  it 'matches on CLINT-driven machine software interrupt trap behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1
      asm.lui(5, 0x2000),        # x5 = 0x02000000 (msip)
      asm.addi(6, 0, 1),
      asm.addi(1, 0, 0x8),       # mie.MSIE = 1
      asm.csrrw(0, 0x304, 1),
      asm.addi(1, 0, 0x8),       # mstatus.MIE = 1
      asm.csrrw(0, 0x300, 1),
      asm.sw(6, 5, 0),           # msip = 1
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x342, 0),    # mcause
      asm.csrrs(4, 0x300, 0),    # mstatus in handler
      asm.jal(0, 0)
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(50)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(70)

    expect(single.read_reg(2)).to eq(0x80000003)
    expect(single.read_reg(4)).to eq(0x1880)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
    expect(pipeline.read_reg(4)).to eq(single.read_reg(4))
  end

  it 'matches on PLIC-driven machine external interrupt trap behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1

      asm.lui(5, 0xC000),        # x5 = 0x0C000000 (PLIC base)
      asm.addi(6, 0, 1),
      asm.sw(6, 5, 4),           # priority[1] = 1

      asm.lui(7, 0xC002),        # x7 = 0x0C002000 (enable)
      asm.addi(11, 0, 2),        # x11 = bit 1 set
      asm.sw(11, 7, 0),          # enable source 1

      asm.lui(8, 0xC200),        # x8 = 0x0C200000 (threshold/claim)
      asm.sw(0, 8, 0),           # threshold = 0

      asm.lui(9, 0x1),           # x9 = 0x1000
      asm.addi(9, 9, -2048),     # x9 = 0x800 (MEIE)
      asm.csrrw(0, 0x304, 9),    # mie = MEIE

      asm.addi(1, 0, 0x8),       # mstatus.MIE = 1
      asm.csrrw(0, 0x300, 1),
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x342, 0),    # mcause
      asm.lui(10, 0xC200),       # claim/complete base
      asm.lw(3, 10, 4),          # claim id
      asm.sw(3, 10, 4),          # complete
      asm.jal(0, 0)
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(26)
    single.set_plic_sources(source1: 1)
    single.run_cycles(18)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(44)
    pipeline.set_plic_sources(source1: 1)
    pipeline.run_cycles(36)

    expect(single.read_reg(2)).to eq(0x8000000B)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
  end

  it 'matches on UART RX external interrupt via PLIC source 10 trap behavior' do
    main_program = [
      asm.addi(1, 0, 0x200),
      asm.nop,
      asm.nop,
      asm.csrrw(0, 0x305, 1),    # mtvec = x1

      asm.lui(5, 0xC000),        # x5 = 0x0C000000 (PLIC base)
      asm.addi(6, 0, 1),
      asm.sw(6, 5, 40),          # priority[10] = 1

      asm.lui(7, 0xC002),        # x7 = 0x0C002000 (enable)
      asm.addi(11, 0, 1024),     # x11 = bit 10 set
      asm.sw(11, 7, 0),          # enable source 10

      asm.lui(8, 0xC200),        # x8 = 0x0C200000 (threshold)
      asm.sw(0, 8, 0),           # threshold = 0

      asm.lui(12, 0x10000),      # x12 = 0x10000000 (UART)
      asm.addi(13, 0, 1),
      asm.sb(13, 12, 1),         # UART IER = RX interrupt enable

      asm.lui(9, 0x1),           # x9 = 0x1000
      asm.addi(9, 9, -2048),     # x9 = 0x800 (MEIE)
      asm.csrrw(0, 0x304, 9),    # mie = MEIE

      asm.addi(1, 0, 0x8),       # mstatus.MIE = 1
      asm.csrrw(0, 0x300, 1),
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(2, 0x342, 0),    # mcause
      asm.jal(0, 0)
    ]

    single = build_single
    single.load_program(main_program, 0)
    single.load_program(trap_handler, 0x200)
    single.reset!
    single.run_cycles(30)
    single.uart_receive_byte(0x41)
    single.run_cycles(20)

    pipeline = build_pipeline
    pipeline.load_program(main_program, 0)
    pipeline.load_program(trap_handler, 0x200)
    pipeline.reset!
    pipeline.run_cycles(58)
    pipeline.uart_receive_byte(0x41)
    pipeline.run_cycles(44)

    expect(single.read_reg(2)).to eq(0x8000000B)
    expect(pipeline.read_reg(2)).to eq(single.read_reg(2))
  end

  it 'matches on UART TX MMIO byte stream' do
    program = [
      asm.lui(1, 0x10000),     # x1 = 0x10000000
      asm.addi(2, 0, 0x41),    # 'A'
      asm.sb(2, 1, 0),         # THR = 'A'
      asm.addi(2, 0, 0x42),    # 'B'
      asm.sb(2, 1, 0),         # THR = 'B'
      asm.addi(2, 0, 0x43),    # 'C'
      asm.sb(2, 1, 0)          # THR = 'C'
    ]

    single = build_single
    single.load_program(program, 0)
    single.reset!
    single.clear_uart_tx_bytes
    single.run_cycles(program.length + 4)

    pipeline = build_pipeline
    pipeline.load_program(program, 0)
    pipeline.reset!
    pipeline.clear_uart_tx_bytes
    pipeline.run_cycles(program.length + 14)

    expect(single.uart_tx_bytes).to eq([0x41, 0x42, 0x43])
    expect(pipeline.uart_tx_bytes).to eq(single.uart_tx_bytes)
  end
end
