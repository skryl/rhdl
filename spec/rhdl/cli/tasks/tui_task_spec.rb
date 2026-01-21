# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::TuiTask do
  let(:temp_dir) { Dir.mktmpdir('rhdl_tui_test') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with list option' do
      expect { described_class.new(list: true) }.not_to raise_error
    end

    it 'can be instantiated with install option' do
      expect { described_class.new(install: true) }.not_to raise_error
    end

    it 'can be instantiated with clean option' do
      expect { described_class.new(clean: true) }.not_to raise_error
    end

    it 'can be instantiated with ink option' do
      expect { described_class.new(ink: true) }.not_to raise_error
    end

    it 'can be instantiated with component option' do
      expect { described_class.new(component: 'sequential/counter') }.not_to raise_error
    end

    it 'can be instantiated with signals option' do
      expect { described_class.new(component: 'sequential/counter', signals: :all) }.not_to raise_error
    end

    it 'can be instantiated with build option' do
      expect { described_class.new(build: true) }.not_to raise_error
    end

    it 'can be instantiated with alu option' do
      expect { described_class.new(alu: true) }.not_to raise_error
    end

    it 'can be instantiated with format option' do
      expect { described_class.new(component: 'sequential/counter', format: :hex) }.not_to raise_error
      expect { described_class.new(component: 'sequential/counter', format: :binary) }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with list option' do
      it 'lists available components without error' do
        task = described_class.new(list: true)

        expect { task.run }.to output(/Available Components/).to_stdout
      end

      it 'includes component categories' do
        task = described_class.new(list: true)

        expect { task.run }.to output(/gates\/not_gate/).to_stdout
      end
    end

    context 'with clean option' do
      it 'cleans Ink TUI build artifacts without error' do
        mock_tui_dir = File.join(temp_dir, 'tui-ink')
        mock_dist_dir = File.join(mock_tui_dir, 'dist')
        FileUtils.mkdir_p(mock_dist_dir)
        File.write(File.join(mock_dist_dir, 'test.js'), 'test')

        allow(RHDL::CLI::Config).to receive(:tui_ink_dir).and_return(mock_tui_dir)

        task = described_class.new(clean: true)
        expect { task.run }.to output(/Cleaned/).to_stdout

        expect(Dir.exist?(mock_dist_dir)).to be false
      end
    end
  end

  describe '#list_components' do
    let(:task) { described_class.new(list: true) }

    it 'outputs all HDL component names' do
      output = capture_stdout { task.list_components }

      # Should include at least some known components
      expect(output).to include('gates/not_gate')
      expect(output).to include('sequential/counter')
    end
  end

  describe '#clean' do
    let(:task) { described_class.new(clean: true) }

    it 'removes the dist directory' do
      mock_tui_dir = File.join(temp_dir, 'tui-ink')
      mock_dist_dir = File.join(mock_tui_dir, 'dist')
      FileUtils.mkdir_p(mock_dist_dir)

      allow(RHDL::CLI::Config).to receive(:tui_ink_dir).and_return(mock_tui_dir)

      task.clean

      expect(Dir.exist?(mock_dist_dir)).to be false
    end

    it 'removes node_modules when CLEAN_NODE_MODULES is set' do
      mock_tui_dir = File.join(temp_dir, 'tui-ink')
      mock_node_modules = File.join(mock_tui_dir, 'node_modules')
      FileUtils.mkdir_p(mock_node_modules)

      allow(RHDL::CLI::Config).to receive(:tui_ink_dir).and_return(mock_tui_dir)

      original_env = ENV['CLEAN_NODE_MODULES']
      ENV['CLEAN_NODE_MODULES'] = '1'

      task.clean

      ENV['CLEAN_NODE_MODULES'] = original_env

      expect(Dir.exist?(mock_node_modules)).to be false
    end
  end

  describe 'private methods' do
    let(:task) { described_class.new }

    describe '#ensure_node_available' do
      it 'raises error when node is not available' do
        allow(task).to receive(:command_available?).with('node').and_return(false)

        expect {
          task.send(:ensure_node_available)
        }.to raise_error(RuntimeError, /Node.js is required/)
      end

      it 'does not raise error when node is available' do
        allow(task).to receive(:command_available?).with('node').and_return(true)

        expect {
          task.send(:ensure_node_available)
        }.not_to raise_error
      end
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
