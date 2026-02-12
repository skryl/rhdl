require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/hdl/virtio_blk'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'virtio-blk MMIO visibility' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 20 : 8))
  end

  it 'exposes virtio identification and queue capability registers' do
    program = [
      asm.lui(3, 0x10001),         # x3 = 0x1000_1000 (virtio-mmio base)
      asm.lw(10, 3, 0x000),        # x10 = magic
      asm.lw(11, 3, 0x004),        # x11 = version
      asm.lw(12, 3, 0x008),        # x12 = device id
      asm.lw(13, 3, 0x00C),        # x13 = vendor id
      asm.addi(14, 0, 0),          # x14 = queue index 0
      asm.sw(14, 3, 0x030),        # QUEUE_SEL = 0
      asm.lw(15, 3, 0x034),        # x15 = QUEUE_NUM_MAX
      asm.nop
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10)).to eq(RHDL::Examples::RISCV::VirtioBlk::VIRTIO_MAGIC)
    expect(cpu.read_reg(11)).to eq(2)
    expect(cpu.read_reg(12)).to eq(2)
    expect(cpu.read_reg(13)).to eq(RHDL::Examples::RISCV::VirtioBlk::VIRTIO_VENDOR_ID)
    expect(cpu.read_reg(15)).to eq(RHDL::Examples::RISCV::VirtioBlk::QUEUE_NUM_MAX)
  end

  it 'supports xv6-like status handshake and queue ready writes' do
    program = [
      asm.lui(3, 0x10001),         # x3 = 0x1000_1000
      asm.addi(14, 0, 1),          # ACKNOWLEDGE
      asm.sw(14, 3, 0x070),        # STATUS = ACKNOWLEDGE
      asm.addi(14, 0, 3),          # ACKNOWLEDGE|DRIVER
      asm.sw(14, 3, 0x070),        # STATUS = 3
      asm.addi(14, 0, 8),          # queue num
      asm.sw(14, 3, 0x038),        # QUEUE_NUM = 8
      asm.addi(14, 0, 1),          # queue ready = 1
      asm.sw(14, 3, 0x044),        # QUEUE_READY = 1
      asm.lw(10, 3, 0x070),        # x10 = STATUS
      asm.lw(11, 3, 0x038),        # x11 = QUEUE_NUM
      asm.lw(12, 3, 0x044),        # x12 = QUEUE_READY
      asm.nop
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10) & 0xFF).to eq(3)
    expect(cpu.read_reg(11)).to eq(8)
    expect(cpu.read_reg(12)).to eq(1)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'virtio-blk MMIO visibility', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('virtio_blk_pipeline', backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'virtio-blk MMIO visibility', pipeline: true
end
