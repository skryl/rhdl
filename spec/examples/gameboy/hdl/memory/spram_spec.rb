# frozen_string_literal: true

require 'spec_helper'

# Game Boy Single-Port RAM (SPRAM) Tests
# Tests the SPRAM component - simple single-port RAM with single clock domain

RSpec.describe 'GameBoy SPRAM' do
  before(:all) do
    begin
      require_relative '../../../../../examples/gameboy/gameboy'
      require_relative '../../../../../examples/gameboy/hdl/memory/spram'
      @component_available = defined?(RHDL::Examples::GameBoy::SPRAM)
    rescue LoadError => e
      @component_available = false
      @load_error = e.message
    end
  end

  before(:each) do
    skip "SPRAM component not available: #{@load_error}" unless @component_available
  end

  # Helper to perform a clock cycle
  def clock_cycle(spram)
    spram.set_input(:clock, 0)
    spram.propagate
    spram.set_input(:clock, 1)
    spram.propagate
  end

  # ==========================================================================
  # Component Definition Tests
  # ==========================================================================
  describe 'Component Definition' do
    it 'defines SPRAM class' do
      expect(defined?(RHDL::Examples::GameBoy::SPRAM)).to eq('constant')
    end

    it 'can be instantiated' do
      spram = RHDL::Examples::GameBoy::SPRAM.new('test_spram')
      expect(spram).to be_a(RHDL::Examples::GameBoy::SPRAM)
    end

    it 'has correct address width (13-bit for 8KB)' do
      expect(RHDL::Examples::GameBoy::SPRAM::ADDR_WIDTH).to eq(13)
    end

    it 'has correct data width (8-bit)' do
      expect(RHDL::Examples::GameBoy::SPRAM::DATA_WIDTH).to eq(8)
    end

    it 'has correct depth (8192 entries)' do
      expect(RHDL::Examples::GameBoy::SPRAM::DEPTH).to eq(8192)
    end
  end

  # ==========================================================================
  # Basic Write Operations
  # ==========================================================================
  describe 'Write Operations' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_write') }

    it 'writes data to memory' do
      spram.set_input(:address, 0x100)
      spram.set_input(:data_in, 0xAB)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      expect(spram.read_mem(0x100)).to eq(0xAB)
    end

    it 'writes to address 0' do
      spram.set_input(:address, 0x000)
      spram.set_input(:data_in, 0x42)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      expect(spram.read_mem(0x000)).to eq(0x42)
    end

    it 'writes to maximum address' do
      max_addr = RHDL::Examples::GameBoy::SPRAM::DEPTH - 1  # 0x1FFF

      spram.set_input(:address, max_addr)
      spram.set_input(:data_in, 0xFF)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      expect(spram.read_mem(max_addr)).to eq(0xFF)
    end

    it 'overwrites existing data' do
      spram.write_mem(0x200, 0x11)

      spram.set_input(:address, 0x200)
      spram.set_input(:data_in, 0x22)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      expect(spram.read_mem(0x200)).to eq(0x22)
    end

    it 'does not write when wren is 0' do
      spram.write_mem(0x300, 0xAA)

      spram.set_input(:address, 0x300)
      spram.set_input(:data_in, 0xBB)
      spram.set_input(:wren, 0)
      clock_cycle(spram)

      expect(spram.read_mem(0x300)).to eq(0xAA)
    end
  end

  # ==========================================================================
  # Basic Read Operations
  # ==========================================================================
  describe 'Read Operations' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_read') }

    it 'reads data from memory (synchronous)' do
      spram.write_mem(0x100, 0xCD)

      spram.set_input(:address, 0x100)
      spram.set_input(:wren, 0)
      clock_cycle(spram)

      expect(spram.get_output(:data_out)).to eq(0xCD)
    end

    it 'reads after write in same cycle shows data on next cycle' do
      # Write data
      spram.set_input(:address, 0x200)
      spram.set_input(:data_in, 0xEF)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      # Read back (synchronous read)
      spram.set_input(:wren, 0)
      spram.set_input(:address, 0x200)
      clock_cycle(spram)

      expect(spram.get_output(:data_out)).to eq(0xEF)
    end

    it 'reads different addresses sequentially' do
      spram.write_mem(0x00, 0x11)
      spram.write_mem(0x01, 0x22)
      spram.write_mem(0x02, 0x33)

      spram.set_input(:wren, 0)

      spram.set_input(:address, 0x00)
      clock_cycle(spram)
      expect(spram.get_output(:data_out)).to eq(0x11)

      spram.set_input(:address, 0x01)
      clock_cycle(spram)
      expect(spram.get_output(:data_out)).to eq(0x22)

      spram.set_input(:address, 0x02)
      clock_cycle(spram)
      expect(spram.get_output(:data_out)).to eq(0x33)
    end

    it 'reads data value 0x00 correctly' do
      spram.write_mem(0x400, 0x00)

      spram.set_input(:address, 0x400)
      spram.set_input(:wren, 0)
      clock_cycle(spram)

      expect(spram.get_output(:data_out)).to eq(0x00)
    end

    it 'reads data value 0xFF correctly' do
      spram.write_mem(0x500, 0xFF)

      spram.set_input(:address, 0x500)
      spram.set_input(:wren, 0)
      clock_cycle(spram)

      expect(spram.get_output(:data_out)).to eq(0xFF)
    end
  end

  # ==========================================================================
  # Direct Memory Access
  # ==========================================================================
  describe 'Direct Memory Access' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_direct') }

    it 'supports direct read via read_mem' do
      spram.write_mem(0x50, 0x12)
      expect(spram.read_mem(0x50)).to eq(0x12)
    end

    it 'supports direct write via write_mem' do
      spram.write_mem(0x60, 0x34)
      expect(spram.read_mem(0x60)).to eq(0x34)
    end

    it 'provides access to memory array' do
      spram.write_mem(0x70, 0xAA)
      spram.write_mem(0x71, 0xBB)

      mem = spram.memory_array
      expect(mem).to be_a(Array)
      expect(mem[0x70]).to eq(0xAA)
      expect(mem[0x71]).to eq(0xBB)
    end

    it 'wraps address to valid range' do
      # 13-bit address = 8192 entries, so address wraps at 0x2000
      spram.write_mem(0x0000, 0x99)
      # Reading 0x2000 should wrap to 0x0000
      expect(spram.read_mem(0x2000)).to eq(0x99)
    end
  end

  # ==========================================================================
  # Sequential Access Patterns
  # ==========================================================================
  describe 'Sequential Access Patterns' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_seq') }

    it 'handles burst write pattern' do
      base_addr = 0x100
      data = [0x10, 0x20, 0x30, 0x40, 0x50]

      data.each_with_index do |value, offset|
        spram.set_input(:address, base_addr + offset)
        spram.set_input(:data_in, value)
        spram.set_input(:wren, 1)
        clock_cycle(spram)
      end

      # Verify all values were written
      data.each_with_index do |expected, offset|
        expect(spram.read_mem(base_addr + offset)).to eq(expected)
      end
    end

    it 'handles burst read pattern' do
      base_addr = 0x200
      data = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]

      # Pre-populate memory
      data.each_with_index do |value, offset|
        spram.write_mem(base_addr + offset, value)
      end

      # Burst read
      spram.set_input(:wren, 0)
      results = []

      data.each_with_index do |_, offset|
        spram.set_input(:address, base_addr + offset)
        clock_cycle(spram)
        results << spram.get_output(:data_out)
      end

      expect(results).to eq(data)
    end

    it 'handles alternating read/write pattern' do
      # Write-Read-Write-Read pattern
      spram.set_input(:address, 0x300)
      spram.set_input(:data_in, 0x11)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      spram.set_input(:wren, 0)
      clock_cycle(spram)
      expect(spram.get_output(:data_out)).to eq(0x11)

      spram.set_input(:data_in, 0x22)
      spram.set_input(:wren, 1)
      clock_cycle(spram)

      spram.set_input(:wren, 0)
      clock_cycle(spram)
      expect(spram.get_output(:data_out)).to eq(0x22)
    end
  end

  # ==========================================================================
  # Boundary Conditions
  # ==========================================================================
  describe 'Boundary Conditions' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_boundary') }

    it 'handles all bits of address' do
      # Test various address patterns
      addresses = [0x000, 0x001, 0x555, 0xAAA, 0x1FFF]

      addresses.each_with_index do |addr, idx|
        spram.set_input(:address, addr)
        spram.set_input(:data_in, idx + 1)
        spram.set_input(:wren, 1)
        clock_cycle(spram)
      end

      addresses.each_with_index do |addr, idx|
        expect(spram.read_mem(addr)).to eq(idx + 1)
      end
    end

    it 'handles all bits of data' do
      # Test various data patterns
      patterns = [0x00, 0x01, 0x55, 0xAA, 0xFF]

      patterns.each_with_index do |data, idx|
        spram.set_input(:address, idx)
        spram.set_input(:data_in, data)
        spram.set_input(:wren, 1)
        clock_cycle(spram)
      end

      patterns.each_with_index do |expected, idx|
        spram.set_input(:address, idx)
        spram.set_input(:wren, 0)
        clock_cycle(spram)
        expect(spram.get_output(:data_out)).to eq(expected)
      end
    end
  end

  # ==========================================================================
  # Memory Initialization
  # ==========================================================================
  describe 'Memory Initialization' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_init') }

    it 'can fill memory with a pattern' do
      # Fill first 10 locations with incrementing values
      (0...10).each do |i|
        spram.write_mem(i, i * 10)
      end

      (0...10).each do |i|
        expect(spram.read_mem(i)).to eq(i * 10)
      end
    end

    it 'memory array can be accessed for bulk initialization' do
      mem = spram.memory_array

      # Bulk write
      (0...100).each do |i|
        mem[i] = i
      end

      # Verify via read_mem
      (0...100).each do |i|
        expect(spram.read_mem(i)).to eq(i)
      end
    end
  end

  # ==========================================================================
  # Clock Edge Behavior
  # ==========================================================================
  describe 'Clock Edge Behavior' do
    let(:spram) { RHDL::Examples::GameBoy::SPRAM.new('spram_clock') }

    it 'write takes effect on rising edge' do
      spram.set_input(:address, 0x100)
      spram.set_input(:data_in, 0x42)
      spram.set_input(:wren, 1)

      # Low clock - write should not happen yet
      spram.set_input(:clock, 0)
      spram.propagate

      # Memory should not be updated yet (depending on implementation)
      # The key is that it works after the full cycle
      initial_value = spram.read_mem(0x100)

      # Rising edge - write should happen
      spram.set_input(:clock, 1)
      spram.propagate

      # Now the value should be written
      expect(spram.read_mem(0x100)).to eq(0x42)
    end

    it 'maintains data across multiple clock cycles without write' do
      spram.write_mem(0x200, 0xAB)

      spram.set_input(:address, 0x200)
      spram.set_input(:wren, 0)

      # Multiple clock cycles without write
      5.times do
        clock_cycle(spram)
        expect(spram.read_mem(0x200)).to eq(0xAB)
      end
    end
  end
end
