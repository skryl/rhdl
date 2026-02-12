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

    it 'can be instantiated with mode option' do
      expect { described_class.new(mode: :ruby) }.not_to raise_error
      expect { described_class.new(mode: :ir) }.not_to raise_error
      expect { described_class.new(mode: :netlist) }.not_to raise_error
      expect { described_class.new(mode: :verilog) }.not_to raise_error
    end

    it 'can be instantiated with sim option' do
      expect { described_class.new(sim: :interpret) }.not_to raise_error
      expect { described_class.new(sim: :jit) }.not_to raise_error
      expect { described_class.new(sim: :compile) }.not_to raise_error
    end

    it 'can be instantiated with all mode/sim combinations' do
      # ir mode with all sim options
      expect { described_class.new(mode: :ir, sim: :interpret) }.not_to raise_error
      expect { described_class.new(mode: :ir, sim: :jit) }.not_to raise_error
      expect { described_class.new(mode: :ir, sim: :compile) }.not_to raise_error

      # netlist mode with all sim options
      expect { described_class.new(mode: :netlist, sim: :interpret) }.not_to raise_error
      expect { described_class.new(mode: :netlist, sim: :jit) }.not_to raise_error
      expect { described_class.new(mode: :netlist, sim: :compile) }.not_to raise_error

      # verilog mode (uses Verilator, sim option not applicable)
      expect { described_class.new(mode: :verilog) }.not_to raise_error
    end

    it 'can be instantiated with program option' do
      expect { described_class.new(program: '/path/to/program.bin') }.not_to raise_error
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


    it 'can be instantiated with speed option' do
      expect { described_class.new(speed: 5000) }.not_to raise_error
    end

    it 'can be instantiated with green option' do
      expect { described_class.new(green: true) }.not_to raise_error
    end

    it 'can be instantiated with run option' do
      expect { described_class.new(build: true, run: true) }.not_to raise_error
    end

    it 'can be instantiated with hires option' do
      expect { described_class.new(hires: true) }.not_to raise_error
    end

    it 'can be instantiated with hires_width option' do
      expect { described_class.new(hires: true, hires_width: 140) }.not_to raise_error
    end

    it 'can be instantiated with color option' do
      expect { described_class.new(color: true) }.not_to raise_error
    end

    it 'can be instantiated with karateka option' do
      expect { described_class.new(karateka: true) }.not_to raise_error
    end

    it 'can be instantiated with bin option' do
      expect { described_class.new(bin: '/path/to/file.bin') }.not_to raise_error
    end

    it 'can be instantiated with disk options' do
      expect { described_class.new(disk: '/path/to/disk.dsk') }.not_to raise_error
      expect { described_class.new(disk2: '/path/to/disk2.dsk') }.not_to raise_error
    end

    it 'can be instantiated with remaining_args option' do
      expect { described_class.new(remaining_args: ['--extra', 'args']) }.not_to raise_error
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

  describe 'path configuration' do
    it 'uses apple2 script path by default' do
      task = described_class.new
      script_path = task.send(:apple2_script)

      expect(script_path).to include('examples/apple2/bin/apple2')
      expect(File.exist?(script_path)).to be true
    end

    it 'uses apple2 script path for mos6502 subcommand' do
      task = described_class.new(subcommand: :mos6502)
      script_path = task.send(:apple2_script)

      expect(script_path).to include('examples/apple2/bin/apple2')
      expect(File.exist?(script_path)).to be true
    end

    it 'uses apple2 script path for apple2 subcommand' do
      task = described_class.new(subcommand: :apple2)
      script_path = task.send(:apple2_script)

      expect(script_path).to include('examples/apple2/bin/apple2')
      expect(File.exist?(script_path)).to be true
    end
  end

  describe 'options handling' do
    it 'stores all provided options' do
      options = {
        build: true,
        debug: true,
        mode: :ruby,
        green: true,
        speed: 5000,
        rom: '/path/to/rom.bin'
      }
      task = described_class.new(options)

      expect(task.options[:build]).to be true
      expect(task.options[:debug]).to be true
      expect(task.options[:mode]).to eq(:ruby)
      expect(task.options[:green]).to be true
      expect(task.options[:speed]).to eq(5000)
      expect(task.options[:rom]).to eq('/path/to/rom.bin')
    end

    it 'stores hires options' do
      task = described_class.new(hires: true, hires_width: 140)

      expect(task.options[:hires]).to be true
      expect(task.options[:hires_width]).to eq(140)
    end
  end

  describe '#add_common_args' do
    it 'adds hires flag when hires option is set' do
      task = described_class.new(hires: true)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-H')
    end

    it 'adds hires-width when hires_width option is set' do
      task = described_class.new(hires_width: 140)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--hires-width')
      expect(exec_args).to include('140')
    end

    it 'adds both hires flags together' do
      task = described_class.new(hires: true, hires_width: 140)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-H')
      expect(exec_args).to include('--hires-width')
      expect(exec_args).to include('140')
    end

    it 'adds color flag when color option is set' do
      task = described_class.new(color: true)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-C')
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
        mode: :netlist,
        sim: :compile,
        speed: 5000,
        green: true,
        hires: true,
        hires_width: 100,
        disk: '/path/to/disk.dsk'
      )
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-d')
      expect(exec_args).to include('-m')
      expect(exec_args).to include('netlist')
      expect(exec_args).to include('--sim')
      expect(exec_args).to include('compile')
      expect(exec_args).to include('-s')
      expect(exec_args).to include('5000')
      expect(exec_args).to include('-g')
      expect(exec_args).to include('-H')
      expect(exec_args).to include('--hires-width')
      expect(exec_args).to include('100')
      expect(exec_args).to include('--disk')
      expect(exec_args).to include('/path/to/disk.dsk')
    end

    it 'does not pass -m for ruby mode (default)' do
      task = described_class.new(mode: :ruby)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).not_to include('-m')
    end

    it 'passes -m for netlist mode' do
      task = described_class.new(mode: :netlist)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-m')
      expect(exec_args).to include('netlist')
    end

    it 'passes -m for verilog mode' do
      task = described_class.new(mode: :verilog)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-m')
      expect(exec_args).to include('verilog')
    end

    it 'does not pass --sim for ruby backend (default)' do
      task = described_class.new(sim: :ruby)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).not_to include('--sim')
    end

    it 'passes --sim for jit backend' do
      task = described_class.new(sim: :jit)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--sim')
      expect(exec_args).to include('jit')
    end

    it 'passes --sim for interpret backend' do
      task = described_class.new(sim: :interpret)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--sim')
      expect(exec_args).to include('interpret')
    end

    it 'passes --sim for compile backend' do
      task = described_class.new(sim: :compile)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('--sim')
      expect(exec_args).to include('compile')
    end

    it 'passes both -m and --sim for netlist with interpret' do
      task = described_class.new(mode: :netlist, sim: :interpret)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-m')
      expect(exec_args).to include('netlist')
      expect(exec_args).to include('--sim')
      expect(exec_args).to include('interpret')
    end

    it 'passes both -m and --sim for netlist with compile' do
      task = described_class.new(mode: :netlist, sim: :compile)
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).to include('-m')
      expect(exec_args).to include('netlist')
      expect(exec_args).to include('--sim')
      expect(exec_args).to include('compile')
    end

    it 'does not add bin flag when bin option is set' do
      task = described_class.new(bin: '/path/to/file.bin')
      exec_args = []

      task.send(:add_common_args, exec_args)

      expect(exec_args).not_to include('-b')
      expect(exec_args).not_to include('/path/to/file.bin')
    end
  end
end
