# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Task do
  let(:task) { described_class.new }
  let(:task_with_options) { described_class.new(foo: 'bar', debug: true) }

  describe '#initialize' do
    it 'accepts options hash' do
      expect(task_with_options.options).to eq(foo: 'bar', debug: true)
    end

    it 'defaults to empty options' do
      expect(task.options).to eq({})
    end
  end

  describe '#run' do
    it 'raises NotImplementedError' do
      expect { task.run }.to raise_error(NotImplementedError, /must implement #run/)
    end
  end

  describe '#execute' do
    let(:successful_task) do
      Class.new(described_class) do
        def run
          true
        end
      end.new
    end

    let(:failing_task) do
      Class.new(described_class) do
        def run
          raise StandardError, 'Task failed'
        end
      end.new
    end

    it 'returns the result of run on success' do
      expect(successful_task.execute).to be true
    end

    it 'returns false on error' do
      expect(failing_task.execute).to be false
    end

    it 'handles errors gracefully' do
      expect { failing_task.execute }.to output(/ERROR/).to_stderr
    end
  end

  describe 'protected helper methods' do
    # Create a subclass to test protected methods
    let(:test_task_class) do
      Class.new(described_class) do
        def run; end

        # Expose protected methods for testing
        public :puts_status, :puts_ok, :puts_error, :puts_header, :puts_separator
        public :ensure_dir, :command_available?
      end
    end
    let(:test_task) { test_task_class.new }

    describe '#puts_status' do
      it 'outputs formatted status message' do
        expect { test_task.puts_status('OK', 'test message') }.to output(/\[OK\] test message/).to_stdout
      end
    end

    describe '#puts_ok' do
      it 'outputs OK status message' do
        expect { test_task.puts_ok('success') }.to output(/\[OK\] success/).to_stdout
      end
    end

    describe '#puts_error' do
      it 'outputs ERROR status message' do
        expect { test_task.puts_error('failure') }.to output(/\[ERROR\] failure/).to_stdout
      end
    end

    describe '#puts_header' do
      it 'outputs title with separator' do
        expect { test_task.puts_header('Test Header') }.to output(/Test Header.*={50}/m).to_stdout
      end
    end

    describe '#puts_separator' do
      it 'outputs separator line' do
        expect { test_task.puts_separator }.to output(/-{50}/).to_stdout
      end
    end

    describe '#ensure_dir' do
      it 'creates directory if it does not exist' do
        test_dir = File.join(Dir.tmpdir, "rhdl_test_#{$$}_#{rand(1000)}")
        expect(Dir.exist?(test_dir)).to be false
        test_task.ensure_dir(test_dir)
        expect(Dir.exist?(test_dir)).to be true
        FileUtils.rm_rf(test_dir)
      end

      it 'does not fail if directory already exists' do
        existing_dir = Dir.tmpdir
        expect { test_task.ensure_dir(existing_dir) }.not_to raise_error
      end
    end

    describe '#command_available?' do
      it 'returns true for available commands' do
        expect(test_task.command_available?('ruby')).to be true
      end

      it 'returns false for unavailable commands' do
        expect(test_task.command_available?('nonexistent_command_xyz123')).to be false
      end
    end
  end
end
