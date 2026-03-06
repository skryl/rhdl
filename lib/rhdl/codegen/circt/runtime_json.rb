# frozen_string_literal: true

require 'json'
require 'set'

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

          modules = normalize_modules_for_runtime(modules)
          expr_cache = {}
          payload = {
            circt_json_version: 1,
            dialects: %w[hw comb seq],
            modules: modules.map { |mod| serialize_module(mod, expr_cache: expr_cache) }
          }

          JSON.generate(payload, max_nesting: false)
        end

        def normalize_modules_for_runtime(modules)
          Array(modules).map { |mod| normalize_module_for_runtime(mod) }
        end

        def normalize_module_for_runtime(mod)
          temp_counter = 0
          extra_nets = []
          extra_assigns = []

          normalized_assigns = mod.assigns.map do |assign|
            expr, hoisted_assigns = hoist_shared_exprs_to_assigns(
              assign.expr,
              temp_counter: temp_counter,
              prefix: "#{assign.target}_rt"
            )
            temp_counter += hoisted_assigns.length
            hoisted_assigns.each do |hoisted|
              extra_assigns << hoisted[:assign]
              extra_nets << hoisted[:net]
            end
            IR::Assign.new(target: assign.target, expr: expr)
          end

          normalized_processes = mod.processes.map do |process|
            statements, hoisted_assigns, hoisted_nets = normalize_process_statements(
              process.statements,
              temp_counter: temp_counter,
              prefix: "#{process.name}_rt"
            )
            temp_counter += hoisted_assigns.length
            extra_assigns.concat(hoisted_assigns)
            extra_nets.concat(hoisted_nets)
            IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: process.clocked,
              clock: process.clock,
              sensitivity_list: process.sensitivity_list
            )
          end

          IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports,
            nets: dedupe_by_name(mod.nets + extra_nets),
            regs: mod.regs,
            assigns: extra_assigns + normalized_assigns,
            processes: normalized_processes,
            instances: mod.instances,
            memories: mod.memories,
            write_ports: mod.write_ports,
            sync_read_ports: mod.sync_read_ports,
            parameters: mod.parameters || {}
          )
        end

        def normalize_process_statements(statements, temp_counter:, prefix:)
          extra_assigns = []
          extra_nets = []
          normalized = Array(statements).map do |stmt|
            case stmt
            when IR::SeqAssign
              expr, hoisted_assigns = hoist_shared_exprs_to_assigns(
                stmt.expr,
                temp_counter: temp_counter + extra_assigns.length,
                prefix: "#{prefix}_#{stmt.target}"
              )
              hoisted_assigns.each do |hoisted|
                extra_assigns << hoisted[:assign]
                extra_nets << hoisted[:net]
              end
              IR::SeqAssign.new(target: stmt.target, expr: expr)
            when IR::If
              cond, hoisted_assigns = hoist_shared_exprs_to_assigns(
                stmt.condition,
                temp_counter: temp_counter + extra_assigns.length,
                prefix: "#{prefix}_if"
              )
              hoisted_assigns.each do |hoisted|
                extra_assigns << hoisted[:assign]
                extra_nets << hoisted[:net]
              end
              then_stmts, then_assigns, then_nets = normalize_process_statements(
                stmt.then_statements,
                temp_counter: temp_counter + extra_assigns.length,
                prefix: "#{prefix}_then"
              )
              else_stmts, else_assigns, else_nets = normalize_process_statements(
                stmt.else_statements,
                temp_counter: temp_counter + extra_assigns.length + then_assigns.length,
                prefix: "#{prefix}_else"
              )
              extra_assigns.concat(then_assigns)
              extra_assigns.concat(else_assigns)
              extra_nets.concat(then_nets)
              extra_nets.concat(else_nets)
              IR::If.new(condition: cond, then_statements: then_stmts, else_statements: else_stmts)
            else
              stmt
            end
          end

          [normalized, extra_assigns, extra_nets]
        end

        def hoist_shared_exprs_to_assigns(expr, temp_counter:, prefix:)
          counts = parent_counts(expr)
          hoisted = {}
          assigns = []
          rewritten = rewrite_expr_for_runtime(
            expr,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: sanitize_runtime_name(prefix),
            counter: temp_counter
          )
          [rewritten, assigns]
        end

        def rewrite_expr_for_runtime(expr, counts:, hoisted:, assigns:, prefix:, counter:)
          return expr if expr.nil? || expr.is_a?(IR::Literal) || expr.is_a?(IR::Signal)

          oid = expr.object_id
          return hoisted[oid][:signal] if hoisted.key?(oid)

          rewritten_children = expr_children(expr).map do |child|
            rewrite_expr_for_runtime(
              child,
              counts: counts,
              hoisted: hoisted,
              assigns: assigns,
              prefix: prefix,
              counter: counter + assigns.length
            )
          end
          rewritten = rebuild_expr(expr, rewritten_children)

          if counts[oid].to_i > 1
            name = sanitize_runtime_name("#{prefix}_tmp_#{counter + assigns.length}")
            signal = IR::Signal.new(name: name, width: expr.width.to_i)
            hoisted[oid] = { signal: signal }
            assigns << {
              net: IR::Net.new(name: name.to_sym, width: expr.width.to_i),
              assign: IR::Assign.new(target: name, expr: rewritten)
            }
            signal
          else
            rewritten
          end
        end

        def parent_counts(root)
          counts = Hash.new(0)
          seen = Set.new
          stack = [root]

          until stack.empty?
            expr = stack.pop
            next if expr.nil?

            children = expr_children(expr)
            children.each { |child| counts[child.object_id] += 1 }

            oid = expr.object_id
            next if seen.include?(oid)

            seen << oid
            children.each { |child| stack << child }
          end

          counts
        end

        def expr_children(expr)
          case expr
          when IR::UnaryOp
            [expr.operand]
          when IR::BinaryOp
            [expr.left, expr.right]
          when IR::Mux
            [expr.condition, expr.when_true, expr.when_false]
          when IR::Slice
            [expr.base]
          when IR::Concat
            Array(expr.parts)
          when IR::Resize
            [expr.expr]
          when IR::Case
            [expr.selector, expr.default, *expr.cases.values]
          when IR::MemoryRead
            [expr.addr]
          else
            []
          end.compact
        end

        def rebuild_expr(expr, children)
          case expr
          when IR::UnaryOp
            IR::UnaryOp.new(op: expr.op, operand: children.fetch(0), width: expr.width.to_i)
          when IR::BinaryOp
            IR::BinaryOp.new(op: expr.op, left: children.fetch(0), right: children.fetch(1), width: expr.width.to_i)
          when IR::Mux
            IR::Mux.new(
              condition: children.fetch(0),
              when_true: children.fetch(1),
              when_false: children.fetch(2),
              width: expr.width.to_i
            )
          when IR::Slice
            IR::Slice.new(base: children.fetch(0), range: expr.range, width: expr.width.to_i)
          when IR::Concat
            IR::Concat.new(parts: children, width: expr.width.to_i)
          when IR::Resize
            IR::Resize.new(expr: children.fetch(0), width: expr.width.to_i)
          when IR::Case
            IR::Case.new(
              selector: children.fetch(0),
              cases: expr.cases.keys.zip(children.drop(2)).to_h,
              default: children.fetch(1),
              width: expr.width.to_i
            )
          when IR::MemoryRead
            IR::MemoryRead.new(memory: expr.memory, addr: children.fetch(0), width: expr.width.to_i)
          else
            expr
          end
        end

        def dedupe_by_name(entries)
          entries.uniq { |entry| entry.name.to_s }
        end

        def sanitize_runtime_name(name)
          value = name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          value = "_#{value}" if value.empty? || value.match?(/\A\d/)
          value
        end

        def serialize_module(mod, expr_cache:)
          {
            name: mod.name.to_s,
            ports: mod.ports.map { |p| serialize_port(p) },
            nets: mod.nets.map { |n| { name: n.name.to_s, width: n.width.to_i } },
            regs: mod.regs.map { |r| { name: r.name.to_s, width: r.width.to_i, reset_value: r.reset_value } },
            assigns: mod.assigns.map { |a| { target: a.target.to_s, expr: serialize_expr(a.expr, cache: expr_cache) } },
            processes: mod.processes.map { |p| serialize_process(p, expr_cache: expr_cache) },
            instances: mod.instances.map { |i| serialize_instance(i, expr_cache: expr_cache) },
            memories: mod.memories.map { |m| serialize_memory(m) },
            write_ports: mod.write_ports.map { |w| serialize_write_port(w, expr_cache: expr_cache) },
            sync_read_ports: mod.sync_read_ports.map { |r| serialize_sync_read_port(r, expr_cache: expr_cache) },
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

        def serialize_process(process, expr_cache:)
          {
            name: process.name.to_s,
            clocked: !!process.clocked,
            clock: process.clock&.to_s,
            sensitivity_list: Array(process.sensitivity_list).map(&:to_s),
            statements: Array(process.statements).map { |s| serialize_stmt(s, expr_cache: expr_cache) }
          }
        end

        def serialize_stmt(stmt, expr_cache:)
          case stmt
          when IR::SeqAssign
            {
              kind: 'seq_assign',
              target: stmt.target.to_s,
              expr: serialize_expr(stmt.expr, cache: expr_cache)
            }
          when IR::If
            {
              kind: 'if',
              condition: serialize_expr(stmt.condition, cache: expr_cache),
              then_statements: Array(stmt.then_statements).map { |s| serialize_stmt(s, expr_cache: expr_cache) },
              else_statements: Array(stmt.else_statements).map { |s| serialize_stmt(s, expr_cache: expr_cache) }
            }
          else
            {
              kind: 'unknown',
              class: stmt.class.to_s
            }
          end
        end

        def serialize_expr(expr, cache:)
          return nil if expr.nil?

          key = expr.object_id
          return cache[key] if cache.key?(key)

          cache[key] = case expr
          when IR::Signal
            { kind: 'signal', name: expr.name.to_s, width: expr.width.to_i }
          when IR::Literal
            { kind: 'literal', value: expr.value.to_i, width: expr.width.to_i }
          when IR::UnaryOp
            { kind: 'unary', op: expr.op.to_s, operand: serialize_expr(expr.operand, cache: cache), width: expr.width.to_i }
          when IR::BinaryOp
            {
              kind: 'binary',
              op: expr.op.to_s,
              left: serialize_expr(expr.left, cache: cache),
              right: serialize_expr(expr.right, cache: cache),
              width: expr.width.to_i
            }
          when IR::Mux
            {
              kind: 'mux',
              condition: serialize_expr(expr.condition, cache: cache),
              when_true: serialize_expr(expr.when_true, cache: cache),
              when_false: serialize_expr(expr.when_false, cache: cache),
              width: expr.width.to_i
            }
          when IR::Slice
            {
              kind: 'slice',
              base: serialize_expr(expr.base, cache: cache),
              range_begin: expr.range.begin,
              range_end: expr.range.end,
              width: expr.width.to_i
            }
          when IR::Concat
            {
              kind: 'concat',
              parts: expr.parts.map { |p| serialize_expr(p, cache: cache) },
              width: expr.width.to_i
            }
          when IR::Resize
            {
              kind: 'resize',
              expr: serialize_expr(expr.expr, cache: cache),
              width: expr.width.to_i
            }
          when IR::Case
            {
              kind: 'case',
              selector: serialize_expr(expr.selector, cache: cache),
              cases: expr.cases.transform_values { |v| serialize_expr(v, cache: cache) },
              default: expr.default ? serialize_expr(expr.default, cache: cache) : nil,
              width: expr.width.to_i
            }
          when IR::MemoryRead
            {
              kind: 'memory_read',
              memory: expr.memory.to_s,
              addr: serialize_expr(expr.addr, cache: cache),
              width: expr.width.to_i
            }
          else
            {
              kind: 'unknown',
              class: expr.class.to_s
            }
          end
        end

        def serialize_instance(instance, expr_cache:)
          {
            name: instance.name.to_s,
            module_name: instance.module_name.to_s,
            parameters: instance.parameters || {},
            connections: instance.connections.map do |c|
              {
                port_name: c.port_name.to_s,
                signal: c.signal.respond_to?(:width) ? serialize_expr(c.signal, cache: expr_cache) : c.signal.to_s,
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

        def serialize_write_port(wp, expr_cache:)
          {
            memory: wp.memory.to_s,
            clock: wp.clock.to_s,
            addr: serialize_expr(wp.addr, cache: expr_cache),
            data: serialize_expr(wp.data, cache: expr_cache),
            enable: serialize_expr(wp.enable, cache: expr_cache)
          }
        end

        def serialize_sync_read_port(rp, expr_cache:)
          {
            memory: rp.memory.to_s,
            clock: rp.clock.to_s,
            addr: serialize_expr(rp.addr, cache: expr_cache),
            data: rp.data.to_s,
            enable: rp.enable ? serialize_expr(rp.enable, cache: expr_cache) : nil
          }
        end
      end
    end
  end
end
