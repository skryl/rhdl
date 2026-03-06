# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'timeout'

RSpec.describe RHDL::Codegen::CIRCT::Raise do
  let(:ir) { RHDL::Codegen::CIRCT::IR }
  let(:tmp_dir) { Dir.mktmpdir('rhdl_circt_raise_spec') }
  let(:simple_mlir) do
    <<~MLIR
      hw.module @simple(%a: i8, %b: i8) -> (y: i8) {
        %sum = comb.add %a, %b : i8
        hw.output %sum : i8
      }
    MLIR
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.to_sources' do
    it 'returns in-memory DSL source map for MLIR input' do
      result = described_class.to_sources(simple_mlir, top: 'simple')
      expect(result.success?).to be(true)
      expect(result.sources.keys).to eq(['simple'])
      expect(result.sources['simple']).to include('class Simple')
      expect(result.sources['simple']).to include('y <= (a + b)')
    end

    it 'emits structure + wire declarations for instance-based modules' do
      child = ir::ModuleOp.new(
        name: 'child',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: :a, width: 8))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )
      top = ir::ModuleOp.new(
        name: 'top',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: 'u__y', width: 8)],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: 'u__y', width: 8))],
        processes: [],
        instances: [
          ir::Instance.new(
            name: 'u',
            module_name: 'child',
            connections: [
              ir::PortConnection.new(port_name: :a, signal: 'a', direction: :in),
              ir::PortConnection.new(port_name: :y, signal: 'u__y', direction: :out)
            ],
            parameters: {}
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_sources([child, top], top: 'top')
      expect(result.success?).to be(true)
      source = result.sources['top']
      expect(source).to include('wire :u__y, width: 8')
      expect(source).to include('instance :u, Child')
      expect(source).to include('port :a => [:u, :a]')
      expect(source).to include('port [:u, :y] => :u__y')
      expect(source).to include('y <= u__y')
    end

    it 'sanitizes invalid ruby identifiers and class names from CIRCT symbols' do
      mlir = <<~MLIR
        hw.module @0.top$mod(%0a: i8, %class: i8) -> (%0y: i8) {
          %sum = comb.add %0a, %class : i8
          hw.output %sum : i8
        }
      MLIR

      result = described_class.to_sources(mlir, top: '0.top$mod')
      expect(result.success?).to be(true)
      source = result.sources['0.top$mod']
      expect(source).to include('class M0TopMod < RHDL::Sim::Component')
      expect(source).to include('input :_0a, width: 8')
      expect(source).to include('input :_class, width: 8')
      expect(source).to include('output :_0y, width: 8')
      expect(source).to include('_0y <= (_0a + _class)')
    end

    it 'raises integer module parameters into DSL parameter declarations' do
      mlir = <<~MLIR
        hw.module @param_mod<WIDTH: i32 = 8>(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }
      MLIR

      result = described_class.to_sources(mlir, top: 'param_mod')
      expect(result.success?).to be(true)
      source = result.sources['param_mod']
      expect(source).to include('class ParamMod < RHDL::Sim::Component')
      expect(source).to include('parameter :WIDTH, default: 8')
      expect(result.diagnostics.any? { |d| d.op == 'raise.module_params' }).to be(false)
    end

    it 'lowers expression-valued instance inputs through generated bridge wires' do
      child = ir::ModuleOp.new(
        name: 'child',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: :a, width: 8))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      top = ir::ModuleOp.new(
        name: 'top_expr_input',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: 'u_y', width: 8)],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: 'u_y', width: 8))],
        processes: [],
        instances: [
          ir::Instance.new(
            name: 'u',
            module_name: 'child',
            connections: [
              ir::PortConnection.new(
                port_name: :a,
                signal: ir::BinaryOp.new(
                  op: :+,
                  left: ir::Signal.new(name: :a, width: 8),
                  right: ir::Signal.new(name: :b, width: 8),
                  width: 8
                ),
                direction: :in
              ),
              ir::PortConnection.new(port_name: :y, signal: 'u_y', direction: :out)
            ],
            parameters: {}
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_sources([child, top], top: 'top_expr_input', strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |d| d.op == 'raise.structure' }).to be(false)

      source = result.sources.fetch('top_expr_input')
      expect(source).to include('wire :u__a__bridge, width: 8')
      expect(source).to include('u__a__bridge <= (a + b)')
      expect(source).to include('port :u__a__bridge => [:u, :a]')
    end

    it 'treats structurally-driven outputs as valid without placeholders' do
      child = ir::ModuleOp.new(
        name: 'child_passthrough',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: :a, width: 8))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      top = ir::ModuleOp.new(
        name: 'top_struct_only',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [],
        processes: [],
        instances: [
          ir::Instance.new(
            name: 'u',
            module_name: 'child_passthrough',
            connections: [
              ir::PortConnection.new(port_name: :a, signal: 'a', direction: :in),
              ir::PortConnection.new(port_name: :y, signal: 'y', direction: :out)
            ],
            parameters: {}
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_sources([child, top], top: 'top_struct_only', strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |d| d.op == 'raise.behavior' }).to be(false)
      source = result.sources.fetch('top_struct_only')
      expect(source).to include('port [:u, :y] => :y')
      expect(source).not_to include('y <= 0')
    end

    it 'pretty-prints long logic assignments in behavior blocks' do
      input_names = (1..10).map { |idx| "input_signal_#{idx}" }
      ports = input_names.map { |name| ir::Port.new(name: name, direction: :in, width: 32) }
      ports << ir::Port.new(name: :y, direction: :out, width: 32)

      expr = input_names.drop(1).reduce(ir::Signal.new(name: input_names.first, width: 32)) do |lhs, name|
        ir::BinaryOp.new(
          op: :+,
          left: lhs,
          right: ir::Signal.new(name: name, width: 32),
          width: 32
        )
      end

      mod = ir::ModuleOp.new(
        name: 'long_logic',
        ports: ports,
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: expr)],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_sources(mod, top: 'long_logic')
      expect(result.success?).to be(true)
      source = result.sources.fetch('long_logic')
      expect(source).to match(/y <=\n\s+\(/)
    end

    it 'raises deep mux chains without stack overflow' do
      chain = ir::Literal.new(value: 0, width: 1)
      sel = ir::Signal.new(name: :sel, width: 1)
      3000.times do |idx|
        chain = ir::Mux.new(
          condition: sel,
          when_true: ir::Literal.new(value: (idx & 1), width: 1),
          when_false: chain,
          width: 1
        )
      end

      mod = ir::ModuleOp.new(
        name: 'deep_mux',
        ports: [
          ir::Port.new(name: :sel, direction: :in, width: 1),
          ir::Port.new(name: :y, direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: chain)],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_sources(mod, top: 'deep_mux', strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.sources.fetch('deep_mux')).to include('y <=')
    end

    it 'raises shared mux DAGs by hoisting repeated subexpressions into locals' do
      sel = ir::Signal.new(name: :sel, width: 1)
      shared = ir::Signal.new(name: :a, width: 1)
      120.times do |idx|
        shared = ir::Mux.new(
          condition: idx.even? ? sel : ir::UnaryOp.new(op: :'~', operand: sel, width: 1),
          when_true: shared,
          when_false: shared,
          width: 1
        )
      end

      mod = ir::ModuleOp.new(
        name: 'shared_mux_dag',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 1),
          ir::Port.new(name: :sel, direction: :in, width: 1),
          ir::Port.new(name: :y, direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: shared)],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = nil
      expect do
        Timeout.timeout(2) do
          result = described_class.to_sources(mod, top: 'shared_mux_dag', strict: true)
        end
      end.not_to raise_error

      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      source = result.sources.fetch('shared_mux_dag')
      expect(source).to include('local(:y_expr_0_local_0')
      expect(source).to include('y <=')
    end

    it 'raises shared sequential mux DAGs by hoisting repeated subexpressions into locals' do
      sel = ir::Signal.new(name: :sel, width: 1)
      shared = ir::Signal.new(name: :d, width: 8)
      80.times do |idx|
        shared = ir::Mux.new(
          condition: idx.even? ? sel : ir::UnaryOp.new(op: :'~', operand: sel, width: 1),
          when_true: shared,
          when_false: shared,
          width: 8
        )
      end

      mod = ir::ModuleOp.new(
        name: 'shared_seq_mux_dag',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :sel, direction: :in, width: 1),
          ir::Port.new(name: :d, direction: :in, width: 8),
          ir::Port.new(name: :q, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :q, expr: ir::Signal.new(name: :q_reg, width: 8))],
        processes: [
          ir::Process.new(
            name: 'p0',
            statements: [ir::SeqAssign.new(target: :q_reg, expr: shared)],
            clocked: true,
            clock: :clk
          )
        ],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = nil
      expect do
        Timeout.timeout(2) do
          result = described_class.to_sources(mod, top: 'shared_seq_mux_dag', strict: true)
        end
      end.not_to raise_error

      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      source = result.sources.fetch('shared_seq_mux_dag')
      expect(source).to include('local(:q_reg_seq_0_local_0')
      expect(source).to include('q_reg <=')
    end
  end

  describe '.format_output_dir' do
    it 'formats generated ruby files with SyntaxTree' do
      file = File.join(tmp_dir, 'format_me.rb')
      File.write(file, "class FormatMe\n  def call;1+2;end\nend\n")

      result = described_class.format_output_dir(tmp_dir)
      expect(result.success?).to be(true)
      expect(result.diagnostics).to be_empty

      formatted = File.read(file)
      expect(formatted).to include('def call')
      expect(formatted).to include('1 + 2')
      expect(formatted).not_to include('def call;1+2;end')
    end
  end

  describe '.to_components' do
    it 'loads raised classes into provided namespace' do
      namespace = Module.new
      result = described_class.to_components(simple_mlir, namespace: namespace, top: 'simple')
      expect(result.success?).to be(true)
      expect(result.components.keys).to eq(['simple'])
      expect(result.components['simple']).to be < RHDL::Sim::Component
      expect(namespace.const_defined?(:Simple, false)).to be(true)
    end

    it 'replaces an existing class constant in namespace on reload' do
      namespace = Module.new
      namespace.const_set(:Simple, Class.new)

      result = described_class.to_components(simple_mlir, namespace: namespace, top: 'simple')
      expect(result.success?).to be(true)
      expect(result.components['simple']).to be < RHDL::Sim::Component
      expect(namespace.const_get(:Simple, false)).to eq(result.components['simple'])
    end

    it 'loads hierarchical components even when parent appears before child in source order' do
      hierarchy_mlir = <<~MLIR
        hw.module @top(%a: i8) -> (y: i8) {
          %u_y = hw.instance "u" @child(a: %a: i8) -> (y: i8)
          hw.output %u_y : i8
        }

        hw.module @child(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }
      MLIR

      namespace = Module.new
      result = described_class.to_components(hierarchy_mlir, namespace: namespace, top: 'top')
      expect(result.success?).to be(true)
      expect(result.components.keys).to include('top', 'child')
      expect(namespace.const_defined?(:Top, false)).to be(true)
      expect(namespace.const_defined?(:Child, false)).to be(true)
    end

    it 'preserves instance module refs when raising into an anonymous namespace' do
      hierarchy_mlir = <<~MLIR
        hw.module @top(%a: i8) -> (y: i8) {
          %u_y = hw.instance "u" @child(a: %a: i8) -> (y: i8)
          hw.output %u_y : i8
        }

        hw.module @child(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }
      MLIR

      result = described_class.to_components(hierarchy_mlir, namespace: Module.new, top: 'top')
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.components.fetch('child').verilog_module_name).to eq('child')

      top = result.components.fetch('top')
      instance_def = top._instance_defs.find { |inst| inst[:name] == :u }
      expect(instance_def).not_to be_nil
      expect(instance_def[:module_name]).to eq('child')

      emitted_mlir = top.to_ir(top_name: 'top')
      expect(emitted_mlir).to include('hw.instance "u" @child(')
    end

    it 'supports uppercase signal names in raised behavior when re-emitting MLIR' do
      mod = ir::ModuleOp.new(
        name: 'caps',
        ports: [ir::Port.new(name: :DDRAM_CLK, direction: :out, width: 1)],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :DDRAM_CLK, expr: ir::Literal.new(value: 0, width: 1))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_components(mod, namespace: Module.new, top: 'caps')
      expect(result.success?).to be(true)
      expect(result.components).to include('caps')

      emitted_mlir = nil
      expect { emitted_mlir = result.components.fetch('caps').to_ir(top_name: 'caps') }.not_to raise_error
      expect(emitted_mlir).to include('hw.module @caps')
    end

    it 'reuses imported CIRCT modules when re-emitting raised components' do
      mod = ir::ModuleOp.new(
        name: 'cached_roundtrip',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: :a, width: 8))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_components(mod, namespace: Module.new, top: 'cached_roundtrip')
      expect(result.success?).to be(true)
      component = result.components.fetch('cached_roundtrip')

      component.define_singleton_method(:build_circt_module) do |*|
        raise 'should not rebuild CIRCT from raised DSL'
      end

      emitted_mlir = nil
      expect do
        emitted_mlir = component.to_ir(top_name: 'cached_roundtrip')
      end.not_to raise_error
      expect(emitted_mlir).to include('hw.module @cached_roundtrip')
      expect(emitted_mlir).to include('hw.output %a : i8')
    end

    it 'reuses original imported CIRCT text when re-emitting raised components from MLIR input' do
      mlir = <<~MLIR
        hw.module @cached_text(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }
      MLIR

      result = described_class.to_components(mlir, namespace: Module.new, top: 'cached_text')
      expect(result.success?).to be(true)
      component = result.components.fetch('cached_text')

      allow(RHDL::Codegen::CIRCT::MLIR).to receive(:generate).and_raise('should not regenerate imported MLIR text')

      emitted_mlir = nil
      expect do
        emitted_mlir = component.to_ir(top_name: 'cached_text')
      end.not_to raise_error
      expect(emitted_mlir.strip).to eq(mlir.strip)
    end

    it 'renames cached imported CIRCT modules without rebuilding DSL state' do
      mod = ir::ModuleOp.new(
        name: 'rename_me',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 1),
          ir::Port.new(name: :y, direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: :a, width: 1))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_components(mod, namespace: Module.new, top: 'rename_me')
      expect(result.success?).to be(true)
      component = result.components.fetch('rename_me')

      component.define_singleton_method(:build_circt_module) do |*|
        raise 'should not rebuild CIRCT from raised DSL'
      end

      emitted_mlir = component.to_ir(top_name: 'renamed_copy')
      expect(emitted_mlir).to include('hw.module @renamed_copy')
      expect(emitted_mlir).not_to include('hw.module @rename_me(')
    end

    it 'renames cached imported CIRCT text without regenerating MLIR' do
      mlir = <<~MLIR
        hw.module @rename_text(%a: i1) -> (y: i1) {
          hw.output %a : i1
        }
      MLIR

      result = described_class.to_components(mlir, namespace: Module.new, top: 'rename_text')
      expect(result.success?).to be(true)
      component = result.components.fetch('rename_text')

      allow(RHDL::Codegen::CIRCT::MLIR).to receive(:generate).and_raise('should not regenerate imported MLIR text')

      emitted_mlir = component.to_ir(top_name: 'renamed_text_copy')
      expect(emitted_mlir).to include('hw.module @renamed_text_copy')
      expect(emitted_mlir).not_to include('hw.module @rename_text(')
    end

    it 'rewrites <= comparisons so output proxies are not treated as assignments in expressions' do
      mod = ir::ModuleOp.new(
        name: 'cmp_internal',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 1)
        ],
        nets: [ir::Net.new(name: :w, width: 8)],
        regs: [],
        assigns: [
          ir::Assign.new(target: :w, expr: ir::Signal.new(name: :a, width: 8)),
          ir::Assign.new(
            target: :y,
            expr: ir::BinaryOp.new(
              op: :<=,
              left: ir::Signal.new(name: :w, width: 8),
              right: ir::Signal.new(name: :b, width: 8),
              width: 1
            )
          )
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      source_result = described_class.to_sources(mod, top: 'cmp_internal', strict: true)
      expect(source_result.success?).to be(true), source_result.diagnostics.map(&:message).join("\n")
      expect(source_result.sources.fetch('cmp_internal')).to include('y <= ((w < b) | (w == b))')

      component_result = described_class.to_components(mod, namespace: Module.new, top: 'cmp_internal', strict: true)
      expect(component_result.success?).to be(true), component_result.diagnostics.map(&:message).join("\n")

      emitted_mlir = nil
      expect do
        emitted_mlir = component_result.components.fetch('cmp_internal').to_ir(top_name: 'cmp_internal')
      end.not_to raise_error
      expect(emitted_mlir).to include('comb.icmp')
    end
  end

  describe '.to_dsl' do
    it 'raises CIRCT nodes into Ruby DSL files' do
      mod = ir::ModuleOp.new(
        name: 'simple',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::BinaryOp.new(
              op: :+,
              left: ir::Signal.new(name: :a, width: 8),
              right: ir::Signal.new(name: :b, width: 8),
              width: 8
            )
          )
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_dsl(mod, out_dir: tmp_dir, top: 'simple')
      expect(result.success?).to be(true)
      expect(result.files_written).to eq([File.join(tmp_dir, 'simple.rb')])

      generated = File.read(result.files_written.first)
      expect(generated).to include('class Simple')
      expect(generated).to include('behavior do')
      expect(generated).to include('y <= (a + b)')
    end

    it 'preserves DSL <= assignment statements when format mode is enabled' do
      mod = ir::ModuleOp.new(
        name: 'formatted_assign',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::BinaryOp.new(
              op: :+,
              left: ir::Signal.new(name: :a, width: 8),
              right: ir::Signal.new(name: :b, width: 8),
              width: 8
            )
          )
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_dsl(mod, out_dir: tmp_dir, top: 'formatted_assign', format: true)
      expect(result.success?).to be(true)

      generated = File.read(File.join(tmp_dir, 'formatted_assign.rb'))
      expect(generated).to include('y <= ')
      expect(generated).not_to match(/^\s*y\s*$/)
      expect { Module.new.module_eval(generated, 'formatted_assign.rb', 1) }.not_to raise_error
    end

    it 'fails output recovery when assignments are missing instead of emitting placeholders' do
      mod = ir::ModuleOp.new(
        name: 'placeholder',
        ports: [ir::Port.new(name: :y, direction: :out, width: 1)],
        nets: [],
        regs: [],
        assigns: [],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_dsl(mod, out_dir: tmp_dir, top: 'placeholder', strict: true)
      expect(result.success?).to be(false)
      expect(
        result.diagnostics.any? do |d|
          d.op == 'raise.behavior' && d.severity.to_s == 'error'
        end
      ).to be(true)

      generated = File.read(File.join(tmp_dir, 'placeholder.rb'))
      expect(generated).not_to include('y <= 0')
    end

    it 'fails raise when expression lowering has unsupported semantics' do
      mod = ir::ModuleOp.new(
        name: 'unsupported_expr',
        ports: [ir::Port.new(name: :y, direction: :out, width: 8)],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::MemoryRead.new(
              memory: :ram,
              addr: ir::Literal.new(value: 0, width: 8),
              width: 8
            )
          )
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_dsl(mod, out_dir: tmp_dir, top: 'unsupported_expr', strict: true)
      expect(result.success?).to be(false)
      expect(
        result.diagnostics.any? do |d|
          d.op == 'raise.memory_read' && d.severity.to_s == 'error'
        end
      ).to be(true)
    end

    it 'returns an error diagnostic when requested top module is missing' do
      mod = ir::ModuleOp.new(
        name: 'exists',
        ports: [ir::Port.new(name: :y, direction: :out, width: 1)],
        nets: [],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Literal.new(value: 1, width: 1))],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      result = described_class.to_dsl(mod, out_dir: tmp_dir, top: 'missing')
      expect(result.success?).to be(false)
      expect(result.diagnostics.any? { |d| d.severity.to_s == 'error' && d.message.include?("Top module 'missing' not found") }).to be(true)
      expect(result.files_written).to include(File.join(tmp_dir, 'exists.rb'))
    end

    it 'lowers sequential if-chains into mux-based assignments' do
      mod = ir::ModuleOp.new(
        name: 'seq_if',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :d, direction: :in, width: 1),
          ir::Port.new(name: :q, direction: :out, width: 1)
        ],
        nets: [],
        regs: [ir::Reg.new(name: :q, width: 1)],
        assigns: [ir::Assign.new(target: :q, expr: ir::Signal.new(name: :q, width: 1))],
        processes: [
          ir::Process.new(
            name: :seq_logic,
            clocked: true,
            clock: :clk,
            statements: [
              ir::If.new(
                condition: ir::Signal.new(name: :d, width: 1),
                then_statements: [
                  ir::SeqAssign.new(target: :q, expr: ir::Literal.new(value: 1, width: 1))
                ],
                else_statements: []
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

      result = described_class.to_dsl(mod, out_dir: tmp_dir, top: 'seq_if')
      expect(result.success?).to be(true)
      expect(result.diagnostics.any? { |d| d.op == 'raise.sequential_if' }).to be(false)

      generated = File.read(File.join(tmp_dir, 'seq_if.rb'))
      expect(generated).to include('sequential clock: :clk do')
      expect(generated).to include('q <= mux(d, lit(1, width: 1), q)')
    end
  end
end
