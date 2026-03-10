# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'

RSpec.describe RHDL::Examples::AO486::IrRunner, timeout: 30 do
  it 'reaches the BIOS reset-vector fetch state with the compiler-backed runner' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    state = runner.run(cycles: 2)

    expect(state[:bios_loaded]).to be(true)
    expect(state[:simulator_type]).to eq(:ao486_ir_compile)
    expect(runner.peek('rst_n')).to eq(1)
    expect(runner.peek('pipeline_inst__decode_inst__eip')).to eq(0xFFF0)
    expect(runner.peek('memory_inst__prefetch_inst__prefetch_address')).to eq(0xFFFF0)
    expect(runner.peek('memory_inst__prefetch_inst__prefetch_length')).to eq(16)
  end

  it 'advances beyond the reset vector into BIOS code with the compiler-backed runner' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.run(cycles: 24)

    expect(runner.peek('pipeline_inst__decode_inst__eip')).to be >= 0xE05B
    expect(runner.peek('trace_wr_eip')).to be >= 0xE05B
  end

  it 'drains the early BIOS prefetch queue and branches past the CMOS shutdown read' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    retired_eips = []
    80.times do
      runner.run(cycles: 1)
      retired_eips << runner.peek('trace_wr_eip')
    end

    expect(retired_eips).to include(0xE06B)
    expect(retired_eips).to include(0xE071)
    expect(retired_eips).to include(0xE09F)
    expect(runner.peek('trace_wr_eip')).to be >= 0xE09F
    expect(runner.peek('memory_inst__prefetch_control_inst__prefetchfifo_used')).to eq(0)
  end

  it 'initializes the IVT before leaving the early ROM helper path' do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runner = described_class.new(backend: :compile, headless: true)
    runner.load_bios
    runner.run(cycles: 500)

    expect(runner.read_bytes(0x0000, 4, mapped: true)).to eq([0x53, 0xFF, 0x00, 0xF0])
    expect(runner.peek('pipeline_inst__decode_inst__eip')).not_to be < 0x0020
    expect(runner.peek('pipeline_inst__decode_inst__cs_cache')).to eq(0x930F0000FFFF)
  end
end
