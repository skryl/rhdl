# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'
require 'support/cpu_assembler'

RSpec.describe '8-bit CPU gem_gpu instruction-stream parity' do
  def build_harness(sim)
    RHDL::HDL::CPU::FastHarness.new(nil, sim: sim)
  end

  def checksum_region(memory, start_addr, length)
    sum = 0
    length.times do |offset|
      byte = memory.read((start_addr + offset) & 0xFFFF).to_i & 0xFF
      sum = (sum + byte) & 0xFFFF_FFFF
    end
    sum
  end

  around do |example|
    old_mode = ENV['RHDL_GEM_GPU_EXECUTION_MODE']
    ENV['RHDL_GEM_GPU_EXECUTION_MODE'] = 'instruction_stream'
    example.run
  ensure
    if old_mode.nil?
      ENV.delete('RHDL_GEM_GPU_EXECUTION_MODE')
    else
      ENV['RHDL_GEM_GPU_EXECUTION_MODE'] = old_mode
    end
  end

  before do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    status = RHDL::HDL::CPU::FastHarness.gem_gpu_status
    skip "gem_gpu backend unavailable: #{status.inspect}" unless status[:ready]
  end

  it 'matches compiler checkpoints for arithmetic loop in instruction-stream mode', timeout: 300 do
    program = Assembler.build(0x40) do |p|
      p.instr :LDI, 1
      p.instr :STA, 0x02
      p.instr :LDI, 0
      p.instr :STA, 0x0E

      p.label :loop
      p.instr :LDA, 0x0E
      p.instr :ADD, 0x02
      p.instr :STA, 0x0E
      p.instr :LDA, 0x0E
      p.instr :STA, 0x90
      p.instr :JMP_LONG, :loop
    end

    compiler = build_harness(:compile)
    gpu = build_harness(:gem_gpu)

    [compiler, gpu].each do |harness|
      harness.memory.load(program, 0)
      harness.pc = 0x40
    end

    [10_000, 20_000, 40_000].each do |checkpoint|
      compiler_ran = compiler.run_cycles(checkpoint - compiler.cycle_count, batch_size: 2048)
      gpu_ran = gpu.run_cycles(checkpoint - gpu.cycle_count, batch_size: 2048)
      expect(gpu_ran).to eq(compiler_ran)

      expect(gpu.acc).to eq(compiler.acc)
      expect(gpu.pc).to eq(compiler.pc)
      expect(gpu.sp).to eq(compiler.sp)
      expect(gpu.state).to eq(compiler.state)
      expect(gpu.zero_flag).to eq(compiler.zero_flag)
      expect(checksum_region(gpu.memory, 0x0080, 0x40)).to eq(checksum_region(compiler.memory, 0x0080, 0x40))
      expect(checksum_region(gpu.memory, 0x0800, 0x80)).to eq(checksum_region(compiler.memory, 0x0800, 0x80))
    end
  end

  it 'matches compiler checkpoints when output-watch override mode is enabled', timeout: 300 do
    old_override = ENV['RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE']
    ENV['RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE'] = '1'

    program = Assembler.build(0x40) do |p|
      p.instr :LDI, 1
      p.instr :STA, 0x02
      p.instr :LDI, 0
      p.instr :STA, 0x0E

      p.label :loop
      p.instr :LDA, 0x0E
      p.instr :ADD, 0x02
      p.instr :STA, 0x0E
      p.instr :LDA, 0x0E
      p.instr :STA, 0x90
      p.instr :JMP_LONG, :loop
    end

    compiler = build_harness(:compile)
    gpu = build_harness(:gem_gpu)

    [compiler, gpu].each do |harness|
      harness.memory.load(program, 0)
      harness.pc = 0x40
    end

    [2_500, 5_000, 10_000].each do |checkpoint|
      compiler_ran = compiler.run_cycles(checkpoint - compiler.cycle_count, batch_size: 1024)
      gpu_ran = gpu.run_cycles(checkpoint - gpu.cycle_count, batch_size: 1024)
      expect(gpu_ran).to eq(compiler_ran)

      expect(gpu.acc).to eq(compiler.acc)
      expect(gpu.pc).to eq(compiler.pc)
      expect(gpu.sp).to eq(compiler.sp)
      expect(gpu.state).to eq(compiler.state)
      expect(gpu.zero_flag).to eq(compiler.zero_flag)
      expect(checksum_region(gpu.memory, 0x0080, 0x40)).to eq(checksum_region(compiler.memory, 0x0080, 0x40))
      expect(checksum_region(gpu.memory, 0x0800, 0x80)).to eq(checksum_region(compiler.memory, 0x0800, 0x80))
    end
  ensure
    if old_override.nil?
      ENV.delete('RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE')
    else
      ENV['RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE'] = old_override
    end
  end
end
