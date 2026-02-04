# frozen_string_literal: true

require 'spec_helper'

# MBC2 Memory Bank Controller Tests
# Tests bank switching, RAM enable, and 4-bit RAM addressing

RSpec.describe 'RHDL::Examples::GameBoy::MBC2' do
  before(:all) do
    require_relative '../../../../../examples/gameboy/gameboy'
  end

  # Helper to clock the component
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  # Helper to write to a mapper register
  def write_register(component, addr, data)
    component.set_input(:cpu_addr, addr)
    component.set_input(:cpu_di, data)
    component.set_input(:cpu_wr, 1)
    clock_cycle(component)
    component.set_input(:cpu_wr, 0)
  end

  let(:mbc2) { RHDL::Examples::GameBoy::MBC2.new('mbc2') }

  before do
    # Initialize with default values
    mbc2.set_input(:clk, 0)
    mbc2.set_input(:ce, 1)
    mbc2.set_input(:reset, 0)
    mbc2.set_input(:cpu_addr, 0)
    mbc2.set_input(:cpu_di, 0)
    mbc2.set_input(:cpu_wr, 0)
    mbc2.set_input(:rom_mask, 0x0F)  # 16 banks max (256KB)
    mbc2.set_input(:cart_mbc_type, 0x05)  # MBC2 without battery

    # Apply reset
    mbc2.set_input(:reset, 1)
    clock_cycle(mbc2)
    mbc2.set_input(:reset, 0)
    clock_cycle(mbc2)
  end

  describe 'Component Definition' do
    it 'is a SequentialComponent' do
      expect(RHDL::Examples::GameBoy::MBC2.ancestors).to include(RHDL::HDL::SequentialComponent)
    end

    it 'has the expected inputs' do
      input_names = RHDL::Examples::GameBoy::MBC2._port_defs.select { |p| p[:direction] == :in }.map { |p| p[:name] }
      expect(input_names).to include(:clk, :ce, :reset)
      expect(input_names).to include(:cpu_addr, :cpu_di, :cpu_wr)
      expect(input_names).to include(:rom_mask, :cart_mbc_type)
    end

    it 'has the expected outputs' do
      output_names = RHDL::Examples::GameBoy::MBC2._port_defs.select { |p| p[:direction] == :out }.map { |p| p[:name] }
      expect(output_names).to include(:rom_bank)
      expect(output_names).to include(:ram_addr, :ram_enable)
      expect(output_names).to include(:has_battery)
    end
  end

  describe 'Reset Behavior' do
    it 'sets ROM bank to 1 after reset' do
      expect(mbc2.get_output(:rom_bank)).to eq(1)
    end

    it 'disables RAM after reset' do
      expect(mbc2.get_output(:ram_enable)).to eq(0)
    end
  end

  describe 'RAM Enable Register (0x0000-0x1FFF with A8=0)' do
    # MBC2 uses address bit 8 to distinguish between RAM enable and ROM bank

    it 'enables RAM when 0x0A is written to address with A8=0' do
      # A8=0 means bit 8 of address is 0 (e.g., 0x0000, 0x0100 is NOT valid)
      write_register(mbc2, 0x0000, 0x0A)
      expect(mbc2.get_output(:ram_enable)).to eq(1)
    end

    it 'disables RAM when other values are written with A8=0' do
      write_register(mbc2, 0x0000, 0x0A)  # Enable first
      expect(mbc2.get_output(:ram_enable)).to eq(1)

      write_register(mbc2, 0x0000, 0x00)
      expect(mbc2.get_output(:ram_enable)).to eq(0)
    end

    it 'ignores writes with A8=1 for RAM enable' do
      # A8=1 (e.g., 0x0100) should be ROM bank, not RAM enable
      write_register(mbc2, 0x0100, 0x0A)
      expect(mbc2.get_output(:ram_enable)).to eq(0)  # Not affected
    end

    it 'only checks low 4 bits for 0x0A' do
      write_register(mbc2, 0x0000, 0xFA)  # Low nibble is 0xA
      expect(mbc2.get_output(:ram_enable)).to eq(1)
    end

    it 'responds to addresses throughout 0x0000-0x1FFF with A8=0' do
      # 0x1E00 has A8=0 (bit 8 = 0): 0001 1110 0000 0000
      write_register(mbc2, 0x1E00, 0x0A)  # A8=0
      expect(mbc2.get_output(:ram_enable)).to eq(1)
    end
  end

  describe 'ROM Bank Register (0x2000-0x3FFF with A8=1)' do
    it 'sets ROM bank when A8=1' do
      write_register(mbc2, 0x2100, 0x05)  # A8=1
      expect(mbc2.get_output(:rom_bank)).to eq(5)
    end

    it 'maps bank 0 to bank 1 (quirk)' do
      write_register(mbc2, 0x2100, 0x00)
      expect(mbc2.get_output(:rom_bank)).to eq(1)
    end

    it 'only uses lower 4 bits' do
      write_register(mbc2, 0x2100, 0xFF)
      expect(mbc2.get_output(:rom_bank)).to eq(0x0F)
    end

    it 'ignores writes with A8=0' do
      initial_bank = mbc2.get_output(:rom_bank)
      write_register(mbc2, 0x2000, 0x05)  # A8=0
      expect(mbc2.get_output(:rom_bank)).to eq(initial_bank)
    end

    it 'applies ROM mask' do
      mbc2.set_input(:rom_mask, 0x07)  # 8 banks
      write_register(mbc2, 0x2100, 0x0F)
      expect(mbc2.get_output(:rom_bank)).to eq(0x07)  # Masked
    end

    it 'responds to addresses throughout 0x2000-0x3FFF with A8=1' do
      write_register(mbc2, 0x3F00, 0x0A)  # A8=1
      expect(mbc2.get_output(:rom_bank)).to eq(0x0A)
    end
  end

  describe 'Built-in RAM Addressing' do
    # MBC2 has 512x4-bit built-in RAM at 0xA000-0xA1FF

    it 'provides 9-bit RAM address from CPU address' do
      mbc2.set_input(:cpu_addr, 0xA123)
      mbc2.propagate
      expect(mbc2.get_output(:ram_addr)).to eq(0x123)
    end

    it 'masks RAM address to 9 bits (512 bytes)' do
      mbc2.set_input(:cpu_addr, 0xAFFF)  # Would be 0xFFF
      mbc2.propagate
      expect(mbc2.get_output(:ram_addr)).to eq(0x1FF)  # Masked to 9 bits
    end
  end

  describe 'Battery Detection' do
    it 'reports no battery for type 0x05 (MBC2)' do
      mbc2.set_input(:cart_mbc_type, 0x05)
      mbc2.propagate
      expect(mbc2.get_output(:has_battery)).to eq(0)
    end

    it 'reports battery for type 0x06 (MBC2+BATTERY)' do
      mbc2.set_input(:cart_mbc_type, 0x06)
      mbc2.propagate
      expect(mbc2.get_output(:has_battery)).to eq(1)
    end
  end

  describe 'Bank Selection Range' do
    it 'can select banks 1-15' do
      (1..0x0F).each do |bank|
        write_register(mbc2, 0x2100, bank)
        expect(mbc2.get_output(:rom_bank)).to eq(bank),
          "Bank #{bank}: expected #{bank}, got #{mbc2.get_output(:rom_bank)}"
      end
    end
  end

  describe 'CE (Chip Enable) Signal' do
    it 'ignores writes when CE is low' do
      initial_bank = mbc2.get_output(:rom_bank)

      mbc2.set_input(:ce, 0)
      write_register(mbc2, 0x2100, 0x0F)

      expect(mbc2.get_output(:rom_bank)).to eq(initial_bank)
    end

    it 'responds to writes when CE is high' do
      mbc2.set_input(:ce, 1)
      write_register(mbc2, 0x2100, 0x0F)

      expect(mbc2.get_output(:rom_bank)).to eq(0x0F)
    end
  end

  describe 'Address Bit 8 Selection' do
    # The unique MBC2 quirk: bit 8 of the address determines register

    it 'distinguishes RAM enable (A8=0) from ROM bank (A8=1)' do
      # Write to 0x0000 (A8=0) - RAM enable
      write_register(mbc2, 0x0000, 0x0A)
      expect(mbc2.get_output(:ram_enable)).to eq(1)
      expect(mbc2.get_output(:rom_bank)).to eq(1)  # Unchanged

      # Write to 0x0100 (A8=1) - ROM bank
      write_register(mbc2, 0x0100, 0x05)
      expect(mbc2.get_output(:rom_bank)).to eq(5)
      expect(mbc2.get_output(:ram_enable)).to eq(1)  # Unchanged
    end

    it 'pattern: even hundreds are RAM enable, odd hundreds are ROM bank' do
      # 0x0000, 0x0200, 0x0400, etc. (A8=0) -> RAM enable
      # 0x0100, 0x0300, 0x0500, etc. (A8=1) -> ROM bank (only in 0x0000-0x3FFF)

      # Reset for clean state
      mbc2.set_input(:reset, 1)
      clock_cycle(mbc2)
      mbc2.set_input(:reset, 0)
      clock_cycle(mbc2)

      # RAM enable at 0x0200 (A8=0)
      write_register(mbc2, 0x0200, 0x0A)
      expect(mbc2.get_output(:ram_enable)).to eq(1)

      # ROM bank at 0x0300 (A8=1) - but this is still in 0x0000-0x1FFF
      # Actually need to be in 0x2000-0x3FFF range
      write_register(mbc2, 0x2300, 0x07)  # A8=1 in ROM bank range
      expect(mbc2.get_output(:rom_bank)).to eq(7)
    end
  end

  describe 'Typical Usage Pattern' do
    it 'follows standard game initialization sequence' do
      # Step 1: Enable RAM
      write_register(mbc2, 0x0000, 0x0A)
      expect(mbc2.get_output(:ram_enable)).to eq(1)

      # Step 2: Select ROM bank 2
      write_register(mbc2, 0x2100, 0x02)
      expect(mbc2.get_output(:rom_bank)).to eq(2)

      # Step 3: Access RAM at 0xA000-0xA1FF
      mbc2.set_input(:cpu_addr, 0xA050)
      mbc2.propagate
      expect(mbc2.get_output(:ram_addr)).to eq(0x050)

      # Step 4: Switch to ROM bank 5
      write_register(mbc2, 0x2100, 0x05)
      expect(mbc2.get_output(:rom_bank)).to eq(5)

      # Step 5: Disable RAM when done
      write_register(mbc2, 0x0000, 0x00)
      expect(mbc2.get_output(:ram_enable)).to eq(0)
    end
  end
end
