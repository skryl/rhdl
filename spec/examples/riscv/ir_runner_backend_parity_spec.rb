require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe 'RISC-V IR runner backend parity', timeout: 30 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  backends = {
    jit: RHDL::Codegen::IR::IR_JIT_AVAILABLE,
    interpreter: RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE,
    compiler: RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  }

  backends.each do |backend, available|
    context "single-cycle on #{backend}" do
      let(:cpu) { RHDL::Examples::RISCV::IRHarness.new(mem_size: 4096, backend: backend, allow_fallback: false) }

      before do
        skip "#{backend} backend not available" unless available
      end

      it 'uses the native RISC-V runner and executes ADDI' do
        expect(cpu.native?).to eq(true)
        expect(cpu.sim.runner_kind).to eq(:riscv)

        cpu.load_program([asm.addi(1, 0, 42)])
        cpu.reset!
        cpu.run_cycles(1)

        expect(cpu.read_reg(1)).to eq(42)
      end

      it 'handles UART RX/TX through runner controls' do
        program = [
          asm.lui(1, 0x10000),
          asm.nop,
          asm.lb(3, 1, 0),
          asm.addi(2, 0, 0x41),
          asm.sb(2, 1, 0),
          asm.addi(2, 0, 0x42),
          asm.sb(2, 1, 0)
        ]

        cpu.load_program(program)
        cpu.reset!
        cpu.uart_receive_byte(0x55)
        cpu.run_cycles(program.length + 4)

        expect(cpu.read_reg(3)).to eq(0x55)
        expect(cpu.uart_tx_bytes).to eq([0x41, 0x42])
        cpu.clear_uart_tx_bytes
        expect(cpu.uart_tx_bytes).to eq([])
      end

      it 'loads and reads virtio disk bytes through runner memory spaces' do
        cpu.reset!
        cpu.load_virtio_disk([0x10, 0x20, 0x30, 0x40], offset: 512)
        expect(cpu.read_virtio_disk_byte(512)).to eq(0x10)
        expect(cpu.read_virtio_disk_byte(513)).to eq(0x20)
        expect(cpu.read_virtio_disk_byte(515)).to eq(0x40)
      end
    end

    context "pipeline on #{backend}" do
      let(:cpu) { RHDL::Examples::RISCV::Pipeline::IRHarness.new('backend_parity_pipeline', backend: backend, allow_fallback: false) }

      before do
        skip "#{backend} backend not available" unless available
      end

      it 'uses the native RISC-V runner and executes ADDI' do
        expect(cpu.native?).to eq(true)
        expect(cpu.sim.runner_kind).to eq(:riscv)

        cpu.load_program([asm.addi(1, 0, 42), asm.nop, asm.nop, asm.nop, asm.nop])
        cpu.reset!
        cpu.run_cycles(10)

        expect(cpu.read_reg(1)).to eq(42)
      end

      it 'handles UART RX/TX through runner controls' do
        program = [
          asm.lui(1, 0x10000),
          asm.nop,
          asm.lb(3, 1, 0),
          asm.addi(2, 0, 0x41),
          asm.sb(2, 1, 0),
          asm.addi(2, 0, 0x42),
          asm.sb(2, 1, 0),
          asm.nop,
          asm.nop,
          asm.nop,
          asm.nop
        ]

        cpu.load_program(program)
        cpu.reset!
        cpu.uart_receive_byte(0x55)
        cpu.run_cycles(program.length + 10)

        expect(cpu.read_reg(3)).to eq(0x55)
        expect(cpu.uart_tx_bytes).to eq([0x41, 0x42])
        cpu.clear_uart_tx_bytes
        expect(cpu.uart_tx_bytes).to eq([])
      end

      it 'loads and reads virtio disk bytes through runner memory spaces' do
        cpu.reset!
        cpu.load_virtio_disk([0x10, 0x20, 0x30, 0x40], offset: 512)
        expect(cpu.read_virtio_disk_byte(512)).to eq(0x10)
        expect(cpu.read_virtio_disk_byte(513)).to eq(0x20)
        expect(cpu.read_virtio_disk_byte(515)).to eq(0x40)
      end
    end
  end
end
