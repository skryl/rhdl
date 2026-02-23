require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zbb core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 10))
  end

  it 'executes andn/orn/xnor subset operations' do
    program = [
      asm.addi(6, 0, 0x55),
      asm.addi(7, 0, 0x0f),
      asm.andn(5, 6, 7),
      asm.orn(8, 6, 7),
      asm.xnor(9, 6, 7)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(5)).to eq(0x50)
    expect(cpu.read_reg(8)).to eq(0xFFFF_FFF5)
    expect(cpu.read_reg(9)).to eq(0xFFFF_FFA5)
  end

  it 'executes min/max and minu/maxu subset operations' do
    program = [
      asm.addi(6, 0, -5),
      asm.addi(7, 0, 3),
      asm.min(10, 6, 7),
      asm.max(11, 6, 7),
      asm.minu(12, 6, 7),
      asm.maxu(13, 6, 7)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10)).to eq(0xFFFF_FFFB)
    expect(cpu.read_reg(11)).to eq(3)
    expect(cpu.read_reg(12)).to eq(3)
    expect(cpu.read_reg(13)).to eq(0xFFFF_FFFB)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zbb core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zbb_pipeline', backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zbb core behavior', pipeline: true
end
