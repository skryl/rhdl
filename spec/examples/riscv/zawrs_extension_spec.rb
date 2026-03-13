require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zawrs core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 36 : 12))
  end

  it 'accepts wrs.nto/wrs.sto without illegal-instruction trap regressions' do
    if pipeline
      cpu.write_data(0x120, 7)
    else
      cpu.write_data_word(0x120, 7)
    end

    program = [
      asm.addi(1, 0, 0x120),
      asm.lr_w(2, 1),
      asm.wrs_nto,
      asm.wrs_sto,
      asm.addi(3, 0, 9),
      asm.sc_w(4, 3, 1),
      asm.lw(5, 1, 0),
      asm.j(0)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(2)).to eq(7)
    expect(cpu.read_reg(4)).to eq(0)
    expect(cpu.read_reg(5)).to eq(9)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  include_examples 'zawrs core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zawrs_pipeline', backend: :compile) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  include_examples 'zawrs core behavior', pipeline: true
end
