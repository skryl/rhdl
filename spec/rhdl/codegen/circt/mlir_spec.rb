# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe RHDL::Codegen::CIRCT::MLIR do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  describe '.generate' do
    it 'avoids infinite recursion when self-referential expression graphs appear in assign selection' do
      mod = ir::ModuleOp.new(
        name: 'cycle_guard',
        ports: [],
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
      emitter = described_class::ModuleEmitter.new(mod)
      cyclic_expr = ir::Resize.new(expr: ir::Literal.new(value: 1, width: 1), width: 1)
      cyclic_expr.instance_variable_set(:@expr, cyclic_expr)
      literal = ir::Literal.new(value: 0, width: 1)

      selected = nil
      Timeout.timeout(2) do
        expect(emitter.send(:signal_expr_references_target?, cyclic_expr, :y)).to be(false)
        selected = emitter.send(:preferred_assigned_expr, :y, [cyclic_expr, literal])
      end

      expect([cyclic_expr, literal]).to include(selected)
    end

    it 'prefers a live assigned expression over non-zero literal overlay defaults' do
      mod = ir::ModuleOp.new(
        name: 'overlay_live_value',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: :overlay, width: 8)],
        regs: [ir::Reg.new(name: :q, width: 8)],
        assigns: [
          ir::Assign.new(target: :overlay, expr: ir::Signal.new(name: :q, width: 8)),
          ir::Assign.new(target: :overlay, expr: ir::Literal.new(value: 0xA5, width: 8)),
          ir::Assign.new(target: :y, expr: ir::Signal.new(name: :overlay, width: 8))
        ],
        processes: [
          ir::Process.new(
            name: :seq_logic,
            clocked: true,
            clock: :clk,
            statements: [
              ir::SeqAssign.new(target: :q, expr: ir::Literal.new(value: 1, width: 8))
            ]
          )
        ],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(mod)
      expect(mlir).not_to include('comb.or')

      imported = RHDL::Codegen.import_circt_mlir(mlir, strict: true, top: 'overlay_live_value')
      expect(imported).to be_success

      output_assign = imported.modules.first.assigns.find { |assign| assign.target.to_s == 'y' }
      expect(output_assign).not_to be_nil
      expect(output_assign.expr).to be_a(ir::Signal)
      expect(output_assign.expr.name.to_s).not_to eq('overlay')
    end

    it 'emits hw/comb/seq operations for mixed combinational and sequential logic' do
      mod = ir::ModuleOp.new(
        name: 'demo',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :y, direction: :out, width: 8),
          ir::Port.new(name: :q, direction: :out, width: 8)
        ],
        nets: [],
        regs: [ir::Reg.new(name: :q, width: 8)],
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
        processes: [
          ir::Process.new(
            name: :seq_logic,
            clocked: true,
            clock: :clk,
            statements: [
              ir::SeqAssign.new(
                target: :q,
                expr: ir::Mux.new(
                  condition: ir::BinaryOp.new(
                    op: :==,
                    left: ir::Signal.new(name: :a, width: 8),
                    right: ir::Signal.new(name: :b, width: 8),
                    width: 1
                  ),
                  when_true: ir::Signal.new(name: :a, width: 8),
                  when_false: ir::Signal.new(name: :b, width: 8),
                  width: 8
                )
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

      mlir = described_class.generate(mod)
      expect(mlir).to include('hw.module @demo')
      expect(mlir).to include('comb.add')
      expect(mlir).to include('comb.icmp')
      expect(mlir).to include('comb.mux')
      expect(mlir).to include('seq.compreg')
      expect(mlir).to include('hw.output')
    end

    it 'canonicalizes wrapped integer literals into parser-valid signed hw.constant forms' do
      skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

      mod = ir::ModuleOp.new(
        name: 'const_wrap_demo',
        ports: [
          ir::Port.new(name: :y_pos, direction: :out, width: 32),
          ir::Port.new(name: :y_neg, direction: :out, width: 32)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(target: :y_pos, expr: ir::Literal.new(value: 0xFFFF_FFFF, width: 32)),
          ir::Assign.new(target: :y_neg, expr: ir::Literal.new(value: -4_278_190_081, width: 32))
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(mod)
      expect(mlir).to include('hw.constant -1 : i32')
      expect(mlir).to include('hw.constant 16777215 : i32')
      expect(mlir).not_to include('hw.constant 4294967295 : i32')
      expect(mlir).not_to include('hw.constant -4278190081 : i32')

      Dir.mktmpdir('rhdl_mlir_const_wrap') do |dir|
        input_path = File.join(dir, 'const_wrap_demo.mlir')
        File.write(input_path, mlir)
        _stdout, stderr, status = Open3.capture3('circt-opt', input_path, '-o', File.join(dir, 'out.mlir'))
        expect(status.success?).to be(true), stderr
      end
    end

    it 'emits async memory reads as array state instead of seq.firmem read ports' do
      mod = ir::ModuleOp.new(
        name: 'async_mem_demo',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :rd, direction: :in, width: 2),
          ir::Port.new(name: :wr, direction: :in, width: 2),
          ir::Port.new(name: :we, direction: :in, width: 1),
          ir::Port.new(name: :din, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::MemoryRead.new(
              memory: :mem,
              addr: ir::Signal.new(name: :rd, width: 2),
              width: 8
            )
          )
        ],
        processes: [],
        instances: [],
        memories: [
          ir::Memory.new(name: :mem, depth: 4, width: 8)
        ],
        write_ports: [
          ir::MemoryWritePort.new(
            memory: :mem,
            clock: :clk,
            addr: ir::Signal.new(name: :wr, width: 2),
            data: ir::Signal.new(name: :din, width: 8),
            enable: ir::Signal.new(name: :we, width: 1)
          )
        ],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(mod)
      expect(mlir).to include('hw.array_get')
      expect(mlir).to include('hw.array_inject')
      expect(mlir).to include('seq.firreg')
      expect(mlir).not_to include('seq.firmem.read_port')

      imported = RHDL::Codegen.import_circt_mlir(mlir, strict: true, top: 'async_mem_demo')
      expect(imported).to be_success
    end

    it 'short-circuits mux emission when the condition resolves to a constant' do
      mod = ir::ModuleOp.new(
        name: 'const_mux_short_circuit',
        ports: [
          ir::Port.new(name: :y, direction: :out, width: 32)
        ],
        nets: [
          ir::Net.new(name: :cond, width: 1),
          ir::Net.new(name: :rec, width: 32)
        ],
        regs: [],
        assigns: [
          ir::Assign.new(target: :cond, expr: ir::Literal.new(value: 0, width: 1)),
          ir::Assign.new(target: :rec, expr: ir::Signal.new(name: :y, width: 32)),
          ir::Assign.new(
            target: :y,
            expr: ir::Mux.new(
              condition: ir::Signal.new(name: :cond, width: 1),
              when_true: ir::Signal.new(name: :rec, width: 32),
              when_false: ir::Literal.new(value: 42, width: 32),
              width: 32
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

      mlir = described_class.generate(mod)
      expect(mlir).not_to include('comb.mux')
      expect(mlir).to include('hw.constant 42')
    end

    it 'emits multiple modules when given a package' do
      pkg = ir::Package.new(
        modules: [
          ir::ModuleOp.new(
            name: 'a',
            ports: [],
            nets: [],
            regs: [],
            assigns: [],
            processes: [],
            instances: [],
            memories: [],
            write_ports: [],
            sync_read_ports: [],
            parameters: {}
          ),
          ir::ModuleOp.new(
            name: 'b',
            ports: [],
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
        ]
      )

      mlir = described_class.generate(pkg)
      expect(mlir).to include('hw.module @a')
      expect(mlir).to include('hw.module @b')
    end

    it 'lowers nested sequential if trees into mux expressions and one compreg per target' do
      mod = ir::ModuleOp.new(
        name: 'seq_nested_if',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :sel1, direction: :in, width: 1),
          ir::Port.new(name: :sel2, direction: :in, width: 1),
          ir::Port.new(name: :q, direction: :out, width: 8)
        ],
        nets: [],
        regs: [ir::Reg.new(name: :q, width: 8)],
        assigns: [],
        processes: [
          ir::Process.new(
            name: :seq_logic,
            clocked: true,
            clock: :clk,
            statements: [
              ir::If.new(
                condition: ir::Signal.new(name: :sel1, width: 1),
                then_statements: [
                  ir::If.new(
                    condition: ir::Signal.new(name: :sel2, width: 1),
                    then_statements: [ir::SeqAssign.new(target: :q, expr: ir::Literal.new(value: 1, width: 8))],
                    else_statements: [ir::SeqAssign.new(target: :q, expr: ir::Literal.new(value: 2, width: 8))]
                  )
                ],
                else_statements: [ir::SeqAssign.new(target: :q, expr: ir::Literal.new(value: 3, width: 8))]
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

      mlir = described_class.generate(mod)
      expect(mlir.scan(/comb\.mux/).length).to be >= 2
      expect(mlir.scan(/seq\.compreg/).length).to eq(1)
      expect(mlir).to include('hw.output')
    end

    it 'resizes sequential next-state expressions to the declared register width before seq.compreg' do
      mod = ir::ModuleOp.new(
        name: 'seq_width_trim',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :q, direction: :out, width: 8)
        ],
        nets: [],
        regs: [ir::Reg.new(name: :q, width: 8)],
        assigns: [],
        processes: [
          ir::Process.new(
            name: :seq_logic,
            clocked: true,
            clock: :clk,
            statements: [
              ir::SeqAssign.new(
                target: :q,
                expr: ir::BinaryOp.new(
                  op: :+,
                  left: ir::Signal.new(name: :q, width: 8),
                  right: ir::Signal.new(name: :a, width: 8),
                  width: 9
                )
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

      mlir = described_class.generate(mod)
      expect(mlir).to include('comb.extract')
      expect(mlir).to match(/seq\.compreg .* : i8/)
      expect(mlir).not_to match(/%q_8 = seq\.compreg .* : i9/)
    end

    it 'emits divu and modu for division and modulo binary ops' do
      mod = ir::ModuleOp.new(
        name: 'arith_div_mod',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :q, direction: :out, width: 8),
          ir::Port.new(name: :r, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :q,
            expr: ir::BinaryOp.new(
              op: :/,
              left: ir::Signal.new(name: :a, width: 8),
              right: ir::Signal.new(name: :b, width: 8),
              width: 8
            )
          ),
          ir::Assign.new(
            target: :r,
            expr: ir::BinaryOp.new(
              op: :%,
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

      mlir = described_class.generate(mod)
      expect(mlir).to include('comb.divu')
      expect(mlir).to include('comb.modu')
    end

    it 'emits canonical right-shift op spellings accepted by firtool' do
      mod = ir::ModuleOp.new(
        name: 'arith_shift_right',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :lu, direction: :out, width: 8),
          ir::Port.new(name: :as, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :lu,
            expr: ir::BinaryOp.new(
              op: :'>>',
              left: ir::Signal.new(name: :a, width: 8),
              right: ir::Signal.new(name: :b, width: 8),
              width: 8
            )
          ),
          ir::Assign.new(
            target: :as,
            expr: ir::BinaryOp.new(
              op: :'>>>',
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

      mlir = described_class.generate(mod)
      expect(mlir).to include('comb.shru')
      expect(mlir).to include('comb.shrs')
      expect(mlir).not_to include('comb.shr_u')
      expect(mlir).not_to include('comb.shr_s')
    end

    it 'emits icmp with operand width for unary-not and case-selector comparisons' do
      mod = ir::ModuleOp.new(
        name: 'icmp_widths',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y_not, direction: :out, width: 1),
          ir::Port.new(name: :y_case, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y_not,
            expr: ir::UnaryOp.new(
              op: :'!',
              operand: ir::Signal.new(name: :a, width: 8),
              width: 1
            )
          ),
          ir::Assign.new(
            target: :y_case,
            expr: ir::Case.new(
              selector: ir::Signal.new(name: :a, width: 8),
              cases: { [1] => ir::Literal.new(value: 7, width: 8) },
              default: ir::Literal.new(value: 0, width: 8),
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

      mlir = described_class.generate(mod)
      expect(mlir).to match(/comb\.icmp eq .* : i8/)
      expect(mlir).not_to match(/comb\.icmp eq .* : i1/)
    end

    it 'emits hw.instance operations and wires instance outputs into hw.output' do
      mod = ir::ModuleOp.new(
        name: 'top_with_instance',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: 'u__y', width: 8)],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::Signal.new(name: 'u__y', width: 8)
          )
        ],
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

      mlir = described_class.generate(mod)
      expect(mlir).to include('hw.instance "u" @child(')
      expect(mlir).to include('-> (y: i8)')
      expect(mlir).to include('hw.output %')
      expect(mlir).not_to include('hw.output %a : i8')
    end

    it 'orders instance inputs by callee signature and includes unconnected outputs' do
      child = ir::ModuleOp.new(
        name: 'child',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :rst, direction: :in, width: 1),
          ir::Port.new(name: :data_in, direction: :in, width: 8),
          ir::Port.new(name: :load, direction: :in, width: 1),
          ir::Port.new(name: :a, direction: :out, width: 8),
          ir::Port.new(name: :done, direction: :out, width: 1)
        ],
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

      parent = ir::ModuleOp.new(
        name: 'parent',
        ports: [
          ir::Port.new(name: :clk, direction: :in, width: 1),
          ir::Port.new(name: :rst, direction: :in, width: 1),
          ir::Port.new(name: :in_data, direction: :in, width: 8),
          ir::Port.new(name: :load, direction: :in, width: 1),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: :child_a, width: 8)],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: :child_a, width: 8))],
        processes: [],
        instances: [
          ir::Instance.new(
            name: 'u',
            module_name: 'child',
            connections: [
              ir::PortConnection.new(port_name: :load, signal: 'load', direction: :in),
              ir::PortConnection.new(port_name: :data_in, signal: 'in_data', direction: :in),
              ir::PortConnection.new(port_name: :clk, signal: 'clk', direction: :in),
              ir::PortConnection.new(port_name: :rst, signal: 'rst', direction: :in),
              ir::PortConnection.new(port_name: :a, signal: 'child_a', direction: :out)
            ],
            parameters: {}
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(ir::Package.new(modules: [child, parent]))
      instance_line = mlir.lines.find { |line| line.include?('hw.instance "u" @child(') }

      expect(instance_line).to include('clk: %clk: i1, rst: %rst: i1, data_in: %in_data: i8, load: %load: i1')
      expect(instance_line).to include('-> (a: i8, done: i1)')
    end

    it 'preserves forward references to later instance outputs through assign chains' do
      child = ir::ModuleOp.new(
        name: 'child_buf',
        ports: [
          ir::Port.new(name: :in, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::Signal.new(name: :in, width: 8)
          )
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      parent = ir::ModuleOp.new(
        name: 'parent_forward_ref',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [
          ir::Net.new(name: :forwarded, width: 8),
          ir::Net.new(name: :prod__y, width: 8),
          ir::Net.new(name: :cons__y, width: 8)
        ],
        regs: [],
        assigns: [
          ir::Assign.new(target: :forwarded, expr: ir::Signal.new(name: :prod__y, width: 8)),
          ir::Assign.new(target: :y, expr: ir::Signal.new(name: :cons__y, width: 8))
        ],
        processes: [],
        instances: [
          ir::Instance.new(
            name: 'cons',
            module_name: 'child_buf',
            connections: [
              ir::PortConnection.new(port_name: :in, signal: 'forwarded', direction: :in),
              ir::PortConnection.new(port_name: :y, signal: 'cons__y', direction: :out)
            ],
            parameters: {}
          ),
          ir::Instance.new(
            name: 'prod',
            module_name: 'child_buf',
            connections: [
              ir::PortConnection.new(port_name: :in, signal: 'a', direction: :in),
              ir::PortConnection.new(port_name: :y, signal: 'prod__y', direction: :out)
            ],
            parameters: {}
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(ir::Package.new(modules: [child, parent]))
      cons_line = mlir.lines.find { |line| line.include?('hw.instance "cons" @child_buf(') }
      prod_line = mlir.lines.find { |line| line.include?('hw.instance "prod" @child_buf(') }

      expect(cons_line).to include('in: %prod__y_8: i8')
      expect(prod_line).to include('%prod__y_8 = hw.instance "prod" @child_buf(')
    end

    it 'prefers non-default internal drivers over trailing zero initializers' do
      mod = ir::ModuleOp.new(
        name: 'internal_driver_preference',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: :w, width: 8)],
        regs: [],
        assigns: [
          ir::Assign.new(target: :w, expr: ir::Signal.new(name: :a, width: 8)),
          ir::Assign.new(target: :w, expr: ir::Literal.new(value: 0, width: 8)),
          ir::Assign.new(target: :y, expr: ir::Signal.new(name: :w, width: 8))
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(mod)
      expect(mlir).to include('hw.output %a : i8')
    end

    it 'or-combines multiple live internal drivers for the same net' do
      mod = ir::ModuleOp.new(
        name: 'internal_driver_merge',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :b, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: :w, width: 8)],
        regs: [],
        assigns: [
          ir::Assign.new(target: :w, expr: ir::Signal.new(name: :a, width: 8)),
          ir::Assign.new(target: :w, expr: ir::Signal.new(name: :b, width: 8)),
          ir::Assign.new(target: :w, expr: ir::Literal.new(value: 0, width: 8)),
          ir::Assign.new(target: :y, expr: ir::Signal.new(name: :w, width: 8))
        ],
        processes: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(mod)
      expect(mlir).to include('comb.or %a, %b : i8')
      expect(mlir).to include('hw.output %')
    end

    it 'emits signed icmp predicates when comparing against negative literals' do
      mod = ir::ModuleOp.new(
        name: 'signed_compare',
        ports: [
          ir::Port.new(name: :addr, direction: :in, width: 32),
          ir::Port.new(name: :y, direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :y,
            expr: ir::BinaryOp.new(
              op: :>,
              left: ir::Signal.new(name: :addr, width: 32),
              right: ir::Literal.new(value: -1, width: 32),
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

      mlir = described_class.generate(mod)
      expect(mlir).to include('comb.icmp sgt')
      expect(mlir).not_to include('comb.icmp ugt')
    end

    it 'emits hw.instance parameter lists for integer and boolean params' do
      mod = ir::ModuleOp.new(
        name: 'top_with_param_instance',
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
            parameters: { width: 8, enable: true }
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      mlir = described_class.generate(mod)
      expect(mlir).to include('@child<width: i4 = 8, enable: i1 = 1>')
    end

    it 'emits hw.module parameter lists for integer and boolean params' do
      mod = ir::ModuleOp.new(
        name: 'param_mod',
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
        parameters: { width: 8, enable: true }
      )

      mlir = described_class.generate(mod)
      expect(mlir).to include('hw.module @param_mod<width: i4 = 8, enable: i1 = 1>(in %a: i8, out y: i8) {')
    end
  end
end
