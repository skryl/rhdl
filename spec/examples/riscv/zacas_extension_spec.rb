require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zacas core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 42 : 14))
  end

  it 'implements AMOCAS.W success/failure return semantics' do
    if pipeline
      cpu.write_data(0x140, 7)
    else
      cpu.write_data_word(0x140, 7)
    end

    program = [
      asm.addi(1, 0, 0x140),
      asm.addi(2, 0, 42),
      asm.addi(3, 0, 7),
      asm.amocas_w(3, 2, 1),
      asm.addi(4, 0, 9),
      asm.addi(5, 0, 99),
      asm.amocas_w(4, 5, 1),
      asm.lw(6, 1, 0),
      asm.j(0)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(3)).to eq(7)
    expect(cpu.read_reg(4)).to eq(42)
    expect(cpu.read_reg(6)).to eq(42)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zacas core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zacas_pipeline', backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zacas core behavior', pipeline: true
end
