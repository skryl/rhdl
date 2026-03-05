# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Codegen::CIRCT::MLIR do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  describe '.generate' do
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
