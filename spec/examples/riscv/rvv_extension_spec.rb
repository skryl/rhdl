require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'rvv baseline core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 28 : 0))
  end

  it 'sets vl/vtype with vsetvli and surfaces them through CSR reads' do
    program = [
      asm.addi(1, 0, 9),
      asm.vsetvli(6, 1, 0),
      asm.csrrs(7, 0xC20, 0),
      asm.csrrs(8, 0xC21, 0),
      asm.vsetvli(9, 0, 0),
      asm.csrrs(13, 0xC20, 0)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(6)).to eq(4)
    expect(cpu.read_reg(7)).to eq(4)
    expect(cpu.read_reg(8)).to eq(0)
    expect(cpu.read_reg(9)).to eq(4)
    expect(cpu.read_reg(13)).to eq(4)
  end

  it 'executes vmv/vadd baseline subset and honors vl=0 write suppression' do
    program = [
      asm.addi(1, 0, 4),
      asm.vsetvli(0, 1, 0),
      asm.addi(2, 0, 7),
      asm.addi(3, 0, 5),
      asm.vmv_v_x(1, 2),
      asm.nop,
      asm.nop,
      asm.vadd_vx(2, 1, 3),
      asm.nop,
      asm.nop,
      asm.addi(4, 0, 2),
      asm.vmv_v_x(3, 4),
      asm.nop,
      asm.nop,
      asm.vadd_vv(4, 2, 3),
      asm.nop,
      asm.nop,
      asm.vmv_x_s(10, 4),
      asm.addi(5, 0, 0),
      asm.csrrw(0, 0xC20, 5),
      asm.addi(2, 0, 99),
      asm.vmv_v_x(4, 2),
      asm.vmv_x_s(11, 4),
      asm.csrrs(12, 0xC20, 0)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10)).to eq(14)
    expect(cpu.read_reg(11)).to eq(14)
    expect(cpu.read_reg(12)).to eq(0)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'rvv baseline core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('rvv_pipeline', backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'rvv baseline core behavior', pipeline: true
end

RSpec.describe 'RVV baseline differential parity', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  def build_single
    RHDL::Examples::RISCV::IRHarness.new(mem_size: 4096, backend: :jit, allow_fallback: false)
  end

  def build_pipeline
    RHDL::Examples::RISCV::Pipeline::IRHarness.new('rvv_diff', backend: :jit, allow_fallback: false)
  end

  it 'matches scalar architectural state between single-cycle and pipelined cores' do
    program = [
      asm.addi(1, 0, 4),
      asm.vsetvli(5, 1, 0),
      asm.addi(2, 0, 9),
      asm.addi(3, 0, 6),
      asm.vmv_v_x(1, 2),
      asm.nop,
      asm.nop,
      asm.vadd_vx(2, 1, 3),
      asm.nop,
      asm.nop,
      asm.vmv_x_s(10, 2),
      asm.csrrs(11, 0xC20, 0),
      asm.csrrs(12, 0xC21, 0)
    ]
    padded = program + Array.new(8, asm.nop)

    single = build_single
    single.load_program(padded)
    single.reset!
    single.run_cycles(padded.length + 12)

    pipeline = build_pipeline
    pipeline.load_program(padded)
    pipeline.reset!
    pipeline.run_cycles(padded.length + 30)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
  end
end
