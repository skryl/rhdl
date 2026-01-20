# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::Apple2Task do
  let(:temp_dir) { Dir.mktmpdir('rhdl_apple2_test') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with clean option' do
      expect { described_class.new(clean: true) }.not_to raise_error
    end

    it 'can be instantiated with build option' do
      expect { described_class.new(build: true) }.not_to raise_error
    end

    it 'can be instantiated with demo option' do
      expect { described_class.new(demo: true) }.not_to raise_error
    end

    it 'can be instantiated with appleiigo option' do
      expect { described_class.new(appleiigo: true) }.not_to raise_error
    end

    it 'can be instantiated with ink option' do
      expect { described_class.new(ink: true) }.not_to raise_error
    end

    it 'can be instantiated with hdl option' do
      expect { described_class.new(ink: true, hdl: true) }.not_to raise_error
    end

    it 'can be instantiated with program option' do
      expect { described_class.new(ink: true, program: '/path/to/program.bin') }.not_to raise_error
    end

    it 'can be instantiated with rom option' do
      expect { described_class.new(rom: '/path/to/rom.bin') }.not_to raise_error
    end

    it 'can be instantiated with address option' do
      expect { described_class.new(address: '0800') }.not_to raise_error
    end

    it 'can be instantiated with rom_address option' do
      expect { described_class.new(rom_address: 'F800') }.not_to raise_error
    end

    it 'can be instantiated with debug option' do
      expect { described_class.new(debug: true) }.not_to raise_error
    end

    it 'can be instantiated with fast option' do
      expect { described_class.new(fast: true) }.not_to raise_error
    end

    it 'can be instantiated with speed option' do
      expect { described_class.new(speed: 5000) }.not_to raise_error
    end

    it 'can be instantiated with green option' do
      expect { described_class.new(green: true) }.not_to raise_error
    end

    it 'can be instantiated with run option' do
      expect { described_class.new(build: true, run: true) }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with clean option' do
      it 'cleans ROM output files without error' do
        FileUtils.mkdir_p(temp_dir)
        File.write(File.join(temp_dir, 'test.bin'), 'test')

        allow(RHDL::CLI::Config).to receive(:rom_output_dir).and_return(temp_dir)

        task = described_class.new(clean: true)
        expect { task.run }.to output(/Cleaned/).to_stdout

        expect(Dir.exist?(temp_dir)).to be false
      end
    end
  end

  describe '#clean' do
    let(:task) { described_class.new(clean: true) }

    it 'removes the ROM output directory' do
      allow(RHDL::CLI::Config).to receive(:rom_output_dir).and_return(temp_dir)

      FileUtils.mkdir_p(temp_dir)
      File.write(File.join(temp_dir, 'test.bin'), 'test')

      expect { task.clean }.to output(/Cleaned/).to_stdout

      expect(Dir.exist?(temp_dir)).to be false
    end
  end

  describe '#create_demo_program' do
    let(:task) { described_class.new }

    it 'returns an array of bytes' do
      program = task.create_demo_program
      expect(program).to be_an(Array)
      expect(program.all? { |b| b.is_a?(Integer) && b >= 0 && b <= 255 }).to be true
    end

    it 'starts with initialization code (LDA #$00)' do
      program = task.create_demo_program
      expect(program[0]).to eq(0xA9) # LDA immediate
      expect(program[1]).to eq(0x00) # #$00
    end

    it 'includes print character subroutine (ends with RTS)' do
      program = task.create_demo_program
      expect(program.last).to eq(0x60) # RTS
    end
  end

  describe 'path configuration' do
    it 'uses correct apple2 script path' do
      task = described_class.new
      script_path = task.send(:apple2_script)

      expect(script_path).to include('examples/mos6502/bin/apple2')
      expect(File.exist?(script_path)).to be true
    end
  end

  describe 'options handling' do
    it 'stores all provided options' do
      options = {
        build: true,
        debug: true,
        fast: true,
        green: true,
        speed: 5000,
        rom: '/path/to/rom.bin'
      }
      task = described_class.new(options)

      expect(task.options[:build]).to be true
      expect(task.options[:debug]).to be true
      expect(task.options[:fast]).to be true
      expect(task.options[:green]).to be true
      expect(task.options[:speed]).to eq(5000)
      expect(task.options[:rom]).to eq('/path/to/rom.bin')
    end
  end
end
