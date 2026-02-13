# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'
require_relative '../../../../../examples/riscv/hdl/register_file'

module RHDL
  module Spec
    module IRJitMemoryPorts
      class SyncReadProbe < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory

        input :clk
        input :rst
        input :we
        input :addr, width: 2
        input :din, width: 8
        output :dout, width: 8

        memory :mem, depth: 4, width: 8
        sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
        sync_read :dout, from: :mem, clock: :clk, addr: :addr
      end
    end
  end
end

RSpec.describe 'IR JIT memory ports' do
  def create_jit(ir)
    ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
    RHDL::Codegen::IR::IrSimulator.new(ir_json, backend: :jit, allow_fallback: false)
  end

  def step(sim, inputs)
    inputs.each { |k, v| sim.poke(k.to_s, v) }
    sim.poke('clk', 0)
    sim.evaluate

    inputs.each { |k, v| sim.poke(k.to_s, v) }
    sim.poke('clk', 1)
    sim.tick

    inputs.each { |k, v| sim.poke(k.to_s, v) }
    sim.poke('clk', 0)
    sim.evaluate
  end

  before do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  it 'commits memory sync_write ports for the RISC-V register file' do
    sim = create_jit(RHDL::Examples::RISCV::RegisterFile.to_flat_ir)
    sim.reset

    # Write x1 = 0x1234_5678
    step(sim, {
      rst: 0,
      rs1_addr: 0,
      rs2_addr: 0,
      rd_addr: 1,
      rd_data: 0x1234_5678,
      rd_we: 1,
      forwarding_en: 0,
      debug_raddr: 1
    })

    sim.poke('rd_we', 0)
    sim.evaluate
    expect(sim.peek('debug_x1')).to eq(0x1234_5678)
    expect(sim.peek('debug_rdata')).to eq(0x1234_5678)
  end

  it 'updates signals driven by sync_read_ports on clock edges' do
    sim = create_jit(RHDL::Spec::IRJitMemoryPorts::SyncReadProbe.to_flat_ir)
    sim.reset

    step(sim, { rst: 0, we: 1, addr: 2, din: 0xAB })
    step(sim, { rst: 0, we: 0, addr: 2, din: 0 })

    expect(sim.peek('dout')).to eq(0xAB)
  end
end
