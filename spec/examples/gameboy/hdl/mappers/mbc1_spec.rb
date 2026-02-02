# frozen_string_literal: true

require 'spec_helper'

# MBC1 Memory Bank Controller Tests
# Tests bank switching, RAM enable, and banking modes

RSpec.describe 'GameBoy::MBC1' do
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

  let(:mbc1) { GameBoy::MBC1.new('mbc1') }

  before do
    # Initialize with default values
    mbc1.set_input(:clk, 0)
    mbc1.set_input(:ce, 1)
    mbc1.set_input(:reset, 0)
    mbc1.set_input(:cpu_addr, 0)
    mbc1.set_input(:cpu_di, 0)
    mbc1.set_input(:cpu_wr, 0)
    mbc1.set_input(:rom_mask, 0x7F)  # 128 banks (2MB)
    mbc1.set_input(:ram_mask, 0x03)  # 4 RAM banks (32KB)

    # Apply reset
    mbc1.set_input(:reset, 1)
    clock_cycle(mbc1)
    mbc1.set_input(:reset, 0)
    clock_cycle(mbc1)
  end

  describe 'Component Definition' do
    it 'is a SequentialComponent' do
      expect(GameBoy::MBC1.ancestors).to include(RHDL::HDL::SequentialComponent)
    end

    it 'has the expected inputs' do
      input_names = GameBoy::MBC1._port_defs.select { |p| p[:direction] == :in }.map { |p| p[:name] }
      expect(input_names).to include(:clk, :ce, :reset)
      expect(input_names).to include(:cpu_addr, :cpu_di, :cpu_wr)
      expect(input_names).to include(:rom_mask, :ram_mask)
    end

    it 'has the expected outputs' do
      output_names = GameBoy::MBC1._port_defs.select { |p| p[:direction] == :out }.map { |p| p[:name] }
      expect(output_names).to include(:rom_bank, :rom_bank_0)
      expect(output_names).to include(:ram_bank, :ram_enable)
    end
  end

  describe 'Reset Behavior' do
    it 'sets ROM bank to 1 after reset' do
      expect(mbc1.get_output(:rom_bank)).to eq(1)
    end

    it 'sets ROM bank 0 to 0 after reset' do
      expect(mbc1.get_output(:rom_bank_0)).to eq(0)
    end

    it 'sets RAM bank to 0 after reset' do
      expect(mbc1.get_output(:ram_bank)).to eq(0)
    end

    it 'disables RAM after reset' do
      expect(mbc1.get_output(:ram_enable)).to eq(0)
    end
  end

  describe 'RAM Enable Register (0x0000-0x1FFF)' do
    it 'enables RAM when 0x0A is written' do
      write_register(mbc1, 0x0000, 0x0A)
      expect(mbc1.get_output(:ram_enable)).to eq(1)
    end

    it 'disables RAM when other values are written' do
      write_register(mbc1, 0x0000, 0x0A)  # Enable first
      expect(mbc1.get_output(:ram_enable)).to eq(1)

      write_register(mbc1, 0x0000, 0x00)
      expect(mbc1.get_output(:ram_enable)).to eq(0)
    end

    it 'only checks low 4 bits for 0x0A' do
      write_register(mbc1, 0x0000, 0xFA)  # Low nibble is 0xA
      expect(mbc1.get_output(:ram_enable)).to eq(1)
    end

    it 'responds to any address in 0x0000-0x1FFF range' do
      write_register(mbc1, 0x1FFF, 0x0A)
      expect(mbc1.get_output(:ram_enable)).to eq(1)

      write_register(mbc1, 0x1000, 0x00)
      expect(mbc1.get_output(:ram_enable)).to eq(0)
    end
  end

  describe 'ROM Bank Register (0x2000-0x3FFF)' do
    it 'sets ROM bank to written value' do
      write_register(mbc1, 0x2000, 0x10)
      expect(mbc1.get_output(:rom_bank)).to eq(0x10)
    end

    it 'maps bank 0 to bank 1 (quirk)' do
      write_register(mbc1, 0x2000, 0x00)
      expect(mbc1.get_output(:rom_bank)).to eq(1)
    end

    it 'only uses lower 5 bits' do
      write_register(mbc1, 0x2000, 0x1F)
      expect(mbc1.get_output(:rom_bank) & 0x1F).to eq(0x1F)
    end

    it 'applies ROM mask' do
      mbc1.set_input(:rom_mask, 0x0F)  # 16 banks
      write_register(mbc1, 0x2000, 0x1F)
      expect(mbc1.get_output(:rom_bank)).to eq(0x0F)  # Masked to 4 bits
    end

    it 'responds to any address in 0x2000-0x3FFF range' do
      write_register(mbc1, 0x3FFF, 0x05)
      expect(mbc1.get_output(:rom_bank)).to eq(0x05)
    end
  end

  describe 'RAM Bank / Upper ROM Bank Register (0x4000-0x5FFF)' do
    it 'sets upper ROM bank bits in mode 0' do
      # Set ROM bank lower bits first
      write_register(mbc1, 0x2000, 0x01)
      # Set upper 2 bits
      write_register(mbc1, 0x4000, 0x02)
      # In mode 0, upper bits should combine with lower bits for ROM bank
      expected_bank = (0x02 << 5) | 0x01  # 0x41
      expect(mbc1.get_output(:rom_bank)).to eq(expected_bank)
    end

    it 'has no effect on RAM bank in mode 0' do
      write_register(mbc1, 0x4000, 0x03)
      expect(mbc1.get_output(:ram_bank)).to eq(0)  # Mode 0, always bank 0
    end

    it 'applies RAM mask in mode 1' do
      # Switch to mode 1
      write_register(mbc1, 0x6000, 0x01)
      # Set RAM bank
      write_register(mbc1, 0x4000, 0x03)
      expect(mbc1.get_output(:ram_bank)).to eq(0x03)
    end

    it 'responds to any address in 0x4000-0x5FFF range' do
      write_register(mbc1, 0x6000, 0x01)  # Mode 1
      write_register(mbc1, 0x5FFF, 0x02)
      expect(mbc1.get_output(:ram_bank)).to eq(0x02)
    end
  end

  describe 'Banking Mode Register (0x6000-0x7FFF)' do
    it 'starts in mode 0 (ROM banking mode)' do
      expect(mbc1.get_output(:rom_bank_0)).to eq(0)  # Bank 0 area always 0
      expect(mbc1.get_output(:ram_bank)).to eq(0)    # RAM bank always 0
    end

    it 'switches to mode 1 (RAM banking mode)' do
      write_register(mbc1, 0x6000, 0x01)
      # Now upper bits affect RAM bank and ROM bank 0
      write_register(mbc1, 0x4000, 0x02)
      expect(mbc1.get_output(:ram_bank)).to eq(0x02)
    end

    it 'affects ROM bank 0 in mode 1' do
      # Set upper ROM bits
      write_register(mbc1, 0x4000, 0x02)
      # Switch to mode 1
      write_register(mbc1, 0x6000, 0x01)
      # ROM bank 0 should now be 0x40 (upper bits << 5)
      expect(mbc1.get_output(:rom_bank_0)).to eq(0x40)
    end

    it 'responds to any address in 0x6000-0x7FFF range' do
      write_register(mbc1, 0x7FFF, 0x01)
      write_register(mbc1, 0x4000, 0x01)
      expect(mbc1.get_output(:ram_bank)).to eq(0x01)
    end

    it 'only checks bit 0' do
      write_register(mbc1, 0x6000, 0xFF)  # Only bit 0 matters
      write_register(mbc1, 0x4000, 0x01)
      expect(mbc1.get_output(:ram_bank)).to eq(0x01)
    end
  end

  describe 'Bank 0 Mapping Quirks' do
    # MBC1 has a quirk where writing 0x00, 0x20, 0x40, or 0x60 to ROM bank
    # gets remapped to 0x01, 0x21, 0x41, or 0x61 respectively

    it 'maps bank 0x20 to 0x21' do
      write_register(mbc1, 0x4000, 0x01)  # Upper bits = 1
      write_register(mbc1, 0x2000, 0x00)  # Lower bits = 0
      # Should be 0x20 | 1 = 0x21 (because lower 5 bits are 0, maps to 1)
      expect(mbc1.get_output(:rom_bank)).to eq(0x21)
    end

    it 'maps bank 0x40 to 0x41' do
      write_register(mbc1, 0x4000, 0x02)  # Upper bits = 2
      write_register(mbc1, 0x2000, 0x00)  # Lower bits = 0
      expect(mbc1.get_output(:rom_bank)).to eq(0x41)
    end

    it 'maps bank 0x60 to 0x61' do
      write_register(mbc1, 0x4000, 0x03)  # Upper bits = 3
      write_register(mbc1, 0x2000, 0x00)  # Lower bits = 0
      expect(mbc1.get_output(:rom_bank)).to eq(0x61)
    end

    it 'does not map non-zero lower banks' do
      write_register(mbc1, 0x4000, 0x01)  # Upper bits = 1
      write_register(mbc1, 0x2000, 0x02)  # Lower bits = 2
      expect(mbc1.get_output(:rom_bank)).to eq(0x22)  # No remapping
    end
  end

  describe 'Large ROM Configuration (2MB / 128 banks)' do
    before do
      mbc1.set_input(:rom_mask, 0x7F)  # 128 banks
    end

    it 'can select all 128 banks' do
      (1..0x7F).each do |bank|
        low_bits = bank & 0x1F
        high_bits = (bank >> 5) & 0x03

        # Handle the bank 0 -> 1 quirk
        expected = bank
        if low_bits == 0
          expected = bank | 1
        end

        write_register(mbc1, 0x4000, high_bits)
        write_register(mbc1, 0x2000, low_bits)
        expect(mbc1.get_output(:rom_bank)).to eq(expected),
          "Bank #{bank}: expected #{expected}, got #{mbc1.get_output(:rom_bank)}"
      end
    end
  end

  describe 'Small ROM Configuration (512KB / 32 banks)' do
    before do
      mbc1.set_input(:rom_mask, 0x1F)  # 32 banks
    end

    it 'masks upper bits when accessing beyond ROM size' do
      write_register(mbc1, 0x4000, 0x03)  # Upper bits (would be 0x60)
      write_register(mbc1, 0x2000, 0x10)  # Lower bits
      # ROM mask should limit to 32 banks
      expect(mbc1.get_output(:rom_bank)).to be <= 0x1F
    end
  end

  describe 'CE (Chip Enable) Signal' do
    it 'ignores writes when CE is low' do
      initial_bank = mbc1.get_output(:rom_bank)

      mbc1.set_input(:ce, 0)
      write_register(mbc1, 0x2000, 0x10)

      expect(mbc1.get_output(:rom_bank)).to eq(initial_bank)
    end

    it 'responds to writes when CE is high' do
      mbc1.set_input(:ce, 1)
      write_register(mbc1, 0x2000, 0x10)

      expect(mbc1.get_output(:rom_bank)).to eq(0x10)
    end
  end

  describe 'Multi-Game Cartridge Support (Mode 1)' do
    # Some multi-game cartridges use mode 1 to select which 512KB segment
    # appears in the 0x0000-0x3FFF region

    it 'allows different games in mode 1 by setting upper bits' do
      # Switch to mode 1
      write_register(mbc1, 0x6000, 0x01)

      # Game 1 (upper bits = 0)
      write_register(mbc1, 0x4000, 0x00)
      expect(mbc1.get_output(:rom_bank_0)).to eq(0)

      # Game 2 (upper bits = 1, bank 0 = 0x20)
      write_register(mbc1, 0x4000, 0x01)
      expect(mbc1.get_output(:rom_bank_0)).to eq(0x20)

      # Game 3 (upper bits = 2, bank 0 = 0x40)
      write_register(mbc1, 0x4000, 0x02)
      expect(mbc1.get_output(:rom_bank_0)).to eq(0x40)

      # Game 4 (upper bits = 3, bank 0 = 0x60)
      write_register(mbc1, 0x4000, 0x03)
      expect(mbc1.get_output(:rom_bank_0)).to eq(0x60)
    end
  end
end
