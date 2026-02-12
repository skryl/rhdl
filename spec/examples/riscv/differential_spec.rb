# Differential tests for single-cycle vs pipelined RV32I CPUs
# Ensures both implementations produce the same architectural state

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/harness'
require_relative '../../../examples/riscv/hdl/pipeline/harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe 'RISC-V single-cycle vs pipelined equivalence', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def build_single
    RHDL::Examples::RISCV::Harness.new(mem_size: 65_536)
  end

  def build_pipeline
    RHDL::Examples::RISCV::Pipeline::Harness.new('pipeline_equiv')
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
      0x10500073,                # WFI (unsupported here) => illegal instruction
      asm.addi(2, 0, 1),
      asm.nop,
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(4, 0x342, 0),    # x4 = mcause
      asm.csrrs(3, 0x341, 0),    # x3 = mepc
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
end
