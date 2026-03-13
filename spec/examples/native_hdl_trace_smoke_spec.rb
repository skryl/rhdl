# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'

require_relative '../../examples/riscv/utilities/assembler'
require_relative '../../examples/riscv/utilities/runners/verilator_runner'
require_relative '../../examples/riscv/utilities/runners/arcilator_runner'
require_relative '../../examples/apple2/utilities/runners/verilator_runner'
require_relative '../../examples/apple2/utilities/runners/arcilator_runner'
require_relative '../../examples/mos6502/utilities/runners/verilator_runner'
require_relative '../../examples/gameboy/utilities/runners/verilator_runner'
require_relative '../../examples/gameboy/utilities/runners/arcilator_runner'
require_relative '../../examples/gameboy/utilities/runners/headless_runner'

RSpec.describe 'Native HDL trace smoke', :slow, timeout: 300 do
  def expect_trace_smoke(runner)
    sim = runner.sim
    expect(sim.trace_supported?).to be(true)

    sim.trace_all_signals
    sim.trace_start
    yield runner, sim
    sim.trace_stop

    vcd = sim.trace_to_vcd
    expect(sim.trace_change_count).to be > 0
    expect(vcd).to include('$timescale')
    expect(vcd).to include('$var wire')
    expect(vcd).to include('#')
  ensure
    runner&.close if runner&.respond_to?(:close)
  end

  it 'traces RISC-V Verilator' do
    skip 'Verilator not available' unless HdlToolchain.verilator_available?

    asm = RHDL::Examples::RISCV::Assembler
    runner = RHDL::Examples::RISCV::VerilogRunner.new(mem_size: 4096)
    runner.load_program([asm.addi(1, 0, 42), asm.addi(2, 1, 1)])

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset!
      2.times do
        cpu.run_cycles(1)
        sim.trace_capture
      end
    end
  end

  it 'traces RISC-V Arcilator' do
    skip 'Arcilator not available' unless HdlToolchain.arcilator_available?

    asm = RHDL::Examples::RISCV::Assembler
    runner = RHDL::Examples::RISCV::ArcilatorRunner.new(mem_size: 4096, jit: false)
    runner.load_program([asm.addi(1, 0, 42), asm.addi(2, 1, 1)])

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset!
      2.times do
        cpu.run_cycles(1)
        sim.trace_capture
      end
    end
  end

  it 'traces Apple II Verilator' do
    skip 'Verilator not available' unless HdlToolchain.verilator_available?

    runner = RHDL::Examples::Apple2::VerilogRunner.new(sub_cycles: 2)

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset
      2.times do
        cpu.run_steps(1)
        sim.trace_capture
      end
    end
  end

  it 'traces Apple II Arcilator' do
    skip 'Arcilator not available' unless HdlToolchain.arcilator_available?

    runner = RHDL::Examples::Apple2::ArcilatorRunner.new(sub_cycles: 2)

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset
      2.times do
        cpu.run_steps(1)
        sim.trace_capture
      end
    end
  end

  it 'traces MOS6502 Verilator' do
    skip 'Verilator not available' unless HdlToolchain.verilator_available?

    runner = RHDL::Examples::MOS6502::VerilogRunner.new
    runner.load_program([0xA9, 0x42, 0x00], 0x8000)

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset
      3.times do
        cpu.run_cycles(1)
        sim.trace_capture
      end
    end
  end

  it 'traces Game Boy Verilator' do
    skip 'Verilator not available' unless HdlToolchain.verilator_available?

    runner = RHDL::Examples::GameBoy::VerilogRunner.new
    runner.load_rom(RHDL::Examples::GameBoy::HeadlessRunner.create_test_rom)

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset
      4.times do
        cpu.run_steps(1)
        sim.trace_capture
      end
    end
  end

  it 'traces Game Boy Arcilator' do
    skip 'Arcilator not available' unless HdlToolchain.arcilator_available?

    runner = RHDL::Examples::GameBoy::ArcilatorRunner.new
    runner.load_rom(RHDL::Examples::GameBoy::HeadlessRunner.create_test_rom)

    expect_trace_smoke(runner) do |cpu, sim|
      cpu.reset
      4.times do
        cpu.run_steps(1)
        sim.trace_capture
      end
    end
  end
end
