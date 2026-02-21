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
  File.expand_path('../../../examples/riscv/software/bin/rhdl_riscv_virt.dtb', __dir__)
)
LINUX_LOAD_ADDR = int_env('RHDL_LINUX_LOAD_ADDR', 0x8020_0000)
LINUX_BOOT_CYCLES = int_env('RHDL_LINUX_BOOT_CYCLES', 80_000_000)
LINUX_MILESTONE_CYCLES = int_env('RHDL_LINUX_MILESTONE_CYCLES', 120_000_000)
LINUX_STEP_CYCLES = int_env('RHDL_LINUX_STEP_CYCLES', 200_000)

LINUX_PROMPT_MARKERS = begin
  raw = ENV.fetch(
    'RHDL_LINUX_PROMPT_MARKERS',
    'Machine model:,earlycon:,printk:,Kernel panic - not syncing:,Run /sbin/init,login:,Please press Enter to activate this console.,/ #,# '
  )
  markers = raw.split(',').map(&:strip).reject(&:empty?)
  markers.empty? ? ['Machine model:'] : markers
end.freeze

LINUX_BOOT_BACKEND = if RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
                       :compile
                     elsif RHDL::Codegen::IR::IR_JIT_AVAILABLE
                       :jit
                     elsif RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
                       :interpret
                     end

RSpec.describe 'RISC-V Linux boot milestones over UART', :slow, timeout: 600 do
  let(:runner) { RHDL::Examples::RISCV::HeadlessRunner.new(mode: :ir, sim: LINUX_BOOT_BACKEND) }
  let(:cpu) { runner.cpu }

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

  def wait_for_uart_any(cpu, markers, max_cycles:, chunk:)
    ran = 0
    loop do
      output = cpu.uart_tx_bytes.pack('C*')
      marker = markers.find { |m| output.include?(m) }
      return [output, marker] if marker
      raise "Timed out waiting for UART milestones #{markers.inspect} after #{ran} cycles" if ran >= max_cycles

      step = [chunk, max_cycles - ran].min
      cpu.run_cycles(step)
      ran += step
    end
  end

  it 'reaches Linux version and a follow-on UART milestone when Linux artifacts are available' do
    skip 'No native IR backend available for Linux boot spec' if LINUX_BOOT_BACKEND.nil?
    skip "Missing Linux kernel artifact at #{LINUX_KERNEL_PATH}" unless File.file?(LINUX_KERNEL_PATH)
    skip "Missing Linux DTB artifact at #{LINUX_DTB_PATH}" unless File.file?(LINUX_DTB_PATH)
    skip 'Native RISC-V runner unavailable' unless runner.native? && cpu.sim.runner_kind == :riscv

    runner.load_linux(kernel: LINUX_KERNEL_PATH, dtb: LINUX_DTB_PATH, kernel_addr: LINUX_LOAD_ADDR)

    boot_output = wait_for_uart_text(cpu, 'Linux version', max_cycles: LINUX_BOOT_CYCLES, chunk: LINUX_STEP_CYCLES)
    milestone_output, milestone = wait_for_uart_any(
      cpu,
      LINUX_PROMPT_MARKERS,
      max_cycles: LINUX_MILESTONE_CYCLES,
      chunk: LINUX_STEP_CYCLES
    )

    expect(boot_output).to include('Linux version')
    expect(milestone_output).to include(milestone)
  end
end
