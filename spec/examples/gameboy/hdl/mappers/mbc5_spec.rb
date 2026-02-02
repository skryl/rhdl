# frozen_string_literal: true

require 'spec_helper'

# MBC5 Memory Bank Controller Tests
# Tests bank switching, RAM enable, and rumble motor support

RSpec.describe 'GameBoy::MBC5' do
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

  let(:mbc5) { GameBoy::MBC5.new('mbc5') }

  before do
    # Initialize with default values
    mbc5.set_input(:clk, 0)
    mbc5.set_input(:ce, 1)
    mbc5.set_input(:reset, 0)
    mbc5.set_input(:cpu_addr, 0)
    mbc5.set_input(:cpu_di, 0)
    mbc5.set_input(:cpu_wr, 0)
    mbc5.set_input(:rom_mask, 0x1FF)  # 512 banks (8MB)
    mbc5.set_input(:ram_mask, 0x0F)  # 16 RAM banks (128KB)
    mbc5.set_input(:has_ram, 1)
    mbc5.set_input(:cart_mbc_type, 0x19)  # MBC5

    # Apply reset
    mbc5.set_input(:reset, 1)
    clock_cycle(mbc5)
    mbc5.set_input(:reset, 0)
    clock_cycle(mbc5)
  end

  describe 'Component Definition' do
    it 'is a SequentialComponent' do
      expect(GameBoy::MBC5.ancestors).to include(RHDL::HDL::SequentialComponent)
    end

    it 'has the expected inputs' do
      input_names = GameBoy::MBC5._port_defs.select { |p| p[:direction] == :in }.map { |p| p[:name] }
      expect(input_names).to include(:clk, :ce, :reset)
      expect(input_names).to include(:cpu_addr, :cpu_di, :cpu_wr)
      expect(input_names).to include(:rom_mask, :ram_mask, :has_ram)
      expect(input_names).to include(:cart_mbc_type)
    end

    it 'has the expected outputs' do
      output_names = GameBoy::MBC5._port_defs.select { |p| p[:direction] == :out }.map { |p| p[:name] }
      expect(output_names).to include(:rom_bank, :ram_bank)
      expect(output_names).to include(:ram_enable, :has_battery)
      expect(output_names).to include(:rumbling)
    end
  end

  describe 'Reset Behavior' do
    it 'sets ROM bank to 1 after reset' do
      expect(mbc5.get_output(:rom_bank)).to eq(1)
    end

    it 'sets RAM bank to 0 after reset' do
      expect(mbc5.get_output(:ram_bank)).to eq(0)
    end

    it 'disables RAM after reset' do
      expect(mbc5.get_output(:ram_enable)).to eq(0)
    end

    it 'disables rumble after reset' do
      expect(mbc5.get_output(:rumbling)).to eq(0)
    end
  end

  describe 'RAM Enable Register (0x0000-0x1FFF)' do
    it 'enables RAM when 0x0A is written' do
      write_register(mbc5, 0x0000, 0x0A)
      expect(mbc5.get_output(:ram_enable)).to eq(1)
    end

    it 'disables RAM when other values are written' do
      write_register(mbc5, 0x0000, 0x0A)  # Enable first
      expect(mbc5.get_output(:ram_enable)).to eq(1)

      write_register(mbc5, 0x0000, 0x00)
      expect(mbc5.get_output(:ram_enable)).to eq(0)
    end

    it 'requires exact 0x0A match (unlike MBC1/MBC2/MBC3)' do
      # MBC5 checks the full byte, not just low nibble
      write_register(mbc5, 0x0000, 0xFA)  # Low nibble is 0xA
      expect(mbc5.get_output(:ram_enable)).to eq(0)  # Not enabled!
    end

    it 'responds to any address in 0x0000-0x1FFF range' do
      write_register(mbc5, 0x1FFF, 0x0A)
      expect(mbc5.get_output(:ram_enable)).to eq(1)
    end
  end

  describe 'ROM Bank Low Register (0x2000-0x2FFF)' do
    it 'sets lower 8 bits of ROM bank' do
      write_register(mbc5, 0x2000, 0xAB)
      expect(mbc5.get_output(:rom_bank) & 0xFF).to eq(0xAB)
    end

    it 'does NOT map bank 0 to bank 1 (unlike MBC1/MBC2/MBC3)' do
      write_register(mbc5, 0x2000, 0x00)
      expect(mbc5.get_output(:rom_bank)).to eq(0)  # Actually 0, not 1!
    end

    it 'preserves upper bit when writing' do
      # First set upper bit
      write_register(mbc5, 0x3000, 0x01)
      # Then set lower bits
      write_register(mbc5, 0x2000, 0x80)
      expect(mbc5.get_output(:rom_bank)).to eq(0x180)  # Upper + lower
    end

    it 'responds to any address in 0x2000-0x2FFF range' do
      write_register(mbc5, 0x2FFF, 0x55)
      expect(mbc5.get_output(:rom_bank) & 0xFF).to eq(0x55)
    end
  end

  describe 'ROM Bank High Register (0x3000-0x3FFF)' do
    it 'sets bit 8 (9th bit) of ROM bank' do
      write_register(mbc5, 0x3000, 0x01)
      expect(mbc5.get_output(:rom_bank) & 0x100).to eq(0x100)
    end

    it 'only uses bit 0' do
      write_register(mbc5, 0x3000, 0xFF)  # Only bit 0 matters
      expect(mbc5.get_output(:rom_bank) & 0x100).to eq(0x100)
    end

    it 'preserves lower 8 bits when writing' do
      # First set lower bits
      write_register(mbc5, 0x2000, 0xCD)
      # Then set upper bit
      write_register(mbc5, 0x3000, 0x01)
      expect(mbc5.get_output(:rom_bank)).to eq(0x1CD)  # Upper + lower
    end

    it 'responds to any address in 0x3000-0x3FFF range' do
      write_register(mbc5, 0x3FFF, 0x01)
      expect(mbc5.get_output(:rom_bank) & 0x100).to eq(0x100)
    end
  end

  describe 'Full 9-bit ROM Bank Selection' do
    it 'can access all 512 banks' do
      # Test a few representative banks
      test_banks = [0, 1, 0xFF, 0x100, 0x1FF]

      test_banks.each do |bank|
        low = bank & 0xFF
        high = (bank >> 8) & 0x01

        write_register(mbc5, 0x2000, low)
        write_register(mbc5, 0x3000, high)
        expect(mbc5.get_output(:rom_bank)).to eq(bank),
          "Bank #{bank}: expected #{bank}, got #{mbc5.get_output(:rom_bank)}"
      end
    end

    it 'applies ROM mask' do
      mbc5.set_input(:rom_mask, 0x7F)  # 128 banks (2MB)
      write_register(mbc5, 0x2000, 0xFF)
      write_register(mbc5, 0x3000, 0x01)
      expect(mbc5.get_output(:rom_bank)).to eq(0x7F)  # Masked to 128 banks
    end
  end

  describe 'RAM Bank Register (0x4000-0x5FFF)' do
    it 'sets RAM bank to lower 4 bits' do
      write_register(mbc5, 0x4000, 0x05)
      expect(mbc5.get_output(:ram_bank)).to eq(0x05)
    end

    it 'can select all 16 RAM banks' do
      (0..0x0F).each do |bank|
        write_register(mbc5, 0x4000, bank)
        expect(mbc5.get_output(:ram_bank)).to eq(bank),
          "Bank #{bank}: expected #{bank}, got #{mbc5.get_output(:ram_bank)}"
      end
    end

    it 'applies RAM mask' do
      mbc5.set_input(:ram_mask, 0x03)  # 4 banks (32KB)
      write_register(mbc5, 0x4000, 0x0F)
      expect(mbc5.get_output(:ram_bank)).to eq(0x03)  # Masked
    end

    it 'responds to any address in 0x4000-0x5FFF range' do
      write_register(mbc5, 0x5FFF, 0x07)
      expect(mbc5.get_output(:ram_bank)).to eq(0x07)
    end
  end

  describe 'Rumble Motor Support' do
    it 'activates rumble when bit 3 of RAM bank register is set' do
      write_register(mbc5, 0x4000, 0x08)  # Bit 3 = rumble
      expect(mbc5.get_output(:rumbling)).to eq(1)
    end

    it 'deactivates rumble when bit 3 is cleared' do
      write_register(mbc5, 0x4000, 0x08)  # Enable rumble
      expect(mbc5.get_output(:rumbling)).to eq(1)

      write_register(mbc5, 0x4000, 0x00)  # Disable rumble
      expect(mbc5.get_output(:rumbling)).to eq(0)
    end

    it 'allows simultaneous RAM bank selection and rumble' do
      write_register(mbc5, 0x4000, 0x0B)  # Bank 3 + rumble
      expect(mbc5.get_output(:ram_bank)).to eq(0x0B)  # Full value
      expect(mbc5.get_output(:rumbling)).to eq(1)
    end

    it 'rumble uses bit 3 regardless of RAM mask' do
      mbc5.set_input(:ram_mask, 0x07)  # 8 banks - mask doesn't include bit 3
      write_register(mbc5, 0x4000, 0x0D)
      expect(mbc5.get_output(:rumbling)).to eq(1)
    end
  end

  describe 'Battery Detection' do
    it 'reports no battery for type 0x19 (MBC5)' do
      mbc5.set_input(:cart_mbc_type, 0x19)
      mbc5.propagate
      expect(mbc5.get_output(:has_battery)).to eq(0)
    end

    it 'reports no battery for type 0x1A (MBC5+RAM)' do
      mbc5.set_input(:cart_mbc_type, 0x1A)
      mbc5.propagate
      expect(mbc5.get_output(:has_battery)).to eq(0)
    end

    it 'reports battery for type 0x1B (MBC5+RAM+BATTERY)' do
      mbc5.set_input(:cart_mbc_type, 0x1B)
      mbc5.propagate
      expect(mbc5.get_output(:has_battery)).to eq(1)
    end

    it 'reports no battery for type 0x1C (MBC5+RUMBLE)' do
      mbc5.set_input(:cart_mbc_type, 0x1C)
      mbc5.propagate
      expect(mbc5.get_output(:has_battery)).to eq(0)
    end

    it 'reports no battery for type 0x1D (MBC5+RUMBLE+RAM)' do
      mbc5.set_input(:cart_mbc_type, 0x1D)
      mbc5.propagate
      expect(mbc5.get_output(:has_battery)).to eq(0)
    end

    it 'reports battery for type 0x1E (MBC5+RUMBLE+RAM+BATTERY)' do
      mbc5.set_input(:cart_mbc_type, 0x1E)
      mbc5.propagate
      expect(mbc5.get_output(:has_battery)).to eq(1)
    end
  end

  describe 'CE (Chip Enable) Signal' do
    it 'ignores writes when CE is low' do
      initial_bank = mbc5.get_output(:rom_bank)

      mbc5.set_input(:ce, 0)
      write_register(mbc5, 0x2000, 0x10)

      expect(mbc5.get_output(:rom_bank)).to eq(initial_bank)
    end

    it 'responds to writes when CE is high' do
      mbc5.set_input(:ce, 1)
      write_register(mbc5, 0x2000, 0x10)

      expect(mbc5.get_output(:rom_bank)).to eq(0x10)
    end
  end

  describe 'has_ram Input' do
    it 'disables RAM when has_ram is 0' do
      mbc5.set_input(:has_ram, 0)
      write_register(mbc5, 0x0000, 0x0A)
      expect(mbc5.get_output(:ram_enable)).to eq(0)
    end

    it 'allows RAM enable when has_ram is 1' do
      mbc5.set_input(:has_ram, 1)
      write_register(mbc5, 0x0000, 0x0A)
      expect(mbc5.get_output(:ram_enable)).to eq(1)
    end
  end

  describe 'Large ROM Support (8MB)' do
    before do
      mbc5.set_input(:rom_mask, 0x1FF)  # 512 banks
    end

    it 'can access banks in high range (256-511)' do
      # Set to bank 300
      write_register(mbc5, 0x2000, 0x2C)  # Low byte: 0x2C = 44
      write_register(mbc5, 0x3000, 0x01)  # High bit: 1
      expect(mbc5.get_output(:rom_bank)).to eq(0x12C)  # 300
    end

    it 'can access last bank (511)' do
      write_register(mbc5, 0x2000, 0xFF)
      write_register(mbc5, 0x3000, 0x01)
      expect(mbc5.get_output(:rom_bank)).to eq(0x1FF)  # 511
    end
  end

  describe 'Large RAM Support (128KB)' do
    before do
      mbc5.set_input(:ram_mask, 0x0F)  # 16 banks
    end

    it 'can access all 16 RAM banks' do
      (0..15).each do |bank|
        write_register(mbc5, 0x4000, bank)
        expect(mbc5.get_output(:ram_bank)).to eq(bank)
      end
    end
  end

  describe 'Differences from Other MBCs' do
    it 'allows bank 0 selection (unlike MBC1/MBC2/MBC3)' do
      write_register(mbc5, 0x2000, 0x00)
      write_register(mbc5, 0x3000, 0x00)
      expect(mbc5.get_output(:rom_bank)).to eq(0)  # Bank 0, not remapped to 1
    end

    it 'requires exact 0x0A for RAM enable (unlike MBC1/MBC2/MBC3)' do
      write_register(mbc5, 0x0000, 0x1A)  # Would enable on other MBCs
      expect(mbc5.get_output(:ram_enable)).to eq(0)  # Not enabled on MBC5
    end

    it 'has no banking mode register' do
      # MBC5 doesn't have the mode switching of MBC1
      # All ROM banks are directly selectable via 9-bit register
    end
  end

  describe 'Typical Usage Pattern' do
    it 'follows standard game initialization sequence' do
      # Step 1: Enable RAM
      write_register(mbc5, 0x0000, 0x0A)
      expect(mbc5.get_output(:ram_enable)).to eq(1)

      # Step 2: Select ROM bank 50
      write_register(mbc5, 0x2000, 0x32)  # Low byte
      write_register(mbc5, 0x3000, 0x00)  # High byte
      expect(mbc5.get_output(:rom_bank)).to eq(0x32)

      # Step 3: Select ROM bank 300 (> 256)
      write_register(mbc5, 0x2000, 0x2C)
      write_register(mbc5, 0x3000, 0x01)
      expect(mbc5.get_output(:rom_bank)).to eq(0x12C)

      # Step 4: Select RAM bank 5
      write_register(mbc5, 0x4000, 0x05)
      expect(mbc5.get_output(:ram_bank)).to eq(0x05)

      # Step 5: Enable rumble
      write_register(mbc5, 0x4000, 0x0D)  # Bank 5 + rumble
      expect(mbc5.get_output(:rumbling)).to eq(1)

      # Step 6: Disable RAM when done
      write_register(mbc5, 0x0000, 0x00)
      expect(mbc5.get_output(:ram_enable)).to eq(0)
    end
  end

  describe 'ROM Bank Edge Cases' do
    it 'correctly handles boundary between low and high bytes' do
      # Test transition from bank 255 to 256
      write_register(mbc5, 0x2000, 0xFF)
      write_register(mbc5, 0x3000, 0x00)
      expect(mbc5.get_output(:rom_bank)).to eq(0xFF)

      write_register(mbc5, 0x2000, 0x00)
      write_register(mbc5, 0x3000, 0x01)
      expect(mbc5.get_output(:rom_bank)).to eq(0x100)
    end

    it 'handles sequential bank increments across boundary' do
      (0xFD..0x102).each do |bank|
        low = bank & 0xFF
        high = (bank >> 8) & 0x01

        write_register(mbc5, 0x2000, low)
        write_register(mbc5, 0x3000, high)
        expect(mbc5.get_output(:rom_bank)).to eq(bank),
          "Bank #{bank}: expected #{bank}, got #{mbc5.get_output(:rom_bank)}"
      end
    end
  end
end
