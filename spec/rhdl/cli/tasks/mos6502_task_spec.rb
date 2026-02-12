# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::MOS6502Task do
  let(:temp_dir) { Dir.mktmpdir('rhdl_mos6502_test') }

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

    it 'can be instantiated with mode option' do
      expect { described_class.new(mode: :isa) }.not_to raise_error
      expect { described_class.new(mode: :ruby) }.not_to raise_error
      expect { described_class.new(mode: :ir) }.not_to raise_error
    end

    it 'can be instantiated with sim option' do
      expect { described_class.new(sim: :native) }.not_to raise_error
      expect { described_class.new(sim: :ruby) }.not_to raise_error
      expect { described_class.new(sim: :interpret) }.not_to raise_error
      expect { described_class.new(sim: :jit) }.not_to raise_error
      expect { described_class.new(sim: :compile) }.not_to raise_error
    end

    it 'can be instantiated with hires option' do
      expect { described_class.new(hires: true) }.not_to raise_error
    end

    it 'can be instantiated with color option' do
      expect { described_class.new(color: true) }.not_to raise_error
    end

    it 'can be instantiated with hires_width option' do
      expect { described_class.new(hires: true, hires_width: 140) }.not_to raise_error
    end

    it 'can be instantiated with karateka option' do
      expect { described_class.new(karateka: true) }.not_to raise_error
    end

    it 'can be instantiated with disk options' do
      expect { described_class.new(disk: '/path/to/disk.dsk') }.not_to raise_error
      expect { described_class.new(disk2: '/path/to/disk2.dsk') }.not_to raise_error
    end
  end

  describe 'path configuration' do
    it 'uses mos6502 script path' do
      task = described_class.new
      script_path = task.send(:mos6502_script)

      expect(script_path).to include('examples/mos6502/bin/mos6502')
      expect(File.exist?(script_path)).to be true
    end
  end

  describe 'options handling' do
    it 'stores all provided options' do
      options = {
        build: true,
        debug: true,
        mode: :ir,
        green: true,
        speed: 5000,
        rom: '/path/to/rom.bin'
      }
      task = described_class.new(options)

      expect(task.options[:build]).to be true
      expect(task.options[:debug]).to be true
      expect(task.options[:mode]).to eq(:ir)
      expect(task.options[:green]).to be true
      expect(task.options[:speed]).to eq(5000)
      expect(task.options[:rom]).to eq('/path/to/rom.bin')
    end

    it 'stores hires options' do
      task = described_class.new(hires: true, hires_width: 140)

      expect(task.options[:hires]).to be true
      expect(task.options[:hires_width]).to eq(140)
    end

    it 'stores color option' do
      task = described_class.new(color: true)

      expect(task.options[:color]).to be true
    end
  end

  describe '#add_common_args' do
    it 'adds hires flag when hires option is set' do
      task = described_class.new(hires: true)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-H')
    end

    it 'adds color flag when color option is set' do
      task = described_class.new(color: true)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-C')
    end

    it 'adds hires-width when hires_width option is set' do
      task = described_class.new(hires_width: 140)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--hires-width')
      expect(exec_args).to include('140')
    end

    it 'adds both hires and color flags together' do
      task = described_class.new(hires: true, color: true, hires_width: 140)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-H')
      expect(exec_args).to include('-C')
      expect(exec_args).to include('--hires-width')
      expect(exec_args).to include('140')
    end

    it 'adds all common args correctly' do
      task = described_class.new(
        debug: true,
        mode: :ir,
        sim: :jit,
        speed: 5000,
        green: true,
        hires: true,
        color: true,
        hires_width: 100,
        disk: '/path/to/disk.dsk',
        disk2: '/path/to/disk2.dsk'
      )
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-d')
      expect(exec_args).to include('-m')
      expect(exec_args).to include('ir')
      expect(exec_args).to include('--sim')
      expect(exec_args).to include('jit')
      expect(exec_args).to include('-s')
      expect(exec_args).to include('5000')
      expect(exec_args).to include('-g')
      expect(exec_args).to include('-H')
      expect(exec_args).to include('-C')
      expect(exec_args).to include('--hires-width')
      expect(exec_args).to include('100')
      expect(exec_args).to include('--disk')
      expect(exec_args).to include('/path/to/disk.dsk')
      expect(exec_args).to include('--disk2')
      expect(exec_args).to include('/path/to/disk2.dsk')
    end

    it 'does not pass -m for isa mode (default)' do
      task = described_class.new(mode: :isa)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).not_to include('-m')
    end

    it 'passes -m for ir mode' do
      task = described_class.new(mode: :ir)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-m')
      expect(exec_args).to include('ir')
    end

    it 'does not pass --sim for default isa backend' do
      default_isa_backend = if defined?(RHDL::Examples::MOS6502::NATIVE_AVAILABLE) && RHDL::Examples::MOS6502::NATIVE_AVAILABLE
                              :native
                            else
                              :ruby
                            end
      task = described_class.new(mode: :isa, sim: default_isa_backend)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).not_to include('--sim')
    end

    it 'passes --sim for interpret backend' do
      task = described_class.new(mode: :ir, sim: :interpret)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--sim')
      expect(exec_args).to include('interpret')
    end

    it 'passes --sim for jit backend' do
      task = described_class.new(mode: :ir, sim: :jit)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--sim')
      expect(exec_args).to include('jit')
    end

    it 'passes --sim for non-default isa backend' do
      default_isa_backend = if defined?(RHDL::Examples::MOS6502::NATIVE_AVAILABLE) && RHDL::Examples::MOS6502::NATIVE_AVAILABLE
                              :native
                            else
                              :ruby
                            end
      non_default_backend = default_isa_backend == :native ? :ruby : :native
      task = described_class.new(mode: :isa, sim: non_default_backend)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--sim')
      expect(exec_args).to include(non_default_backend.to_s)
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
end
