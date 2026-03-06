# frozen_string_literal: true

require 'set'

module RHDL
  module Codegen
    module CIRCT
      module Flatten
        module_function

        def to_flat_module(nodes_or_package, top:)
          modules = case nodes_or_package
                    when IR::Package
                      nodes_or_package.modules
                    when Array
                      nodes_or_package
                    else
                      [nodes_or_package]
                    end

          module_index = modules.each_with_object({}) { |mod, acc| acc[mod.name.to_s] = mod }
          top_name = top.to_s
          top_module = module_index[top_name]
          raise KeyError, "Top module '#{top_name}' not found in CIRCT package" unless top_module

          flatten_module(
            mod: top_module,
            module_index: module_index,
            top_name: top_module.name.to_s,
            prefix: ''
          )
        end

        def flatten_module(mod:, module_index:, top_name:, prefix:)
          expr_cache = {}
          all_ports = prefix.empty? ? mod.ports.map { |port| copy_port(port) } : []
          all_nets = mod.nets.map { |net| prefix_net(net, prefix) }
          all_regs = mod.regs.map { |reg| prefix_reg(reg, prefix) }
          all_assigns = mod.assigns.map { |assign| prefix_assign(assign, prefix, expr_cache: expr_cache) }
          all_processes = mod.processes.map { |process| prefix_process(process, prefix, expr_cache: expr_cache) }
          all_memories = mod.memories.map { |memory| prefix_memory(memory, prefix) }
          all_write_ports = mod.write_ports.map { |wp| prefix_write_port(wp, prefix, expr_cache: expr_cache) }
          all_sync_read_ports = mod.sync_read_ports.map { |rp| prefix_sync_read_port(rp, prefix, expr_cache: expr_cache) }

          unless prefix.empty?
            mod.ports.each do |port|
              next unless port.direction.to_s == 'out'

              prefixed_name = :"#{prefix}__#{port.name}"
              next if all_nets.any? { |net| net.name.to_s == prefixed_name.to_s }
              next if all_regs.any? { |reg| reg.name.to_s == prefixed_name.to_s }

              all_nets << IR::Net.new(name: prefixed_name, width: port.width)
            end
          end

          mod.instances.each do |inst|
            child_mod = module_index.fetch(inst.module_name.to_s) do
              raise KeyError, "Missing CIRCT module definition for instance target '#{inst.module_name}'"
            end
            inst_prefix = prefix.empty? ? inst.name.to_s : "#{prefix}__#{inst.name}"

            child_flat = flatten_module(
              mod: child_mod,
              module_index: module_index,
              top_name: top_name,
              prefix: inst_prefix
            )

            all_nets.concat(child_flat.nets)
            all_regs.concat(child_flat.regs)
            all_assigns.concat(child_flat.assigns)
            all_processes.concat(child_flat.processes)
            all_memories.concat(child_flat.memories)
            all_write_ports.concat(child_flat.write_ports)
            all_sync_read_ports.concat(child_flat.sync_read_ports)

            connected_ports = Set.new
            inst.connections.each do |conn|
              port_name = conn.port_name.to_s
              connected_ports << port_name

              port_def = child_mod.ports.find { |port| port.name.to_s == port_name }
              port_width = connection_width(conn, port_def)
              child_signal = "#{inst_prefix}__#{port_name}"

              if conn.direction.to_s == 'out'
                parent_target = prefixed_target_name(conn.signal, prefix)
                next if parent_target.nil?

                all_assigns << IR::Assign.new(
                  target: parent_target,
                  expr: IR::Signal.new(name: child_signal, width: port_width)
                )
              else
                child_expr = prefixed_connection_expr(
                  conn.signal,
                  prefix,
                  width_hint: port_width,
                  expr_cache: expr_cache
                )
                next if child_expr.nil?

                all_assigns << IR::Assign.new(
                  target: child_signal,
                  expr: child_expr
                )
              end

              ensure_net_present(all_nets, all_regs, child_signal, port_width)
            end

            child_mod.ports.each do |port|
              next if connected_ports.include?(port.name.to_s)
              next unless port.direction.to_s == 'in'
              next if port.default.nil?

              child_signal = "#{inst_prefix}__#{port.name}"
              all_assigns << IR::Assign.new(
                target: child_signal,
                expr: IR::Literal.new(value: port.default.to_i, width: port.width.to_i)
              )
              ensure_net_present(all_nets, all_regs, child_signal, port.width.to_i)
            end
          end

          IR::ModuleOp.new(
            name: top_name,
            ports: all_ports,
            nets: dedupe_by_name(all_nets),
            regs: dedupe_by_name(all_regs),
            assigns: all_assigns,
            processes: all_processes,
            instances: [],
            memories: dedupe_by_name(all_memories),
            write_ports: all_write_ports,
            sync_read_ports: all_sync_read_ports,
            parameters: mod.parameters || {}
          )
        end

        def copy_port(port)
          IR::Port.new(
            name: port.name,
            direction: port.direction,
            width: port.width,
            default: port.default
          )
        end

        def prefix_net(net, prefix)
          return net if prefix.empty?

          IR::Net.new(name: :"#{prefix}__#{net.name}", width: net.width)
        end

        def prefix_reg(reg, prefix)
          return reg if prefix.empty?

          IR::Reg.new(name: :"#{prefix}__#{reg.name}", width: reg.width, reset_value: reg.reset_value)
        end

        def prefix_assign(assign, prefix, expr_cache:)
          return assign if prefix.empty?

          IR::Assign.new(
            target: "#{prefix}__#{assign.target}",
            expr: prefix_expr(assign.expr, prefix, cache: expr_cache)
          )
        end

        def prefix_process(process, prefix, expr_cache:)
          return process if prefix.empty?

          IR::Process.new(
            name: :"#{prefix}__#{process.name}",
            statements: process.statements.map { |stmt| prefix_stmt(stmt, prefix, expr_cache: expr_cache) },
            clocked: process.clocked,
            clock: process.clock ? "#{prefix}__#{process.clock}" : nil,
            sensitivity_list: Array(process.sensitivity_list).map { |entry| "#{prefix}__#{entry}" }
          )
        end

        def prefix_stmt(stmt, prefix, expr_cache:)
          case stmt
          when IR::SeqAssign
            IR::SeqAssign.new(
              target: "#{prefix}__#{stmt.target}",
              expr: prefix_expr(stmt.expr, prefix, cache: expr_cache)
            )
          when IR::If
            IR::If.new(
              condition: prefix_expr(stmt.condition, prefix, cache: expr_cache),
              then_statements: Array(stmt.then_statements).map { |sub| prefix_stmt(sub, prefix, expr_cache: expr_cache) },
              else_statements: Array(stmt.else_statements).map { |sub| prefix_stmt(sub, prefix, expr_cache: expr_cache) }
            )
          else
            stmt
          end
        end

        def prefix_expr(expr, prefix, cache:)
          return expr if expr.nil? || prefix.empty?

          key = [prefix, expr.object_id]
          return cache[key] if cache.key?(key)

          cache[key] = case expr
          when IR::Signal
            IR::Signal.new(name: "#{prefix}__#{expr.name}", width: expr.width)
          when IR::Literal
            expr
          when IR::UnaryOp
            IR::UnaryOp.new(op: expr.op, operand: prefix_expr(expr.operand, prefix, cache: cache), width: expr.width)
          when IR::BinaryOp
            IR::BinaryOp.new(
              op: expr.op,
              left: prefix_expr(expr.left, prefix, cache: cache),
              right: prefix_expr(expr.right, prefix, cache: cache),
              width: expr.width
            )
          when IR::Mux
            IR::Mux.new(
              condition: prefix_expr(expr.condition, prefix, cache: cache),
              when_true: prefix_expr(expr.when_true, prefix, cache: cache),
              when_false: prefix_expr(expr.when_false, prefix, cache: cache),
              width: expr.width
            )
          when IR::Slice
            IR::Slice.new(base: prefix_expr(expr.base, prefix, cache: cache), range: expr.range, width: expr.width)
          when IR::Concat
            IR::Concat.new(parts: expr.parts.map { |part| prefix_expr(part, prefix, cache: cache) }, width: expr.width)
          when IR::Resize
            IR::Resize.new(expr: prefix_expr(expr.expr, prefix, cache: cache), width: expr.width)
          when IR::Case
            IR::Case.new(
              selector: prefix_expr(expr.selector, prefix, cache: cache),
              cases: expr.cases.transform_values { |value| prefix_expr(value, prefix, cache: cache) },
              default: expr.default ? prefix_expr(expr.default, prefix, cache: cache) : nil,
              width: expr.width
            )
          when IR::MemoryRead
            IR::MemoryRead.new(
              memory: "#{prefix}__#{expr.memory}",
              addr: prefix_expr(expr.addr, prefix, cache: cache),
              width: expr.width
            )
          else
            expr
          end
        end

        def prefix_memory(memory, prefix)
          return memory if prefix.empty?

          IR::Memory.new(
            name: "#{prefix}__#{memory.name}",
            depth: memory.depth,
            width: memory.width,
            read_ports: memory.read_ports,
            write_ports: memory.write_ports,
            initial_data: memory.initial_data
          )
        end

        def prefix_write_port(write_port, prefix, expr_cache:)
          return write_port if prefix.empty?

          IR::MemoryWritePort.new(
            memory: "#{prefix}__#{write_port.memory}",
            clock: "#{prefix}__#{write_port.clock}",
            addr: prefix_expr(write_port.addr, prefix, cache: expr_cache),
            data: prefix_expr(write_port.data, prefix, cache: expr_cache),
            enable: prefix_expr(write_port.enable, prefix, cache: expr_cache)
          )
        end

        def prefix_sync_read_port(read_port, prefix, expr_cache:)
          return read_port if prefix.empty?

          IR::MemorySyncReadPort.new(
            memory: "#{prefix}__#{read_port.memory}",
            clock: "#{prefix}__#{read_port.clock}",
            addr: prefix_expr(read_port.addr, prefix, cache: expr_cache),
            data: "#{prefix}__#{read_port.data}",
            enable: read_port.enable ? prefix_expr(read_port.enable, prefix, cache: expr_cache) : nil
          )
        end

        def prefixed_target_name(signal, prefix)
          case signal
          when String, Symbol
            prefix.empty? ? signal.to_s : "#{prefix}__#{signal}"
          when IR::Signal
            prefix.empty? ? signal.name.to_s : "#{prefix}__#{signal.name}"
          else
            nil
          end
        end

        def prefixed_connection_expr(signal, prefix, width_hint:, expr_cache:)
          case signal
          when String, Symbol
            IR::Signal.new(
              name: prefix.empty? ? signal.to_s : "#{prefix}__#{signal}",
              width: width_hint
            )
          when IR::Signal
            IR::Signal.new(
              name: prefix.empty? ? signal.name.to_s : "#{prefix}__#{signal.name}",
              width: signal.width.to_i.positive? ? signal.width.to_i : width_hint
            )
          when IR::Expr
            prefix_expr(signal, prefix, cache: expr_cache)
          else
            nil
          end
        end

        def connection_width(conn, port_def)
          candidates = [conn.width, port_def&.width]
          expr_width = conn.signal.width if conn.signal.respond_to?(:width)
          candidates << expr_width
          width = candidates.compact.map(&:to_i).max
          width && width.positive? ? width : 1
        end

        def ensure_net_present(nets, regs, name, width)
          return if nets.any? { |net| net.name.to_s == name.to_s }
          return if regs.any? { |reg| reg.name.to_s == name.to_s }

          nets << IR::Net.new(name: name.to_sym, width: width.to_i)
        end

        def dedupe_by_name(entries)
          entries.uniq { |entry| entry.name.to_s }
        end
      end
    end
  end
end
