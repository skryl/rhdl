# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'
require 'rhdl/codegen'

module RHDL
  module SpecFixtures
    class IrInputFormatCounter < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :en
      output :q, width: 4

      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(en, q + 1, q)
      end
    end

    class IrInputFormatWireChild < RHDL::Sim::Component
      input :a, width: 4
      output :y, width: 4

      behavior do
        y <= a + 1
      end
    end

    class IrInputFormatHierTop < RHDL::Sim::Component
      input :a, width: 4
      output :y, width: 4

      instance :u, IrInputFormatWireChild
      port :a => %i[u a]
      port %i[u y] => :y
    end
  end
end

RSpec.describe 'IR simulator input formats' do
  def counter_ir
    RHDL::SpecFixtures::IrInputFormatCounter.to_flat_circt_nodes(top_name: 'ir_input_format_counter')
  end

  def counter_mlir
    RHDL::SpecFixtures::IrInputFormatCounter.to_mlir_hierarchy(top_name: 'ir_input_format_counter')
  end

  def hierarchical_mlir
    RHDL::SpecFixtures::IrInputFormatHierTop.to_mlir_hierarchy(top_name: 'ir_input_format_top')
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
    it 'defaults interpreter to auto format' do
      expect(RHDL::Sim::Native::IR.input_format_for_backend(:interpreter, env: {})).to eq(:auto)
    end

    it 'defaults jit to auto format' do
      expect(RHDL::Sim::Native::IR.input_format_for_backend(:jit, env: {})).to eq(:auto)
    end

    it 'defaults compiler to auto format' do
      expect(RHDL::Sim::Native::IR.input_format_for_backend(:compiler, env: {})).to eq(:auto)
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
      end.to raise_error(ArgumentError, /Valid: :auto, :circt, :mlir/)
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
      expected_q = [0, 1, 2, 2, 3]

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        circt_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend, format: :circt)
        sim = RHDL::Sim::Native::IR::Simulator.new(
          circt_json,
          backend: backend,
          input_format: :circt
        )
        sim.reset

        expect(sim.input_format).to eq(:circt)
        expect(sim.effective_input_format).to eq(:circt)

        sequence.each_with_index do |inputs, idx|
          step(sim, **inputs)
          expect(sim.peek('q')).to eq(expected_q[idx])
        end
      end
    end

    it 'runs expected counter behavior without Ruby-side signal width extraction' do
      ir = counter_ir
      sequence = [
        { rst: true, en: false },
        { rst: false, en: true },
        { rst: false, en: true },
        { rst: false, en: false },
        { rst: false, en: true }
      ]
      expected_q = [0, 1, 2, 2, 3]

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        circt_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend, format: :circt)
        sim = RHDL::Sim::Native::IR::Simulator.new(
          circt_json,
          backend: backend,
          input_format: :circt,
          skip_signal_widths: true
        )
        sim.reset

        sequence.each_with_index do |inputs, idx|
          step(sim, **inputs)
          expect(sim.peek('q')).to eq(expected_q[idx])
        end
      end
    end

    it 'can discard retained input JSON after native initialization' do
      ir = counter_ir

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        circt_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend, format: :circt)
        sim = RHDL::Sim::Native::IR::Simulator.new(
          circt_json,
          backend: backend,
          input_format: :circt,
          retain_ir_json: false
        )

        expect(sim.ir_json).to be_nil
        sim.reset
        step(sim, rst: true, en: false)
        expect(sim.peek('q')).to eq(0)
      end
    end

    it 'uses JSON export plus circt autodetection by default for available native backends' do
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
        expect(sim.input_format).to eq(:auto)
        expect(sim.effective_input_format).to eq(:circt)
      end
    end

    it 'streams compact CIRCT runtime JSON for all native backends' do
      ir = counter_ir
      expected = StringIO.new
      RHDL::Codegen::CIRCT::RuntimeJSON.dump_to_io(ir, expected, compact_exprs: true)

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        backend_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend)
        expect(backend_json).to eq(expected.string)
      end
    end
  end

  describe 'mlir frontend input and backend parity' do
    it 'runs expected counter behavior with MLIR input format per backend' do
      mlir = counter_mlir
      sequence = [
        { rst: true, en: false },
        { rst: false, en: true },
        { rst: false, en: true },
        { rst: false, en: false },
        { rst: false, en: true }
      ]
      expected_q = [0, 1, 2, 2, 3]

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        sim = RHDL::Sim::Native::IR::Simulator.new(
          mlir,
          backend: backend,
          input_format: :mlir
        )
        sim.reset

        expect(sim.input_format).to eq(:mlir)
        expect(sim.effective_input_format).to eq(:mlir)

        sequence.each_with_index do |inputs, idx|
          step(sim, **inputs)
          expect(sim.peek('q')).to eq(expected_q[idx])
        end
      end
    end

    it 'autodetects MLIR payloads when no input format override is provided' do
      mlir = counter_mlir

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        sim = RHDL::Sim::Native::IR::Simulator.new(
          mlir,
          backend: backend
        )

        expect(sim.input_format).to eq(:auto)
        expect(sim.effective_input_format).to eq(:mlir)
      end
    end

    it 'flattens hierarchical MLIR instance outputs for available native backends' do
      mlir = hierarchical_mlir

      [
        [:interpreter, RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE],
        [:jit, RHDL::Sim::Native::IR::JIT_AVAILABLE],
        [:compiler, RHDL::Sim::Native::IR::COMPILER_AVAILABLE]
      ].each do |backend, available|
        next unless available

        sim = RHDL::Sim::Native::IR::Simulator.new(
          mlir,
          backend: backend,
          input_format: :mlir
        )

        sim.poke('a', 2)
        sim.evaluate
        expect(sim.peek('y')).to eq(3)
        expect(sim.has_signal?('u__y')).to be(true)
        expect(sim.peek('u__y')).to eq(3)
      end
    end
  end

  describe 'simulator lifecycle' do
    it 'destroys the native context at most once when closed repeatedly' do
      sim = RHDL::Sim::Native::IR::Simulator.allocate
      ctx = Fiddle::Pointer.malloc(1)
      destroy_calls = []

      sim.instance_variable_set(:@ctx, ctx)
      sim.instance_variable_set(:@ctx_state, {
        ptr: ctx,
        destroy: ->(ptr) { destroy_calls << ptr.to_i },
        closed: false
      })

      expect(sim.close).to be(true)
      expect(sim.close).to be(false)
      expect(sim.closed?).to be(true)
      expect(sim.instance_variable_get(:@ctx)).to be_nil
      expect(destroy_calls).to eq([ctx.to_i])
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
