# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'rhdl/codegen'

module RHDL
  module SpecFixtures
    class IrInputFormatCounter < RHDL::Sim::Component
      input :clk
      input :rst
      input :en
      output :q, width: 4

      behavior do
        if rst
          q <= 0
        elsif en
          q <= q + 1
        end
      end
    end
  end
end

RSpec.describe 'IR simulator input formats' do
  def counter_ir
    RHDL::SpecFixtures::IrInputFormatCounter.to_flat_circt_nodes(top_name: 'ir_input_format_counter')
  end

  def step(sim, rst:, en:)
    sim.poke('rst', rst ? 1 : 0)
    sim.poke('en', en ? 1 : 0)
    sim.poke('clk', 0)
    sim.evaluate
    sim.poke('clk', 1)
    sim.tick
  end

  describe 'backend input format resolution' do
    it 'defaults interpreter to circt format' do
      expect(RHDL::Sim::Native::IR.input_format_for_backend(:interpreter, env: {})).to eq(:circt)
    end

    it 'defaults jit to circt format' do
      expect(RHDL::Sim::Native::IR.input_format_for_backend(:jit, env: {})).to eq(:circt)
    end

    it 'defaults compiler to circt format' do
      expect(RHDL::Sim::Native::IR.input_format_for_backend(:compiler, env: {})).to eq(:circt)
    end

    it 'uses backend-specific env override before global override' do
      env = {
        'RHDL_IR_INPUT_FORMAT' => 'not_a_format',
        'RHDL_IR_INPUT_FORMAT_JIT' => 'circt'
      }

      expect(RHDL::Sim::Native::IR.input_format_for_backend(:jit, env: env)).to eq(:circt)
      expect do
        RHDL::Sim::Native::IR.input_format_for_backend(:compiler, env: env)
      end.to raise_error(ArgumentError, /Unknown IR input format/)
    end

    it 'raises on invalid input format override' do
      env = { 'RHDL_IR_INPUT_FORMAT' => 'not_a_format' }

      expect do
        RHDL::Sim::Native::IR.input_format_for_backend(:interpreter, env: env)
      end.to raise_error(ArgumentError, /Unknown IR input format/)
    end

    it 'rejects legacy input format override' do
      env = { 'RHDL_IR_INPUT_FORMAT' => 'legacy' }

      expect do
        RHDL::Sim::Native::IR.input_format_for_backend(:interpreter, env: env)
      end.to raise_error(ArgumentError, /Valid: :circt/)
    end
  end

  describe 'circt runtime json generation and backend parity' do
    it 'produces CIRCT runtime JSON with expected module payload shape' do
      ir = counter_ir

      circt_json = RHDL::Sim::Native::IR.sim_json(ir, format: :circt)
      circt_hash = JSON.parse(circt_json, max_nesting: false)
      expect(circt_hash['circt_json_version']).to eq(1)
      expect(circt_hash['modules']).to be_an(Array)
      expect(circt_hash['modules'].first['name']).to eq('ir_input_format_counter')
      expect(circt_hash['modules'].first['ports'].map { |p| p['name'] }).to include('clk', 'rst', 'en', 'q')
      expect(circt_hash['modules'].first).to have_key('assigns')
      expect(circt_hash['modules'].first).to have_key('processes')
    end

    it 'runs expected counter behavior with CIRCT input format per backend' do
      ir = counter_ir
      sequence = [
        { rst: true, en: false },
        { rst: false, en: true },
        { rst: false, en: true },
        { rst: false, en: false },
        { rst: false, en: true }
      ]
      expected_q = [0, 0, 0, 0, 0]

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        circt_json = RHDL::Sim::Native::IR.sim_json(ir, format: :circt)
        sim = RHDL::Sim::Native::IR::Simulator.new(
          circt_json,
          backend: backend,
          input_format: :circt
        )

        expect(sim.input_format).to eq(:circt)
        expect(sim.effective_input_format).to eq(:circt)

        sequence.each_with_index do |inputs, idx|
          step(sim, **inputs)
          expect(sim.peek('q')).to eq(expected_q[idx])
        end
      end
    end

    it 'uses circt path by default for available native backends' do
      ir = counter_ir

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        backend_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend)
        parsed = JSON.parse(backend_json, max_nesting: false)
        expect(parsed['circt_json_version']).to eq(1)

        sim = RHDL::Sim::Native::IR::Simulator.new(
          backend_json,
          backend: backend
        )
        expect(sim.input_format).to eq(:circt)
        expect(sim.effective_input_format).to eq(:circt)
      end
    end
  end

  describe 'hard-cut fallback behavior' do
    it 'rejects removed allow_fallback keyword' do
      ir = counter_ir
      circt_json = RHDL::Sim::Native::IR.sim_json(ir, format: :circt)

      expect do
        RHDL::Sim::Native::IR::Simulator.new(
          circt_json,
          backend: :interpreter,
          input_format: :circt,
          allow_fallback: true
        )
      end.to raise_error(ArgumentError, /allow_fallback/)
    end

    it 'rejects malformed CIRCT runtime JSON wrappers' do
      expect do
        RHDL::Sim::Native::IR.sim_json({ 'circt_json_version' => 1 }, format: :circt)
      end.to raise_error(ArgumentError, /circt_json_version and non-empty modules/)
    end

    it 'does not fallback when backend is unavailable' do
      ir = counter_ir
      circt_json = RHDL::Sim::Native::IR.sim_json(ir, format: :circt)

      allow_any_instance_of(RHDL::Sim::Native::IR::Simulator).to receive(:select_backend).and_return(nil)

      expect do
        RHDL::Sim::Native::IR::Simulator.new(
          circt_json,
          backend: :interpreter,
          input_format: :circt
        )
      end.to raise_error(LoadError, /IR interpreter extension not found/)
    end
  end
end
