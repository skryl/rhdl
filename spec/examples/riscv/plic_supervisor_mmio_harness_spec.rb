require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.shared_examples 'PLIC supervisor MMIO compatibility' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:)
    cpu.load_program(program, 0)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 12))
  end

  it 'handles delegated external interrupts with supervisor PLIC enable/claim addresses' do
    main_program = [
      asm.addi(1, 0, 0x300),       # x1 = supervisor trap handler base
      asm.csrrw(0, 0x105, 1),      # stvec = x1

      asm.lui(2, 0x1),             # x2 = 0x1000
      asm.addi(2, 2, -2048),       # x2 = 0x800 (MEIP delegation/enable bit)
      asm.csrrw(0, 0x303, 2),      # mideleg = MEIP
      asm.csrrw(0, 0x104, 2),      # sie = MEIP bit (delegated external)
      asm.addi(2, 0, 0x2),         # x2 = sstatus.SIE
      asm.csrrw(0, 0x100, 2),      # sstatus = SIE

      asm.lui(5, 0xC000),          # x5 = 0x0C000000 (PLIC base)
      asm.addi(6, 0, 1),
      asm.sw(6, 5, 4),             # priority[1] = 1

      asm.lui(7, 0xC002),          # x7 = 0x0C002000
      asm.addi(7, 7, 0x80),        # x7 = 0x0C002080 (SENABLE hart0)
      asm.addi(6, 0, 2),           # x6 = bit 1 set
      asm.sw(6, 7, 0),             # senable = source 1

      asm.lui(8, 0xC201),          # x8 = 0x0C201000 (SPRORITY/SCALIM region)
      asm.sw(0, 8, 0),             # spriority threshold = 0
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x142, 0),     # x10 = scause
      asm.lui(11, 0xC201),         # x11 = 0x0C201000
      asm.lw(12, 11, 4),           # x12 = claim id from SCLAIM
      asm.sw(12, 11, 4),           # complete claim id to SCLAIM
      asm.jal(0, 0)
    ]

    cpu.load_program(main_program, 0)
    cpu.load_program(trap_handler, 0x300)
    cpu.reset!
    cpu.run_cycles(main_program.length + (pipeline ? 20 : 8))
    cpu.set_plic_sources(source1: 1)
    cpu.run_cycles(pipeline ? 40 : 20)

    expect(cpu.read_reg(12)).to eq(1)
    expect(cpu.read_reg(10)).to eq(0x80000009)
  end
end

RSpec.describe 'RISC-V PLIC supervisor MMIO harness', timeout: 30 do
  backends = {
    jit: RHDL::Codegen::IR::IR_JIT_AVAILABLE,
    interpreter: RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE,
    compiler: RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  }

  backends.each do |backend, available|
    context "single-cycle on #{backend}" do
      let(:cpu) { RHDL::Examples::RISCV::IRHarness.new(mem_size: 4096, backend: backend, allow_fallback: false) }

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'PLIC supervisor MMIO compatibility', pipeline: false
    end

    context "pipeline on #{backend}" do
      let(:cpu) do
        RHDL::Examples::RISCV::Pipeline::IRHarness.new(
          "plic_supervisor_pipeline_#{backend}",
          backend: backend,
          allow_fallback: false
        )
      end

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'PLIC supervisor MMIO compatibility', pipeline: true
    end
  end
end
