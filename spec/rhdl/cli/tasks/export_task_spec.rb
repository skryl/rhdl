# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::ExportTask do
  let(:temp_dir) { Dir.mktmpdir('rhdl_export_test') }

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

    it 'can be instantiated with all option' do
      expect { described_class.new(all: true) }.not_to raise_error
    end

    it 'can be instantiated with scope option (lib)' do
      expect { described_class.new(all: true, scope: 'lib') }.not_to raise_error
    end

    it 'can be instantiated with scope option (examples)' do
      expect { described_class.new(all: true, scope: 'examples') }.not_to raise_error
    end

    it 'can be instantiated with scope option (all)' do
      expect { described_class.new(all: true, scope: 'all') }.not_to raise_error
    end

    it 'can be instantiated with component option' do
      expect { described_class.new(component: 'RHDL::HDL::NotGate') }.not_to raise_error
    end

    it 'can be instantiated with lang option' do
      expect { described_class.new(component: 'RHDL::HDL::NotGate', lang: 'verilog') }.not_to raise_error
    end

    it 'can be instantiated with out option' do
      expect { described_class.new(component: 'RHDL::HDL::NotGate', lang: 'verilog', out: '/tmp') }.not_to raise_error
    end

    it 'can be instantiated with top option' do
      expect { described_class.new(component: 'RHDL::HDL::NotGate', lang: 'verilog', out: '/tmp', top: 'my_module') }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with clean option' do
      it 'cleans generated Verilog files' do
        test_subdir = File.join(temp_dir, 'gates')
        FileUtils.mkdir_p(test_subdir)
        File.write(File.join(test_subdir, 'test.v'), 'module test; endmodule')

        allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(temp_dir)

        task = described_class.new(clean: true)
        expect { task.run }.to output(/Cleaned/).to_stdout

        expect(File.exist?(File.join(test_subdir, 'test.v'))).to be false
      end
    end

    context 'with all option and lib scope' do
      it 'starts export without error' do
        allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(temp_dir)

        task = described_class.new(all: true, scope: 'lib')

        expect { task.run }.to output(/Exporting lib\/ components/).to_stdout
      end
    end
  end

  describe '#export_all' do
    it 'exports lib components when scope includes lib' do
      allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(temp_dir)

      task = described_class.new(all: true, scope: 'lib')
      expect { task.export_all }.to output(/Exporting lib/).to_stdout
    end

    it 'reports exported component count' do
      allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(temp_dir)

      task = described_class.new(all: true, scope: 'lib')
      expect { task.export_all }.to output(/Exported \d+ components/).to_stdout
    end
  end

  describe '#clean' do
    let(:task) { described_class.new(clean: true) }

    it 'removes all Verilog files' do
      allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(temp_dir)

      test_file = File.join(temp_dir, 'test.v')
      File.write(test_file, 'module test; endmodule')

      expect { task.clean }.to output(/Cleaned/).to_stdout

      expect(File.exist?(test_file)).to be false
    end

    it 'removes empty subdirectories' do
      allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(temp_dir)

      test_subdir = File.join(temp_dir, 'gates')
      FileUtils.mkdir_p(test_subdir)
      test_file = File.join(test_subdir, 'test.v')
      File.write(test_file, 'module test; endmodule')

      task.clean

      expect(Dir.exist?(test_subdir)).to be false
    end
  end
end
