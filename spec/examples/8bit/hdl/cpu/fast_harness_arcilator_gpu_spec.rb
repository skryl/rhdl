# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/8bit/utilities/runners/arcilator_gpu_runner'

RSpec.describe RHDL::HDL::CPU::FastHarness do
  let(:sim) do
    instance_double(
      RHDL::Examples::CPU8Bit::ArcilatorGpuRunner,
      native?: true,
      backend: :arcilator_gpu,
      runner_mode?: true,
      runner_kind: :cpu8bit,
      poke: true,
      evaluate: true
    )
  end

  before do
    allow(RHDL::Examples::CPU8Bit::ArcilatorGpuRunner).to receive(:new).and_return(sim)
    allow(described_class).to receive(:ensure_arcilator_gpu_available!).and_return(true)

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

  it 'uses runner-backed memory in arcilator_gpu mode' do
    harness = described_class.new(nil, sim: :arcilator_gpu)

    harness.memory.load([0xAA, 0xBB, 0xCC], 0x20)
    harness.memory.write(0x40, 0x55)

    expect(harness.memory.read(0x20)).to eq(0xAA)
    expect(harness.memory.read(0x21)).to eq(0xBB)
    expect(harness.memory.read(0x40)).to eq(0x55)
    expect(harness.backend).to eq(:arcilator_gpu)
    expect(harness.native?).to be(true)
  end

  it 'requires runner-capable cpu8bit mode for arcilator_gpu' do
    allow(sim).to receive(:runner_mode?).and_return(false)

    expect { described_class.new(nil, sim: :arcilator_gpu) }
      .to raise_error(ArgumentError, /runner mode/i)
  end

  it 'surfaces ArcToGPU capability failures clearly' do
    allow(described_class).to receive(:ensure_arcilator_gpu_available!)
      .and_raise(ArgumentError, 'ArcToGPU pipeline not available in arcilator build')

    expect { described_class.new(nil, sim: :arcilator_gpu) }
      .to raise_error(ArgumentError, /ArcToGPU pipeline not available/)
  end

  it 'stops batch execution when runner reports no forward progress' do
    allow(sim).to receive(:runner_run_cycles).and_return({ cycles_run: 0, text_dirty: false, key_cleared: false, speaker_toggles: 0 })
    allow(sim).to receive(:peek).with('halted').and_return(1)

    harness = described_class.new(nil, sim: :arcilator_gpu)
    expect(harness.run_cycles(64, batch_size: 16)).to eq(0)
    expect(harness.halted).to be(true)
  end
end
