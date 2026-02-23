require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'zbc core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 10))
  end

  def clmul_full_ref(a, b)
    full = 0
    32.times do |i|
      full ^= (a << i) if ((b >> i) & 1) == 1
    end
    full & 0xFFFF_FFFF_FFFF_FFFF
  end

  it 'executes clmul/clmulh/clmulr family operations' do
    a = 0x1B3
    b = 0x02D
    full = clmul_full_ref(a, b)

    program = [
      asm.addi(6, 0, a),
      asm.addi(7, 0, b),
      asm.clmul(5, 6, 7),
      asm.clmulh(8, 6, 7),
      asm.clmulr(9, 6, 7)
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(5)).to eq(full & 0xFFFF_FFFF)
    expect(cpu.read_reg(8)).to eq((full >> 32) & 0xFFFF_FFFF)
    expect(cpu.read_reg(9)).to eq((full >> 31) & 0xFFFF_FFFF)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zbc core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('zbc_pipeline', backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'zbc core behavior', pipeline: true
end
