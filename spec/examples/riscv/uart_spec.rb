require 'spec_helper'
require_relative '../../../examples/riscv/hdl/uart'
require_relative '../../../examples/riscv/hdl/constants'

RSpec.describe RHDL::Examples::RISCV::Uart do
  let(:uart) { described_class.new('uart') }

  def drive(clk:, rst:, addr: 0, write_data: 0, mem_read: 0, mem_write: 0, funct3: RHDL::Examples::RISCV::Funct3::BYTE_U, rx_valid: 0, rx_data: 0)
    uart.set_input(:clk, clk)
    uart.set_input(:rst, rst)
    uart.set_input(:addr, addr)
    uart.set_input(:write_data, write_data)
    uart.set_input(:mem_read, mem_read)
    uart.set_input(:mem_write, mem_write)
    uart.set_input(:funct3, funct3)
    uart.set_input(:rx_valid, rx_valid)
    uart.set_input(:rx_data, rx_data)
    uart.propagate
  end

  def reset_uart
    drive(clk: 0, rst: 1)
    drive(clk: 1, rst: 1)
    drive(clk: 0, rst: 0)
  end

  def tick(addr: 0, write_data: 0, mem_read: 0, mem_write: 0, funct3: RHDL::Examples::RISCV::Funct3::BYTE_U, rx_valid: 0, rx_data: 0)
    drive(clk: 0, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write, funct3: funct3, rx_valid: rx_valid, rx_data: rx_data)
    drive(clk: 1, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write, funct3: funct3, rx_valid: rx_valid, rx_data: rx_data)
  end

  def write_byte(addr, value)
    tick(addr: addr, write_data: value & 0xFF, mem_write: 1, funct3: RHDL::Examples::RISCV::Funct3::BYTE)
  end

  def read_byte(addr)
    drive(clk: 0, rst: 0, addr: addr, mem_read: 1, funct3: RHDL::Examples::RISCV::Funct3::BYTE_U)
    uart.get_output(:read_data) & 0xFF
  end

  before do
    reset_uart
  end

  it 'exposes THR writes on tx output' do
    tick(
      addr: described_class::BASE_ADDR + described_class::REG_THR_RBR_DLL,
      write_data: 0x55,
      mem_write: 1,
      funct3: RHDL::Examples::RISCV::Funct3::BYTE
    )

    expect(uart.get_output(:tx_valid)).to eq(1)
    expect(uart.get_output(:tx_data)).to eq(0x55)

    drive(clk: 0, rst: 0)
    expect(uart.get_output(:tx_valid)).to eq(0)
  end

  it 'raises RX interrupt when byte arrives and IER enables it' do
    write_byte(described_class::BASE_ADDR + described_class::REG_IER_DLM, 0x01)

    tick(rx_valid: 1, rx_data: 0x41)
    drive(clk: 0, rst: 0)

    expect(uart.get_output(:irq)).to eq(1)
    expect(read_byte(described_class::BASE_ADDR + described_class::REG_IIR_FCR)).to eq(0x04)
    expect(read_byte(described_class::BASE_ADDR + described_class::REG_LSR)).to eq(0x61)

    expect(read_byte(described_class::BASE_ADDR + described_class::REG_THR_RBR_DLL)).to eq(0x41)
    drive(
      clk: 1,
      rst: 0,
      addr: described_class::BASE_ADDR + described_class::REG_THR_RBR_DLL,
      mem_read: 1,
      funct3: RHDL::Examples::RISCV::Funct3::BYTE_U
    )
    drive(clk: 0, rst: 0)
    expect(uart.get_output(:irq)).to eq(0)
    expect(read_byte(described_class::BASE_ADDR + described_class::REG_IIR_FCR)).to eq(0x01)
  end
end
