require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'rvv compile behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 36 : 14))
  end

  it 'executes baseline vector subset on compile backend' do
    program = [
      asm.addi(1, 0, 4),
      asm.vsetvli(5, 1, 0),
      asm.addi(2, 0, 7),
      asm.addi(3, 0, 5),
      asm.vmv_v_x(1, 2),
      asm.nop,
      asm.nop,
      asm.vadd_vx(2, 1, 3),
      asm.nop,
      asm.nop,
      asm.vmv_x_s(10, 2)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(5)).to eq(4)
    expect(cpu.read_reg(10)).to eq(12)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'rvv compile behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('rvv_compile_pipeline', backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'rvv compile behavior', pipeline: true
end
