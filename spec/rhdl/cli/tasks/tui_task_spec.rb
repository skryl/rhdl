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

    it 'can be instantiated with component option' do
      expect { described_class.new(component: 'sequential/counter') }.not_to raise_error
    end

    it 'can be instantiated with signals option' do
      expect { described_class.new(component: 'sequential/counter', signals: :all) }.not_to raise_error
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
