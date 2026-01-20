# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'

RSpec.describe RHDL::CLI::Tasks::DepsTask do
  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with check option' do
      expect { described_class.new(check: true) }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with check option' do
      it 'displays dependency status' do
        task = described_class.new(check: true)

        expect { task.run }.to output(/Test Dependencies Status/).to_stdout
      end

      it 'shows ruby in dependency check' do
        task = described_class.new(check: true)

        expect { task.run }.to output(/ruby/).to_stdout
      end

      it 'shows bundler in dependency check' do
        task = described_class.new(check: true)

        expect { task.run }.to output(/bundler/).to_stdout
      end

      it 'shows optional dependencies' do
        task = described_class.new(check: true)

        expect { task.run }.to output(/iverilog/).to_stdout
      end
    end

    context 'without check option (install)' do
      it 'displays platform information' do
        task = described_class.new

        expect { task.run }.to output(/Platform:/).to_stdout
      end

      it 'checks for iverilog availability' do
        task = described_class.new

        expect { task.run }.to output(/iverilog/).to_stdout
      end
    end
  end

  describe '#check_status' do
    let(:task) { described_class.new(check: true) }

    it 'displays header' do
      expect { task.check_status }.to output(/Test Dependencies Status/).to_stdout
    end

    it 'shows ruby as installed' do
      expect { task.check_status }.to output(/\[OK\].*ruby/).to_stdout
    end

    it 'shows bundler status' do
      output = capture_stdout { task.check_status }
      expect(output).to match(/bundler/)
      # Bundler may or may not be in PATH depending on environment
      expect(output).to match(/\[(OK|MISSING)\]/)
    end

    it 'shows iverilog status' do
      output = capture_stdout { task.check_status }
      expect(output).to match(/iverilog/)
      expect(output).to match(/\[(OK|OPTIONAL)\]/)
    end
  end

  describe '#install' do
    let(:task) { described_class.new }

    it 'displays installer header' do
      expect { task.install }.to output(/Test Dependencies Installer/).to_stdout
    end

    it 'detects platform' do
      expect { task.install }.to output(/Platform:/).to_stdout
    end

    it 'completes dependency check' do
      expect { task.install }.to output(/Dependency check complete/).to_stdout
    end
  end

  describe 'private methods' do
    let(:task) { described_class.new }

    describe '#detect_platform' do
      it 'returns a symbol' do
        platform = task.send(:detect_platform)
        expect(platform).to be_a(Symbol)
      end

      it 'returns a known platform type' do
        platform = task.send(:detect_platform)
        expect([:linux, :macos, :windows, :unknown]).to include(platform)
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
