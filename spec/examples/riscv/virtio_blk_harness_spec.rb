require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/hdl/virtio_blk'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'virtio-blk MMIO visibility' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:, extra_cycles: 0)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 20 : 8) + extra_cycles)
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

  it 'exposes virtio identification and queue capability registers' do
    program = [
      asm.lui(3, 0x10001),         # x3 = 0x1000_1000 (virtio-mmio base)
      asm.lw(10, 3, 0x000),        # x10 = magic
      asm.lw(11, 3, 0x004),        # x11 = version
      asm.lw(12, 3, 0x008),        # x12 = device id
      asm.lw(13, 3, 0x00C),        # x13 = vendor id
      asm.addi(14, 0, 0),          # x14 = queue index 0
      asm.sw(14, 3, 0x030),        # QUEUE_SEL = 0
      asm.lw(15, 3, 0x034),        # x15 = QUEUE_NUM_MAX
      asm.nop
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10)).to eq(RHDL::Examples::RISCV::VirtioBlk::VIRTIO_MAGIC)
    expect(cpu.read_reg(11)).to eq(1)
    expect(cpu.read_reg(12)).to eq(2)
    expect(cpu.read_reg(13)).to eq(RHDL::Examples::RISCV::VirtioBlk::VIRTIO_VENDOR_ID)
    expect(cpu.read_reg(15)).to eq(RHDL::Examples::RISCV::VirtioBlk::QUEUE_NUM_MAX)
  end

  it 'supports xv6-like status handshake and queue ready writes' do
    program = [
      asm.lui(3, 0x10001),         # x3 = 0x1000_1000
      asm.addi(14, 0, 1),          # ACKNOWLEDGE
      asm.sw(14, 3, 0x070),        # STATUS = ACKNOWLEDGE
      asm.addi(14, 0, 3),          # ACKNOWLEDGE|DRIVER
      asm.sw(14, 3, 0x070),        # STATUS = 3
      asm.addi(14, 0, 8),          # queue num
      asm.sw(14, 3, 0x038),        # QUEUE_NUM = 8
      asm.addi(14, 0, 1),          # queue ready = 1
      asm.sw(14, 3, 0x044),        # QUEUE_READY = 1
      asm.lw(10, 3, 0x070),        # x10 = STATUS
      asm.lw(11, 3, 0x038),        # x11 = QUEUE_NUM
      asm.lw(12, 3, 0x044),        # x12 = QUEUE_READY
      asm.nop
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10) & 0xFF).to eq(3)
    expect(cpu.read_reg(11)).to eq(8)
    expect(cpu.read_reg(12)).to eq(1)
  end

  it 'processes disk reads through legacy queue_pfn setup' do
    desc_base = 0x2000
    avail_base = desc_base + (8 * 16)
    used_base = desc_base + 0x1000
    req_addr = 0x5000
    data_addr = 0x6000
    status_addr = 0x7000

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

    program = [
      asm.lui(3, 0x10001),   # x3 = 0x1000_1000
      asm.addi(14, 0, 0),
      asm.sw(14, 3, 0x030),  # QUEUE_SEL = 0
      asm.addi(14, 0, 8),
      asm.sw(14, 3, 0x038),  # QUEUE_NUM = 8
      asm.lui(14, 0x1),
      asm.sw(14, 3, 0x028),  # GUEST_PAGE_SIZE = 4096
      asm.addi(14, 0, 2),
      asm.sw(14, 3, 0x040),  # QUEUE_PFN = 0x2000 >> 12
      asm.addi(14, 0, 7),
      asm.sw(14, 3, 0x070),  # STATUS = ACK|DRIVER|DRIVER_OK
      asm.addi(14, 0, 0),
      asm.sw(14, 3, 0x050),  # QUEUE_NOTIFY = 0
      asm.lw(10, 3, 0x060),  # x10 = INTERRUPT_STATUS
      asm.nop
    ]

    cpu.load_program(program)
    cpu.run_cycles(program.length + (pipeline ? 60 : 30))

    expect(mem_read_word(cpu, data_addr)).to eq(0x0302_0100)
    expect(mem_read_word(cpu, data_addr + 12)).to eq(0x0F0E_0D0C)
    expect(mem_read_word(cpu, status_addr) & 0xFF).to eq(0)
    expect(mem_read_word(cpu, used_base) >> 16).to eq(1)
    expect(cpu.read_reg(10) & 0x1).to eq(1)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'virtio-blk MMIO visibility', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('virtio_blk_pipeline', backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'virtio-blk MMIO visibility', pipeline: true
end
