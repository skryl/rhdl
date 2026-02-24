require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zicbo core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 10))
  end

  it 'accepts prefetch and cbo operations without trap regressions' do
    program = [
      asm.addi(10, 0, 0x100),
      asm.prefetch_i(10, 0),
      asm.prefetch_r(10, 0),
      asm.prefetch_w(10, 0),
      asm.cbo_inval(10, 0),
      asm.cbo_clean(10, 0),
      asm.cbo_flush(10, 0),
      asm.cbo_zero(10, 0),
      asm.addi(11, 10, 1)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(11)).to eq(0x101)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zicbo core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zicbo_pipeline', backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zicbo core behavior', pipeline: true
end
