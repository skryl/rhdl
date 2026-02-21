require 'spec_helper'
require_relative '../../../examples/riscv/hdl/csr_file'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/hdl/plic'
require_relative '../../../examples/riscv/hdl/constants'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe RHDL::Examples::RISCV::Plic do
  let(:plic) { described_class.new('linux_plic') }

  def drive(clk:, rst:, addr: 0, write_data: 0, mem_read: 0, mem_write: 0, source1: 0, source10: 0)
    plic.set_input(:clk, clk)
    plic.set_input(:rst, rst)
    plic.set_input(:addr, addr)
    plic.set_input(:write_data, write_data)
    plic.set_input(:mem_read, mem_read)
    plic.set_input(:mem_write, mem_write)
    plic.set_input(:funct3, RHDL::Examples::RISCV::Funct3::WORD)
    plic.set_input(:source1, source1)
    plic.set_input(:source10, source10)
    plic.propagate
  end

  def reset_plic
    drive(clk: 0, rst: 1)
    drive(clk: 1, rst: 1)
    drive(clk: 0, rst: 0)
  end

  def tick(source1: 0, source10: 0, addr: 0, write_data: 0, mem_read: 0, mem_write: 0)
    drive(clk: 0, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write, source1: source1, source10: source10)
    drive(clk: 1, rst: 0, addr: addr, write_data: write_data, mem_read: mem_read, mem_write: mem_write, source1: source1, source10: source10)
  end

  def write_word(addr, value)
    tick(addr: addr, write_data: value, mem_write: 1)
    drive(clk: 0, rst: 0)
  end

  def read_word(addr)
    drive(clk: 0, rst: 0, addr: addr, mem_read: 1)
    plic.get_output(:read_data)
  end

  before do
    reset_plic
  end

  it 'supports supervisor-context enable/threshold/claim aliases used in Linux trap setup' do
    write_word(described_class::PRIORITY_1_ADDR, 1)
    write_word(described_class::SENABLE_ADDR, 0b10)
    write_word(described_class::STHRESHOLD_ADDR, 0)
    tick(source1: 1)

    expect(read_word(described_class::PENDING_ADDR)).to eq(0b10)
    expect(plic.get_output(:irq_external)).to eq(1)

    drive(clk: 0, rst: 0, addr: described_class::SCLAIM_COMPLETE_ADDR, mem_read: 1)
    expect(plic.get_output(:read_data)).to eq(1)
    drive(clk: 1, rst: 0, addr: described_class::SCLAIM_COMPLETE_ADDR, mem_read: 1)
    drive(clk: 0, rst: 0)

    expect(read_word(described_class::PENDING_ADDR)).to eq(0)
    write_word(described_class::SCLAIM_COMPLETE_ADDR, 1)
    tick(source1: 1)
    expect(read_word(described_class::PENDING_ADDR)).to eq(0b10)
  end
end

RSpec.shared_examples 'linux csr/mmio native compatibility' do |pipeline:|
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  def run_program(cpu, program, pipeline:, extra_cycles: 0)
    cpu.load_program(program, 0)
    cpu.reset!
    cpu.run_cycles(program.length + (pipeline ? 30 : 12) + extra_cycles)
  end

  it 'reports Linux-compatible machine identification CSRs' do
    program = [
      asm.csrrs(10, 0x301, 0),  # x10 = misa
      asm.addi(1, 0, 0),        # x1 = 0
      asm.csrrw(0, 0x301, 1),   # attempt write misa
      asm.csrrs(11, 0x301, 0),  # x11 = misa again
      asm.csrrs(12, 0xF14, 0),  # x12 = mhartid
      asm.csrrs(13, 0xF11, 0),  # x13 = mvendorid
      asm.nop
    ]

    run_program(cpu, program, pipeline: pipeline)

    expect(cpu.read_reg(10)).to eq(RHDL::Examples::RISCV::CSRFile::MISA_VALUE)
    expect(cpu.read_reg(11)).to eq(RHDL::Examples::RISCV::CSRFile::MISA_VALUE)
    expect(cpu.read_reg(12)).to eq(0)
    expect(cpu.read_reg(13)).to eq(0)
  end

  it 'handles delegated external interrupts through supervisor PLIC MMIO addresses' do
    main_program = [
      asm.addi(1, 0, 0x300),  # stvec = 0x300
      asm.csrrw(0, 0x105, 1),

      asm.lui(2, 0x1),
      asm.addi(2, 2, -2048),  # x2 = 0x800 (MEIP)
      asm.csrrw(0, 0x303, 2), # mideleg = MEIP
      asm.csrrw(0, 0x104, 2), # sie = MEIP
      asm.addi(2, 0, 0x2),    # sstatus.SIE
      asm.csrrw(0, 0x100, 2),

      asm.lui(5, 0xC000),     # 0x0C000000
      asm.addi(6, 0, 1),
      asm.sw(6, 5, 4),        # priority[1] = 1

      asm.lui(7, 0xC002),     # 0x0C002000
      asm.addi(7, 7, 0x80),   # 0x0C002080
      asm.addi(6, 0, 2),      # enable source 1
      asm.sw(6, 7, 0),

      asm.lui(8, 0xC201),     # 0x0C201000
      asm.sw(0, 8, 0),        # threshold = 0
      asm.nop,
      asm.nop
    ]

    trap_handler = [
      asm.csrrs(10, 0x142, 0), # scause
      asm.lui(11, 0xC201),     # 0x0C201000
      asm.lw(12, 11, 4),       # sclaim
      asm.sw(12, 11, 4),       # scomplete
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

RSpec.describe 'RISC-V Linux CSR/MMIO compatibility', timeout: 30 do
  backends = {
    jit: RHDL::Codegen::IR::IR_JIT_AVAILABLE,
    interpreter: RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
  }
  backends[:compiler] = RHDL::Codegen::IR::IR_COMPILER_AVAILABLE if ENV['RHDL_LINUX_INCLUDE_COMPILER'] == '1'

  backends.each do |backend, available|
    context "single-cycle on #{backend}" do
      let(:cpu) { RHDL::Examples::RISCV::IRHarness.new(mem_size: 4096, backend: backend, allow_fallback: false) }

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'linux csr/mmio native compatibility', pipeline: false
    end

    context "pipeline on #{backend}" do
      let(:cpu) do
        RHDL::Examples::RISCV::Pipeline::IRHarness.new(
          "linux_csr_mmio_pipeline_#{backend}",
          backend: backend,
          allow_fallback: false
        )
      end

      before(:each) do
        skip "#{backend} backend not available" unless available
      end

      include_examples 'linux csr/mmio native compatibility', pipeline: true
    end
  end
end
