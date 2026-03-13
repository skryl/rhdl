# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/runners/headless_runner'

AOT_COMPILER_ENV_FLAG = 'RHDL_IR_COMPILER_AOT'.freeze

RSpec.shared_examples 'xv6 shell UART I/O' do |pipeline:, backend_id:, boot_cycles:, prompt_cycles:, timeout_seconds:, boot_marker: 'init: starting sh', require_shell: true|
  let(:kernel_path) { File.expand_path('../../../examples/riscv/software/bin/xv6_kernel.bin', __dir__) }
  let(:fs_path) { File.expand_path('../../../examples/riscv/software/bin/xv6_fs.img', __dir__) }

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

  def run_target_cycles(target, cycles)
    if target.respond_to?(:run_cycles)
      target.run_cycles(cycles)
    elsif target.respond_to?(:run_steps)
      target.run_steps(cycles)
    else
      raise ArgumentError, "Target does not support cycle stepping: #{target.class}"
    end
  end

  def uart_tx_bytes_for(target)
    return target.uart_tx_bytes if target.respond_to?(:uart_tx_bytes)
    return target.cpu.uart_tx_bytes if target.respond_to?(:cpu) && target.cpu.respond_to?(:uart_tx_bytes)

    raise ArgumentError, "Target does not expose UART TX bytes: #{target.class}"
  end

  def clear_uart_tx_bytes_for(target)
    if target.respond_to?(:clear_uart_tx_bytes)
      target.clear_uart_tx_bytes
      return
    end
    if target.respond_to?(:cpu) && target.cpu.respond_to?(:clear_uart_tx_bytes)
      target.cpu.clear_uart_tx_bytes
      return
    end

    raise ArgumentError, "Target does not expose UART clear API: #{target.class}"
  end

  def uart_receive_text_for(target, text)
    if target.respond_to?(:uart_receive_text)
      target.uart_receive_text(text)
      return
    end
    if target.respond_to?(:cpu) && target.cpu.respond_to?(:uart_receive_text)
      target.cpu.uart_receive_text(text)
      return
    end

    raise ArgumentError, "Target does not expose UART RX API: #{target.class}"
  end

  def load_xv6_for_target(target, kernel_path:, fs_path:)
    if target.respond_to?(:load_xv6)
      target.load_xv6(kernel: kernel_path, fs: fs_path, pc: 0x8000_0000)
      return
    end

    kernel_bytes = with_fast_boot_patch(File.binread(kernel_path))
    fs_bytes = File.binread(fs_path)

    target.reset!
    clear_uart_tx_bytes_for(target)
    target.sim.runner_load_rom(kernel_bytes, 0x8000_0000)
    target.sim.runner_riscv_load_disk(fs_bytes, 0)
    target.write_pc(0x8000_0000)
  end

  def wait_for_uart_text(target, text, max_cycles:, chunk:)
    ran = 0
    loop do
      output = uart_tx_bytes_for(target).pack('C*')
      return output if output.include?(text)
      raise "Timed out waiting for UART text #{text.inspect} after #{ran} cycles" if ran >= max_cycles

      step = [chunk, max_cycles - ran].min
      run_target_cycles(target, step)
      ran += step
    end
  end

  description = if require_shell
                  "boots xv6 shell and executes an echo command over UART (#{backend_id})"
                else
                  "reaches xv6 boot banner over UART using batched execution (#{backend_id})"
                end

  it description, :slow, timeout: timeout_seconds do
    case backend_id
    when :jit
      skip 'IR JIT not available' unless RHDL::Sim::Native::IR::JIT_AVAILABLE
    when :compiler
      skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
    when :compiler_aot
      skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
      skip "IR compiler AOT mode not enabled (set #{AOT_COMPILER_ENV_FLAG}=1 and build ir_compiler with --features aot)" unless ENV[AOT_COMPILER_ENV_FLAG] == '1'
    when :verilator
      skip 'Verilator not available' unless HdlToolchain.verilator_available?
    when :arcilator
      skip 'Arcilator not available' unless HdlToolchain.arcilator_available?
    else
      raise ArgumentError, "Unsupported backend #{backend_id.inspect}"
    end

    skip "Missing kernel artifact at #{kernel_path}" unless File.file?(kernel_path)
    skip "Missing fs artifact at #{fs_path}" unless File.file?(fs_path)

    expect(cpu.native?).to eq(true)
    expect(cpu.sim.runner_kind).to eq(:riscv) if cpu.respond_to?(:sim) && cpu.sim.respond_to?(:runner_kind)
    expect(cpu.sim.compiled?).to eq(true) if [:compiler, :compiler_aot].include?(backend_id)

    load_xv6_for_target(cpu, kernel_path: kernel_path, fs_path: fs_path)

    boot_output = wait_for_uart_text(cpu, boot_marker, max_cycles: boot_cycles, chunk: 200_000)
    expect(boot_output).to include(boot_marker)

    unless require_shell
      # HDL backends use the same batched runner API but currently only guarantee
      # boot-banner coverage in this spec; full shell parity is tracked separately.
      run_target_cycles(cpu, 1_000_000)
      expect(uart_tx_bytes_for(cpu).pack('C*')).to include(boot_marker)
      next
    end

    wait_for_uart_text(cpu, '$ ', max_cycles: prompt_cycles, chunk: 50_000)

    clear_uart_tx_bytes_for(cpu)
    uart_receive_text_for(cpu, "echo rhdl_io_ok\n")

    output = wait_for_uart_text(cpu, 'rhdl_io_ok', max_cycles: 4_000_000, chunk: 20_000)
    expect(output).to include('rhdl_io_ok')
  end
end

XV6_SINGLE_BACKEND_CASES = [
  { id: :jit, harness_backend: :jit, boot_cycles: 25_000_000, prompt_cycles: 6_000_000, timeout_seconds: 240, boot_marker: 'init: starting sh', require_shell: true },
  { id: :compiler, harness_backend: :compiler, boot_cycles: 25_000_000, prompt_cycles: 6_000_000, timeout_seconds: 300, boot_marker: 'init: starting sh', require_shell: true },
  { id: :compiler_aot, harness_backend: :compiler, boot_cycles: 25_000_000, prompt_cycles: 6_000_000, timeout_seconds: 300, boot_marker: 'init: starting sh', require_shell: true }
].freeze

XV6_SINGLE_HDL_BACKEND_CASES = [
  { id: :verilator, mode: :verilog, boot_cycles: 30_000_000, prompt_cycles: 6_000_000, timeout_seconds: 300, boot_marker: 'init: starting sh', require_shell: true },
  { id: :arcilator, mode: :circt, boot_cycles: 30_000_000, prompt_cycles: 6_000_000, timeout_seconds: 300, boot_marker: 'init: starting sh', require_shell: true }
].freeze

XV6_PIPELINE_BACKEND_CASES = [
  { id: :jit, harness_backend: :jit, boot_cycles: 200_000_000, prompt_cycles: 40_000_000, timeout_seconds: 900, boot_marker: 'init: starting sh', require_shell: true },
  { id: :compiler, harness_backend: :compiler, boot_cycles: 200_000_000, prompt_cycles: 40_000_000, timeout_seconds: 900, boot_marker: 'init: starting sh', require_shell: true },
  { id: :compiler_aot, harness_backend: :compiler, boot_cycles: 200_000_000, prompt_cycles: 40_000_000, timeout_seconds: 900, boot_marker: 'init: starting sh', require_shell: true }
].freeze

RSpec.describe RHDL::Examples::RISCV::IRHarness do
  XV6_SINGLE_BACKEND_CASES.each do |test_case|
    context "backend #{test_case[:id]}" do
      let(:backend) { test_case[:harness_backend] }
      let(:cpu) { described_class.new(mem_size: 4096, backend: backend) }

      include_examples 'xv6 shell UART I/O',
                       pipeline: false,
                       backend_id: test_case[:id],
                       boot_cycles: test_case[:boot_cycles],
                       prompt_cycles: test_case[:prompt_cycles],
                       timeout_seconds: test_case[:timeout_seconds],
                       boot_marker: test_case[:boot_marker],
                       require_shell: test_case[:require_shell]
    end
  end
end

RSpec.describe RHDL::Examples::RISCV::Pipeline::IRHarness do
  XV6_PIPELINE_BACKEND_CASES.each do |test_case|
    context "backend #{test_case[:id]}" do
      let(:backend) { test_case[:harness_backend] }
      let(:cpu) { described_class.new("xv6_shell_pipeline_#{backend}", backend: backend) }

      include_examples 'xv6 shell UART I/O',
                       pipeline: true,
                       backend_id: test_case[:id],
                       boot_cycles: test_case[:boot_cycles],
                       prompt_cycles: test_case[:prompt_cycles],
                       timeout_seconds: test_case[:timeout_seconds],
                       boot_marker: test_case[:boot_marker],
                       require_shell: test_case[:require_shell]
    end
  end
end

RSpec.describe RHDL::Examples::RISCV::HeadlessRunner do
  XV6_SINGLE_HDL_BACKEND_CASES.each do |test_case|
    context "backend #{test_case[:id]}" do
      let(:cpu) do
        described_class.new(mode: test_case[:mode], core: :single)
      rescue LoadError, RuntimeError => e
        skip "HDL backend unavailable for #{test_case[:id]}: #{e.message}"
      end

      include_examples 'xv6 shell UART I/O',
                       pipeline: false,
                       backend_id: test_case[:id],
                       boot_cycles: test_case[:boot_cycles],
                       prompt_cycles: test_case[:prompt_cycles],
                       timeout_seconds: test_case[:timeout_seconds],
                       boot_marker: test_case[:boot_marker],
                       require_shell: test_case[:require_shell]
    end
  end
end
