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
            @sanitized_cache = {}
            @value_widths = {}
            @instance_output_tokens = build_instance_output_tokens
            @clock_values = {}
            @assigns_by_target = Hash.new { |h, k| h[k] = [] }
            @internal_assign_targets = Set.new
            @llhd_signal_tokens = {}
            @llhd_probe_tokens = {}
            @llhd_time_token = nil
            @memory_tokens = {}
            @memory_by_name = {}
            @used_memories = Set.new
            @resolving = Set.new
            @expr_values = {}
            @active_exprs = Set.new
            seed_known_widths
          end

          def emit
            build_assign_map
            build_memory_map
            emit_header
            emit_memories
            emit_reg_processes
            emit_instances
            emit_internal_assign_drivers
            emit_memory_write_ports
            emit_output
            @lines << '}'
            @lines.join("\n")
          end

          private

          def build_assign_map
            @assigns_by_target.clear
            @internal_assign_targets.clear

            @mod.assigns.each do |assign|
              target = assign.target.to_s
              @assigns_by_target[target] << assign.expr
            end
          end

          def build_memory_map
            @memory_by_name.clear
            @used_memories.clear
            @mod.memories.each do |memory|
              @memory_by_name[memory.name.to_s] = memory
            end

            @mod.write_ports.each do |write_port|
              @used_memories << write_port.memory.to_s
            end

            @mod.assigns.each do |assign|
              collect_memory_reads(assign.expr)
            end

            @mod.processes.each do |process|
              process.statements.each do |statement|
                collect_memory_reads(statement)
              end
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

          def seed_known_widths
            @mod.ports.each do |port|
              @value_widths[sanitize(port.name.to_s)] = port.width.to_i
            end
            @mod.regs.each do |reg|
              @value_widths[sanitize(reg.name.to_s)] = reg.width.to_i
            end
            @mod.nets.each do |net|
              @value_widths[sanitize(net.name.to_s)] = net.width.to_i
            end
          end

          def emit_reg_processes
            shared_reg_tokens = preseed_clocked_reg_tokens
            @mod.processes.each do |process|
              next unless process.clocked

              clock_name = process.clock ? process.clock.to_s : 'clk'
              clock_value = resolve_clock(clock_name)
              emit_seq_statements(process.statements, clock_value, shared_reg_tokens: shared_reg_tokens)
            end
          end

          def preseed_clocked_reg_tokens
            reg_tokens = {}

            @mod.processes.each do |process|
              next unless process.clocked

              collect_seq_targets(Array(process.statements)).each do |target|
                next if reg_tokens.key?(target)

                width = find_width(target)
                reg_tokens[target] = fresh(width)
                @values[target.to_s] = reg_tokens[target]
              end
            end

            reg_tokens
          end

          def collect_seq_targets(statements, acc = [])
            Array(statements).each do |stmt|
              case stmt
              when IR::SeqAssign
                target = stmt.target.to_s
                acc << target unless acc.include?(target)
              when IR::If
                collect_seq_targets(stmt.then_statements, acc)
                collect_seq_targets(stmt.else_statements, acc)
              end
            end

            acc
          end

          def emit_instances
            @mod.instances.each do |instance|
              emit_instance(instance)
            end
          end

          def emit_memories
            @mod.memories.each do |memory|
              next unless @used_memories.include?(memory.name.to_s)

              token = memory_token(memory.name.to_s)
              @lines << "  #{token} = seq.firmem 0, 1, undefined, port_order : <#{memory.depth} x #{memory.width}>"
            end
          end

          def emit_memory_write_ports
            @mod.write_ports.each do |write_port|
              memory_name = write_port.memory.to_s
              memory = @memory_by_name[memory_name]
              next unless memory

              mem_token = memory_token(memory_name)
              addr_width = memory_addr_width(memory.depth)

              addr_raw = emit_expr(write_port.addr)
              addr_raw_width = write_port.addr.respond_to?(:width) ? write_port.addr.width : find_value_width(addr_raw)
              addr_value = resize_value(addr_raw, addr_raw_width, addr_width)

              data_raw = emit_expr(write_port.data)
              data_raw_width = write_port.data.respond_to?(:width) ? write_port.data.width : find_value_width(data_raw)
              data_value = resize_value(data_raw, data_raw_width, memory.width)

              enable_raw = emit_expr(write_port.enable)
              enable_raw_width = write_port.enable.respond_to?(:width) ? write_port.enable.width : find_value_width(enable_raw)
              enable_value = resize_value(enable_raw, enable_raw_width, 1)

              clock_name = write_port.clock.to_s
              clock_value = resolve_clock(clock_name.empty? ? default_memory_clock(memory_name) : clock_name)

              @lines << "  seq.firmem.write_port #{mem_token}[#{addr_value}] = #{data_value}, " \
                        "clock #{clock_value} enable #{enable_value} : <#{memory.depth} x #{memory.width}>"
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
                source_width = conn ? connection_width(conn) : port.width
                value = if conn
                          raw = connection_value(conn, source_width)
                          resize_value(raw, source_width, port.width)
                        else
                          emit_zero(port.width)
                        end
                "#{sanitize(port.name)}: #{value}: #{iwidth(port.width)}"
              end

              output_entries = output_ports.map do |port|
                "#{sanitize(port.name)}: #{iwidth(port.width)}"
              end

              lhs = output_ports.map do |port|
                conn = conn_by_port[port.name.to_s]
                ssa = if conn
                        instance_output_token(conn.signal.to_s, port.width)
                      else
                        fresh(port.width)
                      end
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
                ssa = instance_output_token(conn.signal.to_s, width)
                @values[conn.signal.to_s] = ssa
                ssa
              end
            end

            line = +'  '
            line << "#{lhs.join(', ')} = " unless lhs.empty?
            line << 'hw.instance '
            line << mlir_string(instance.name)
            line << " @#{sanitize(instance.module_name)}#{instance_params_suffix(instance.parameters || {}, module_parameters: (target_mod&.parameters || {}))}"
            line << "(#{input_entries.join(', ')})"
            line << " -> (#{output_entries.join(', ')})"
            @lines << line
          end

          def resolve_instance_module(module_name)
            key = module_name.to_s
            @module_lookup[key] || @module_lookup[sanitize(key)]
          end

          def build_instance_output_tokens
            tokens = {}
            used = Set.new

            @mod.instances.each do |instance|
              instance.connections.each do |conn|
                next unless conn.direction.to_s == 'out'

                signal_name = conn.signal.to_s
                next if signal_name.empty?
                next if tokens.key?(signal_name)

                width = connection_width(conn)
                base = "%#{sanitize(signal_name)}_#{[width.to_i, 1].max}"
                token = base
                suffix = 2
                while used.include?(token)
                  token = "#{base}_#{suffix}"
                  suffix += 1
                end

                tokens[signal_name] = token
                used << token
              end
            end

            tokens
          end

          def instance_output_token(signal_name, width)
            key = signal_name.to_s
            return @instance_output_tokens[key] if @instance_output_tokens.key?(key)

            token = "%#{sanitize(key)}_#{[width.to_i, 1].max}"
            @instance_output_tokens[key] = token
            token
          end

          def emit_seq_statements(statements, clock_value, shared_reg_tokens: nil)
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
              reg_tokens[target] = shared_reg_tokens&.fetch(target, nil) || fresh(width)
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

            values = outputs.map do |port|
              raw = resolve_signal(port.name.to_s, port.width)
              raw_width = find_value_width(raw)
              resize_value(raw, raw_width, port.width)
            end
            types = outputs.map { |port| iwidth(port.width) }
            @lines << "  hw.output #{values.join(', ')} : #{types.join(', ')}"
          end

          def emit_internal_assign_drivers
            @mod.assigns.each do |assign|
              target = assign.target.to_s
              next unless @internal_assign_targets.include?(target)
              next if output_self_assign?(assign, target)

              width = find_width(target)
              signal_token = ensure_llhd_signal(target, width)
              time_token = ensure_llhd_time_token

              @resolving << target
              expr_value = emit_expr(assign.expr)
              @resolving.delete(target)
              @lines << "  llhd.drv #{signal_token}, #{expr_value} after #{time_token} : #{iwidth(width)}"
            end
          end

          def emit_memory_read(expr)
            memory_name = expr.memory.to_s
            memory = @memory_by_name[memory_name]
            return emit_zero(expr.width) unless memory

            mem_token = memory_token(memory_name)
            addr_width = memory_addr_width(memory.depth)
            addr_raw = emit_expr(expr.addr)
            addr_raw_width = expr.addr.respond_to?(:width) ? expr.addr.width : find_value_width(addr_raw)
            addr_value = resize_value(addr_raw, addr_raw_width, addr_width)

            clock_name = default_memory_clock(memory_name)
            clock_value = resolve_clock(clock_name)
            read_value = fresh(memory.width)
            @lines << "  #{read_value} = seq.firmem.read_port #{mem_token}[#{addr_value}], " \
                      "clock #{clock_value} : <#{memory.depth} x #{memory.width}>"
            resize_value(read_value, memory.width, expr.width)
          end

          def collect_memory_reads(node, visited = Set.new)
            return if node.nil?

            case node
            when Array
              node.each { |child| collect_memory_reads(child, visited) }
              return
            end

            return unless node.respond_to?(:instance_variables)

            node_id = node.object_id
            return if visited.include?(node_id)

            visited << node_id

            if node.is_a?(IR::MemoryRead)
              @used_memories << node.memory.to_s
              collect_memory_reads(node.addr, visited)
            end

            node.instance_variables.each do |ivar|
              collect_memory_reads(node.instance_variable_get(ivar), visited)
            end
          end

          def memory_token(name)
            key = name.to_s
            @memory_tokens[key] ||= "%#{sanitize(key)}"
          end

          def memory_addr_width(depth)
            value = depth.to_i
            return 1 if value <= 1

            Math.log2(value).ceil
          end

          def default_memory_clock(memory_name)
            write_port = @mod.write_ports.find { |port| port.memory.to_s == memory_name.to_s }
            clock = write_port&.clock.to_s
            return clock unless clock.nil? || clock.empty?

            clocked_process = @mod.processes.find(&:clocked)
            process_clock = clocked_process&.clock.to_s
            return process_clock unless process_clock.nil? || process_clock.empty?

            'clk'
          end

          def connection_width(conn)
            signal = conn.signal
            return signal.width if signal.respond_to?(:width)
            return conn.width if conn.respond_to?(:width) && conn.width
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

	          def instance_params_suffix(parameters, module_parameters: {})
              module_parameter_widths = {}
              module_parameters.each do |k, v|
                key = k.to_s
                next unless v.is_a?(Integer)

                width = [v.abs.bit_length + (v.negative? ? 1 : 0), 1].max
                module_parameter_widths[key] = width
              end

	            parts = parameters.map do |k, v|
	              case v
              when Integer
                width = module_parameter_widths[k.to_s] || [v.abs.bit_length + (v.negative? ? 1 : 0), 1].max
                "#{sanitize(k)}: i#{width} = #{normalize_const(v, width)}"
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

            if @internal_assign_targets.include?(key)
              return probe_llhd_signal(key, width)
            end

            if @instance_output_tokens.key?(key)
              @values[key] = @instance_output_tokens[key]
              return @values[key]
            end

            if input_port?(key)
              value = "%#{sanitize(key)}"
              @values[key] = value
              return value
            end

            if @resolving.include?(key)
              return emit_zero(width)
            end

            assigned_exprs = @assigns_by_target[key]
            if assigned_exprs && !assigned_exprs.empty?
              assigned = preferred_assigned_expr(key, assigned_exprs)
              @resolving << key
              @values[key] = emit_expr(assigned)
              @resolving.delete(key)
              return @values[key]
            end

            # If we do not know this symbol yet, materialize a typed zero.
            @values[key] = emit_zero(width)
          end

          def emit_expr(expr)
            expr_key = expr.object_id
            return @expr_values[expr_key] if @expr_values.key?(expr_key)

            if @active_exprs.include?(expr_key)
              return emit_zero(expr.respond_to?(:width) ? expr.width : 1)
            end

            @active_exprs << expr_key

            case expr
            when IR::Literal
              emitted = emit_const(expr.value, expr.width)
            when IR::Signal
              emitted = resolve_signal(expr.name.to_s, expr.width)
            when IR::BinaryOp
              emitted = emit_binary(expr)
            when IR::UnaryOp
              emitted = emit_unary(expr)
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
              emitted = out
            when IR::Slice
              base = emit_expr(expr.base)
              range_begin = expr.range.begin.to_i
              range_end = expr.range.end.to_i
              range_end -= 1 if expr.range.exclude_end?
              low = [range_begin, range_end].min
              base_width = [expr.base&.width.to_i, find_value_width(base), 1].max
              target_width = [expr.width.to_i, 1].max
              emitted = if low >= base_width
                          emit_zero(target_width)
                        else
                          available_width = base_width - low
                          extract_width = [available_width, target_width].min
                          extracted = fresh(extract_width)
                          @lines << "  #{extracted} = comb.extract #{base} from #{low} : (#{iwidth(base_width)}) -> #{iwidth(extract_width)}"
                          resize_value(extracted, extract_width, target_width)
                        end
            when IR::Concat
              emitted = emit_concat(expr)
            when IR::Resize
              emitted = emit_resize(expr)
            when IR::Case
              emitted = emit_case(expr)
            when IR::MemoryRead
              emitted = emit_memory_read(expr)
            else
              emitted = emit_zero(expr.respond_to?(:width) ? expr.width : 1)
            end

            @expr_values[expr_key] = emitted
            emitted
          ensure
            @active_exprs.delete(expr_key) if expr_key
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
            operand_raw = emit_expr(expr.operand)
            operand_width = expr.operand.respond_to?(:width) ? expr.operand.width : find_value_width(operand_raw)
            op = expr.op.to_s

            case op
            when '~', :'~'
              operand = resize_value(operand_raw, operand_width, expr.width)
              all_ones = emit_const((1 << expr.width) - 1, expr.width)
              emit_comb('xor', operand, all_ones, expr.width)
            when '!', :'!'
              zero = emit_const(0, operand_width)
              emit_icmp('eq', operand_raw, zero, operand_width)
            when 'reduce_or', :reduce_or
              zero = emit_const(0, operand_width)
              emit_icmp('ne', operand_raw, zero, operand_width)
            when 'reduce_and', :reduce_and
              all_ones = emit_const((1 << operand_width) - 1, operand_width)
              emit_icmp('eq', operand_raw, all_ones, operand_width)
            when '-', :-@
              operand = resize_value(operand_raw, operand_width, expr.width)
              zero = emit_const(0, expr.width)
              emit_comb('sub', zero, operand, expr.width)
            else
              @lines << "  // Unsupported unary op #{op.inspect}; emitting passthrough"
              operand_raw
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
            widths = parts.map { |value| find_value_width(value) }
            types = widths.map { |width| iwidth(width) }
            concat_width = [widths.sum, 1].max
            out = fresh(concat_width)
            @lines << "  #{out} = comb.concat #{parts.join(', ')} : #{types.join(', ')}"
            resize_value(out, concat_width, expr.width)
          end

          def emit_resize(expr)
            current = emit_expr(expr.expr)
            current_width = expr.expr.width
            target_width = expr.width
            resize_value(current, current_width, target_width)
          end

          def emit_const(value, width)
            width = [width.to_i, 1].max
            normalized = normalize_const(value, width)
            out = fresh(width)
            @lines << "  #{out} = hw.constant #{normalized} : #{iwidth(width)}"
            out
          end

          def emit_zero(width)
            emit_const(0, width)
          end

          def normalize_const(value, width)
            modulus = 1 << width
            wrapped = value.to_i % modulus
            return wrapped if value.to_i >= 0

            wrapped.zero? ? 0 : wrapped - modulus
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
            return @value_widths[key] if @value_widths.key?(key)

            if (port = @mod.ports.find { |p| sanitize(p.name.to_s) == key })
              @value_widths[key] = port.width.to_i
              return @value_widths[key]
            end

            if (reg = @mod.regs.find { |r| sanitize(r.name.to_s) == key })
              @value_widths[key] = reg.width.to_i
              return @value_widths[key]
            end

            if (net = @mod.nets.find { |n| sanitize(n.name.to_s) == key })
              @value_widths[key] = net.width.to_i
              return @value_widths[key]
            end

            if (m = key.match(/_(\d+)\z/))
              @value_widths[key] = [m[1].to_i, 1].max
              return @value_widths[key]
            end

            @value_widths[key] = 1
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

          def output_port?(name)
            @mod.ports.any? { |p| p.direction.to_s == 'out' && p.name.to_s == name.to_s }
          end

          def ensure_llhd_signal(name, width)
            key = name.to_s
            return @llhd_signal_tokens[key] if @llhd_signal_tokens.key?(key)

            init = emit_zero(width)
            signal_token = fresh(width)
            @lines << "  #{signal_token} = llhd.sig name #{mlir_string(key)} #{init} : #{iwidth(width)}"
            @llhd_signal_tokens[key] = signal_token
            signal_token
          end

          def probe_llhd_signal(name, width)
            key = name.to_s
            return @llhd_probe_tokens[key] if @llhd_probe_tokens.key?(key)

            signal_token = ensure_llhd_signal(key, width)
            probe_token = fresh(width)
            @lines << "  #{probe_token} = llhd.prb #{signal_token} : #{iwidth(width)}"
            @llhd_probe_tokens[key] = probe_token
            @values[key] = probe_token
          end

          def ensure_llhd_time_token
            return @llhd_time_token if @llhd_time_token

            @llhd_time_token = fresh(1)
            @lines << "  #{@llhd_time_token} = llhd.constant_time <0s, 1d, 0e>"
            @llhd_time_token
          end

          def output_self_assign?(assign, target)
            return false unless output_port?(target)
            return false unless assign.expr.is_a?(IR::Signal)

            assign.expr.name.to_s == target.to_s
          end

          def preserve_non_output_assign_target?(target, exprs, referenced_in_assign_exprs)
            return true if exprs.length > 1
            return true if exprs.any? { |expr| !expr.is_a?(IR::Signal) }
            return true if referenced_in_assign_exprs.include?(target.to_s)

            false
          end

          def collect_signal_refs_from_expr(expr, out)
            case expr
            when IR::Signal
              out << expr.name.to_s
            when IR::UnaryOp
              collect_signal_refs_from_expr(expr.operand, out)
            when IR::BinaryOp
              collect_signal_refs_from_expr(expr.left, out)
              collect_signal_refs_from_expr(expr.right, out)
            when IR::Mux
              collect_signal_refs_from_expr(expr.condition, out)
              collect_signal_refs_from_expr(expr.when_true, out)
              collect_signal_refs_from_expr(expr.when_false, out)
            when IR::Concat
              Array(expr.parts).each { |part| collect_signal_refs_from_expr(part, out) }
            when IR::Slice
              collect_signal_refs_from_expr(expr.base, out)
            when IR::Resize
              collect_signal_refs_from_expr(expr.expr, out)
            when IR::Case
              collect_signal_refs_from_expr(expr.selector, out)
              expr.cases.each_value { |branch| collect_signal_refs_from_expr(branch, out) }
              collect_signal_refs_from_expr(expr.default, out)
            when IR::MemoryRead
              collect_signal_refs_from_expr(expr.addr, out)
            end
          end

          def signal_expr_references_target?(expr, target_name)
            case expr
            when IR::Signal
              expr.name.to_s == target_name.to_s
            when IR::UnaryOp
              signal_expr_references_target?(expr.operand, target_name)
            when IR::BinaryOp
              signal_expr_references_target?(expr.left, target_name) ||
                signal_expr_references_target?(expr.right, target_name)
            when IR::Mux
              signal_expr_references_target?(expr.condition, target_name) ||
                signal_expr_references_target?(expr.when_true, target_name) ||
                signal_expr_references_target?(expr.when_false, target_name)
            when IR::Concat
              Array(expr.parts).any? { |part| signal_expr_references_target?(part, target_name) }
            when IR::Slice
              signal_expr_references_target?(expr.base, target_name)
            when IR::Resize
              signal_expr_references_target?(expr.expr, target_name)
            when IR::Case
              signal_expr_references_target?(expr.selector, target_name) ||
                expr.cases.any? { |_keys, branch| signal_expr_references_target?(branch, target_name) } ||
                signal_expr_references_target?(expr.default, target_name)
            when IR::MemoryRead
              signal_expr_references_target?(expr.addr, target_name)
            else
              false
            end
          end

          def preferred_assigned_expr(target_name, exprs)
            candidates = Array(exprs).compact
            return IR::Literal.new(value: 0, width: 1) if candidates.empty?

            non_self = candidates.reject { |expr| signal_expr_references_target?(expr, target_name) }
            candidates = non_self unless non_self.empty?

            non_default = candidates.reject { |expr| zero_literal?(expr) }
            candidates = non_default unless non_default.empty?

            if candidates.length > 1
              width = find_width(target_name)
              return combine_assigned_exprs(candidates, width)
            end

            candidates.max_by { |expr| [assign_expr_priority(expr), expr.object_id] }
          end

          def combine_assigned_exprs(exprs, width)
            Array(exprs).compact.reduce do |lhs, rhs|
              IR::BinaryOp.new(
                op: :'|',
                left: lhs,
                right: rhs,
                width: width
              )
            end
          end

          def assign_expr_priority(expr)
            case expr
            when IR::Literal
              zero_literal?(expr) ? 0 : 1
            when IR::Signal
              2
            else
              3
            end
          end

          def zero_literal?(expr)
            expr.is_a?(IR::Literal) && expr.value.to_i.zero?
          end

          def fresh(width)
            @temp_idx += 1
            token = "%v#{@temp_idx}_#{width}"
            @value_widths[token.sub(/^%/, '')] = [width.to_i, 1].max
            token
          end

          def iwidth(width)
            "i#{[width.to_i, 1].max}"
          end

          def sanitize(name)
            raw = name.to_s
            @sanitized_cache[raw] ||= raw.gsub(/[^A-Za-z0-9_]/, '_')
          end
        end
      end
    end
  end
end
