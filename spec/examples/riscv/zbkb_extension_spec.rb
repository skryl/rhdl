require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zbkb core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 10))
  end

  it 'executes pack/packh subset operations' do
    program = [
      asm.addi(6, 0, 0x123),
      asm.addi(7, 0, 0x456),
      asm.pack(5, 6, 7),
      asm.packh(8, 6, 7)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(5)).to eq(0x0456_0123)
    expect(cpu.read_reg(8)).to eq(0x0000_5623)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zbkb core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zbkb_pipeline', backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zbkb core behavior', pipeline: true
end
