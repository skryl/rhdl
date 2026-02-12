require 'spec_helper'
require_relative '../../../examples/riscv/hdl/virtio_blk'
require_relative '../../../examples/riscv/hdl/memory'
require_relative '../../../examples/riscv/hdl/constants'

RSpec.describe RHDL::Examples::RISCV::VirtioBlk do
  let(:virtio) { described_class.new('virtio', disk_size: 16 * 1024, queue_num_max: 8) }
  let(:mem) { RHDL::Examples::RISCV::Memory.new('virtio_mem', size: 128 * 1024) }

  def drive(clk:, rst:, addr: 0, write_data: 0, mem_read: 0, mem_write: 0, funct3: RHDL::Examples::RISCV::Funct3::WORD)
    virtio.set_input(:clk, clk)
    virtio.set_input(:rst, rst)
    virtio.set_input(:addr, addr)
    virtio.set_input(:write_data, write_data)
    virtio.set_input(:mem_read, mem_read)
    virtio.set_input(:mem_write, mem_write)
    virtio.set_input(:funct3, funct3)
    virtio.propagate
  end

  def reset_device
    drive(clk: 0, rst: 1)
    drive(clk: 1, rst: 1)
    drive(clk: 0, rst: 0)
  end

  def tick(addr: 0, write_data: 0, mem_read: 0, mem_write: 0)
    drive(clk: 0, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write)
    drive(clk: 1, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write)
  end

  def write_word(addr, value)
    tick(addr: addr, write_data: value, mem_write: 1)
    drive(clk: 0, rst: 0)
  end

  def read_word(addr)
    drive(clk: 0, rst: 0, addr: addr, mem_read: 1)
    virtio.get_output(:read_data) & 0xFFFF_FFFF
  end

  def write_u16(addr, value)
    mem.write_byte(addr, value & 0xFF)
    mem.write_byte(addr + 1, (value >> 8) & 0xFF)
  end

  def write_u32(addr, value)
    mem.write_word(addr, value & 0xFFFF_FFFF)
  end

  def write_u64(addr, value)
    write_u32(addr, value & 0xFFFF_FFFF)
    write_u32(addr + 4, (value >> 32) & 0xFFFF_FFFF)
  end

  def read_u16(addr)
    (mem.read_byte(addr) & 0xFF) | ((mem.read_byte(addr + 1) & 0xFF) << 8)
  end

  before do
    reset_device
  end

  it 'exposes expected virtio-blk identity registers for xv6' do
    expect(read_word(described_class::MAGIC_VALUE_ADDR)).to eq(described_class::VIRTIO_MAGIC)
    expect(read_word(described_class::VERSION_ADDR)).to eq(2)
    expect(read_word(described_class::DEVICE_ID_ADDR)).to eq(2)
    expect(read_word(described_class::VENDOR_ID_ADDR)).to eq(described_class::VIRTIO_VENDOR_ID)
  end

  it 'tracks status and queue configuration registers through MMIO' do
    expect(read_word(described_class::QUEUE_NUM_MAX_ADDR)).to eq(8)

    write_word(described_class::STATUS_ADDR, 0x1)
    write_word(described_class::STATUS_ADDR, 0x3)
    write_word(described_class::QUEUE_SEL_ADDR, 0)
    write_word(described_class::QUEUE_NUM_ADDR, 8)
    write_word(described_class::QUEUE_READY_ADDR, 1)

    expect(read_word(described_class::STATUS_ADDR) & 0xFF).to eq(0x3)
    expect(read_word(described_class::QUEUE_NUM_ADDR)).to eq(8)
    expect(read_word(described_class::QUEUE_READY_ADDR)).to eq(1)
  end

  it 'processes queued disk reads and raises/acks an interrupt' do
    desc_base = 0x2000
    avail_base = 0x3000
    used_base = 0x4000
    req_addr = 0x5000
    data_addr = 0x6000
    status_addr = 0x7000

    write_word(described_class::QUEUE_SEL_ADDR, 0)
    write_word(described_class::QUEUE_NUM_ADDR, 8)
    write_word(described_class::QUEUE_DESC_LOW_ADDR, desc_base)
    write_word(described_class::QUEUE_DESC_HIGH_ADDR, 0)
    write_word(described_class::QUEUE_DRIVER_LOW_ADDR, avail_base)
    write_word(described_class::QUEUE_DRIVER_HIGH_ADDR, 0)
    write_word(described_class::QUEUE_DEVICE_LOW_ADDR, used_base)
    write_word(described_class::QUEUE_DEVICE_HIGH_ADDR, 0)
    write_word(described_class::QUEUE_READY_ADDR, 1)
    write_word(described_class::STATUS_ADDR, described_class::STATUS_ACKNOWLEDGE | described_class::STATUS_DRIVER | described_class::STATUS_DRIVER_OK)

    virtio.load_disk_bytes((0...64).to_a, offset: 512)

    # Desc0: request header
    write_u64(desc_base + 0, req_addr)
    write_u32(desc_base + 8, 16)
    write_u16(desc_base + 12, described_class::DESC_F_NEXT)
    write_u16(desc_base + 14, 1)

    # Desc1: data buffer
    write_u64(desc_base + 16, data_addr)
    write_u32(desc_base + 24, 16)
    write_u16(desc_base + 28, described_class::DESC_F_NEXT | described_class::DESC_F_WRITE)
    write_u16(desc_base + 30, 2)

    # Desc2: status byte
    write_u64(desc_base + 32, status_addr)
    write_u32(desc_base + 40, 1)
    write_u16(desc_base + 44, described_class::DESC_F_WRITE)
    write_u16(desc_base + 46, 0)

    # Request: type=IN, reserved=0, sector=1
    write_u32(req_addr + 0, described_class::REQ_T_IN)
    write_u32(req_addr + 4, 0)
    write_u64(req_addr + 8, 1)

    write_u16(avail_base + 0, 0)
    write_u16(avail_base + 2, 1)
    write_u16(avail_base + 4, 0)

    write_word(described_class::QUEUE_NOTIFY_ADDR, 0)
    virtio.service_queues!(mem)

    expect(mem.read_byte(data_addr)).to eq(0)
    expect(mem.read_byte(data_addr + 1)).to eq(1)
    expect(mem.read_byte(data_addr + 15)).to eq(15)
    expect(mem.read_byte(status_addr)).to eq(0)
    expect(read_u16(used_base + 2)).to eq(1)
    expect(read_word(described_class::INTERRUPT_STATUS_ADDR) & 0x1).to eq(1)

    write_word(described_class::INTERRUPT_ACK_ADDR, 0x1)
    expect(read_word(described_class::INTERRUPT_STATUS_ADDR) & 0x1).to eq(0)
    drive(clk: 0, rst: 0)
    expect(virtio.get_output(:irq)).to eq(0)
  end

  it 'processes queued disk writes into the backing store' do
    desc_base = 0x2200
    avail_base = 0x3200
    used_base = 0x4200
    req_addr = 0x5200
    data_addr = 0x6200
    status_addr = 0x7200

    write_word(described_class::QUEUE_SEL_ADDR, 0)
    write_word(described_class::QUEUE_NUM_ADDR, 8)
    write_word(described_class::QUEUE_DESC_LOW_ADDR, desc_base)
    write_word(described_class::QUEUE_DESC_HIGH_ADDR, 0)
    write_word(described_class::QUEUE_DRIVER_LOW_ADDR, avail_base)
    write_word(described_class::QUEUE_DRIVER_HIGH_ADDR, 0)
    write_word(described_class::QUEUE_DEVICE_LOW_ADDR, used_base)
    write_word(described_class::QUEUE_DEVICE_HIGH_ADDR, 0)
    write_word(described_class::QUEUE_READY_ADDR, 1)
    write_word(described_class::STATUS_ADDR, described_class::STATUS_ACKNOWLEDGE | described_class::STATUS_DRIVER | described_class::STATUS_DRIVER_OK)

    16.times { |i| mem.write_byte(data_addr + i, (0xA0 + i) & 0xFF) }

    # Desc0: request header
    write_u64(desc_base + 0, req_addr)
    write_u32(desc_base + 8, 16)
    write_u16(desc_base + 12, described_class::DESC_F_NEXT)
    write_u16(desc_base + 14, 1)

    # Desc1: data buffer (device reads from memory for OUT)
    write_u64(desc_base + 16, data_addr)
    write_u32(desc_base + 24, 16)
    write_u16(desc_base + 28, described_class::DESC_F_NEXT)
    write_u16(desc_base + 30, 2)

    # Desc2: status byte
    write_u64(desc_base + 32, status_addr)
    write_u32(desc_base + 40, 1)
    write_u16(desc_base + 44, described_class::DESC_F_WRITE)
    write_u16(desc_base + 46, 0)

    # Request: type=OUT, reserved=0, sector=2
    write_u32(req_addr + 0, described_class::REQ_T_OUT)
    write_u32(req_addr + 4, 0)
    write_u64(req_addr + 8, 2)

    write_u16(avail_base + 0, 0)
    write_u16(avail_base + 2, 1)
    write_u16(avail_base + 4, 0)

    write_word(described_class::QUEUE_NOTIFY_ADDR, 0)
    virtio.service_queues!(mem)

    expect(virtio.read_disk_byte(1024)).to eq(0xA0)
    expect(virtio.read_disk_byte(1024 + 15)).to eq(0xAF)
    expect(mem.read_byte(status_addr)).to eq(0)
    expect(read_word(described_class::INTERRUPT_STATUS_ADDR) & 0x1).to eq(1)
  end
end
