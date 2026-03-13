# frozen_string_literal: true

require 'spec_helper'

require_relative '../../examples/apple2/utilities/runners/headless_runner'
require_relative '../../examples/mos6502/utilities/runners/headless_runner'
require_relative '../../examples/riscv/utilities/runners/headless_runner'
require_relative '../../examples/gameboy/utilities/runners/headless_runner'
require_relative '../../examples/sparc64/utilities/runners/headless_runner'
require_relative '../../examples/ao486/utilities/runners/headless_runner'

RSpec.describe 'HeadlessRunner trace API' do
  shared_examples 'delegates trace methods to the runner' do |klass|
    let(:trace_backend) do
      instance_double(
        'TraceBackend',
        trace_supported?: true,
        trace_start: true,
        trace_to_vcd: '$timescale 1ns $end'
      )
    end

    it 'delegates to the active runner when trace support is present' do
      runner = klass.allocate
      runner.instance_variable_set(:@runner, trace_backend)

      expect(runner.trace_supported?).to be(true)
      expect(runner.trace_start).to be(true)
      expect(runner.trace_to_vcd).to include('$timescale')
    end

    it 'raises an explicit error when the active runner does not support tracing' do
      runner = klass.allocate
      runner.instance_variable_set(:@runner, instance_double('PlainRunner'))

      expect(runner.trace_supported?).to be(false)
      expect { runner.trace_start }.to raise_error(RuntimeError, /does not support tracing/i)
    end
  end

  include_examples 'delegates trace methods to the runner', RHDL::Examples::Apple2::HeadlessRunner
  include_examples 'delegates trace methods to the runner', RHDL::Examples::MOS6502::HeadlessRunner
  include_examples 'delegates trace methods to the runner', RHDL::Examples::GameBoy::HeadlessRunner
  include_examples 'delegates trace methods to the runner', RHDL::Examples::SPARC64::HeadlessRunner
  include_examples 'delegates trace methods to the runner', RHDL::Examples::AO486::HeadlessRunner

  describe RHDL::Examples::RISCV::HeadlessRunner do
    let(:trace_backend) do
      instance_double(
        'TraceBackend',
        trace_supported?: true,
        trace_start: true,
        trace_to_vcd: '$timescale 1ns $end'
      )
    end

    let(:cpu) do
      instance_double('CpuRunner', sim: trace_backend)
    end

    it 'delegates to the native sim object when the CPU exposes it' do
      runner = described_class.allocate
      runner.instance_variable_set(:@cpu, cpu)

      expect(runner.trace_supported?).to be(true)
      expect(runner.trace_start).to be(true)
      expect(runner.trace_to_vcd).to include('$timescale')
    end

    it 'raises an explicit error when the CPU sim does not support tracing' do
      runner = described_class.allocate
      runner.instance_variable_set(:@cpu, instance_double('CpuRunner', sim: instance_double('PlainSim')))

      expect(runner.trace_supported?).to be(false)
      expect { runner.trace_start }.to raise_error(RuntimeError, /does not support tracing/i)
    end
  end
end
