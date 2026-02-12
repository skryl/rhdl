# RV32A atomic extension checks for both cores and differential parity

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'rv32a core behavior' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 10 : 0))
  end

  it 'implements LR/SC reservation success and failure behavior' do
    cpu.write_data_word(0x100, 7) unless pipeline
    cpu.write_data(0x100, 7) if pipeline

    program = [
      asm.addi(1, 0, 0x100),
      asm.addi(2, 0, 42),
      asm.sc_w(3, 2, 1),
      asm.lr_w(4, 1),
      asm.sc_w(5, 2, 1),
      asm.sw(0, 1, 0),
      asm.sc_w(6, 2, 1),
      asm.lw(7, 1, 0)
    ]
    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(3)).to eq(1)
    expect(cpu.read_reg(4)).to eq(7)
    expect(cpu.read_reg(5)).to eq(0)
    expect(cpu.read_reg(6)).to eq(1)
    expect(cpu.read_reg(7)).to eq(0)
  end

  it 'implements AMOSWAP/AMOADD/AMOXOR/AMOAND/AMOOR word ops' do
    cpu.write_data_word(0x104, 5) unless pipeline
    cpu.write_data(0x104, 5) if pipeline

    program = [
      asm.addi(1, 0, 0x104),
      asm.addi(2, 0, 9),
      asm.amoswap_w(3, 2, 1),
      asm.amoadd_w(4, 2, 1),
      asm.amoxor_w(5, 2, 1),
      asm.amoand_w(6, 2, 1),
      asm.amoor_w(7, 2, 1),
      asm.lw(8, 1, 0)
    ]
    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(3)).to eq(5)
    expect(cpu.read_reg(4)).to eq(9)
    expect(cpu.read_reg(5)).to eq(18)
    expect(cpu.read_reg(6)).to eq(27)
    expect(cpu.read_reg(7)).to eq(9)
    expect(cpu.read_reg(8)).to eq(9)
  end

  it 'implements AMOMIN/AMOMAX/AMOMINU/AMOMAXU word ops' do
    cpu.write_data_word(0x108, 0xFFFF_FFFE) unless pipeline
    cpu.write_data(0x108, 0xFFFF_FFFE) if pipeline

    program = [
      asm.addi(1, 0, 0x108),         # x1 = addr
      asm.addi(2, 0, 1),             # x2 = 1
      asm.amomin_w(3, 2, 1),         # x3 = -2, mem=-2
      asm.amomax_w(4, 2, 1),         # x4 = -2, mem=1
      asm.addi(2, 0, -2),            # x2 = 0xFFFFFFFE
      asm.amominu_w(5, 2, 1),        # x5 = 1, mem=1
      asm.amomaxu_w(6, 2, 1),        # x6 = 1, mem=0xFFFFFFFE
      asm.lw(7, 1, 0)
    ]
    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(3)).to eq(0xFFFF_FFFE)
    expect(cpu.read_reg(4)).to eq(0xFFFF_FFFE)
    expect(cpu.read_reg(5)).to eq(1)
    expect(cpu.read_reg(6)).to eq(1)
    expect(cpu.read_reg(7)).to eq(0xFFFF_FFFE)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'rv32a core behavior', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('rv32a_pipeline', backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'rv32a core behavior', pipeline: true
end

RSpec.describe 'RV32A differential parity', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  def build_single
    RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: :jit, allow_fallback: false)
  end

  def build_pipeline
    RHDL::Examples::RISCV::Pipeline::IRHarness.new('rv32a_diff', backend: :jit, allow_fallback: false)
  end

  it 'matches single-cycle and pipelined architectural state on atomic sequences' do
    program = [
      asm.addi(1, 0, 0x120),
      asm.addi(2, 0, 5),
      asm.lr_w(3, 1),
      asm.sc_w(4, 2, 1),
      asm.amoadd_w(5, 2, 1),
      asm.amoswap_w(6, 2, 1),
      asm.amoxor_w(7, 2, 1),
      asm.amoand_w(8, 2, 1),
      asm.amoor_w(9, 2, 1),
      asm.amomin_w(11, 2, 1),
      asm.amomax_w(12, 2, 1),
      asm.amominu_w(13, 2, 1),
      asm.amomaxu_w(14, 2, 1),
      asm.lw(10, 1, 0)
    ]
    padded = program + Array.new(8, asm.nop)

    single = build_single
    single.write_data_word(0x120, 11)
    single.load_program(padded)
    single.reset!
    single.run_cycles(padded.length + 12)

    pipeline = build_pipeline
    pipeline.write_data(0x120, 11)
    pipeline.load_program(padded)
    pipeline.reset!
    pipeline.run_cycles(padded.length + 24)

    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)), "register x#{idx} mismatch"
    end
    expect(pipeline.read_data(0x120)).to eq(single.read_data_word(0x120))
  end
end
