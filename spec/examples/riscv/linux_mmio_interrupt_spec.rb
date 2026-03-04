# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/hdl/virtio_blk'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'linux mmio/interrupt integration' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def mem_read_word(cpu, addr)
    if cpu.respond_to?(:read_data_word)
      cpu.read_data_word(addr)
    else
      cpu.read_data(addr)
    end
  end

  def mem_write_word(cpu, addr, value)
    if cpu.respond_to?(:write_data_word)
      cpu.write_data_word(addr, value)
    else
      cpu.write_data(addr, value)
    end
  end

  def write_u16(cpu, addr, value)
    base = addr & ~0x3
    shift = (addr & 0x3) * 8
    word = mem_read_word(cpu, base)
    mask = 0xFFFF << shift
    mem_write_word(cpu, base, (word & ~mask) | ((value & 0xFFFF) << shift))
  end

  def write_u32(cpu, addr, value)
    mem_write_word(cpu, addr, value & 0xFFFF_FFFF)
  end

  def write_u64(cpu, addr, value)
    write_u32(cpu, addr, value & 0xFFFF_FFFF)
    write_u32(cpu, addr + 4, (value >> 32) & 0xFFFF_FFFF)
  end

  it 'routes CLINT mtimecmp timer interrupts via M-mode relay into supervisor SSIP trap' do
    # MTIP is not delegable to S-mode.  The xv6 flow is:
    #   drop to S-mode -> hardware MTIP -> M-mode trap -> M-mode handler
    #   sets SSIP in sip -> mret to S-mode -> SSIP fires -> scause 0x80000001
    s_mode_entry = 0x200   # S-mode code runs here

    main_program = [
      asm.addi(1, 0, 0x400),       # mtvec = M-mode handler at 0x400
      asm.csrrw(0, 0x305, 1),
      asm.addi(1, 0, 0x300),       # stvec = S-mode handler at 0x300
      asm.csrrw(0, 0x105, 1),
      asm.addi(2, 0, 0x2),         # SSIP bit (bit 1)
      asm.csrrw(0, 0x303, 2),      # mideleg = SSIP (delegable)
      asm.csrrw(0, 0x104, 2),      # sie = SSIE
      asm.csrrw(0, 0x100, 2),      # sstatus.SIE = 1
      asm.addi(2, 0, 0x80),        # MTIP bit (bit 7)
      asm.csrrw(0, 0x304, 2),      # mie = MTIP
      # Set mstatus: MPP=S
      asm.lui(2, 0x1),             # x2 = 0x1000
      asm.addi(2, 2, -2048),       # x2 = 0x800 (MPP=S)
      asm.csrrs(0, 0x300, 2),      # mstatus |= MPP_S
      asm.addi(2, 0, s_mode_entry),# mepc = S-mode entry
      asm.csrrw(0, 0x341, 2),      # mepc = s_mode_entry
      asm.mret                     # drop to S-mode at s_mode_entry
    ]

    # S-mode code: set mtimecmp then wait
    s_mode_code = [
      asm.lui(5, 0x2004),          # CLINT mtimecmp low = 0x02004000
      asm.addi(6, 0, 100),         # low threshold
      asm.sw(6, 5, 0),             # mtimecmp_lo = 100
      asm.sw(0, 5, 4),             # mtimecmp_hi = 0
      asm.nop,
      asm.nop,
      asm.nop,
      asm.nop
    ]

    # M-mode trap handler: set SSIP in sip, clear MTIP enable, then mret
    m_trap_handler = [
      asm.addi(3, 0, 0x2),         # SSIP bit
      asm.csrrs(0, 0x144, 3),      # sip |= SSIP
      asm.addi(3, 0, 0x80),        # MTIP bit
      asm.csrrc(0, 0x304, 3),      # mie &= ~MTIP (prevent re-entry)
      asm.csrrs(4, 0x341, 0),      # x4 = mepc
      asm.addi(4, 4, 4),           # mepc += 4
      asm.csrrw(0, 0x341, 4),      # mepc = mepc + 4
      asm.mret                     # return to S-mode (MPP=S from original trap)
    ]

    # S-mode trap handler: read scause
    s_trap_handler = [
      asm.csrrs(10, 0x142, 0),     # x10 = scause
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(s_mode_code, s_mode_entry)
    cpu.load_program(s_trap_handler, 0x300)
    cpu.load_program(m_trap_handler, 0x400)
    cpu.reset!
    cpu.run_cycles(pipeline ? 260 : 130)

    expect(cpu.read_reg(10)).to eq(0x80000001)
  end

  it 'routes UART RX through PLIC source10 supervisor enable and claim/complete path' do
    s_mode_entry = 0x200
    main_program = [
      asm.addi(1, 0, 0x300),      # stvec
      asm.csrrw(0, 0x105, 1),
      asm.addi(2, 0, 0x200),      # x2 = 0x200 (SEIP)
      asm.csrrw(0, 0x303, 2),     # mideleg = SEIP
      asm.csrrw(0, 0x104, 2),     # sie = SEIE
      asm.addi(2, 0, 0x2),
      asm.csrrw(0, 0x100, 2),     # sstatus.SIE = 1

      asm.lui(5, 0xC000),         # PLIC priority
      asm.addi(6, 0, 1),
      asm.sw(6, 5, 40),           # priority[10] = 1

      asm.lui(7, 0xC002),         # SENABLE (hart0)
      asm.addi(7, 7, 0x80),       # 0x0C002080
      asm.addi(6, 0, 1024),       # bit 10
      asm.sw(6, 7, 0),

      asm.lui(8, 0xC201),         # STHRESHOLD/SCLAIM
      asm.sw(0, 8, 0),            # threshold = 0

      asm.lui(12, 0x10000),       # UART base
      asm.addi(13, 0, 1),
      asm.sb(13, 12, 1),          # UART IER = RX interrupt enable

      # Drop to S-mode: mstatus MPP=S
      asm.lui(2, 0x1),
      asm.addi(2, 2, -2048),      # x2 = 0x800 (MPP=S)
      asm.csrrs(0, 0x300, 2),     # mstatus |= MPP_S
      asm.addi(2, 0, s_mode_entry),
      asm.csrrw(0, 0x341, 2),     # mepc = s_mode_entry
      asm.mret
    ]

    s_mode_code = [asm.jal(0, 0)]

    trap_handler = [
      asm.csrrs(10, 0x142, 0),    # scause
      asm.lui(11, 0xC201),
      asm.lw(12, 11, 4),          # claim
      asm.sw(12, 11, 4),          # complete
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(s_mode_code, s_mode_entry)
    cpu.load_program(trap_handler, 0x300)
    cpu.reset!
    cpu.run_cycles(pipeline ? 100 : 48)
    cpu.uart_receive_byte(0x41)
    cpu.run_cycles(pipeline ? 80 : 40)

    expect(cpu.read_reg(10)).to eq(0x80000009)
    expect(cpu.read_reg(12)).to eq(10)
  end

  it 'surfaces virtio queue notify completion through PLIC source1 and virtio interrupt status' do
    desc_base = 0x2000
    avail_base = desc_base + (8 * 16)
    used_base = desc_base + 0x1000
    req_addr = 0x5000
    data_addr = 0x6000
    status_addr = 0x7000
    s_mode_entry = 0x400

    main_program = [
      asm.addi(1, 0, 0x300),      # stvec
      asm.csrrw(0, 0x105, 1),
      asm.addi(2, 0, 0x200),      # x2 = 0x200 (SEIP)
      asm.csrrw(0, 0x303, 2),     # mideleg = SEIP
      asm.csrrw(0, 0x104, 2),     # sie = SEIE
      asm.addi(2, 0, 0x2),
      asm.csrrw(0, 0x100, 2),     # sstatus.SIE = 1

      asm.lui(5, 0xC000),         # PLIC priority[1]
      asm.addi(6, 0, 1),
      asm.sw(6, 5, 4),
      asm.lui(7, 0xC002),         # SENABLE
      asm.addi(7, 7, 0x80),       # 0x0C002080
      asm.addi(6, 0, 2),          # bit 1
      asm.sw(6, 7, 0),
      asm.lui(8, 0xC201),         # STHRESHOLD
      asm.sw(0, 8, 0),

      asm.lui(3, 0x10001),        # virtio-mmio base
      asm.addi(14, 0, 0),
      asm.sw(14, 3, 0x030),       # QUEUE_SEL = 0
      asm.addi(14, 0, 8),
      asm.sw(14, 3, 0x038),       # QUEUE_NUM = 8
      asm.lui(14, 0x1),
      asm.sw(14, 3, 0x028),       # GUEST_PAGE_SIZE = 4096
      asm.addi(14, 0, 2),
      asm.sw(14, 3, 0x040),       # QUEUE_PFN = 0x2000 >> 12
      asm.addi(14, 0, 7),
      asm.sw(14, 3, 0x070),       # STATUS = ACK|DRIVER|DRIVER_OK
      asm.addi(14, 0, 0),
      asm.sw(14, 3, 0x050),       # QUEUE_NOTIFY = 0

      # Drop to S-mode: mstatus MPP=S
      asm.lui(2, 0x1),
      asm.addi(2, 2, -2048),      # x2 = 0x800 (MPP=S)
      asm.csrrs(0, 0x300, 2),     # mstatus |= MPP_S
      asm.addi(2, 0, s_mode_entry),
      asm.csrrw(0, 0x341, 2),     # mepc = s_mode_entry
      asm.mret
    ]

    s_mode_code = [asm.jal(0, 0)]

    trap_handler = [
      asm.csrrs(10, 0x142, 0),    # scause
      asm.lui(11, 0xC201),
      asm.lw(12, 11, 4),          # claim
      asm.lui(13, 0x10001),
      asm.lw(14, 13, 0x060),      # virtio INTERRUPT_STATUS (sample before clear/complete)
      asm.sw(14, 13, 0x064),      # virtio INTERRUPT_ACK
      asm.sw(12, 11, 4),          # complete
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(s_mode_code, s_mode_entry)
    cpu.load_program(trap_handler, 0x300)
    cpu.reset!
    cpu.load_virtio_disk((0...64).to_a, offset: 512)

    # Desc0: request header
    write_u64(cpu, desc_base + 0, req_addr)
    write_u32(cpu, desc_base + 8, 16)
    write_u16(cpu, desc_base + 12, RHDL::Examples::RISCV::VirtioBlk::DESC_F_NEXT)
    write_u16(cpu, desc_base + 14, 1)

    # Desc1: data buffer
    write_u64(cpu, desc_base + 16, data_addr)
    write_u32(cpu, desc_base + 24, 16)
    write_u16(
      cpu,
      desc_base + 28,
      RHDL::Examples::RISCV::VirtioBlk::DESC_F_NEXT | RHDL::Examples::RISCV::VirtioBlk::DESC_F_WRITE
    )
    write_u16(cpu, desc_base + 30, 2)

    # Desc2: status byte
    write_u64(cpu, desc_base + 32, status_addr)
    write_u32(cpu, desc_base + 40, 1)
    write_u16(cpu, desc_base + 44, RHDL::Examples::RISCV::VirtioBlk::DESC_F_WRITE)
    write_u16(cpu, desc_base + 46, 0)

    # Request: type=IN, reserved=0, sector=1
    write_u32(cpu, req_addr + 0, RHDL::Examples::RISCV::VirtioBlk::REQ_T_IN)
    write_u32(cpu, req_addr + 4, 0)
    write_u64(cpu, req_addr + 8, 1)

    # avail.flags=0, avail.idx=1, avail.ring[0]=0
    write_u16(cpu, avail_base + 0, 0)
    write_u16(cpu, avail_base + 2, 1)
    write_u16(cpu, avail_base + 4, 0)
    write_u16(cpu, used_base + 2, 0)

    cpu.run_cycles(pipeline ? 280 : 150)

    expect(cpu.read_reg(10)).to eq(0x80000009)
    expect(cpu.read_reg(12)).to eq(1)
    expect(mem_read_word(cpu, data_addr)).to eq(0x0302_0100)
    expect(mem_read_word(cpu, status_addr) & 0xFF).to eq(0)
  end
end

RSpec.describe 'RISC-V Linux MMIO/interrupt integration', timeout: 30 do
  backends = {
    jit: RHDL::Sim::Native::IR::JIT_AVAILABLE,
    interpreter: RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE
  }
  backends[:compiler] = RHDL::Sim::Native::IR::COMPILER_AVAILABLE if ENV['RHDL_LINUX_INCLUDE_COMPILER'] == '1'

  backends.each do |backend, available|
    context "single-cycle on #{backend}" do
      let(:cpu) { RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: backend) }

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'linux mmio/interrupt integration', pipeline: false
    end

    context "pipeline on #{backend}" do
      let(:cpu) do
        RHDL::Examples::RISCV::Pipeline::IRHarness.new(
          "linux_mmio_pipeline_#{backend}",
          mem_size: 65_536,
          backend: backend
        )
      end

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'linux mmio/interrupt integration', pipeline: true
    end
  end
end
