# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/8bit/utilities/runners/synth_to_gpu_runner'

RSpec.describe RHDL::HDL::CPU::FastHarness do
  let(:sim) do
    instance_double(
      RHDL::Examples::CPU8Bit::SynthToGpuRunner,
      native?: true,
      backend: :gem_gpu,
      runner_mode?: true,
      runner_kind: :cpu8bit,
      runner_parallel_instances: 1,
      poke: true,
      evaluate: true
    )
  end

  before do
    allow(RHDL::Examples::CPU8Bit::SynthToGpuRunner).to receive(:new).and_return(sim)
    allow(described_class).to receive(:ensure_gem_gpu_available!).and_return(true)

    @runner_mem = Array.new(0x10000, 0)
    allow(sim).to receive(:runner_load_memory) do |data, offset, _is_rom|
      bytes = data.is_a?(String) ? data.bytes : data
      bytes.each_with_index { |byte, i| @runner_mem[(offset + i) & 0xFFFF] = byte & 0xFF }
      true
    end
    allow(sim).to receive(:runner_read_memory) do |offset, length, mapped:|
      expect(mapped).to eq(false)
      Array.new(length) { |i| @runner_mem[(offset + i) & 0xFFFF] }
    end
    allow(sim).to receive(:runner_write_memory) do |offset, data, mapped:|
      expect(mapped).to eq(false)
      bytes = data.is_a?(String) ? data.bytes : data
      bytes.each_with_index { |byte, i| @runner_mem[(offset + i) & 0xFFFF] = byte & 0xFF }
      bytes.length
    end
    allow(sim).to receive(:runner_run_cycles).and_return({ cycles_run: 1, text_dirty: false, key_cleared: false, speaker_toggles: 0 })
    allow(sim).to receive(:peek).and_return(0)
  end

  it 'uses runner-backed memory in gem_gpu mode' do
    harness = described_class.new(nil, sim: :gem_gpu)

    harness.memory.load([0xDE, 0xAD, 0xBE, 0xEF], 0x30)
    harness.memory.write(0x50, 0x77)

    expect(harness.memory.read(0x30)).to eq(0xDE)
    expect(harness.memory.read(0x31)).to eq(0xAD)
    expect(harness.memory.read(0x50)).to eq(0x77)
    expect(harness.backend).to eq(:gem_gpu)
    expect(harness.native?).to be(true)
  end

  it 'requires runner-capable cpu8bit mode for gem_gpu' do
    allow(sim).to receive(:runner_mode?).and_return(false)

    expect { described_class.new(nil, sim: :gem_gpu) }
      .to raise_error(ArgumentError, /runner mode/i)
  end

  it 'surfaces gem_gpu capability failures clearly' do
    allow(described_class).to receive(:ensure_gem_gpu_available!)
      .and_raise(ArgumentError, 'gem_gpu toolchain unavailable')

    expect { described_class.new(nil, sim: :gem_gpu) }
      .to raise_error(ArgumentError, /gem_gpu toolchain unavailable/)
  end

  it 'runs native runner cycles as a single host-side batch' do
    allow(sim).to receive(:runner_run_cycles) do |n, _key_data, _key_ready|
      { cycles_run: n, text_dirty: false, key_cleared: false, speaker_toggles: 0 }
    end
    harness = described_class.new(nil, sim: :gem_gpu)

    expect(harness.run_cycles(100, batch_size: 16)).to eq(100)
    expect(sim).to have_received(:runner_run_cycles).with(100, 0, false).once
    expect(sim).not_to have_received(:runner_run_cycles).with(16, 0, false)
  end

  it 'reports runner parallel instance count' do
    allow(sim).to receive(:runner_parallel_instances).and_return(8)
    harness = described_class.new(nil, sim: :gem_gpu)

    expect(harness.parallel_instances).to eq(8)
  end
end
