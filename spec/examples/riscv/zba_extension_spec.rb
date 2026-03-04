require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zba core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 10))
  end

  it 'executes sh1add/sh2add/sh3add on positive operands' do
    program = [
      asm.addi(6, 0, 3),
      asm.addi(7, 0, 4),
      asm.sh1add(5, 6, 7),
      asm.sh2add(8, 6, 7),
      asm.sh3add(9, 6, 7)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(5)).to eq(11)
    expect(cpu.read_reg(8)).to eq(19)
    expect(cpu.read_reg(9)).to eq(35)
  end

  it 'executes sh1add/sh2add/sh3add on negative operands' do
    program = [
      asm.addi(6, 0, -4),
      asm.addi(7, 0, 5),
      asm.sh1add(10, 6, 7),
      asm.sh2add(11, 6, 7),
      asm.sh3add(12, 6, 7)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10)).to eq(6)
    expect(cpu.read_reg(11)).to eq(16)
    expect(cpu.read_reg(12)).to eq(36)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  include_examples 'zba core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zba_pipeline', backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  include_examples 'zba core behavior', pipeline: true
end
