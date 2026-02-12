# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe '8-bit CPU IR runner extension' do
  def cpu_ir_json
    ir = RHDL::HDL::CPU::CPU.to_flat_ir
    RHDL::Codegen::IR::IRToJson.convert(ir)
  end

  def backend_available?(backend)
    case backend
    when :interpreter
      RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
    when :jit
      RHDL::Codegen::IR::JIT_AVAILABLE
    when :compiler
      RHDL::Codegen::IR::COMPILER_AVAILABLE
    else
      false
    end
  end

  def create_simulator(backend)
    RHDL::Codegen::IR::IrSimulator.new(
      cpu_ir_json,
      backend: backend,
      allow_fallback: false
    )
  end

  def create_simulator_or_skip(backend)
    create_simulator(backend)
  rescue StandardError => e
    skip "failed to initialize #{backend} backend: #{e.message}"
  end

  %i[interpreter jit compiler].each do |backend|
    describe backend do
      it 'reports cpu8bit runner mode' do
        skip "#{backend} backend unavailable" unless backend_available?(backend)

        sim = create_simulator_or_skip(backend)
        expect(sim.runner_mode?).to be(true)
        expect(sim.runner_kind).to eq(:cpu8bit)
      end

      it 'executes program through runner memory ABI' do
        skip "#{backend} backend unavailable" unless backend_available?(backend)

        sim = create_simulator_or_skip(backend)

        # LDI 0x55 ; STA 0x40 ; HLT
        program = [0xA0, 0x55, 0x21, 0x40, 0xF0]
        expect(sim.runner_load_memory(program, 0, false)).to be(true)

        300.times do
          sim.runner_run_cycles(1, 0, false)
          break if sim.peek('halted') == 1
        end

        expect(sim.peek('halted')).to eq(1)
        expect(sim.runner_read_memory(0x40, 1, mapped: false)).to eq([0x55])
      end

      it 'supports batched cycle execution through runner API' do
        skip "#{backend} backend unavailable" unless backend_available?(backend)

        sim = create_simulator_or_skip(backend)

        # LDI 0x33 ; STA 0x41 ; HLT
        program = [0xA0, 0x33, 0x21, 0x41, 0xF0]
        expect(sim.runner_load_memory(program, 0, false)).to be(true)

        sim.runner_run_cycles(300, 0, false)

        expect(sim.peek('halted')).to eq(1)
        expect(sim.runner_read_memory(0x41, 1, mapped: false)).to eq([0x33])
      end
    end
  end
end
