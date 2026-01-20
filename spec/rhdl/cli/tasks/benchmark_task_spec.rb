# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'

RSpec.describe RHDL::CLI::Tasks::BenchmarkTask do
  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with type: :gates' do
      expect { described_class.new(type: :gates) }.not_to raise_error
    end

    it 'can be instantiated with type: :tests' do
      expect { described_class.new(type: :tests) }.not_to raise_error
    end

    it 'can be instantiated with type: :timing' do
      expect { described_class.new(type: :timing) }.not_to raise_error
    end

    it 'can be instantiated with type: :quick' do
      expect { described_class.new(type: :quick) }.not_to raise_error
    end

    it 'can be instantiated with lanes option' do
      expect { described_class.new(type: :gates, lanes: 8) }.not_to raise_error
    end

    it 'can be instantiated with cycles option' do
      expect { described_class.new(type: :gates, cycles: 1000) }.not_to raise_error
    end

    it 'can be instantiated with count option' do
      expect { described_class.new(type: :tests, count: 10) }.not_to raise_error
    end

    it 'can be instantiated with pattern option' do
      expect { described_class.new(type: :tests, pattern: 'spec/rhdl/') }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with type: :gates' do
      it 'starts gate benchmark without error' do
        task = described_class.new(type: :gates, lanes: 2, cycles: 10)
        expect { task.run }.to output(/Gate-level Simulation Benchmark/).to_stdout
      end

      it 'respects lanes and cycles parameters' do
        task = described_class.new(type: :gates, lanes: 4, cycles: 50)
        expect { task.run }.to output(/Lanes: 4/).to_stdout
      end
    end
  end

  describe '#benchmark_gates' do
    it 'runs gate benchmark and reports results' do
      task = described_class.new(type: :gates, lanes: 2, cycles: 10)
      expect { task.benchmark_gates }.to output(/Result:/).to_stdout
    end
  end

  describe 'environment variables' do
    it 'respects RHDL_BENCH_LANES environment variable' do
      original_lanes = ENV['RHDL_BENCH_LANES']
      ENV['RHDL_BENCH_LANES'] = '16'

      task = described_class.new(type: :gates, cycles: 10)
      expect { task.benchmark_gates }.to output(/Lanes: 16/).to_stdout

      ENV['RHDL_BENCH_LANES'] = original_lanes
    end

    it 'respects RHDL_BENCH_CYCLES environment variable' do
      original_cycles = ENV['RHDL_BENCH_CYCLES']
      ENV['RHDL_BENCH_CYCLES'] = '200'

      task = described_class.new(type: :gates, lanes: 2)
      expect { task.benchmark_gates }.to output(/Cycles: 200/).to_stdout

      ENV['RHDL_BENCH_CYCLES'] = original_cycles
    end
  end

  describe 'private methods' do
    let(:task) { described_class.new(type: :tests) }

    describe '#rspec_cmd' do
      it 'returns a command string' do
        cmd = task.send(:rspec_cmd)
        expect(cmd).to be_a(String)
      end
    end
  end
end
