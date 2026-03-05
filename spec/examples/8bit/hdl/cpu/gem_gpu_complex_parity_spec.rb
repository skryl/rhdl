# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'
require 'support/cpu_assembler'

RSpec.describe '8-bit CPU gem_gpu complex parity' do
  DISPLAY_START = 0x0800
  DISPLAY_LEN = 80 * 24

  def build_harness(sim)
    RHDL::HDL::CPU::FastHarness.new(nil, sim: sim)
  end

  def checksum_region(memory, start_addr, length)
    sum = 0
    rolling_xor = 0

    length.times do |offset|
      byte = memory.read((start_addr + offset) & 0xFFFF).to_i & 0xFF
      sum = (sum + byte) & 0xFFFF_FFFF
      rolling_xor ^= ((byte << (offset & 7)) & 0xFF)
    end

    [sum, rolling_xor]
  end

  def compare_snapshots(compiler:, gpu:, regions:, label:)
    expect(gpu.halted).to eq(compiler.halted), "halted mismatch at #{label}"
    expect(gpu.acc).to eq(compiler.acc), "acc mismatch at #{label}"
    expect(gpu.pc).to eq(compiler.pc), "pc mismatch at #{label}"
    expect(gpu.sp).to eq(compiler.sp), "sp mismatch at #{label}"
    expect(gpu.state).to eq(compiler.state), "state mismatch at #{label}"
    expect(gpu.zero_flag).to eq(compiler.zero_flag), "zero_flag mismatch at #{label}"

    regions.each do |region|
      compiler_sig = checksum_region(compiler.memory, region.fetch(:start), region.fetch(:length))
      gpu_sig = checksum_region(gpu.memory, region.fetch(:start), region.fetch(:length))
      expect(gpu_sig).to eq(compiler_sig),
        "memory checksum mismatch at #{label} for 0x#{region.fetch(:start).to_s(16)}+#{region.fetch(:length)}"
    end
  end

  def run_checkpoint_parity(program_bytes:, start_pc:, checkpoints:, regions:, batch_size: 4096)
    compiler = build_harness(:compile)
    gpu = build_harness(:gem_gpu)

    [compiler, gpu].each do |harness|
      harness.memory.load(program_bytes, 0)
      harness.pc = start_pc
    end

    last = 0
    checkpoints.each do |checkpoint|
      step = checkpoint - last
      raise ArgumentError, "checkpoints must be increasing (#{checkpoints.inspect})" if step <= 0

      compiler_ran = compiler.run_cycles(step, batch_size: batch_size)
      gpu_ran = gpu.run_cycles(step, batch_size: batch_size)
      expect(gpu_ran).to eq(compiler_ran), "cycle progress mismatch at checkpoint #{checkpoint}"

      compare_snapshots(
        compiler: compiler,
        gpu: gpu,
        regions: regions,
        label: "#{checkpoint} cycles"
      )

      last = checkpoint
    end
  end

  before do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    status = RHDL::HDL::CPU::FastHarness.gem_gpu_status
    skip "gem_gpu backend unavailable: #{status.inspect}" unless status[:ready]
  end

  it 'matches compiler backend on conway glider 80x24 checkpoints', timeout: 900 do
    bin_path = File.expand_path('../../../../../examples/8bit/software/bin/conway_glider_80x24.bin', __dir__)
    program = File.binread(bin_path).bytes

    run_checkpoint_parity(
      program_bytes: program,
      start_pc: 0x20,
      checkpoints: [25_000, 50_000, 100_000],
      regions: [
        { start: DISPLAY_START, length: DISPLAY_LEN },
        { start: 0x0200, length: 0x240 }
      ]
    )
  end

  it 'matches compiler backend on mandelbrot 80x24 checkpoints', timeout: 900 do
    bin_path = File.expand_path('../../../../../examples/8bit/software/bin/mandelbrot_80x24.bin', __dir__)
    program = File.binread(bin_path).bytes

    run_checkpoint_parity(
      program_bytes: program,
      start_pc: 0x00,
      checkpoints: [20_000, 40_000, 80_000],
      regions: [
        { start: DISPLAY_START, length: DISPLAY_LEN },
        { start: 0x0100, length: 0x300 }
      ]
    )
  end

  it 'matches compiler backend on long-running arithmetic loop checkpoints', timeout: 600 do
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

    run_checkpoint_parity(
      program_bytes: program,
      start_pc: 0x40,
      checkpoints: [25_000, 50_000, 100_000],
      regions: [
        { start: 0x0080, length: 0x40 },
        { start: 0x0800, length: 0x80 }
      ]
    )
  end
end
