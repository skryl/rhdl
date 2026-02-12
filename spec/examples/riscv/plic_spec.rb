require 'spec_helper'
require_relative '../../../examples/riscv/hdl/plic'
require_relative '../../../examples/riscv/hdl/constants'

RSpec.describe RHDL::Examples::RISCV::Plic do
  let(:plic) { described_class.new('plic') }

  def drive(clk:, rst:, addr: 0, write_data: 0, mem_read: 0, mem_write: 0, source1: 0, source10: 0)
    plic.set_input(:clk, clk)
    plic.set_input(:rst, rst)
    plic.set_input(:addr, addr)
    plic.set_input(:write_data, write_data)
    plic.set_input(:mem_read, mem_read)
    plic.set_input(:mem_write, mem_write)
    plic.set_input(:funct3, RHDL::Examples::RISCV::Funct3::WORD)
    plic.set_input(:source1, source1)
    plic.set_input(:source10, source10)
    plic.propagate
  end

  def reset_plic
    drive(clk: 0, rst: 1)
    drive(clk: 1, rst: 1)
    drive(clk: 0, rst: 0)
  end

  def tick(source1: 0, source10: 0, addr: 0, write_data: 0, mem_read: 0, mem_write: 0)
    drive(clk: 0, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write, source1: source1, source10: source10)
    drive(clk: 1, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write, source1: source1, source10: source10)
  end

  def write_word(addr, value)
    tick(addr: addr, write_data: value, mem_write: 1)
    drive(clk: 0, rst: 0)
  end

  def read_word(addr)
    drive(clk: 0, rst: 0, addr: addr, mem_read: 1)
    plic.get_output(:read_data)
  end

  def configure_source1
    write_word(described_class::PRIORITY_1_ADDR, 1)
    write_word(described_class::ENABLE_ADDR, 0b10)
    write_word(described_class::THRESHOLD_ADDR, 0)
  end

  before do
    reset_plic
  end

  it 'asserts external interrupt when source 1 is pending and enabled' do
    configure_source1
    tick(source1: 1)

    expect(read_word(described_class::PENDING_ADDR)).to eq(0b10)
    expect(plic.get_output(:irq_external)).to eq(1)
  end

  it 'supports claim/complete flow for source 1' do
    configure_source1
    tick(source1: 1)

    # Claim source 1.
    drive(clk: 0, rst: 0, addr: described_class::CLAIM_COMPLETE_ADDR, mem_read: 1)
    expect(plic.get_output(:read_data)).to eq(1)
    drive(clk: 1, rst: 0, addr: described_class::CLAIM_COMPLETE_ADDR, mem_read: 1)
    expect(plic.get_output(:read_data)).to eq(1)
    drive(clk: 0, rst: 0)

    expect(read_word(described_class::PENDING_ADDR)).to eq(0)
    expect(read_word(described_class::CLAIM_COMPLETE_ADDR)).to eq(0)
    expect(plic.get_output(:irq_external)).to eq(0)

    # Complete source 1 and verify it can fire again.
    write_word(described_class::CLAIM_COMPLETE_ADDR, 1)
    tick(source1: 1)

    expect(read_word(described_class::PENDING_ADDR)).to eq(0b10)
    expect(plic.get_output(:irq_external)).to eq(1)
  end

  it 'supports source 10 pending/enable/claim-complete flow' do
    write_word(described_class::PRIORITY_10_ADDR, 2)
    write_word(described_class::ENABLE_ADDR, (1 << 10))
    write_word(described_class::THRESHOLD_ADDR, 0)

    tick(source10: 1)

    expect(read_word(described_class::PENDING_ADDR)).to eq(1 << 10)
    expect(plic.get_output(:irq_external)).to eq(1)

    drive(clk: 0, rst: 0, addr: described_class::CLAIM_COMPLETE_ADDR, mem_read: 1)
    expect(plic.get_output(:read_data)).to eq(10)
    drive(clk: 1, rst: 0, addr: described_class::CLAIM_COMPLETE_ADDR, mem_read: 1)
    expect(plic.get_output(:read_data)).to eq(10)
    drive(clk: 0, rst: 0)

    expect(read_word(described_class::PENDING_ADDR)).to eq(0)
    expect(plic.get_output(:irq_external)).to eq(0)

    write_word(described_class::CLAIM_COMPLETE_ADDR, 10)
    tick(source10: 1)
    expect(read_word(described_class::PENDING_ADDR)).to eq(1 << 10)
    expect(plic.get_output(:irq_external)).to eq(1)
  end
end
