# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::GenerateTask do
  let(:temp_dir) { Dir.mktmpdir('rhdl_generate_test') }
  let(:diagrams_dir) { File.join(temp_dir, 'diagrams') }
  let(:verilog_dir) { File.join(temp_dir, 'export/verilog') }
  let(:gates_dir) { File.join(temp_dir, 'export/gates') }

  before do
    allow(RHDL::CLI::Config).to receive(:diagrams_dir).and_return(diagrams_dir)
    allow(RHDL::CLI::Config).to receive(:verilog_dir).and_return(verilog_dir)
    allow(RHDL::CLI::Config).to receive(:gates_dir).and_return(gates_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with action: :generate' do
      expect { described_class.new(action: :generate) }.not_to raise_error
    end

    it 'can be instantiated with action: :clean' do
      expect { described_class.new(action: :clean) }.not_to raise_error
    end

    it 'can be instantiated with action: :regenerate' do
      expect { described_class.new(action: :regenerate) }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with action: :generate (default)' do
      it 'starts generation without error' do
        task = described_class.new(action: :generate, root: temp_dir)

        expect { task.run }.to output(/Generating all output files/).to_stdout
      end
    end

    context 'with action: :clean' do
      it 'starts cleanup without error' do
        FileUtils.mkdir_p(File.join(diagrams_dir, 'component'))
        FileUtils.mkdir_p(verilog_dir)
        FileUtils.mkdir_p(gates_dir)
        FileUtils.mkdir_p(File.join(temp_dir, 'tmp'))
        FileUtils.mkdir_p(File.join(temp_dir, '.tmp'))
        FileUtils.mkdir_p(File.join(temp_dir, 'web', 'dist'))
        FileUtils.mkdir_p(File.join(temp_dir, 'web', 'test-results'))
        FileUtils.mkdir_p(File.join(temp_dir, 'web', 'build', 'arcilator'))
        FileUtils.mkdir_p(File.join(temp_dir, 'web', 'build', 'verilator'))
        File.write(File.join(temp_dir, 'web', 'build', 'arcilator', '.gitignore'), "")
        File.write(File.join(temp_dir, 'web', 'build', 'verilator', '.gitignore'), "")

        allow_any_instance_of(RHDL::CLI::Tasks::NativeTask).to receive(:run)

        task = described_class.new(action: :clean, root: temp_dir)

        expect { task.run }.to output(/Cleaning all generated files/).to_stdout
      end
    end

    context 'with action: :regenerate' do
      it 'cleans and then generates' do
        allow_any_instance_of(RHDL::CLI::Tasks::NativeTask).to receive(:run)
        task = described_class.new(action: :regenerate, root: temp_dir)

        output = capture_stdout { task.run }

        expect(output).to include('Cleaning')
        expect(output).to include('Generating')
      end
    end
  end

  describe '#generate_all' do
    let(:task) { described_class.new(action: :generate, root: temp_dir) }

    it 'displays completion message' do
      expect { task.generate_all }.to output(/All output files generated/).to_stdout
    end
  end

  describe '#clean_all' do
    let(:task) { described_class.new(action: :clean, root: temp_dir) }

    it 'displays completion message' do
      allow_any_instance_of(RHDL::CLI::Tasks::NativeTask).to receive(:run)
      expect { task.clean_all }.to output(/All generated files cleaned/).to_stdout
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
