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
        task = described_class.new(action: :generate)

        expect { task.run }.to output(/Generating all output files/).to_stdout
      end
    end

    context 'with action: :clean' do
      it 'starts cleanup without error' do
        FileUtils.mkdir_p(File.join(diagrams_dir, 'component'))
        FileUtils.mkdir_p(verilog_dir)
        FileUtils.mkdir_p(gates_dir)

        task = described_class.new(action: :clean)

        expect { task.run }.to output(/Cleaning all generated files/).to_stdout
      end
    end

    context 'with action: :regenerate' do
      it 'cleans and then generates' do
        task = described_class.new(action: :regenerate)

        output = capture_stdout { task.run }

        expect(output).to include('Cleaning')
        expect(output).to include('Generating')
      end
    end
  end

  describe '#generate_all' do
    let(:task) { described_class.new(action: :generate) }

    it 'displays completion message' do
      expect { task.generate_all }.to output(/All output files generated/).to_stdout
    end
  end

  describe '#clean_all' do
    let(:task) { described_class.new(action: :clean) }

    it 'displays completion message' do
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
