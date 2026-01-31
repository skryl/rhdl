# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/gameboy/gameboy'

RSpec.describe 'GameBoy RHDL Implementation' do
  describe 'Module Loading' do
    it 'loads the GameBoy module' do
      expect(defined?(GameBoy)).to eq('constant')
    end

    it 'has version information' do
      expect(GameBoy::VERSION).to eq('0.1.0')
    end
  end

  describe 'CPU Components' do
    it 'defines SM83 CPU' do
      expect(defined?(GameBoy::SM83)).to eq('constant')
    end

    it 'defines SM83_ALU' do
      expect(defined?(GameBoy::SM83_ALU)).to eq('constant')
    end

    it 'defines SM83_Registers' do
      expect(defined?(GameBoy::SM83_Registers)).to eq('constant')
    end

    it 'defines SM83_MCode' do
      expect(defined?(GameBoy::SM83_MCode)).to eq('constant')
    end
  end

  describe 'PPU Components' do
    it 'defines Video' do
      expect(defined?(GameBoy::Video)).to eq('constant')
    end

    it 'defines Sprites' do
      expect(defined?(GameBoy::Sprites)).to eq('constant')
    end

    it 'defines LCD' do
      expect(defined?(GameBoy::LCD)).to eq('constant')
    end
  end

  describe 'APU Components' do
    it 'defines Sound' do
      expect(defined?(GameBoy::Sound)).to eq('constant')
    end

    it 'defines ChannelSquare' do
      expect(defined?(GameBoy::ChannelSquare)).to eq('constant')
    end

    it 'defines ChannelWave' do
      expect(defined?(GameBoy::ChannelWave)).to eq('constant')
    end

    it 'defines ChannelNoise' do
      expect(defined?(GameBoy::ChannelNoise)).to eq('constant')
    end
  end

  describe 'Memory Components' do
    it 'defines DPRAM' do
      expect(defined?(GameBoy::DPRAM)).to eq('constant')
    end

    it 'defines SPRAM' do
      expect(defined?(GameBoy::SPRAM)).to eq('constant')
    end

    it 'defines HDMA' do
      expect(defined?(GameBoy::HDMA)).to eq('constant')
    end
  end

  describe 'Mapper Components' do
    it 'defines MBC1' do
      expect(defined?(GameBoy::MBC1)).to eq('constant')
    end

    it 'defines MBC2' do
      expect(defined?(GameBoy::MBC2)).to eq('constant')
    end

    it 'defines MBC3' do
      expect(defined?(GameBoy::MBC3)).to eq('constant')
    end

    it 'defines MBC5' do
      expect(defined?(GameBoy::MBC5)).to eq('constant')
    end

    it 'defines mapper type constants' do
      expect(GameBoy::Mappers::ROM_ONLY).to eq(0x00)
      expect(GameBoy::Mappers::MBC1).to eq(0x01)
      expect(GameBoy::Mappers::MBC2).to eq(0x05)
      expect(GameBoy::Mappers::MBC3).to eq(0x11)
      expect(GameBoy::Mappers::MBC5).to eq(0x19)
    end

    it 'defines ROM size constants' do
      expect(GameBoy::Mappers::ROM_SIZES[0x00]).to eq(32 * 1024)
      expect(GameBoy::Mappers::ROM_SIZES[0x05]).to eq(1024 * 1024)
    end

    it 'defines RAM size constants' do
      expect(GameBoy::Mappers::RAM_SIZES[0x00]).to eq(0)
      expect(GameBoy::Mappers::RAM_SIZES[0x03]).to eq(32 * 1024)
    end
  end

  describe 'Other Components' do
    it 'defines Timer' do
      expect(defined?(GameBoy::Timer)).to eq('constant')
    end

    it 'defines Link' do
      expect(defined?(GameBoy::Link)).to eq('constant')
    end

    it 'defines GB (top-level)' do
      expect(defined?(GameBoy::GB)).to eq('constant')
    end
  end
end
