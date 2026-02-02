# frozen_string_literal: true

require 'spec_helper'

# Base Mapper Constants and Types Tests
# Tests the mapper type constants defined in mappers.rb

RSpec.describe 'GameBoy::Mappers' do
  before(:all) do
    require_relative '../../../../../examples/gameboy/gameboy'
  end

  describe 'Module Loading' do
    it 'defines the Mappers module' do
      expect(defined?(GameBoy::Mappers)).to eq('constant')
    end
  end

  describe 'Mapper Type Constants' do
    describe 'ROM-only cartridge types' do
      it 'defines ROM_ONLY as 0x00' do
        expect(GameBoy::Mappers::ROM_ONLY).to eq(0x00)
      end

      it 'defines ROM_RAM as 0x08' do
        expect(GameBoy::Mappers::ROM_RAM).to eq(0x08)
      end

      it 'defines ROM_RAM_BATTERY as 0x09' do
        expect(GameBoy::Mappers::ROM_RAM_BATTERY).to eq(0x09)
      end
    end

    describe 'MBC1 cartridge types' do
      it 'defines MBC1 as 0x01' do
        expect(GameBoy::Mappers::MBC1).to eq(0x01)
      end

      it 'defines MBC1_RAM as 0x02' do
        expect(GameBoy::Mappers::MBC1_RAM).to eq(0x02)
      end

      it 'defines MBC1_RAM_BATTERY as 0x03' do
        expect(GameBoy::Mappers::MBC1_RAM_BATTERY).to eq(0x03)
      end
    end

    describe 'MBC2 cartridge types' do
      it 'defines MBC2 as 0x05' do
        expect(GameBoy::Mappers::MBC2).to eq(0x05)
      end

      it 'defines MBC2_BATTERY as 0x06' do
        expect(GameBoy::Mappers::MBC2_BATTERY).to eq(0x06)
      end
    end

    describe 'MBC3 cartridge types' do
      it 'defines MBC3_TIMER_BATTERY as 0x0F' do
        expect(GameBoy::Mappers::MBC3_TIMER_BATTERY).to eq(0x0F)
      end

      it 'defines MBC3_TIMER_RAM_BATTERY as 0x10' do
        expect(GameBoy::Mappers::MBC3_TIMER_RAM_BATTERY).to eq(0x10)
      end

      it 'defines MBC3 as 0x11' do
        expect(GameBoy::Mappers::MBC3).to eq(0x11)
      end

      it 'defines MBC3_RAM as 0x12' do
        expect(GameBoy::Mappers::MBC3_RAM).to eq(0x12)
      end

      it 'defines MBC3_RAM_BATTERY as 0x13' do
        expect(GameBoy::Mappers::MBC3_RAM_BATTERY).to eq(0x13)
      end
    end

    describe 'MBC5 cartridge types' do
      it 'defines MBC5 as 0x19' do
        expect(GameBoy::Mappers::MBC5).to eq(0x19)
      end

      it 'defines MBC5_RAM as 0x1A' do
        expect(GameBoy::Mappers::MBC5_RAM).to eq(0x1A)
      end

      it 'defines MBC5_RAM_BATTERY as 0x1B' do
        expect(GameBoy::Mappers::MBC5_RAM_BATTERY).to eq(0x1B)
      end

      it 'defines MBC5_RUMBLE as 0x1C' do
        expect(GameBoy::Mappers::MBC5_RUMBLE).to eq(0x1C)
      end

      it 'defines MBC5_RUMBLE_RAM as 0x1D' do
        expect(GameBoy::Mappers::MBC5_RUMBLE_RAM).to eq(0x1D)
      end

      it 'defines MBC5_RUMBLE_RAM_BATTERY as 0x1E' do
        expect(GameBoy::Mappers::MBC5_RUMBLE_RAM_BATTERY).to eq(0x1E)
      end
    end

    describe 'Other mapper types' do
      it 'defines MMM01 as 0x0B' do
        expect(GameBoy::Mappers::MMM01).to eq(0x0B)
      end

      it 'defines MBC6 as 0x20' do
        expect(GameBoy::Mappers::MBC6).to eq(0x20)
      end

      it 'defines POCKET_CAMERA as 0xFC' do
        expect(GameBoy::Mappers::POCKET_CAMERA).to eq(0xFC)
      end

      it 'defines HUC3 as 0xFE' do
        expect(GameBoy::Mappers::HUC3).to eq(0xFE)
      end

      it 'defines HUC1_RAM_BATTERY as 0xFF' do
        expect(GameBoy::Mappers::HUC1_RAM_BATTERY).to eq(0xFF)
      end
    end
  end

  describe 'ROM Size Constants' do
    it 'defines ROM size for code 0x00 as 32KB (no banking)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x00]).to eq(32 * 1024)
    end

    it 'defines ROM size for code 0x01 as 64KB (4 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x01]).to eq(64 * 1024)
    end

    it 'defines ROM size for code 0x02 as 128KB (8 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x02]).to eq(128 * 1024)
    end

    it 'defines ROM size for code 0x03 as 256KB (16 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x03]).to eq(256 * 1024)
    end

    it 'defines ROM size for code 0x04 as 512KB (32 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x04]).to eq(512 * 1024)
    end

    it 'defines ROM size for code 0x05 as 1MB (64 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x05]).to eq(1024 * 1024)
    end

    it 'defines ROM size for code 0x06 as 2MB (128 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x06]).to eq(2048 * 1024)
    end

    it 'defines ROM size for code 0x07 as 4MB (256 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x07]).to eq(4096 * 1024)
    end

    it 'defines ROM size for code 0x08 as 8MB (512 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x08]).to eq(8192 * 1024)
    end

    it 'defines special ROM size for code 0x52 as 1.1MB (72 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x52]).to eq(1152 * 1024)
    end

    it 'defines special ROM size for code 0x53 as 1.2MB (80 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x53]).to eq(1280 * 1024)
    end

    it 'defines special ROM size for code 0x54 as 1.5MB (96 banks)' do
      expect(GameBoy::Mappers::ROM_SIZES[0x54]).to eq(1536 * 1024)
    end
  end

  describe 'RAM Size Constants' do
    it 'defines RAM size for code 0x00 as 0 (none)' do
      expect(GameBoy::Mappers::RAM_SIZES[0x00]).to eq(0)
    end

    it 'defines RAM size for code 0x01 as 2KB (unused)' do
      expect(GameBoy::Mappers::RAM_SIZES[0x01]).to eq(2 * 1024)
    end

    it 'defines RAM size for code 0x02 as 8KB (1 bank)' do
      expect(GameBoy::Mappers::RAM_SIZES[0x02]).to eq(8 * 1024)
    end

    it 'defines RAM size for code 0x03 as 32KB (4 banks)' do
      expect(GameBoy::Mappers::RAM_SIZES[0x03]).to eq(32 * 1024)
    end

    it 'defines RAM size for code 0x04 as 128KB (16 banks)' do
      expect(GameBoy::Mappers::RAM_SIZES[0x04]).to eq(128 * 1024)
    end

    it 'defines RAM size for code 0x05 as 64KB (8 banks)' do
      expect(GameBoy::Mappers::RAM_SIZES[0x05]).to eq(64 * 1024)
    end
  end

  describe 'Mapper Component Definitions' do
    it 'defines MBC1 class' do
      expect(defined?(GameBoy::MBC1)).to eq('constant')
      expect(GameBoy::MBC1).to be_a(Class)
    end

    it 'defines MBC2 class' do
      expect(defined?(GameBoy::MBC2)).to eq('constant')
      expect(GameBoy::MBC2).to be_a(Class)
    end

    it 'defines MBC3 class' do
      expect(defined?(GameBoy::MBC3)).to eq('constant')
      expect(GameBoy::MBC3).to be_a(Class)
    end

    it 'defines MBC5 class' do
      expect(defined?(GameBoy::MBC5)).to eq('constant')
      expect(GameBoy::MBC5).to be_a(Class)
    end
  end
end
