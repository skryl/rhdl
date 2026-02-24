require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'rv32c compile behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles((pipeline ? 20 : 4) + program.length * (pipeline ? 6 : 3))
  end

  it 'executes mixed-width compressed and base instructions on compile backend' do
    program = asm.pack_mixed([
      asm.c_li(1, 3),
      asm.addi(1, 1, 4),
      asm.c_addi(1, 5),
      asm.c_mv(2, 1),
      asm.c_nop,
      asm.j(0)
    ])

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(1)).to eq(12)
    expect(cpu.read_reg(2)).to eq(12)
  end

  it 'executes expanded rv32c integer subset used by Linux/toolchain output' do
    program = asm.pack_mixed([
      asm.addi(2, 0, 128),    # sp = 128
      asm.addi(5, 0, 0x123),  # t0 = 0x123
      asm.c_swsp(5, 12),
      asm.addi(5, 0, 0),
      asm.c_lwsp(6, 12),
      asm.c_addi4spn(8, 16),
      asm.c_addi16sp(32),      # sp = 160
      asm.c_lui(3, 1),
      asm.c_slli(3, 3),
      asm.c_li(8, 15),
      asm.c_srli(8, 1),
      asm.c_srai(8, 1),
      asm.c_andi(8, 2),
      asm.c_li(9, 1),
      asm.c_sub(8, 9),
      asm.c_xor(8, 9),
      asm.c_or(8, 9),
      asm.c_and(8, 9),
      asm.j(0)
    ])

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(2)).to eq(160)
    expect(cpu.read_reg(3)).to eq(0x8000)
    expect(cpu.read_reg(6)).to eq(0x123)
    expect(cpu.read_reg(8)).to eq(1)
    expect(cpu.read_reg(9)).to eq(1)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'rv32c compile behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('rv32c_compile_pipeline', backend: :compile, allow_fallback: false) }

  before(:each) do
    skip 'IR compiler backend unavailable' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  end

  include_examples 'rv32c compile behavior', pipeline: true
end
