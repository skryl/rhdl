# frozen_string_literal: true

require 'set'

module RHDL
  module Codegen
    module CIRCT
      module MLIR
        module_function

        def generate(ir)
          case ir
          when IR::Package
            module_lookup = build_module_lookup(ir.modules)
            ir.modules.map { |mod| generate_module(mod, module_lookup: module_lookup) }.join("\n\n")
          when Array
            module_lookup = build_module_lookup(ir)
            ir.map { |mod| generate_module(mod, module_lookup: module_lookup) }.join("\n\n")
          else
            generate_module(ir)
          end
        end

        def generate_module(mod, module_lookup: nil)
          emitter = ModuleEmitter.new(mod, module_lookup: module_lookup || {})
          emitter.emit
        end

        def build_module_lookup(modules)
          modules.each_with_object({}) do |mod, map|
            key = mod.name.to_s
            map[key] = mod
            map[key.gsub(/[^A-Za-z0-9_]/, '_')] = mod
          end
        end

        class ModuleEmitter
          def initialize(mod, module_lookup: {})
            @mod = mod
            @module_lookup = module_lookup
            @lines = []
            @temp_idx = 0
            @values = {}
            @clock_values = {}
            @assign_map = {}
            @resolving = Set.new
          end

          def emit
            build_assign_map
            emit_header
            emit_reg_processes
            emit_instances
            emit_output
            @lines << '}'
            @lines.join("\n")
          end

          private

          def build_assign_map
            @mod.assigns.each do |assign|
              @assign_map[assign.target.to_s] = assign.expr
            end
          end

          def emit_header
            ports = @mod.ports.map do |port|
              direction = port.direction.to_s == 'out' ? 'out' : 'in'
              name = direction == 'out' ? sanitize(port.name) : "%#{sanitize(port.name)}"
              "#{direction} #{name}: #{iwidth(port.width)}"
            end
            module_params = module_params_suffix(@mod.parameters || {})
            @lines << "hw.module @#{sanitize(@mod.name)}#{module_params}(#{ports.join(', ')}) {"
          end

          def emit_reg_processes
            @mod.processes.each do |process|
              next unless process.clocked

              clock_name = process.clock ? process.clock.to_s : 'clk'
              clock_value = resolve_clock(clock_name)
              emit_seq_statements(process.statements, clock_value)
            end
          end

          def emit_instances
            @mod.instances.each do |instance|
              emit_instance(instance)
            end
          end

          def emit_instance(instance)
            conn_by_port = instance.connections.each_with_object({}) do |conn, map|
              map[conn.port_name.to_s] = conn
            end
            target_mod = resolve_instance_module(instance.module_name)

            if target_mod
              input_ports = target_mod.ports.select { |p| p.direction.to_s != 'out' }
              output_ports = target_mod.ports.select { |p| p.direction.to_s == 'out' }

              input_entries = input_ports.map do |port|
                conn = conn_by_port[port.name.to_s]
                width = conn ? connection_width(conn) : port.width
                value = conn ? connection_value(conn, width) : emit_zero(width)
                "#{sanitize(port.name)}: #{value}: #{iwidth(width)}"
              end

              output_entries = output_ports.map do |port|
                conn = conn_by_port[port.name.to_s]
                width = conn ? connection_width(conn) : port.width
                "#{sanitize(port.name)}: #{iwidth(width)}"
              end

              lhs = output_ports.map do |port|
                conn = conn_by_port[port.name.to_s]
                width = conn ? connection_width(conn) : port.width
                ssa = fresh(width)
                if conn
                  @values[conn.signal.to_s] = ssa
                end
                ssa
              end
            else
              input_conns = instance.connections.select { |c| c.direction.to_s != 'out' }
              output_conns = instance.connections.select { |c| c.direction.to_s == 'out' }

              input_entries = input_conns.map do |conn|
                width = connection_width(conn)
                value = connection_value(conn, width)
                "#{sanitize(conn.port_name)}: #{value}: #{iwidth(width)}"
              end

              output_entries = output_conns.map do |conn|
                width = connection_width(conn)
                "#{sanitize(conn.port_name)}: #{iwidth(width)}"
              end

              lhs = output_conns.map do |conn|
                width = connection_width(conn)
                ssa = fresh(width)
                @values[conn.signal.to_s] = ssa
                ssa
              end
            end

            line = +'  '
            line << "#{lhs.join(', ')} = " unless lhs.empty?
            line << 'hw.instance '
            line << mlir_string(instance.name)
            line << " @#{sanitize(instance.module_name)}#{instance_params_suffix(instance.parameters || {})}"
            line << "(#{input_entries.join(', ')})"
            line << " -> (#{output_entries.join(', ')})"
            @lines << line
          end

          def resolve_instance_module(module_name)
            key = module_name.to_s
            @module_lookup[key] || @module_lookup[sanitize(key)]
          end

          def emit_seq_statements(statements, clock_value)
            seq_state = {}
            target_order = []
            lower_seq_statements(
              Array(statements),
              seq_state: seq_state,
              target_order: target_order
            )

            reg_tokens = {}
            target_order.each do |target|
              next unless seq_state.key?(target)
              expr = seq_state[target]
              width = expr.respond_to?(:width) ? expr.width : find_width(target)
              reg_tokens[target] = fresh(width)
              # Make current-cycle register values available while emitting next-state logic.
              @values[target.to_s] = reg_tokens[target]
            end

            target_order.each do |target|
              next unless seq_state.key?(target)
              expr = seq_state[target]
              width = expr.respond_to?(:width) ? expr.width : find_width(target)
              input_value = emit_expr(expr)
              reg = reg_tokens[target] || fresh(width)
              @lines << "  #{reg} = seq.compreg #{input_value}, #{clock_value} : #{iwidth(width)}"
              @values[target.to_s] = reg
            end
          end

          def lower_seq_statements(statements, seq_state:, target_order:)
            touched = Set.new

            Array(statements).each do |stmt|
              case stmt
              when IR::SeqAssign
                target = stmt.target.to_s
                seq_state[target] = stmt.expr
                target_order << target unless target_order.include?(target)
                touched << target
              when IR::If
                then_state = seq_state.dup
                else_state = seq_state.dup

                then_touched = lower_seq_statements(
                  stmt.then_statements,
                  seq_state: then_state,
                  target_order: target_order
                )
                else_touched = lower_seq_statements(
                  stmt.else_statements,
                  seq_state: else_state,
                  target_order: target_order
                )

                branch_targets = (then_touched + else_touched).uniq
                branch_targets.each do |target|
                  width = then_state[target]&.width || else_state[target]&.width || seq_state[target]&.width || find_width(target)
                  prior = seq_state[target] || IR::Signal.new(name: target, width: width)
                  when_true = then_state[target] || prior
                  when_false = else_state[target] || prior

                  seq_state[target] = IR::Mux.new(
                    condition: stmt.condition,
                    when_true: when_true,
                    when_false: when_false,
                    width: width
                  )
                  target_order << target unless target_order.include?(target)
                  touched << target
                end
              end
            end

            touched.to_a
          end

          def emit_output
            outputs = @mod.ports.select { |p| p.direction.to_s == 'out' }
            if outputs.empty?
              @lines << '  hw.output'
              return
            end

            values = outputs.map { |port| resolve_signal(port.name.to_s, port.width) }
            types = outputs.map { |port| iwidth(port.width) }
            @lines << "  hw.output #{values.join(', ')} : #{types.join(', ')}"
          end

          def connection_width(conn)
            signal = conn.signal
            return signal.width if signal.respond_to?(:width)
            return find_width(signal.to_s) if signal

            1
          end

          def connection_value(conn, width)
            signal = conn.signal
            return emit_expr(signal) if signal.respond_to?(:width)

            resolve_signal(signal.to_s, width)
          end

          def mlir_string(value)
            escaped = value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
            "\"#{escaped}\""
          end

	          def instance_params_suffix(parameters)
	            parts = parameters.map do |k, v|
	              case v
              when Integer
                width = [v.abs.bit_length + (v.negative? ? 1 : 0), 1].max
                "#{sanitize(k)}: i#{width} = #{v}"
              when true, false
                "#{sanitize(k)}: i1 = #{v ? 1 : 0}"
              end
            end.compact
            return '' if parts.empty?

	            "<#{parts.join(', ')}>"
	          end

	          def module_params_suffix(parameters)
	            instance_params_suffix(parameters)
	          end

          def resolve_signal(name, width)
            key = name.to_s
            return @values[key] if @values.key?(key)

            if input_port?(key)
              value = "%#{sanitize(key)}"
              @values[key] = value
              return value
            end

            if @resolving.include?(key)
              return emit_zero(width)
            end

            assigned = @assign_map[key]
            if assigned
              @resolving << key
              @values[key] = emit_expr(assigned)
              @resolving.delete(key)
              return @values[key]
            end

            # If we do not know this symbol yet, materialize a typed zero.
            @values[key] = emit_zero(width)
          end

          def emit_expr(expr)
            case expr
            when IR::Literal
              emit_const(expr.value, expr.width)
            when IR::Signal
              resolve_signal(expr.name.to_s, expr.width)
            when IR::BinaryOp
              emit_binary(expr)
            when IR::UnaryOp
              emit_unary(expr)
            when IR::Mux
              cond_raw = emit_expr(expr.condition)
              cond_width = expr.condition.respond_to?(:width) ? expr.condition.width : find_value_width(cond_raw)
              cond = resize_value(cond_raw, cond_width, 1)

              tval_raw = emit_expr(expr.when_true)
              twidth = expr.when_true.respond_to?(:width) ? expr.when_true.width : find_value_width(tval_raw)
              tval = resize_value(tval_raw, twidth, expr.width)

              fval_raw = emit_expr(expr.when_false)
              fwidth = expr.when_false.respond_to?(:width) ? expr.when_false.width : find_value_width(fval_raw)
              fval = resize_value(fval_raw, fwidth, expr.width)

              out = fresh(expr.width)
              @lines << "  #{out} = comb.mux #{cond}, #{tval}, #{fval} : #{iwidth(expr.width)}"
              out
            when IR::Slice
              base = emit_expr(expr.base)
              range_begin = expr.range.begin.to_i
              range_end = expr.range.end.to_i
              range_end -= 1 if expr.range.exclude_end?
              low = [range_begin, range_end].min
              base_width = [expr.base&.width.to_i, find_value_width(base), 1].max
              target_width = [expr.width.to_i, 1].max
              return emit_zero(target_width) if low >= base_width

              available_width = base_width - low
              extract_width = [available_width, target_width].min
              extracted = fresh(extract_width)
              @lines << "  #{extracted} = comb.extract #{base} from #{low} : (#{iwidth(base_width)}) -> #{iwidth(extract_width)}"
              resize_value(extracted, extract_width, target_width)
            when IR::Concat
              emit_concat(expr)
            when IR::Resize
              emit_resize(expr)
            when IR::Case
              emit_case(expr)
            when IR::MemoryRead
              out = fresh(expr.width)
              @lines << "  // Unsupported memory read lowering for #{expr.memory}; emitting zero"
              @lines << "  #{out} = hw.constant 0 : #{iwidth(expr.width)}"
              out
            else
              emit_zero(expr.respond_to?(:width) ? expr.width : 1)
            end
          end

          def emit_binary(expr)
            left = emit_expr(expr.left)
            right = emit_expr(expr.right)
            left_width = expr.left.respond_to?(:width) ? expr.left.width : find_value_width(left)
            right_width = expr.right.respond_to?(:width) ? expr.right.width : find_value_width(right)
            result_width = expr.width
            op = expr.op.to_s

            case op
            when '+', :+
              emit_comb('add', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '-', :-
              emit_comb('sub', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '*', :*
              emit_comb('mul', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '/', :/
              emit_comb('divu', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '%', :%
              emit_comb('modu', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '&', :&
              emit_comb('and', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '|', :|
              emit_comb('or', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '^', :^
              emit_comb('xor', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '<<', :'<<'
              emit_comb('shl', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '>>', :'>>'
              emit_comb('shru', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '>>>', :'>>>'
              emit_comb('shrs', resize_value(left, left_width, result_width), resize_value(right, right_width, result_width), result_width)
            when '==', :==
              cmp_width = [left_width.to_i, right_width.to_i, 1].max
              emit_icmp('eq', resize_value(left, left_width, cmp_width), resize_value(right, right_width, cmp_width), cmp_width)
            when '!=', :'!='
              cmp_width = [left_width.to_i, right_width.to_i, 1].max
              emit_icmp('ne', resize_value(left, left_width, cmp_width), resize_value(right, right_width, cmp_width), cmp_width)
            when '<', :<
              cmp_width = [left_width.to_i, right_width.to_i, 1].max
              emit_icmp('ult', resize_value(left, left_width, cmp_width), resize_value(right, right_width, cmp_width), cmp_width)
            when '<=', :<=
              cmp_width = [left_width.to_i, right_width.to_i, 1].max
              emit_icmp('ule', resize_value(left, left_width, cmp_width), resize_value(right, right_width, cmp_width), cmp_width)
            when '>', :>
              cmp_width = [left_width.to_i, right_width.to_i, 1].max
              emit_icmp('ugt', resize_value(left, left_width, cmp_width), resize_value(right, right_width, cmp_width), cmp_width)
            when '>=', :>=
              cmp_width = [left_width.to_i, right_width.to_i, 1].max
              emit_icmp('uge', resize_value(left, left_width, cmp_width), resize_value(right, right_width, cmp_width), cmp_width)
            else
              @lines << "  // Unsupported binary op #{op.inspect}; emitting zero"
              emit_zero(result_width)
            end
          end

          def emit_unary(expr)
            operand = emit_expr(expr.operand)
            op = expr.op.to_s

            case op
            when '~', :'~'
              all_ones = emit_const((1 << expr.width) - 1, expr.width)
              emit_comb('xor', operand, all_ones, expr.width)
            when '!', :'!'
              zero = emit_const(0, expr.operand.width)
              emit_icmp('eq', operand, zero, expr.operand.width)
            when '-', :-@
              zero = emit_const(0, expr.width)
              emit_comb('sub', zero, operand, expr.width)
            else
              @lines << "  // Unsupported unary op #{op.inspect}; emitting passthrough"
              operand
            end
          end

          def emit_case(expr)
            selector = emit_expr(expr.selector)
            result = if expr.default
                       default_raw = emit_expr(expr.default)
                       default_width = expr.default.respond_to?(:width) ? expr.default.width : find_value_width(default_raw)
                       resize_value(default_raw, default_width, expr.width)
                     else
                       emit_zero(expr.width)
                     end

            expr.cases.each do |keys, value_expr|
              value_raw = emit_expr(value_expr)
              value_width = value_expr.respond_to?(:width) ? value_expr.width : find_value_width(value_raw)
              value = resize_value(value_raw, value_width, expr.width)
              Array(keys).reverse_each do |key|
                key_val = emit_const(key.to_i, expr.selector.width)
                cond = emit_icmp('eq', selector, key_val, expr.selector.width)
                mux = fresh(expr.width)
                @lines << "  #{mux} = comb.mux #{cond}, #{value}, #{result} : #{iwidth(expr.width)}"
                result = mux
              end
            end

            result
          end

          def emit_concat(expr)
            parts = expr.parts.map { |p| emit_expr(p) }
            types = parts.map { |value| iwidth(find_value_width(value)) }
            out = fresh(expr.width)
            @lines << "  #{out} = comb.concat #{parts.join(', ')} : #{types.join(', ')}"
            out
          end

          def emit_resize(expr)
            current = emit_expr(expr.expr)
            current_width = expr.expr.width
            target_width = expr.width
            resize_value(current, current_width, target_width)
          end

          def emit_const(value, width)
            out = fresh(width)
            @lines << "  #{out} = hw.constant #{value} : #{iwidth(width)}"
            out
          end

          def emit_zero(width)
            emit_const(0, width)
          end

          def resolve_clock(name)
            key = name.to_s
            return @clock_values[key] if @clock_values.key?(key)

            raw = resolve_signal(key, 1)
            raw_width = find_width(key)
            raw = resize_value(raw, raw_width, 1) if raw_width != 1

            clock = fresh(1)
            @lines << "  #{clock} = seq.to_clock #{raw}"
            @clock_values[key] = clock
          end

          def emit_icmp(pred, left, right, width = nil)
            cmp_width = width || [find_value_width(left), find_value_width(right)].max
            out = fresh(1)
            @lines << "  #{out} = comb.icmp #{pred} #{left}, #{right} : #{iwidth(cmp_width)}"
            out
          end

          def emit_comb(op, left, right, width)
            out = fresh(width)
            @lines << "  #{out} = comb.#{op} #{left}, #{right} : #{iwidth(width)}"
            out
          end

          def resize_value(value, current_width, target_width)
            current_width = [current_width.to_i, find_value_width(value), 1].max
            target_width = [target_width.to_i, 1].max
            return value if current_width == target_width

            if target_width < current_width
              out = fresh(target_width)
              @lines << "  #{out} = comb.extract #{value} from 0 : (#{iwidth(current_width)}) -> #{iwidth(target_width)}"
              return out
            end

            pad_width = target_width - current_width
            zero = emit_const(0, pad_width)
            out = fresh(target_width)
            @lines << "  #{out} = comb.concat #{zero}, #{value} : #{iwidth(pad_width)}, #{iwidth(current_width)}"
            out
          end

          def find_value_width(value_name)
            key = value_name.to_s.sub(/^%/, '')
            if (port = @mod.ports.find { |p| sanitize(p.name.to_s) == key })
              return port.width
            end

            if (reg = @mod.regs.find { |r| sanitize(r.name.to_s) == key })
              return reg.width
            end

            if (net = @mod.nets.find { |n| sanitize(n.name.to_s) == key })
              return net.width
            end

            if (m = key.match(/_(\d+)\z/))
              return [m[1].to_i, 1].max
            end

            1
          end

          def find_width(signal_name)
            name = signal_name.to_s
            if (port = @mod.ports.find { |p| p.name.to_s == name })
              return port.width
            end
            if (reg = @mod.regs.find { |r| r.name.to_s == name })
              return reg.width
            end
            if (net = @mod.nets.find { |n| n.name.to_s == name })
              return net.width
            end
            1
          end

          def input_port?(name)
            @mod.ports.any? { |p| p.direction.to_s == 'in' && p.name.to_s == name }
          end

          def fresh(width)
            @temp_idx += 1
            "%v#{@temp_idx}_#{width}"
          end

          def iwidth(width)
            "i#{[width.to_i, 1].max}"
          end

          def sanitize(name)
            name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          end
        end
      end
    end
  end
end
