# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/riscv/utilities/runners/headless_runner'

def int_env(name, default)
  raw = ENV[name]
  return default if raw.nil? || raw.strip.empty?

  Integer(raw, 0)
rescue ArgumentError
  default
end

LINUX_KERNEL_PATH = File.expand_path('../../../examples/riscv/software/bin/linux_kernel.bin', __dir__)
LINUX_DTB_PATH = ENV.fetch(
  'RHDL_LINUX_DTB_PATH',
  File.expand_path('../../../examples/riscv/software/bin/linux_virt.dtb', __dir__)
)
LINUX_INITRAMFS_PATH = ENV.fetch(
  'RHDL_LINUX_INITRAMFS_PATH',
  File.expand_path('../../../examples/riscv/software/bin/linux_initramfs.cpio', __dir__)
)
LINUX_LOAD_ADDR = int_env('RHDL_LINUX_LOAD_ADDR', 0x8040_0000)
LINUX_STEP_CYCLES = int_env('RHDL_LINUX_STEP_CYCLES', 200_000)
LINUX_NO_UART_PROGRESS_CYCLES = int_env('RHDL_LINUX_NO_UART_PROGRESS_CYCLES', 80_000_000)
LINUX_LIVE_UART = ENV.fetch('RHDL_LINUX_LIVE_UART', '1') != '0'
LINUX_FAIL_FAST_MARKERS = begin
  raw = ENV.fetch(
    'RHDL_LINUX_FAIL_FAST_MARKERS',
    'Kernel panic - not syncing:,VFS: Unable to mount root fs,Unable to mount root fs,No working init found'
  )
  raw.split(',').map(&:strip).reject(&:empty?)
end.freeze

LINUX_INIT_MARKERS = begin
  raw = ENV.fetch(
    'RHDL_LINUX_INIT_MARKERS',
    'Run /sbin/init as init process,Run /init as init process,Please press Enter to activate this console.'
  )
  markers = raw.split(',').map(&:strip).reject(&:empty?)
  markers.empty? ? ['Run /sbin/init as init process'] : markers
end.freeze

LINUX_SHELL_MARKERS = begin
  raw = ENV.fetch(
    'RHDL_LINUX_SHELL_MARKERS',
    'rhdl-sh$,/ #,# '
  )
  markers = raw.split(',').map(&:strip).reject(&:empty?)
  markers.empty? ? ['# '] : markers
end.freeze

LINUX_BOOT_BACKEND = RHDL::Sim::Native::IR::COMPILER_AVAILABLE ? :compile : nil

RSpec.shared_examples 'linux boot milestones' do |core:, boot_cycles:, milestone_cycles:, timeout_seconds:|
  let(:runner) { RHDL::Examples::RISCV::HeadlessRunner.new(mode: :ir, sim: LINUX_BOOT_BACKEND, core: core) }
  let(:cpu) { runner.cpu }

  def pump_uart(cpu, stream_state)
    bytes = cpu.uart_tx_bytes
    total = bytes.length
    advanced = false

    if total > stream_state[:cursor]
      delta = bytes[stream_state[:cursor]...total].pack('C*')
      stream_state[:cursor] = total
      stream_state[:output] << delta
      advanced = true
      if LINUX_LIVE_UART
        $stderr.print(delta)
        $stderr.flush
      end
    end

    [stream_state[:output], advanced]
  end

  def assert_no_fail_fast_marker!(output)
    marker = LINUX_FAIL_FAST_MARKERS.find { |m| output.include?(m) }
    return if marker.nil?

    raise "Linux boot hit fail-fast marker #{marker.inspect}"
  end

  def wait_for_uart_text(cpu, text, max_cycles:, chunk:, stream_state:)
    ran = 0
    no_progress = 0
    loop do
      output, advanced = pump_uart(cpu, stream_state)
      assert_no_fail_fast_marker!(output)
      no_progress = 0 if advanced
      return output if output.include?(text)
      raise "Timed out waiting for UART text #{text.inspect} after #{ran} cycles" if ran >= max_cycles

      step = [chunk, max_cycles - ran].min
      cpu.run_cycles(step)
      ran += step
      no_progress += step unless advanced
      if no_progress >= LINUX_NO_UART_PROGRESS_CYCLES
        raise "No UART progress for #{no_progress} cycles while waiting for #{text.inspect}"
      end
    end
  end

  def wait_for_uart_any(cpu, markers, max_cycles:, chunk:, stream_state:)
    ran = 0
    no_progress = 0
    loop do
      output, advanced = pump_uart(cpu, stream_state)
      assert_no_fail_fast_marker!(output)
      no_progress = 0 if advanced
      marker = markers.find { |m| output.include?(m) }
      return [output, marker] if marker
      raise "Timed out waiting for UART milestones #{markers.inspect} after #{ran} cycles" if ran >= max_cycles

      step = [chunk, max_cycles - ran].min
      cpu.run_cycles(step)
      ran += step
      no_progress += step unless advanced
      if no_progress >= LINUX_NO_UART_PROGRESS_CYCLES
        raise "No UART progress for #{no_progress} cycles while waiting for milestones #{markers.inspect}"
      end
    end
  end

  it 'reaches Linux version, init, and shell milestones when Linux artifacts are available',
     :slow, timeout: timeout_seconds do
    skip 'Compiler backend unavailable for Linux boot spec' if LINUX_BOOT_BACKEND.nil?
    skip "Missing Linux kernel artifact at #{LINUX_KERNEL_PATH}" unless File.file?(LINUX_KERNEL_PATH)
    skip "Missing Linux initramfs artifact at #{LINUX_INITRAMFS_PATH}" unless File.file?(LINUX_INITRAMFS_PATH)
    skip "Missing Linux DTB artifact at #{LINUX_DTB_PATH}" unless File.file?(LINUX_DTB_PATH)
    skip 'Native RISC-V runner unavailable' unless runner.native? && cpu.sim.runner_kind == :riscv

    runner.load_linux(
      kernel: LINUX_KERNEL_PATH,
      initramfs: LINUX_INITRAMFS_PATH,
      dtb: LINUX_DTB_PATH,
      kernel_addr: LINUX_LOAD_ADDR
    )

    stream_state = { cursor: 0, output: +'' }
    boot_output = wait_for_uart_text(
      cpu,
      'Linux version',
      max_cycles: boot_cycles,
      chunk: LINUX_STEP_CYCLES,
      stream_state: stream_state
    )
    init_output, init_marker = wait_for_uart_any(
      cpu,
      LINUX_INIT_MARKERS,
      max_cycles: milestone_cycles,
      chunk: LINUX_STEP_CYCLES,
      stream_state: stream_state
    )
    cpu.uart_receive_bytes([0x0A]) if init_marker.include?('Please press Enter')
    shell_output, shell_marker = wait_for_uart_any(
      cpu,
      LINUX_SHELL_MARKERS,
      max_cycles: milestone_cycles,
      chunk: LINUX_STEP_CYCLES,
      stream_state: stream_state
    )

    expect(boot_output).to include('Linux version')
    expect(init_output).to include(init_marker)
    expect(shell_output).to include(shell_marker)
  ensure
    $stderr.puts if LINUX_LIVE_UART
  end
end

RSpec.describe 'RISC-V Linux boot milestones over UART (single-cycle)' do
  include_examples 'linux boot milestones',
                   core: :single,
                   boot_cycles: int_env('RHDL_LINUX_BOOT_CYCLES', 80_000_000),
                   milestone_cycles: int_env('RHDL_LINUX_MILESTONE_CYCLES', 400_000_000),
                   timeout_seconds: 600
end

RSpec.describe 'RISC-V Linux boot milestones over UART (pipeline)' do
  include_examples 'linux boot milestones',
                   core: :pipeline,
                   boot_cycles: int_env('RHDL_LINUX_BOOT_CYCLES_PIPELINE', 400_000_000),
                   milestone_cycles: int_env('RHDL_LINUX_MILESTONE_CYCLES_PIPELINE', 2_000_000_000),
                   timeout_seconds: 1800
end
