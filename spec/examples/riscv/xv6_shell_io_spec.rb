# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'

RSpec.shared_examples 'xv6 shell UART I/O' do |pipeline:, boot_cycles:, timeout_seconds:|
  let(:kernel_path) { File.expand_path('../../../examples/riscv/software/bin/kernel.bin', __dir__) }
  let(:fs_path) { File.expand_path('../../../examples/riscv/software/bin/fs.img', __dir__) }

  def with_fast_boot_patch(kernel_bytes)
    patched = kernel_bytes.dup
    (0..(patched.bytesize - 4)).step(4) do |offset|
      word = patched.byteslice(offset, 4).unpack1('V')
      opcode = word & 0x7F
      next unless opcode == 0x37

      imm20 = (word >> 12) & 0xFFFFF
      next unless imm20 == 0x88000

      rd = (word >> 7) & 0x1F
      new_word = (0x80200 << 12) | (rd << 7) | 0x37
      patched.setbyte(offset + 0, new_word & 0xFF)
      patched.setbyte(offset + 1, (new_word >> 8) & 0xFF)
      patched.setbyte(offset + 2, (new_word >> 16) & 0xFF)
      patched.setbyte(offset + 3, (new_word >> 24) & 0xFF)
    end
    patched
  end

  def wait_for_uart_text(cpu, text, max_cycles:, chunk:)
    ran = 0
    loop do
      output = cpu.uart_tx_bytes.pack('C*')
      return output if output.include?(text)
      raise "Timed out waiting for UART text #{text.inspect} after #{ran} cycles" if ran >= max_cycles

      step = [chunk, max_cycles - ran].min
      cpu.run_cycles(step)
      ran += step
    end
  end

  it 'boots xv6 shell and executes an echo command over UART', :slow, timeout: timeout_seconds do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
    skip "Missing kernel artifact at #{kernel_path}" unless File.file?(kernel_path)
    skip "Missing fs artifact at #{fs_path}" unless File.file?(fs_path)

    expect(cpu.native?).to eq(true)
    expect(cpu.sim.runner_kind).to eq(:riscv)

    kernel_bytes = with_fast_boot_patch(File.binread(kernel_path))
    fs_bytes = File.binread(fs_path)

    cpu.reset!
    cpu.clear_uart_tx_bytes
    cpu.sim.runner_load_rom(kernel_bytes, 0x8000_0000)
    cpu.sim.runner_riscv_load_disk(fs_bytes, 0)
    cpu.write_pc(0x8000_0000)

    wait_for_uart_text(cpu, 'init: starting sh', max_cycles: boot_cycles, chunk: 200_000)
    wait_for_uart_text(cpu, '$ ', max_cycles: 6_000_000, chunk: 50_000)

    cpu.clear_uart_tx_bytes
    cpu.uart_receive_text("echo rhdl_io_ok\n")

    output = wait_for_uart_text(cpu, 'rhdl_io_ok', max_cycles: 4_000_000, chunk: 20_000)
    expect(output).to include('rhdl_io_ok')
  end
end

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  let(:cpu) { described_class.new(mem_size: 4096, backend: :jit, allow_fallback: false) }

  include_examples 'xv6 shell UART I/O', pipeline: false, boot_cycles: 25_000_000, timeout_seconds: 240
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  let(:cpu) { described_class.new('xv6_shell_pipeline', backend: :jit, allow_fallback: false) }

  include_examples 'xv6 shell UART I/O', pipeline: true, boot_cycles: 35_000_000, timeout_seconds: 360
end
