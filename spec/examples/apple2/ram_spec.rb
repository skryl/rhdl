# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/ram'

RSpec.describe RHDL::Apple2::RAM do
  let(:ram) { described_class.new('ram') }

  before do
    ram
    ram.set_input(:clk, 0)
    ram.set_input(:cs, 0)
    ram.set_input(:we, 0)
    ram.set_input(:addr, 0)
    ram.set_input(:din, 0)
  end

  def clock_cycle
    ram.set_input(:clk, 0)
    ram.propagate
    ram.set_input(:clk, 1)
    ram.propagate
  end

  def write_byte(addr, data)
    ram.set_input(:addr, addr)
    ram.set_input(:din, data)
    ram.set_input(:cs, 1)
    ram.set_input(:we, 1)
    clock_cycle
    ram.set_input(:we, 0)
    ram.set_input(:cs, 0)
  end

  def read_byte(addr)
    ram.set_input(:addr, addr)
    ram.set_input(:cs, 1)
    ram.set_input(:we, 0)
    ram.propagate  # Async read
    ram.get_output(:dout)
  end

  describe 'initialization' do
    it 'has 48KB capacity' do
      # Verify by writing and reading at high address
      write_byte(0xBFFF, 0x42)
      expect(read_byte(0xBFFF)).to eq(0x42)
    end

    it 'supports 16-bit addressing' do
      # Test various addresses across the 16-bit range
      write_byte(0x0000, 0x11)
      write_byte(0x8000, 0x22)
      write_byte(0xBFFF, 0x33)
      expect(read_byte(0x0000)).to eq(0x11)
      expect(read_byte(0x8000)).to eq(0x22)
      expect(read_byte(0xBFFF)).to eq(0x33)
    end

    it 'has 8-bit data width' do
      # Verify by writing and reading all bit patterns
      write_byte(0x0100, 0xFF)
      expect(read_byte(0x0100)).to eq(0xFF)
    end
  end

  describe 'write operations' do
    it 'writes data when cs=1 and we=1' do
      write_byte(0x0000, 0xAA)

      data = read_byte(0x0000)
      expect(data).to eq(0xAA)
    end

    it 'does not write when cs=0' do
      # Write with cs=0
      ram.set_input(:addr, 0x0100)
      ram.set_input(:din, 0x55)
      ram.set_input(:cs, 0)
      ram.set_input(:we, 1)
      clock_cycle

      # Read should return 0 (uninitialized)
      data = read_byte(0x0100)
      expect(data).to eq(0)
    end

    it 'does not write when we=0' do
      # Write with we=0
      ram.set_input(:addr, 0x0200)
      ram.set_input(:din, 0x77)
      ram.set_input(:cs, 1)
      ram.set_input(:we, 0)
      clock_cycle

      data = read_byte(0x0200)
      expect(data).to eq(0)
    end

    it 'writes on rising clock edge (synchronous)' do
      ram.set_input(:addr, 0x0300)
      ram.set_input(:din, 0x99)
      ram.set_input(:cs, 1)
      ram.set_input(:we, 1)

      # Before rising edge
      ram.set_input(:clk, 0)
      ram.propagate

      # Rising edge
      ram.set_input(:clk, 1)
      ram.propagate

      ram.set_input(:we, 0)
      ram.set_input(:cs, 0)

      data = read_byte(0x0300)
      expect(data).to eq(0x99)
    end
  end

  describe 'read operations' do
    it 'reads data asynchronously (combinational)' do
      # First write some data
      write_byte(0x0400, 0xBB)

      # Async read - output changes immediately with address
      ram.set_input(:addr, 0x0400)
      ram.set_input(:cs, 1)
      ram.set_input(:we, 0)
      ram.propagate  # Propagate combinational logic

      data = ram.get_output(:dout)
      expect(data).to eq(0xBB)
    end

    it 'requires cs=1 to read' do
      write_byte(0x0500, 0xCC)

      # Read with cs=0
      ram.set_input(:addr, 0x0500)
      ram.set_input(:cs, 0)
      ram.propagate

      # Output should be 0 or high-Z equivalent
      data = ram.get_output(:dout)
      expect(data).to eq(0)
    end

    it 'updates output immediately when address changes' do
      write_byte(0x0600, 0x11)
      write_byte(0x0601, 0x22)

      ram.set_input(:cs, 1)
      ram.set_input(:we, 0)

      ram.set_input(:addr, 0x0600)
      ram.propagate
      expect(ram.get_output(:dout)).to eq(0x11)

      ram.set_input(:addr, 0x0601)
      ram.propagate
      expect(ram.get_output(:dout)).to eq(0x22)
    end
  end

  describe 'address space' do
    it 'supports full 48KB address range' do
      # Test various addresses across the range
      test_addresses = [0x0000, 0x1000, 0x4000, 0x8000, 0xBFFF]

      test_addresses.each_with_index do |addr, i|
        write_byte(addr, i + 1)
      end

      test_addresses.each_with_index do |addr, i|
        data = read_byte(addr)
        expect(data).to eq(i + 1), "Failed at address #{addr.to_s(16)}"
      end
    end

    it 'handles zero-page addresses ($00-$FF)' do
      # Zero page is critical for 6502
      (0..15).each do |i|
        write_byte(i, i * 16)
      end

      (0..15).each do |i|
        data = read_byte(i)
        expect(data).to eq(i * 16)
      end
    end

    it 'handles stack page addresses ($100-$1FF)' do
      # Stack page for 6502
      (0x100..0x10F).each do |addr|
        write_byte(addr, addr & 0xFF)
      end

      (0x100..0x10F).each do |addr|
        data = read_byte(addr)
        expect(data).to eq(addr & 0xFF)
      end
    end

    it 'handles text page 1 addresses ($0400-$07FF)' do
      # Apple II text page 1
      write_byte(0x0400, 0xC1)  # 'A' with high bit
      write_byte(0x07FF, 0xD0)  # 'P' with high bit

      expect(read_byte(0x0400)).to eq(0xC1)
      expect(read_byte(0x07FF)).to eq(0xD0)
    end

    it 'handles hires page 1 addresses ($2000-$3FFF)' do
      # Apple II hires page 1
      write_byte(0x2000, 0x00)
      write_byte(0x3FFF, 0xFF)

      expect(read_byte(0x2000)).to eq(0x00)
      expect(read_byte(0x3FFF)).to eq(0xFF)
    end
  end

  describe 'data patterns' do
    it 'preserves all 8 data bits' do
      test_patterns = [0x00, 0xFF, 0xAA, 0x55, 0x0F, 0xF0, 0x01, 0x80]

      test_patterns.each_with_index do |pattern, i|
        write_byte(0x0700 + i, pattern)
      end

      test_patterns.each_with_index do |pattern, i|
        data = read_byte(0x0700 + i)
        expect(data).to eq(pattern), "Pattern #{pattern.to_s(16)} failed"
      end
    end
  end

  describe 'simulation helpers' do
    it 'provides read_mem for direct access' do
      write_byte(0x0800, 0xDE)

      data = ram.read_mem(0x0800)
      expect(data).to eq(0xDE)
    end

    it 'provides write_mem for direct access' do
      ram.write_mem(0x0900, 0xAD)

      data = read_byte(0x0900)
      expect(data).to eq(0xAD)
    end

    it 'provides load_binary for bulk loading' do
      binary_data = [0x01, 0x02, 0x03, 0x04, 0x05]
      ram.load_binary(binary_data, 0x0A00)

      binary_data.each_with_index do |byte, i|
        data = read_byte(0x0A00 + i)
        expect(data).to eq(byte)
      end
    end

    it 'provides dump for bulk reading' do
      ram.write_mem(0x0B00, 0x10)
      ram.write_mem(0x0B01, 0x20)
      ram.write_mem(0x0B02, 0x30)

      dumped = ram.dump(0x0B00, 3)
      expect(dumped).to eq([0x10, 0x20, 0x30])
    end
  end
end

RSpec.describe RHDL::Apple2::DualPortRAM do
  let(:dpram) { described_class.new('dpram') }

  before do
    dpram
    # Port A inputs
    dpram.set_input(:clk_a, 0)
    dpram.set_input(:cs_a, 0)
    dpram.set_input(:we_a, 0)
    dpram.set_input(:addr_a, 0)
    dpram.set_input(:din_a, 0)

    # Port B inputs
    dpram.set_input(:clk_b, 0)
    dpram.set_input(:cs_b, 0)
    dpram.set_input(:addr_b, 0)
  end

  def clock_a
    dpram.set_input(:clk_a, 0)
    dpram.propagate
    dpram.set_input(:clk_a, 1)
    dpram.propagate
  end

  def clock_b
    dpram.set_input(:clk_b, 0)
    dpram.propagate
    dpram.set_input(:clk_b, 1)
    dpram.propagate
  end

  def write_port_a(addr, data)
    dpram.set_input(:addr_a, addr)
    dpram.set_input(:din_a, data)
    dpram.set_input(:cs_a, 1)
    dpram.set_input(:we_a, 1)
    clock_a
    dpram.set_input(:we_a, 0)
    dpram.set_input(:cs_a, 0)
  end

  def read_port_a(addr)
    dpram.set_input(:addr_a, addr)
    dpram.set_input(:cs_a, 1)
    dpram.set_input(:we_a, 0)
    dpram.propagate
    dpram.get_output(:dout_a)
  end

  def read_port_b(addr)
    dpram.set_input(:addr_b, addr)
    dpram.set_input(:cs_b, 1)
    dpram.propagate
    dpram.get_output(:dout_b)
  end

  describe 'dual-port operation' do
    it 'allows simultaneous read from both ports' do
      write_port_a(0x0000, 0xAA)
      write_port_a(0x0001, 0xBB)

      # Simultaneous read
      dpram.set_input(:addr_a, 0x0000)
      dpram.set_input(:addr_b, 0x0001)
      dpram.set_input(:cs_a, 1)
      dpram.set_input(:cs_b, 1)
      dpram.propagate

      data_a = dpram.get_output(:dout_a)
      data_b = dpram.get_output(:dout_b)

      expect(data_a).to eq(0xAA)
      expect(data_b).to eq(0xBB)
    end

    it 'allows port A write while port B reads' do
      # Initial write
      write_port_a(0x0100, 0x11)

      # Set up port B to read
      dpram.set_input(:addr_b, 0x0100)
      dpram.set_input(:cs_b, 1)
      dpram.propagate

      expect(dpram.get_output(:dout_b)).to eq(0x11)

      # Port A writes new value
      write_port_a(0x0100, 0x22)

      # Port B should see updated value
      dpram.set_input(:addr_b, 0x0100)
      dpram.set_input(:cs_b, 1)
      dpram.propagate

      expect(dpram.get_output(:dout_b)).to eq(0x22)
    end

    it 'supports different addresses on each port' do
      write_port_a(0x0200, 0x33)
      write_port_a(0x0300, 0x44)

      # Read different addresses simultaneously
      dpram.set_input(:addr_a, 0x0200)
      dpram.set_input(:addr_b, 0x0300)
      dpram.set_input(:cs_a, 1)
      dpram.set_input(:cs_b, 1)
      dpram.propagate

      expect(dpram.get_output(:dout_a)).to eq(0x33)
      expect(dpram.get_output(:dout_b)).to eq(0x44)
    end
  end

  describe 'port B (video read port)' do
    # Reference: Port B is read-only for video access

    it 'reads correctly from any address' do
      # Populate memory via port A
      (0..15).each do |i|
        write_port_a(i, i * 17)  # 0x00, 0x11, 0x22, ...
      end

      # Read via port B
      (0..15).each do |i|
        data = read_port_b(i)
        expect(data).to eq(i * 17)
      end
    end

    it 'requires cs_b=1 to read' do
      write_port_a(0x0400, 0x55)

      dpram.set_input(:addr_b, 0x0400)
      dpram.set_input(:cs_b, 0)
      dpram.propagate

      # Should return 0 when not selected
      expect(dpram.get_output(:dout_b)).to eq(0)
    end
  end

  describe 'expression-based enable' do
    # Reference: Memory DSL uses [:cs_a, :&, :we_a] for write enable

    it 'only writes when both cs_a and we_a are high' do
      # Test all combinations
      combinations = [
        [0, 0, false],
        [0, 1, false],
        [1, 0, false],
        [1, 1, true]
      ]

      combinations.each_with_index do |(cs, we, should_write), i|
        addr = 0x0500 + i
        dpram.set_input(:addr_a, addr)
        dpram.set_input(:din_a, 0xEE)
        dpram.set_input(:cs_a, cs)
        dpram.set_input(:we_a, we)
        clock_a
        dpram.set_input(:cs_a, 0)
        dpram.set_input(:we_a, 0)

        data = read_port_a(addr)
        if should_write
          expect(data).to eq(0xEE), "Should write when cs=#{cs}, we=#{we}"
        else
          expect(data).to eq(0), "Should not write when cs=#{cs}, we=#{we}"
        end
      end
    end
  end

  describe 'simulation helpers' do
    it 'provides read_mem for direct access' do
      write_port_a(0x0600, 0x77)
      expect(dpram.read_mem(0x0600)).to eq(0x77)
    end

    it 'provides write_mem for direct access' do
      dpram.write_mem(0x0700, 0x88)
      expect(read_port_a(0x0700)).to eq(0x88)
    end
  end
end
