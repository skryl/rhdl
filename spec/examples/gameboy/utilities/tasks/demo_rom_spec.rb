# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/gameboy/utilities/tasks/demo_rom'

RSpec.describe RHDL::GameBoy::Tasks::DemoRom do
  describe '#initialize' do
    it 'uses default title when not specified' do
      demo = described_class.new
      expect(demo.title).to eq("RHDL TEST")
    end

    it 'accepts custom title' do
      demo = described_class.new(title: "CUSTOM")
      expect(demo.title).to eq("CUSTOM")
    end
  end

  describe '#create' do
    let(:demo) { described_class.new }
    let(:rom) { demo.create }

    it 'returns a packed string' do
      expect(rom).to be_a(String)
      expect(rom.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'creates a 32KB ROM' do
      expect(rom.bytesize).to eq(32 * 1024)
    end

    it 'contains Nintendo logo at 0x104' do
      logo_bytes = rom.bytes[0x104, 48]
      expect(logo_bytes).to eq(described_class::NINTENDO_LOGO)
    end

    it 'contains title at 0x134' do
      title_bytes = rom.bytes[0x134, 9]
      expect(title_bytes.pack('C*')).to eq("RHDL TEST")
    end

    it 'has valid header checksum at 0x14D' do
      bytes = rom.bytes
      checksum = 0
      (0x134...0x14D).each { |i| checksum = (checksum - bytes[i] - 1) & 0xFF }
      expect(bytes[0x14D]).to eq(checksum)
    end

    it 'has entry point at 0x100 (NOP NOP JP)' do
      bytes = rom.bytes
      expect(bytes[0x100]).to eq(0x00)  # NOP
      expect(bytes[0x101]).to eq(0x00)  # NOP
      expect(bytes[0x102]).to eq(0xC3)  # JP
    end

    it 'has LCD enable code at 0x150' do
      bytes = rom.bytes
      expect(bytes[0x150]).to eq(0x3E)  # LD A, imm
      expect(bytes[0x151]).to eq(0x91)  # $91 (LCD on)
      expect(bytes[0x152]).to eq(0xE0)  # LDH (n), A
      expect(bytes[0x153]).to eq(0x40)  # LCDC register
    end

    it 'has infinite loop after LCD enable' do
      bytes = rom.bytes
      expect(bytes[0x154]).to eq(0x00)  # NOP
      expect(bytes[0x155]).to eq(0x18)  # JR
      # JR offset should jump back to NOP
    end
  end

  describe '#create_bytes' do
    let(:demo) { described_class.new }
    let(:rom_bytes) { demo.create_bytes }

    it 'returns an array' do
      expect(rom_bytes).to be_a(Array)
    end

    it 'creates a 32KB ROM' do
      expect(rom_bytes.length).to eq(32 * 1024)
    end

    it 'contains same data as #create' do
      expect(rom_bytes).to eq(demo.create.bytes)
    end
  end

  describe 'custom title' do
    let(:demo) { described_class.new(title: "MY GAME") }
    let(:rom) { demo.create }

    it 'includes custom title in ROM' do
      title_bytes = rom.bytes[0x134, 7]
      expect(title_bytes.pack('C*')).to eq("MY GAME")
    end

    it 'has valid checksum for custom title' do
      bytes = rom.bytes
      checksum = 0
      (0x134...0x14D).each { |i| checksum = (checksum - bytes[i] - 1) & 0xFF }
      expect(bytes[0x14D]).to eq(checksum)
    end
  end

  describe 'constants' do
    it 'defines NINTENDO_LOGO with 48 bytes' do
      expect(described_class::NINTENDO_LOGO.length).to eq(48)
    end

    it 'defines ROM_SIZE as 32KB' do
      expect(described_class::ROM_SIZE).to eq(32 * 1024)
    end

    it 'defines DEFAULT_TITLE' do
      expect(described_class::DEFAULT_TITLE).to eq("RHDL TEST")
    end
  end
end
