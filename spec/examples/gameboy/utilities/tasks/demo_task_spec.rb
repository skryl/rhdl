# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../../../examples/gameboy/utilities/tasks/demo_task'

RSpec.describe RHDL::Examples::GameBoy::Tasks::DemoTask do
  describe 'NINTENDO_LOGO constant' do
    it 'has 48 bytes' do
      expect(described_class::NINTENDO_LOGO.length).to eq(48)
    end

    it 'starts with expected bytes' do
      expect(described_class::NINTENDO_LOGO[0]).to eq(0xCE)
      expect(described_class::NINTENDO_LOGO[1]).to eq(0xED)
    end
  end

  describe '#create_demo_rom' do
    let(:task) { described_class.new }
    let(:rom) { task.create_demo_rom('TEST ROM') }
    let(:bytes) { rom.bytes }

    it 'returns a string' do
      expect(rom).to be_a(String)
    end

    it 'defaults to 32KB' do
      expect(rom.length).to eq(32 * 1024)
    end

    it 'supports custom size' do
      rom_64k = task.create_demo_rom('TEST', size_kb: 64)
      expect(rom_64k.length).to eq(64 * 1024)
    end

    it 'includes Nintendo logo at 0x104' do
      described_class::NINTENDO_LOGO.each_with_index do |expected_byte, i|
        expect(bytes[0x104 + i]).to eq(expected_byte)
      end
    end

    it 'includes title at 0x134' do
      title = bytes[0x134, 8].pack('C*')
      expect(title).to eq('TEST ROM')
    end

    it 'truncates long titles to 16 chars' do
      long_title = 'THIS IS A VERY LONG TITLE THAT EXCEEDS 16 CHARS'
      rom_long = task.create_demo_rom(long_title)
      title = rom_long.bytes[0x134, 16].pack('C*')
      expect(title.length).to eq(16)
      expect(title).to eq(long_title[0, 16])
    end

    it 'has valid header checksum' do
      checksum = 0
      (0x134...0x14D).each { |i| checksum = (checksum - bytes[i] - 1) & 0xFF }
      expect(bytes[0x14D]).to eq(checksum)
    end

    it 'has entry point at 0x100' do
      expect(bytes[0x100]).to eq(0x00)  # NOP
      expect(bytes[0x101]).to eq(0x00)  # NOP
      expect(bytes[0x102]).to eq(0xC3)  # JP
    end

    it 'has LCD enable code at 0x150' do
      expect(bytes[0x150]).to eq(0x3E)  # LD A, imm
      expect(bytes[0x151]).to eq(0x91)  # LCD enable value
      expect(bytes[0x152]).to eq(0xE0)  # LDH (n), A
      expect(bytes[0x153]).to eq(0x40)  # LCDC register
    end

    it 'has infinite loop after LCD enable' do
      expect(bytes[0x154]).to eq(0x00)  # NOP
      expect(bytes[0x155]).to eq(0x18)  # JR
    end
  end

  describe '#create_minimal_rom' do
    let(:task) { described_class.new }
    let(:rom) { task.create_minimal_rom }
    let(:bytes) { rom.bytes }

    it 'returns a string' do
      expect(rom).to be_a(String)
    end

    it 'is smaller than full demo ROM' do
      full_rom = task.create_demo_rom
      expect(rom.length).to be < full_rom.length
    end

    it 'has 512 bytes' do
      expect(rom.length).to eq(0x200)
    end

    it 'includes Nintendo logo' do
      described_class::NINTENDO_LOGO.each_with_index do |expected_byte, i|
        expect(bytes[0x104 + i]).to eq(expected_byte)
      end
    end

    it 'has TEST title' do
      title = bytes[0x134, 4].pack('C*')
      expect(title).to eq('TEST')
    end

    it 'has valid header checksum' do
      checksum = 0
      (0x134..0x14C).each { |i| checksum = (checksum - bytes[i] - 1) & 0xFF }
      expect(bytes[0x14D]).to eq(checksum)
    end

    it 'has infinite loop at 0x150' do
      expect(bytes[0x150]).to eq(0x00)  # NOP
      expect(bytes[0x151]).to eq(0x18)  # JR
      expect(bytes[0x152]).to eq(0xFE)  # -2 (jump back)
    end
  end

  describe '#create_demo_rom_file' do
    let(:task) { described_class.new(action: :create, title: 'FILE TEST') }

    it 'creates a file' do
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'test.gb')
        task_with_output = described_class.new(action: :create, output: output_path, title: 'FILE TEST')

        result = task_with_output.create_demo_rom_file

        expect(File.exist?(result)).to be true
        expect(result).to eq(output_path)
      end
    end

    it 'writes valid ROM data to file' do
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'test.gb')
        task_with_output = described_class.new(action: :create, output: output_path, title: 'FILE TEST')

        task_with_output.create_demo_rom_file

        data = File.binread(output_path)
        expect(data.length).to eq(32 * 1024)

        bytes = data.bytes
        title = bytes[0x134, 9].pack('C*')
        expect(title).to eq('FILE TEST')
      end
    end

    it 'defaults to demo.gb filename' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          task_default = described_class.new(action: :create)
          result = task_default.create_demo_rom_file

          expect(result).to eq('demo.gb')
          expect(File.exist?('demo.gb')).to be true
        end
      end
    end
  end

  describe '#show_demo_info' do
    let(:task) { described_class.new(action: :info, title: 'INFO TEST') }

    it 'outputs ROM information' do
      expect { task.show_demo_info }.to output(/Demo ROM Information/).to_stdout
    end

    it 'shows ROM size' do
      expect { task.show_demo_info }.to output(/Size:.*32KB/).to_stdout
    end

    it 'shows title' do
      expect { task.show_demo_info }.to output(/Title:.*INFO TEST/).to_stdout
    end

    it 'shows checksum validity' do
      expect { task.show_demo_info }.to output(/Checksum valid: Yes/).to_stdout
    end
  end

  describe '#run' do
    context 'with :create action' do
      it 'creates a demo ROM file' do
        Dir.mktmpdir do |dir|
          output_path = File.join(dir, 'created.gb')
          task = described_class.new(action: :create, output: output_path)

          task.run

          expect(File.exist?(output_path)).to be true
        end
      end
    end

    context 'with :info action' do
      it 'shows demo info' do
        task = described_class.new(action: :info)
        expect { task.run }.to output(/Demo ROM Information/).to_stdout
      end
    end

    context 'with :run action in headless mode' do
      it 'runs the demo' do
        task = described_class.new(action: :run, headless: true, cycles: 10, mode: :ruby, sim: :ruby)
        result = task.run
        expect(result).to be_a(Hash)
        expect(result[:cycles]).to eq(10)
      end
    end

    context 'with no action (default)' do
      it 'runs the demo in headless mode' do
        task = described_class.new(headless: true, cycles: 10, mode: :ruby, sim: :ruby)
        result = task.run
        expect(result).to be_a(Hash)
      end
    end
  end

  describe 'integration with HeadlessRunner' do
    let(:task) { described_class.new(headless: true, cycles: 100, mode: :ruby, sim: :ruby) }

    it 'runs demo ROM through HeadlessRunner' do
      result = task.run
      expect(result[:cycles]).to eq(100)
    end

    it 'can access CPU state after running' do
      result = task.run
      expect(result).to include(:pc, :a, :f)
    end
  end
end
