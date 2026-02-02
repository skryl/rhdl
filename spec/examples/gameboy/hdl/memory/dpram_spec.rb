# frozen_string_literal: true

require 'spec_helper'

# Game Boy Dual-Port RAM (DPRAM) Tests
# Tests the DPRAM component used for VRAM, WRAM, etc.

RSpec.describe 'GameBoy DPRAM' do
  before(:all) do
    begin
      require_relative '../../../../../examples/gameboy/gameboy'
      require_relative '../../../../../examples/gameboy/hdl/memory/dpram'
      @component_available = defined?(GameBoy::DPRAM)
    rescue LoadError => e
      @component_available = false
      @load_error = e.message
    end
  end

  before(:each) do
    skip "DPRAM component not available: #{@load_error}" unless @component_available
  end

  # Helper to perform a clock cycle on a port
  def clock_cycle_a(dpram)
    dpram.set_input(:clock_a, 0)
    dpram.propagate
    dpram.set_input(:clock_a, 1)
    dpram.propagate
  end

  def clock_cycle_b(dpram)
    dpram.set_input(:clock_b, 0)
    dpram.propagate
    dpram.set_input(:clock_b, 1)
    dpram.propagate
  end

  def clock_cycle_both(dpram)
    dpram.set_input(:clock_a, 0)
    dpram.set_input(:clock_b, 0)
    dpram.propagate
    dpram.set_input(:clock_a, 1)
    dpram.set_input(:clock_b, 1)
    dpram.propagate
  end

  # ==========================================================================
  # Component Definition Tests
  # ==========================================================================
  describe 'Component Definition' do
    it 'defines DPRAM class' do
      expect(defined?(GameBoy::DPRAM)).to eq('constant')
    end

    it 'can be instantiated' do
      dpram = GameBoy::DPRAM.new('test_dpram')
      expect(dpram).to be_a(GameBoy::DPRAM)
    end

    it 'has correct default address width (13-bit for 8KB)' do
      expect(GameBoy::DPRAM::DEFAULT_ADDR_WIDTH).to eq(13)
    end

    it 'has correct data width (8-bit)' do
      expect(GameBoy::DPRAM::DATA_WIDTH).to eq(8)
    end
  end

  # ==========================================================================
  # Port A Operations
  # ==========================================================================
  describe 'Port A Operations' do
    let(:dpram) { GameBoy::DPRAM.new('dpram_a') }

    it 'writes data via Port A' do
      dpram.set_input(:address_a, 0x100)
      dpram.set_input(:data_a, 0xAB)
      dpram.set_input(:wren_a, 1)
      dpram.set_input(:wren_b, 0)
      clock_cycle_a(dpram)

      # Verify data was written
      expect(dpram.read_mem(0x100)).to eq(0xAB)
    end

    it 'reads data via Port A after write' do
      # Write data
      dpram.set_input(:address_a, 0x200)
      dpram.set_input(:data_a, 0xCD)
      dpram.set_input(:wren_a, 1)
      clock_cycle_a(dpram)

      # Read back (synchronous read - needs another clock cycle)
      dpram.set_input(:wren_a, 0)
      dpram.set_input(:address_a, 0x200)
      clock_cycle_a(dpram)

      expect(dpram.get_output(:q_a)).to eq(0xCD)
    end

    it 'reads different addresses via Port A' do
      # Write multiple values
      dpram.write_mem(0x00, 0x11)
      dpram.write_mem(0x01, 0x22)
      dpram.write_mem(0x02, 0x33)

      dpram.set_input(:wren_a, 0)

      # Read address 0x00
      dpram.set_input(:address_a, 0x00)
      clock_cycle_a(dpram)
      expect(dpram.get_output(:q_a)).to eq(0x11)

      # Read address 0x01
      dpram.set_input(:address_a, 0x01)
      clock_cycle_a(dpram)
      expect(dpram.get_output(:q_a)).to eq(0x22)

      # Read address 0x02
      dpram.set_input(:address_a, 0x02)
      clock_cycle_a(dpram)
      expect(dpram.get_output(:q_a)).to eq(0x33)
    end

    it 'does not write when wren_a is 0' do
      dpram.write_mem(0x300, 0x55)

      dpram.set_input(:address_a, 0x300)
      dpram.set_input(:data_a, 0xFF)
      dpram.set_input(:wren_a, 0)
      clock_cycle_a(dpram)

      expect(dpram.read_mem(0x300)).to eq(0x55)
    end
  end

  # ==========================================================================
  # Port B Operations
  # ==========================================================================
  describe 'Port B Operations' do
    let(:dpram) { GameBoy::DPRAM.new('dpram_b') }

    it 'writes data via Port B' do
      dpram.set_input(:address_b, 0x400)
      dpram.set_input(:data_b, 0xEF)
      dpram.set_input(:wren_b, 1)
      dpram.set_input(:wren_a, 0)
      clock_cycle_b(dpram)

      expect(dpram.read_mem(0x400)).to eq(0xEF)
    end

    it 'reads data via Port B after write' do
      # Write data
      dpram.set_input(:address_b, 0x500)
      dpram.set_input(:data_b, 0x77)
      dpram.set_input(:wren_b, 1)
      clock_cycle_b(dpram)

      # Read back
      dpram.set_input(:wren_b, 0)
      dpram.set_input(:address_b, 0x500)
      clock_cycle_b(dpram)

      expect(dpram.get_output(:q_b)).to eq(0x77)
    end

    it 'does not write when wren_b is 0' do
      dpram.write_mem(0x600, 0xAA)

      dpram.set_input(:address_b, 0x600)
      dpram.set_input(:data_b, 0x00)
      dpram.set_input(:wren_b, 0)
      clock_cycle_b(dpram)

      expect(dpram.read_mem(0x600)).to eq(0xAA)
    end
  end

  # ==========================================================================
  # Dual-Port Operations (Simultaneous Access)
  # ==========================================================================
  describe 'Dual-Port Operations' do
    let(:dpram) { GameBoy::DPRAM.new('dpram_dual') }

    it 'allows simultaneous read from both ports at different addresses' do
      # Pre-write data using direct memory access
      dpram.write_mem(0x100, 0x11)
      dpram.write_mem(0x200, 0x22)

      # Read from both ports simultaneously
      dpram.set_input(:wren_a, 0)
      dpram.set_input(:wren_b, 0)
      dpram.set_input(:address_a, 0x100)
      dpram.set_input(:address_b, 0x200)
      clock_cycle_both(dpram)

      expect(dpram.get_output(:q_a)).to eq(0x11)
      expect(dpram.get_output(:q_b)).to eq(0x22)
    end

    it 'allows Port B to read what Port A wrote' do
      # Write via Port A
      dpram.set_input(:address_a, 0x300)
      dpram.set_input(:data_a, 0xBB)
      dpram.set_input(:wren_a, 1)
      dpram.set_input(:wren_b, 0)
      clock_cycle_a(dpram)

      # Read via Port B
      dpram.set_input(:wren_a, 0)
      dpram.set_input(:address_b, 0x300)
      clock_cycle_b(dpram)

      expect(dpram.get_output(:q_b)).to eq(0xBB)
    end

    it 'allows Port A to read what Port B wrote' do
      # Write via Port B
      dpram.set_input(:address_b, 0x400)
      dpram.set_input(:data_b, 0xCC)
      dpram.set_input(:wren_b, 1)
      dpram.set_input(:wren_a, 0)
      clock_cycle_b(dpram)

      # Read via Port A
      dpram.set_input(:wren_b, 0)
      dpram.set_input(:address_a, 0x400)
      clock_cycle_a(dpram)

      expect(dpram.get_output(:q_a)).to eq(0xCC)
    end

    it 'allows simultaneous write to different addresses' do
      dpram.set_input(:address_a, 0x500)
      dpram.set_input(:data_a, 0x55)
      dpram.set_input(:wren_a, 1)
      dpram.set_input(:address_b, 0x600)
      dpram.set_input(:data_b, 0x66)
      dpram.set_input(:wren_b, 1)
      clock_cycle_both(dpram)

      expect(dpram.read_mem(0x500)).to eq(0x55)
      expect(dpram.read_mem(0x600)).to eq(0x66)
    end
  end

  # ==========================================================================
  # Direct Memory Access
  # ==========================================================================
  describe 'Direct Memory Access' do
    let(:dpram) { GameBoy::DPRAM.new('dpram_direct') }

    it 'supports direct read via read_mem' do
      dpram.write_mem(0x50, 0x12)
      expect(dpram.read_mem(0x50)).to eq(0x12)
    end

    it 'supports direct write via write_mem' do
      dpram.write_mem(0x60, 0x34)
      expect(dpram.read_mem(0x60)).to eq(0x34)
    end

    it 'provides access to memory array' do
      dpram.write_mem(0x70, 0xAA)
      dpram.write_mem(0x71, 0xBB)

      mem = dpram.memory_array
      expect(mem).to be_a(Array)
      expect(mem[0x70]).to eq(0xAA)
      expect(mem[0x71]).to eq(0xBB)
    end

    it 'wraps address to valid range' do
      # 13-bit address = 8192 entries, so address wraps at 0x2000
      dpram.write_mem(0x0000, 0x11)
      # Reading 0x2000 should wrap to 0x0000
      expect(dpram.read_mem(0x2000)).to eq(0x11)
    end
  end

  # ==========================================================================
  # Boundary Conditions
  # ==========================================================================
  describe 'Boundary Conditions' do
    let(:dpram) { GameBoy::DPRAM.new('dpram_boundary') }

    it 'handles address 0' do
      dpram.set_input(:address_a, 0x000)
      dpram.set_input(:data_a, 0x01)
      dpram.set_input(:wren_a, 1)
      clock_cycle_a(dpram)

      expect(dpram.read_mem(0x000)).to eq(0x01)
    end

    it 'handles maximum address (0x1FFF for 8KB)' do
      max_addr = 0x1FFF

      dpram.set_input(:address_a, max_addr)
      dpram.set_input(:data_a, 0xFF)
      dpram.set_input(:wren_a, 1)
      clock_cycle_a(dpram)

      expect(dpram.read_mem(max_addr)).to eq(0xFF)
    end

    it 'handles data value 0x00' do
      dpram.write_mem(0x100, 0xFF)

      dpram.set_input(:address_a, 0x100)
      dpram.set_input(:data_a, 0x00)
      dpram.set_input(:wren_a, 1)
      clock_cycle_a(dpram)

      expect(dpram.read_mem(0x100)).to eq(0x00)
    end

    it 'handles data value 0xFF' do
      dpram.set_input(:address_a, 0x110)
      dpram.set_input(:data_a, 0xFF)
      dpram.set_input(:wren_a, 1)
      clock_cycle_a(dpram)

      expect(dpram.read_mem(0x110)).to eq(0xFF)
    end
  end

  # ==========================================================================
  # Configuration Tests
  # ==========================================================================
  describe 'Configuration' do
    it 'supports custom address width' do
      # Create DPRAM with 10-bit address (1KB)
      dpram = GameBoy::DPRAM.new('small_dpram', addr_width: 10)
      expect(dpram).to be_a(GameBoy::DPRAM)

      # Should work for addresses up to 1023
      dpram.write_mem(1023, 0x42)
      expect(dpram.read_mem(1023)).to eq(0x42)
    end
  end
end
