# frozen_string_literal: true

require 'spec_helper'

RSpec.describe '8-bit CPU arcilator_gpu parity' do
  def build_harness(sim)
    RHDL::HDL::CPU::FastHarness.new(nil, sim: sim)
  end

  it 'matches compiler backend for a simple store program' do
    skip 'set RHDL_ENABLE_ARCILATOR_GPU=1 to run ArcToGPU parity checks' unless ENV['RHDL_ENABLE_ARCILATOR_GPU'] == '1'
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    gpu_status = RHDL::HDL::CPU::FastHarness.arcilator_gpu_status
    expect(gpu_status[:ready]).to be(true), "arcilator_gpu backend unavailable: #{gpu_status.inspect}"

    compiler = build_harness(:compile)
    gpu = build_harness(:arcilator_gpu)

    # LDI 0x55 ; STA 0x40 ; HLT
    program = [0xA0, 0x55, 0x21, 0x40, 0xF0]

    [compiler, gpu].each do |harness|
      harness.memory.load(program, 0)
      harness.pc = 0
      harness.run(300)
    end

    expect(gpu.halted).to eq(compiler.halted)
    expect(gpu.acc).to eq(compiler.acc)
    expect(gpu.pc).to eq(compiler.pc)
    expect(gpu.memory.read(0x40)).to eq(compiler.memory.read(0x40))
  end
end
