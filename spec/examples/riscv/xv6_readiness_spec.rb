# xv6-readiness privileged behavior checks for both single-cycle and pipelined cores

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'xv6 privileged compatibility' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 8 : 0))
  end

  it 'treats WFI as a legal non-trapping no-op' do
    program = [
      asm.addi(1, 0, 7),
      asm.wfi,
      asm.addi(1, 1, 5),
      asm.nop
    ]
    run_program(cpu, program, pipeline: pipeline)
    expect(cpu.read_reg(1)).to eq(12)
  end

  it 'treats SFENCE.VMA as a legal non-trapping no-op' do
    program = [
      asm.addi(2, 0, 9),
      asm.sfence_vma,
      asm.addi(2, 2, 3),
      asm.nop
    ]
    run_program(cpu, program, pipeline: pipeline)
    expect(cpu.read_reg(2)).to eq(12)
  end

  it 'treats FENCE.I as a legal non-trapping no-op' do
    program = [
      asm.addi(3, 0, 4),
      asm.fence_i,
      asm.addi(3, 3, 6),
      asm.nop
    ]
    run_program(cpu, program, pipeline: pipeline)
    expect(cpu.read_reg(3)).to eq(10)
  end

  it 'exposes pending interrupt bits through mip and delegated bits through sip' do
    program = [
      asm.addi(3, 0, 0x222),      # x3 = 0x222 (SSIP|STIP|SEIP delegation bits)
      asm.csrrw(0, 0x303, 3),     # mideleg = 0x222
      asm.nop,
      asm.nop,
      asm.csrrs(1, 0x344, 0),     # x1 = mip
      asm.csrrs(2, 0x144, 0)      # x2 = sip
    ]
    cpu.load_program(program)
    cpu.reset!
    cpu.set_interrupts(software: true, timer: true, external: true)
    cpu.run_cycles(program.length + (pipeline ? 8 : 0))
    # MIP: MSIP(bit 3)=0x8, STIP(bit 5)=0x20, MTIP(bit 7)=0x80, SEIP(bit 9)=0x200 => 0x2A8
    expect(cpu.read_reg(1)).to eq(0x2A8)
    # SIP: MIP & effective_mideleg(0x222) => STIP(bit 5, 0x20) + SEIP(bit 9, 0x200) => 0x220
    expect(cpu.read_reg(2)).to eq(0x220)
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'xv6 privileged compatibility', pipeline: false
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('xv6_pipeline', backend: :jit, allow_fallback: false) }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  include_examples 'xv6 privileged compatibility', pipeline: true
end
