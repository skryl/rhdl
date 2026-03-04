# frozen_string_literal: true

require 'json'

module RHDL
  module Codegen
    module CIRCT
      module RuntimeJSON
        module_function

        def dump(nodes_or_package)
          modules = case nodes_or_package
                    when IR::Package
                      nodes_or_package.modules
                    when Array
                      nodes_or_package
                    else
                      [nodes_or_package]
                    end

          payload = {
            circt_json_version: 1,
            dialects: %w[hw comb seq],
            modules: modules.map { |mod| serialize_module(mod) }
          }

          JSON.generate(payload, max_nesting: false)
        end

        def serialize_module(mod)
          {
            name: mod.name.to_s,
            ports: mod.ports.map { |p| serialize_port(p) },
            nets: mod.nets.map { |n| { name: n.name.to_s, width: n.width.to_i } },
            regs: mod.regs.map { |r| { name: r.name.to_s, width: r.width.to_i, reset_value: r.reset_value } },
            assigns: mod.assigns.map { |a| { target: a.target.to_s, expr: serialize_expr(a.expr) } },
            processes: mod.processes.map { |p| serialize_process(p) },
            instances: mod.instances.map { |i| serialize_instance(i) },
            memories: mod.memories.map { |m| serialize_memory(m) },
            write_ports: mod.write_ports.map { |w| serialize_write_port(w) },
            sync_read_ports: mod.sync_read_ports.map { |r| serialize_sync_read_port(r) },
            parameters: mod.parameters || {}
          }
        end

        def serialize_port(port)
          {
            name: port.name.to_s,
            direction: port.direction.to_s,
            width: port.width.to_i,
            default: port.default
          }
        end

        def serialize_process(process)
          {
            name: process.name.to_s,
            clocked: !!process.clocked,
            clock: process.clock&.to_s,
            sensitivity_list: Array(process.sensitivity_list).map(&:to_s),
            statements: Array(process.statements).map { |s| serialize_stmt(s) }
          }
        end

        def serialize_stmt(stmt)
          case stmt
          when IR::SeqAssign
            {
              kind: 'seq_assign',
              target: stmt.target.to_s,
              expr: serialize_expr(stmt.expr)
            }
          when IR::If
            {
              kind: 'if',
              condition: serialize_expr(stmt.condition),
              then_statements: Array(stmt.then_statements).map { |s| serialize_stmt(s) },
              else_statements: Array(stmt.else_statements).map { |s| serialize_stmt(s) }
            }
          else
            {
              kind: 'unknown',
              class: stmt.class.to_s
            }
          end
        end

        def serialize_expr(expr)
          case expr
          when IR::Signal
            { kind: 'signal', name: expr.name.to_s, width: expr.width.to_i }
          when IR::Literal
            { kind: 'literal', value: expr.value.to_i, width: expr.width.to_i }
          when IR::UnaryOp
            { kind: 'unary', op: expr.op.to_s, operand: serialize_expr(expr.operand), width: expr.width.to_i }
          when IR::BinaryOp
            {
              kind: 'binary',
              op: expr.op.to_s,
              left: serialize_expr(expr.left),
              right: serialize_expr(expr.right),
              width: expr.width.to_i
            }
          when IR::Mux
            {
              kind: 'mux',
              condition: serialize_expr(expr.condition),
              when_true: serialize_expr(expr.when_true),
              when_false: serialize_expr(expr.when_false),
              width: expr.width.to_i
            }
          when IR::Slice
            {
              kind: 'slice',
              base: serialize_expr(expr.base),
              range_begin: expr.range.begin,
              range_end: expr.range.end,
              width: expr.width.to_i
            }
          when IR::Concat
            {
              kind: 'concat',
              parts: expr.parts.map { |p| serialize_expr(p) },
              width: expr.width.to_i
            }
          when IR::Resize
            {
              kind: 'resize',
              expr: serialize_expr(expr.expr),
              width: expr.width.to_i
            }
          when IR::Case
            {
              kind: 'case',
              selector: serialize_expr(expr.selector),
              cases: expr.cases.transform_values { |v| serialize_expr(v) },
              default: expr.default ? serialize_expr(expr.default) : nil,
              width: expr.width.to_i
            }
          when IR::MemoryRead
            {
              kind: 'memory_read',
              memory: expr.memory.to_s,
              addr: serialize_expr(expr.addr),
              width: expr.width.to_i
            }
          else
            {
              kind: 'unknown',
              class: expr.class.to_s
            }
          end
        end

        def serialize_instance(instance)
          {
            name: instance.name.to_s,
            module_name: instance.module_name.to_s,
            parameters: instance.parameters || {},
            connections: instance.connections.map do |c|
              {
                port_name: c.port_name.to_s,
                signal: c.signal.respond_to?(:width) ? serialize_expr(c.signal) : c.signal.to_s,
                direction: c.direction.to_s
              }
            end
          }
        end

        def serialize_memory(memory)
          {
            name: memory.name.to_s,
            depth: memory.depth.to_i,
            width: memory.width.to_i,
            initial_data: memory.initial_data
          }
        end

        def serialize_write_port(wp)
          {
            memory: wp.memory.to_s,
            clock: wp.clock.to_s,
            addr: serialize_expr(wp.addr),
            data: serialize_expr(wp.data),
            enable: serialize_expr(wp.enable)
          }
        end

        def serialize_sync_read_port(rp)
          {
            memory: rp.memory.to_s,
            clock: rp.clock.to_s,
            addr: serialize_expr(rp.addr),
            data: rp.data.to_s,
            enable: rp.enable ? serialize_expr(rp.enable) : nil
          }
        end
      end
    end
  end
end
