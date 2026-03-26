# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'
require 'tmpdir'
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

  def nested_clocked_if_ir
    ir = RHDL::Codegen::CIRCT::IR

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ir_input_format_nested_if',
          ports: [
            ir::Port.new(name: 'clk', direction: :in, width: 1),
            ir::Port.new(name: 'rst', direction: :in, width: 1),
            ir::Port.new(name: 'en', direction: :in, width: 1),
            ir::Port.new(name: 'y', direction: :out, width: 4)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: 'q', width: 4, reset_value: 0)
          ],
          assigns: [
            ir::Assign.new(
              target: 'y',
              expr: ir::Signal.new(name: 'q', width: 4)
            )
          ],
          processes: [
            ir::Process.new(
              name: 'p',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::If.new(
                  condition: ir::Signal.new(name: 'rst', width: 1),
                  then_statements: [
                    ir::SeqAssign.new(
                      target: 'q',
                      expr: ir::Literal.new(value: 0, width: 4)
                    )
                  ],
                  else_statements: [
                    ir::If.new(
                      condition: ir::Signal.new(name: 'en', width: 1),
                      then_statements: [
                        ir::SeqAssign.new(
                          target: 'q',
                          expr: ir::BinaryOp.new(
                            op: :+,
                            left: ir::Signal.new(name: 'q', width: 4),
                            right: ir::Literal.new(value: 1, width: 4),
                            width: 4
                          )
                        )
                      ],
                      else_statements: []
                    )
                  ]
                )
              ]
            )
          ],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      ]
    )
  end

  def counter_mlir
    RHDL::SpecFixtures::IrInputFormatCounter.to_mlir_hierarchy(top_name: 'ir_input_format_counter')
  end

  def hierarchical_mlir
    RHDL::SpecFixtures::IrInputFormatHierTop.to_mlir_hierarchy(top_name: 'ir_input_format_top')
  end

  def top_first_hierarchical_mlir
    <<~MLIR
      hw.module @ir_input_format_top_first_top(in %a: i4, out y: i4) {
        %u_y = hw.instance "u" @ir_input_format_top_first_child(a: %a : i4) -> (y: i4)
        %one = hw.constant 1 : i4
        %sum = comb.add %u_y, %one : i4
        hw.output %sum : i4
      }

      hw.module @ir_input_format_top_first_child(in %a: i4, out y: i4) {
        %one = hw.constant 1 : i4
        %sum = comb.add %a, %one : i4
        hw.output %sum : i4
      }
    MLIR
  end

  def imported_async_reset_mlir
    <<~MLIR
      hw.module @import_child(in %clk: i1, in %rst: i1, out y: i8) {
        %c0_i8 = hw.constant 0 : i8
        %c9_i8 = hw.constant 9 : i8
        %q = seq.firreg %c0_i8 clock %clk reset async %rst, %c9_i8 : i8
        hw.output %q : i8
      }

      hw.module @import_top(in %clk: i1, in %rst: i1, out y: i8) {
        %u_y = hw.instance "u" @import_child(clk: %clk: i1, rst: %rst: i1) -> (y: i8)
        hw.output %u_y : i8
      }
    MLIR
  end

  def source_backed_imported_async_reset_mlir
    Dir.mktmpdir('ir_input_format_imported_async_reset') do |dir|
      core_mlir_path = File.join(dir, 'import_top.normalized.core.mlir')
      File.write(core_mlir_path, imported_async_reset_mlir)

      result = RHDL::Codegen.raise_circt_components(
        imported_async_reset_mlir,
        namespace: Module.new,
        top: 'import_top',
        strict: false
      )
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      top_component = result.components.fetch('import_top')
      return top_component.to_mlir_hierarchy(
        top_name: 'import_top',
        core_mlir_path: core_mlir_path
      )
    end
  end

  def bool_constant_mlir
    <<~MLIR
      hw.module @ir_input_format_bool_const(out y: i1) {
        %true = hw.constant true
        hw.output %true : i1
      }
    MLIR
  end

  def variadic_comb_mlir
    <<~MLIR
      hw.module @ir_input_format_variadic_comb(in %a: i1, in %b: i1, in %c: i1, out y_or: i1, out y_add: i3) {
        %or_bits = comb.or %a, %b, %c {sv.namehint = "joined_bits"} : i1
        %one = hw.constant 1 : i3
        %two = hw.constant 2 : i3
        %three = hw.constant 3 : i3
        %sum = comb.add %one, %two, %three : i3
        hw.output %or_bits, %sum : i1, i3
      }
    MLIR
  end

  def void_instance_mlir
    <<~MLIR
      hw.module @ir_input_format_void_child() {
      }

      hw.module @ir_input_format_void_top(out y: i1) {
        hw.instance "u" @ir_input_format_void_child() -> ()
        %true = hw.constant true
        hw.output %true : i1
      }
    MLIR
  end

  def array_select_mlir
    <<~MLIR
      hw.module @ir_input_format_array_select(in %idx: i2, out y_dynamic: i8, out y_const: i8) {
        %one = hw.constant 1 : i8
        %two = hw.constant 2 : i8
        %three = hw.constant 3 : i8
        %four = hw.constant 4 : i8
        %dyn = hw.array_create %one, %two, %three, %four : i8
        %dyn_sel = hw.array_get %dyn[%idx] : !hw.array<4xi8>, i2
        %const = hw.aggregate_constant [1 : i8, 2 : i8, 3 : i8, 4 : i8] : !hw.array<4xi8>
        %const_sel = hw.array_get %const[%idx] : !hw.array<4xi8>, i2
        hw.output %dyn_sel, %const_sel : i8, i8
      }
    MLIR
  end

  def ceq_cne_mlir
    <<~MLIR
      hw.module @ir_input_format_ceq_cne(in %a: i8, in %b: i8, out y_eq: i1, out y_ne: i1) {
        %eqv = comb.icmp ceq %a, %b : i8
        %nev = comb.icmp cne %a, %b : i8
        hw.output %eqv, %nev : i1, i1
      }
    MLIR
  end

  def replicate_mlir
    <<~MLIR
      hw.module @ir_input_format_replicate(in %a: i1, out y: i4) {
        %rep = comb.replicate %a : (i1) -> i4
        hw.output %rep : i4
      }
    MLIR
  end

  def overwide_runtime_fallback_mlir
    <<~MLIR
      hw.module @ir_input_format_overwide_runtime(out y: i32) {
        %one = hw.constant 1 : i300
        %slice = comb.extract %one from 0 : (i300) -> i268
        %a = hw.constant 305419896 : i32
        %cat = comb.concat %slice, %a : i268, i32
        %lo = comb.extract %cat from 0 : (i300) -> i32
        hw.output %lo : i32
      }
    MLIR
  end

  def forward_ref_seq_width_mlir
    <<~MLIR
      hw.module @ir_input_format_forward_ref_seq(in %clk: i1, in %rst: i1, out y: i7) {
        %clock = seq.to_clock %clk
        %c0_7 = hw.constant 0 : i7
        %c1_7 = hw.constant 1 : i7
        %next = comb.add %q, %c1_7 : i7
        %q = seq.firreg %next clock %clock reset async %rst, %c0_7 : i7
        hw.output %q : i7
      }
    MLIR
  end

  def dotted_instance_mlir
    <<~MLIR
      hw.module @ir_input_format_dot_source(out y: i1) {
        %true = hw.constant true
        hw.output %true : i1
      }

      hw.module @ir_input_format_dot_passthrough(in %a: i1, out y: i1) {
        hw.output %a : i1
      }

      hw.module @ir_input_format_dot_top(out y: i1) {
        %src.y = hw.instance "src" @ir_input_format_dot_source() -> (y: i1)
        %passthrough.y = hw.instance "passthrough" @ir_input_format_dot_passthrough(a: %src.y : i1) -> (y: i1)
        hw.output %passthrough.y : i1
      }
    MLIR
  end

  def step(sim, rst:, en:)
    sim.poke('rst', rst ? 1 : 0)
    sim.poke('en', en ? 1 : 0)
    sim.poke('clk', 0)
    sim.evaluate
    sim.poke('clk', 1)
    sim.tick
  end

  def step_clock_only(sim)
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

    it 'preserves nested clocked if priority with CIRCT input format per backend' do
      ir = nested_clocked_if_ir
      sequence = [
        { rst: true, en: true, expected_q: 0 },
        { rst: false, en: true, expected_q: 1 },
        { rst: true, en: true, expected_q: 0 }
      ]

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

        sequence.each do |inputs|
          step(sim, rst: inputs[:rst], en: inputs[:en])
          expect(sim.peek('q')).to eq(inputs[:expected_q])
          expect(sim.peek('y')).to eq(inputs[:expected_q])
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

    it 'chooses the uninstantiated root module instead of the last module in MLIR order' do
      mlir = top_first_hierarchical_mlir

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

        sim.poke('a', 5)
        sim.evaluate
        expect(sim.peek('y')).to eq(7)
        expect(sim.has_signal?('u__y')).to be(true)
        expect(sim.peek('u__y')).to eq(6)
      end
    end

    it 'accepts raw boolean hw.constant forms from normalized source MLIR' do
      mlir = bool_constant_mlir

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

        sim.evaluate
        expect(sim.peek('y')).to eq(1)
      end
    end

    it 'accepts variadic comb ops emitted by source-backed MLIR export' do
      mlir = variadic_comb_mlir

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

        sim.poke('a', 0)
        sim.poke('b', 1)
        sim.poke('c', 0)
        sim.evaluate
        expect(sim.peek('y_or')).to eq(1)
        expect(sim.peek('y_add')).to eq(6)
      end
    end

    it 'accepts bare hw.instance operations with no SSA results' do
      mlir = void_instance_mlir

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

        sim.evaluate
        expect(sim.peek('y')).to eq(1)
      end
    end

    it 'sanitizes dotted instance-result SSA names into stable hierarchical signal names' do
      mlir = dotted_instance_mlir

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

        sim.evaluate
        expect(sim.peek('y')).to eq(1)
        expect(sim.has_signal?('src__y')).to be(true)
        expect(sim.has_signal?('passthrough__y')).to be(true)
        expect(sim.has_signal?('src.y')).to be(false)
        expect(sim.has_signal?('passthrough.y')).to be(false)
      end
    end

    it 'accepts hw.array_create, hw.aggregate_constant, and hw.array_get using CIRCT index order' do
      mlir = array_select_mlir

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

        [[0, 4], [1, 3], [2, 2], [3, 1]].each do |idx, expected|
          sim.poke('idx', idx)
          sim.evaluate
          expect(sim.peek('y_dynamic')).to eq(expected)
          expect(sim.peek('y_const')).to eq(expected)
        end
      end
    end

    it 'accepts ceq and cne comb.icmp predicates from exported MLIR' do
      mlir = ceq_cne_mlir

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

        sim.poke('a', 7)
        sim.poke('b', 7)
        sim.evaluate
        expect(sim.peek('y_eq')).to eq(1)
        expect(sim.peek('y_ne')).to eq(0)

        sim.poke('b', 9)
        sim.evaluate
        expect(sim.peek('y_eq')).to eq(0)
        expect(sim.peek('y_ne')).to eq(1)
      end
    end

    it 'accepts comb.replicate by lowering to concat behavior' do
      mlir = replicate_mlir

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

        sim.poke('a', 1)
        sim.evaluate
        expect(sim.peek('y')).to eq(0b1111)

        sim.poke('a', 0)
        sim.evaluate
        expect(sim.peek('y')).to eq(0)
      end
    end

    it 'allows the compiler backend to mix compiled logic with runtime fallback overwide assigns' do
      skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

      sim = RHDL::Sim::Native::IR::Simulator.new(
        overwide_runtime_fallback_mlir,
        backend: :compiler,
        input_format: :mlir
      )

      sim.evaluate

      expect(sim.compiled?).to be(true)
      expect(sim.has_signal?('y')).to be(true)
    end

    it 'preserves full signal widths for forward-referenced seq registers in MLIR' do
      mlir = forward_ref_seq_width_mlir

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

        sim.poke('clk', 0)
        sim.poke('rst', 1)
        sim.evaluate
        sim.poke('clk', 1)
        sim.poke('rst', 1)
        sim.tick

        expected = [1, 2, 3, 4]
        expected.each do |value|
          sim.poke('clk', 0)
          sim.poke('rst', 0)
          sim.evaluate
          sim.poke('clk', 1)
          sim.poke('rst', 0)
          sim.tick
          expect(sim.peek('y')).to eq(value)
        end
      end
    end

    it 'preserves imported async-reset semantics when hierarchy export is source-backed' do
      mlir = source_backed_imported_async_reset_mlir
      expect(mlir).to include('reset async')

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
        sim.evaluate
        expect(sim.peek('y')).to eq(9)

        sim.poke('rst', 0)
        step_clock_only(sim)
        expect(sim.peek('y')).to eq(0)

        sim.poke('rst', 1)
        step_clock_only(sim)
        expect(sim.peek('y')).to eq(9)

        sim.poke('rst', 0)
        step_clock_only(sim)
        expect(sim.peek('y')).to eq(0)
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
