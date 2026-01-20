# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::GatesTask do
  let(:temp_dir) { Dir.mktmpdir('rhdl_gates_test') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with export option' do
      expect { described_class.new(export: true) }.not_to raise_error
    end

    it 'can be instantiated with stats option' do
      expect { described_class.new(stats: true) }.not_to raise_error
    end

    it 'can be instantiated with simcpu option' do
      expect { described_class.new(simcpu: true) }.not_to raise_error
    end

    it 'can be instantiated with clean option' do
      expect { described_class.new(clean: true) }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with clean option' do
      it 'cleans generated gate-level files without error' do
        FileUtils.mkdir_p(temp_dir)
        File.write(File.join(temp_dir, 'test.json'), '{}')

        allow(RHDL::CLI::Config).to receive(:gates_dir).and_return(temp_dir)

        task = described_class.new(clean: true)
        expect { task.run }.to output(/Cleaned/).to_stdout

        expect(Dir.exist?(temp_dir)).to be false
      end
    end

    context 'with stats option' do
      it 'starts stats display without error' do
        task = described_class.new(stats: true)
        expect { task.run }.to output(/Gate-Level Synthesis Statistics/).to_stdout
      end
    end

    context 'with simcpu option' do
      it 'starts SimCPU export without error' do
        allow(RHDL::CLI::Config).to receive(:gates_dir).and_return(temp_dir)

        task = described_class.new(simcpu: true)
        expect { task.run }.to output(/SimCPU/).to_stdout
      end
    end

    context 'with export option' do
      it 'starts export without error' do
        allow(RHDL::CLI::Config).to receive(:gates_dir).and_return(temp_dir)

        task = described_class.new(export: true)
        # Just verify it starts without error - don't wait for full export
        expect { task.run }.to output(/Gate-Level Synthesis Export/).to_stdout
      end
    end
  end

  describe '#clean' do
    let(:task) { described_class.new(clean: true) }

    it 'removes the entire gates directory' do
      allow(RHDL::CLI::Config).to receive(:gates_dir).and_return(temp_dir)

      FileUtils.mkdir_p(File.join(temp_dir, 'gates'))
      File.write(File.join(temp_dir, 'gates/test.json'), '{}')

      expect { task.clean }.to output(/Cleaned/).to_stdout

      expect(Dir.exist?(temp_dir)).to be false
    end
  end

  describe 'gate-level lowering' do
    it 'can lower a single component to gate-level IR' do
      component = RHDL::HDL::NotGate.new('test_not')
      ir = RHDL::Export::Structure::Lower.from_components([component], name: 'test_not')

      expect(ir).not_to be_nil
      expect(ir.gates).not_to be_empty
    end
  end
end
