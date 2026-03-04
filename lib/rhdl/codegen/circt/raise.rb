# frozen_string_literal: true

require 'fileutils'
require 'set'

module RHDL
  module Codegen
    module CIRCT
      class RaiseResult
        attr_reader :files_written, :diagnostics

        def initialize(files_written:, diagnostics: [])
          @files_written = files_written
          @diagnostics = diagnostics
        end

        def success?
          @diagnostics.none? { |d| d.severity.to_s == 'error' }
        end
      end

      class SourceResult
        attr_reader :sources, :diagnostics

        def initialize(sources:, diagnostics: [])
          @sources = sources
          @diagnostics = diagnostics
        end

        def success?
          @diagnostics.none? { |d| d.severity.to_s == 'error' }
        end
      end

      class ComponentResult
        attr_reader :components, :namespace, :diagnostics

        def initialize(components:, namespace:, diagnostics: [])
          @components = components
          @namespace = namespace
          @diagnostics = diagnostics
        end

        def success?
          @diagnostics.none? { |d| d.severity.to_s == 'error' }
        end
      end

      class FormatResult
        attr_reader :diagnostics

        def initialize(diagnostics: [])
          @diagnostics = diagnostics
        end

        def success?
          @diagnostics.none? { |d| d.severity.to_s == 'error' }
        end
      end

      module Raise
        module_function

        MAX_EMITTED_LINE_LENGTH = 100

        # Raise CIRCT nodes/MLIR into in-memory Ruby DSL source strings.
        # Returns {module_name => ruby_source}.
        def to_sources(nodes_or_mlir, top: nil, strict: false)
          modules, diagnostics = resolve_modules_and_diagnostics(nodes_or_mlir, strict: strict)
          sources = {}

          modules.each do |mod|
            class_name = camelize(mod.name)
            sources[mod.name.to_s] = emit_component(mod, class_name, diagnostics, strict: strict)
          end

          append_missing_top_error(modules, diagnostics, top)
          SourceResult.new(sources: sources, diagnostics: diagnostics)
        end

        def to_dsl(nodes_or_mlir, out_dir:, top: nil, strict: false, format: false)
          source_result = to_sources(nodes_or_mlir, top: top, strict: strict)

          FileUtils.mkdir_p(out_dir)
          files_written = []

          source_result.sources.each do |module_name, ruby|
            out_path = File.join(out_dir, "#{underscore(module_name)}.rb")
            File.write(out_path, ruby)
            files_written << out_path
          end

          if format
            format_result = format_output_dir(out_dir)
            source_result.diagnostics.concat(format_result.diagnostics)
          end

          RaiseResult.new(files_written: files_written, diagnostics: source_result.diagnostics.dup)
        end

        def format_output_dir(out_dir)
          diagnostics = []
          format_generated_output_dir(out_dir, diagnostics)
          FormatResult.new(diagnostics: diagnostics)
        end

        # Raise CIRCT nodes/MLIR into loaded Ruby DSL component classes.
        # Returns {module_name => component_class}.
        def to_components(nodes_or_mlir, namespace: Module.new, top: nil, strict: false)
          source_result = to_sources(nodes_or_mlir, top: top, strict: strict)
          diagnostics = source_result.diagnostics.dup
          components = {}

          pending = source_result.sources.map do |module_name, ruby|
            { module_name: module_name, ruby: ruby, last_error: nil }
          end

          pass_limit = [pending.length + 1, 1].max
          pass = 0
          while pending.any? && pass < pass_limit
            pass += 1
            next_pending = []
            loaded_this_pass = false

            pending.each do |entry|
              module_name = entry[:module_name]
              ruby = entry[:ruby]
              class_name = camelize(module_name)

              begin
                namespace.send(:remove_const, class_name) if namespace.const_defined?(class_name, false)
                namespace.module_eval(ruby, "(circt_raise/#{module_name}.rb)", 1)
                unless namespace.const_defined?(class_name, false)
                  diagnostics << Diagnostic.new(
                    severity: :error,
                    message: "Raised source for #{module_name} did not define #{class_name}",
                    line: nil,
                    column: nil,
                    op: 'raise.components'
                  )
                  next
                end

                components[module_name] = namespace.const_get(class_name, false)
                loaded_this_pass = true
              rescue NameError => e
                next_pending << entry.merge(last_error: e)
              rescue StandardError, ScriptError => e
                diagnostics << Diagnostic.new(
                  severity: :error,
                  message: "Failed loading raised component #{module_name}: #{e.class}: #{e.message}",
                  line: nil,
                  column: nil,
                  op: 'raise.components'
                )
              end
            end

            if next_pending.empty?
              pending = []
              break
            end
            unless loaded_this_pass
              pending = next_pending
              break
            end

            pending = next_pending
          end

          pending.each do |entry|
            e = entry[:last_error]
            msg = if e
                    "Failed loading raised component #{entry[:module_name]} after dependency retries: #{e.class}: #{e.message}"
                  else
                    "Failed loading raised component #{entry[:module_name]} after dependency retries"
                  end
            diagnostics << Diagnostic.new(
              severity: :error,
              message: msg,
              line: nil,
              column: nil,
              op: 'raise.components'
            )
          end

          ComponentResult.new(components: components, namespace: namespace, diagnostics: diagnostics)
        end

        def normalize_modules(nodes_or_mlir)
          case nodes_or_mlir
          when IR::Package
            nodes_or_mlir.modules
          when IR::ModuleOp
            [nodes_or_mlir]
          when Array
            nodes_or_mlir
          else
            []
          end
        end

        def resolve_modules_and_diagnostics(nodes_or_mlir, strict: false)
          if nodes_or_mlir.is_a?(String)
            import_result = Import.from_mlir(nodes_or_mlir, strict: strict)
            [import_result.modules, import_result.diagnostics.dup]
          else
            [normalize_modules(nodes_or_mlir), []]
          end
        end

        def append_missing_top_error(modules, diagnostics, top)
          return unless top
          return if modules.any? { |m| m.name.to_s == top.to_s }

          diagnostics << Diagnostic.new(
            severity: :error,
            message: "Top module '#{top}' not found in CIRCT package",
            line: nil,
            column: nil,
            op: 'raise'
          )
        end

        def emit_component(mod, class_name, diagnostics, strict: false)
          sequential = mod.processes.any?(&:clocked)
          base = sequential ? 'RHDL::Sim::SequentialComponent' : 'RHDL::Sim::Component'
          structure_plan = build_structure_plan(mod, diagnostics)

          lines = []
          lines << '# frozen_string_literal: true'
          lines << ''
          lines << "class #{class_name} < #{base}"

          emit_module_parameters(lines, mod, diagnostics)

          mod.ports.each do |port|
            width_arg = port.width.to_i == 1 ? '' : ", width: #{port.width.to_i}"
            lines << "  #{port.direction == :out ? 'output' : 'input'} :#{sanitize_name(port.name)}#{width_arg}"
          end
          lines << ''

          inferred_wires = infer_referenced_internal_wires(mod, extra_wires: structure_plan[:bridge_wires])
          emit_internal_wires(lines, mod, extra_wires: structure_plan[:bridge_wires] + inferred_wires)
          emit_structure(lines, structure_plan)

          if sequential
            emit_sequential(lines, mod, diagnostics, strict: strict)
          end

          emit_behavior(
            lines,
            mod,
            diagnostics,
            strict: strict,
            bridge_assignments: structure_plan[:bridge_assignments],
            structural_output_targets: structure_plan[:structural_output_targets]
          )

          lines << 'end'
          lines << ''
          lines.join("\n")
        end

        def emit_module_parameters(lines, mod, diagnostics)
          params = mod.parameters || {}
          return if params.empty?

          emitted = 0
          params.each do |name, value|
            case value
            when Integer
              lines << "  parameter :#{sanitize_name(name)}, default: #{value}"
              emitted += 1
            when true, false
              lines << "  parameter :#{sanitize_name(name)}, default: #{value}"
              emitted += 1
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported module parameter #{name}=#{value.inspect} (#{value.class}) while raising #{mod.name}",
                line: nil,
                column: nil,
                op: 'raise.module_params'
              )
            end
          end

          lines << '' if emitted.positive?
        end

        def emit_internal_wires(lines, mod, extra_wires: [])
          port_names = mod.ports.map { |p| sanitize_name(p.name) }.to_set
          seen = Set.new
          internal = (Array(mod.nets) + Array(mod.regs)).map { |n| [sanitize_name(n.name), n.width.to_i] }
          internal.concat(Array(extra_wires).map { |wire| [sanitize_name(wire[:name]), wire[:width].to_i] })

          internal.each do |name, width|
            next if port_names.include?(name)
            next if seen.include?(name)

            width_arg = width == 1 ? '' : ", width: #{width}"
            lines << "  wire :#{name}#{width_arg}"
            seen << name
          end
          lines << '' unless seen.empty?
        end

        def infer_referenced_internal_wires(mod, extra_wires: [])
          declared = Set.new
          mod.ports.each { |port| declared << sanitize_name(port.name) }
          mod.nets.each { |net| declared << sanitize_name(net.name) }
          mod.regs.each { |reg| declared << sanitize_name(reg.name) }
          Array(extra_wires).each { |wire| declared << sanitize_name(wire[:name]) }

          referenced = {}

          mod.assigns.each { |assign| collect_signals_from_expr(assign.expr, referenced) }
          mod.processes.each { |process| collect_signals_from_statements(Array(process.statements), referenced) }

          Array(mod.instances).each do |inst|
            Array(inst.connections).each do |conn|
              collect_signals_from_connection(conn.signal, referenced)
            end
          end

          referenced.each_with_object([]) do |(name, width), wires|
            next if declared.include?(name)

            wires << { name: name, width: width.to_i.positive? ? width.to_i : 1 }
          end
        end

        def collect_signals_from_statements(statements, referenced)
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              collect_signals_from_expr(stmt.expr, referenced)
            when IR::If
              collect_signals_from_expr(stmt.condition, referenced)
              collect_signals_from_statements(stmt.then_statements, referenced)
              collect_signals_from_statements(stmt.else_statements, referenced)
            end
          end
        end

        def collect_signals_from_connection(signal, referenced)
          case signal
          when String, Symbol
            name = sanitize_name(signal)
            referenced[name] = [referenced[name].to_i, 1].max
          when IR::Signal
            name = sanitize_name(signal.name)
            referenced[name] = [referenced[name].to_i, signal.width.to_i].max
          when IR::Expr
            collect_signals_from_expr(signal, referenced)
          end
        end

        def collect_signals_from_expr(expr, referenced)
          case expr
          when IR::Signal
            name = sanitize_name(expr.name)
            referenced[name] = [referenced[name].to_i, expr.width.to_i].max
          when IR::UnaryOp
            collect_signals_from_expr(expr.operand, referenced)
          when IR::BinaryOp
            collect_signals_from_expr(expr.left, referenced)
            collect_signals_from_expr(expr.right, referenced)
          when IR::Mux
            collect_signals_from_expr(expr.condition, referenced)
            collect_signals_from_expr(expr.when_true, referenced)
            collect_signals_from_expr(expr.when_false, referenced)
          when IR::Concat
            Array(expr.parts).each { |part| collect_signals_from_expr(part, referenced) }
          when IR::Slice
            collect_signals_from_expr(expr.base, referenced)
          when IR::Resize
            collect_signals_from_expr(expr.expr, referenced)
          when IR::Case
            collect_signals_from_expr(expr.selector, referenced)
            expr.cases.each_value { |value| collect_signals_from_expr(value, referenced) }
            collect_signals_from_expr(expr.default, referenced)
          when IR::MemoryRead
            collect_signals_from_expr(expr.addr, referenced)
          end
        end

        def emit_structure(lines, structure_plan)
          return if structure_plan[:lines].empty?

          lines.concat(structure_plan[:lines])
          lines << ''
        end

        def build_structure_plan(mod, diagnostics)
          structure_lines = []
          bridge_assignments = []
          bridge_wires = []
          bridge_wire_names = Set.new
          structural_output_targets = Set.new

          Array(mod.instances).each do |inst|
            params = format_instance_params(inst.parameters || {})
            structure_lines << "  instance :#{sanitize_name(inst.name)}, #{camelize(inst.module_name)}#{params}"
          end

          Array(mod.instances).each do |inst|
            inst_name = sanitize_name(inst.name)
            Array(inst.connections).each do |conn|
              port_name = sanitize_name(conn.port_name)
              case conn.direction.to_s
              when 'out'
                dest = connection_ref(conn.signal)
                if dest
                  structure_lines << "  port [:#{inst_name}, :#{port_name}] => #{dest}"
                  target_name = signal_name_for_connection(conn.signal)
                  if target_name && output_port?(mod, target_name)
                    structural_output_targets << sanitize_name(target_name)
                  end
                else
                  diagnostics << Diagnostic.new(
                    severity: :warning,
                    message: "Unsupported instance output connection for #{inst.name}.#{conn.port_name}",
                    line: nil,
                    column: nil,
                    op: 'raise.structure'
                  )
                end
              else
                src = connection_ref(conn.signal)
                if src
                  structure_lines << "  port #{src} => [:#{inst_name}, :#{port_name}]"
                elsif conn.signal.is_a?(IR::Expr)
                  bridge_name = "#{inst_name}__#{port_name}__bridge"
                  unless bridge_wire_names.include?(bridge_name)
                    bridge_wire_names << bridge_name
                    bridge_wires << { name: bridge_name, width: conn.signal.width.to_i }
                    bridge_assignments << IR::Assign.new(target: bridge_name, expr: conn.signal)
                  end
                  structure_lines << "  port :#{sanitize_name(bridge_name)} => [:#{inst_name}, :#{port_name}]"
                else
                  diagnostics << Diagnostic.new(
                    severity: :warning,
                    message: "Unsupported instance input connection for #{inst.name}.#{conn.port_name}",
                    line: nil,
                    column: nil,
                    op: 'raise.structure'
                  )
                end
              end
            end
          end

          {
            lines: structure_lines,
            bridge_assignments: bridge_assignments,
            bridge_wires: bridge_wires,
            structural_output_targets: structural_output_targets.to_a
          }
        end

        def format_instance_params(parameters)
          return '' if parameters.nil? || parameters.empty?

          parts = parameters.map do |k, v|
            next unless v.is_a?(Integer) || v.is_a?(Float) || v == true || v == false
            "#{sanitize_name(k)}: #{v.inspect}"
          end.compact
          return '' if parts.empty?

          ", #{parts.join(', ')}"
        end

        def connection_ref(signal)
          case signal
          when String, Symbol
            ":#{sanitize_name(signal)}"
          when IR::Signal
            ":#{sanitize_name(signal.name)}"
          else
            nil
          end
        end

        def signal_name_for_connection(signal)
          case signal
          when String, Symbol
            signal.to_s
          when IR::Signal
            signal.name.to_s
          else
            nil
          end
        end

        def emit_sequential(lines, mod, diagnostics, strict: false)
          clock = mod.processes.find(&:clocked)&.clock || :clk
          lines << "  sequential clock: :#{sanitize_name(clock)} do"

          mod.processes.each do |process|
            next unless process.clocked

            seq_state = {}
            target_order = []
            lower_seq_statements(
              Array(process.statements),
              seq_state: seq_state,
              target_order: target_order,
              mod: mod,
              diagnostics: diagnostics
            )

            target_order.each do |target|
              next unless seq_state.key?(target)
              emit_assignment(
                lines,
                target: signal_ref(target),
                expr: seq_state[target],
                diagnostics: diagnostics,
                strict: strict,
                indent: 4
              )
            end
          end

          lines << '  end'
          lines << ''
        end

        def lower_seq_statements(statements, seq_state:, target_order:, mod:, diagnostics:)
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
                target_order: target_order,
                mod: mod,
                diagnostics: diagnostics
              )
              else_touched = lower_seq_statements(
                stmt.else_statements,
                seq_state: else_state,
                target_order: target_order,
                mod: mod,
                diagnostics: diagnostics
              )

              branch_targets = (then_touched + else_touched).uniq
              branch_targets.each do |target|
                width = find_target_width(mod, target)
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
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported sequential statement #{stmt.class} in #{mod.name}",
                line: nil,
                column: nil,
                op: 'raise.sequential'
              )
            end
          end

          touched.to_a
        end

        def find_target_width(mod, target_name)
          name = target_name.to_s
          port = mod.ports.find { |p| p.name.to_s == name }
          return port.width if port

          reg = mod.regs.find { |r| r.name.to_s == name }
          return reg.width if reg

          net = mod.nets.find { |n| n.name.to_s == name }
          return net.width if net

          1
        end

        def emit_behavior(lines, mod, diagnostics, strict: false, bridge_assignments: [], structural_output_targets: [])
          lines << '  behavior do'
          driven_outputs = Set.new(Array(structural_output_targets).map { |name| sanitize_name(name) })

          Array(bridge_assignments).each do |assign|
            target = sanitize_name(assign.target)
            emit_assignment(
              lines,
              target: signal_ref(target),
              expr: assign.expr,
              diagnostics: diagnostics,
              strict: strict,
              indent: 4
            )
          end

          mod.assigns.each do |assign|
            target = sanitize_name(assign.target)
            next unless output_port?(mod, target)

            emit_assignment(
              lines,
              target: signal_ref(target),
              expr: assign.expr,
              diagnostics: diagnostics,
              strict: strict,
              indent: 4
            )
            driven_outputs << target
          end

          output_targets = mod.ports.select { |p| p.direction == :out }.map { |p| sanitize_name(p.name) }.to_set
          missing_outputs = output_targets - driven_outputs
          unless missing_outputs.empty?
            if strict
              diagnostics << Diagnostic.new(
                severity: :error,
                message: "No direct output assignments were recovered for #{mod.name}; missing outputs: #{missing_outputs.to_a.sort.join(', ')}",
                line: nil,
                column: nil,
                op: 'raise.behavior'
              )
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "No direct output assignments were recovered for #{mod.name}; emitted placeholders for: #{missing_outputs.to_a.sort.join(', ')}",
                line: nil,
                column: nil,
                op: 'raise.behavior'
              )

              missing_outputs.each do |name|
                lines << "    #{signal_ref(name)} <= 0"
              end
            end
          end

          lines << '  end'
        end

        def emit_assignment(lines, target:, expr:, diagnostics:, strict:, indent:)
          cache = {}
          expr_text = expr_to_ruby_cached(expr, diagnostics, strict: strict, cache: cache)
          return if expr_text.nil? || expr_text.empty?

          prefix = ' ' * indent
          inline = "#{target} <= #{expr_text}"
          if prefix.length + inline.length <= MAX_EMITTED_LINE_LENGTH
            lines << "#{prefix}#{inline}"
            return
          end

          lines << "#{prefix}#{target} <="
          lines.concat(
            render_expr_lines(
              expr,
              diagnostics,
              strict: strict,
              indent: indent + 2,
              cache: cache
            )
          )
        end

        def render_expr_lines(expr, diagnostics, strict:, indent:, cache:)
          inline = expr_to_ruby_cached(expr, diagnostics, strict: strict, cache: cache)
          return [] if inline.nil? || inline.empty?

          if indent + inline.length <= MAX_EMITTED_LINE_LENGTH || !pretty_breakable_expr?(expr)
            return ["#{' ' * indent}#{inline}"]
          end

          case expr
          when IR::BinaryOp
            left_lines = render_expr_lines(expr.left, diagnostics, strict: strict, indent: indent + 2, cache: cache)
            right_lines = render_expr_lines(expr.right, diagnostics, strict: strict, indent: indent + 2, cache: cache)
            append_suffix_to_last_line(left_lines, " #{expr.op}")

            lines = ["#{' ' * indent}("]
            lines.concat(left_lines)
            lines.concat(right_lines)
            lines << "#{' ' * indent})"
            lines
          when IR::Mux
            condition_lines = render_expr_lines(
              expr.condition,
              diagnostics,
              strict: strict,
              indent: indent + 2,
              cache: cache
            )
            true_lines = render_expr_lines(
              expr.when_true,
              diagnostics,
              strict: strict,
              indent: indent + 4,
              cache: cache
            )
            false_lines = render_expr_lines(
              expr.when_false,
              diagnostics,
              strict: strict,
              indent: indent + 4,
              cache: cache
            )
            append_suffix_to_last_line(condition_lines, ' ?')
            append_suffix_to_last_line(true_lines, ' :')

            lines = ["#{' ' * indent}("]
            lines.concat(condition_lines)
            lines.concat(true_lines)
            lines.concat(false_lines)
            lines << "#{' ' * indent})"
            lines
          when IR::Concat
            lines = ["#{' ' * indent}cat("]
            parts = expr.parts || []
            parts.each_with_index do |part, idx|
              part_lines = render_expr_lines(part, diagnostics, strict: strict, indent: indent + 2, cache: cache)
              if idx < parts.length - 1 && !part_lines.empty?
                part_lines[-1] = "#{part_lines[-1]},"
              end
              lines.concat(part_lines)
            end
            lines << "#{' ' * indent})"
            lines
          else
            ["#{' ' * indent}#{inline}"]
          end
        end

        def expr_to_ruby_cached(expr, diagnostics, strict:, cache:)
          key = [expr.object_id, strict]
          return cache[key] if cache.key?(key)

          cache[key] = expr_to_ruby(expr, diagnostics, strict: strict)
        end

        def pretty_breakable_expr?(expr)
          expr.is_a?(IR::BinaryOp) || expr.is_a?(IR::Mux) || expr.is_a?(IR::Concat)
        end

        def append_suffix_to_last_line(lines, suffix)
          return lines if lines.empty?

          lines[-1] = "#{lines[-1]}#{suffix}"
          lines
        end

        def output_port?(mod, name)
          mod.ports.any? { |p| p.direction == :out && sanitize_name(p.name) == name.to_s }
        end

        def expr_to_ruby(expr, diagnostics, strict: false)
          case expr
          when IR::Literal
            "lit(#{expr.value.inspect}, width: #{expr.width.to_i})"
          when IR::Signal
            signal_ref(expr.name)
          when IR::BinaryOp
            left = expr_to_ruby(expr.left, diagnostics, strict: strict)
            right = expr_to_ruby(expr.right, diagnostics, strict: strict)
            return nil if left.nil? || right.nil?

            "(#{left} #{expr.op} #{right})"
          when IR::UnaryOp
            operand = expr_to_ruby(expr.operand, diagnostics, strict: strict)
            return nil if operand.nil?

            "(#{expr.op}#{operand})"
          when IR::Mux
            condition = expr_to_ruby(expr.condition, diagnostics, strict: strict)
            when_true = expr_to_ruby(expr.when_true, diagnostics, strict: strict)
            when_false = expr_to_ruby(expr.when_false, diagnostics, strict: strict)
            return nil if condition.nil? || when_true.nil? || when_false.nil?

            "(#{condition} ? #{when_true} : #{when_false})"
          when IR::Slice
            range = expr.range
            if range.begin == range.end
              base = expr_to_ruby(expr.base, diagnostics, strict: strict)
              return nil if base.nil?

              "#{base}[#{range.begin}]"
            else
              base = expr_to_ruby(expr.base, diagnostics, strict: strict)
              return nil if base.nil?

              "#{base}[#{range.end}..#{range.begin}]"
            end
          when IR::Concat
            parts = expr.parts.map { |p| expr_to_ruby(p, diagnostics, strict: strict) }
            return nil if parts.any?(&:nil?)

            "cat(#{parts.join(', ')})"
          when IR::Resize
            expr_to_ruby(expr.expr, diagnostics, strict: strict)
          when IR::Case
            if strict
              diagnostics << Diagnostic.new(
                severity: :error,
                message: 'Case expression lowering is unsupported in CIRCT->DSL strict raise',
                line: nil,
                column: nil,
                op: 'raise.case'
              )
              nil
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: 'Case expression emitted as default branch only',
                line: nil,
                column: nil,
                op: 'raise.case'
              )
              expr.default ? expr_to_ruby(expr.default, diagnostics, strict: strict) : '0'
            end
          when IR::MemoryRead
            if strict
              diagnostics << Diagnostic.new(
                severity: :error,
                message: 'Memory read lowering is unsupported in CIRCT->DSL strict raise',
                line: nil,
                column: nil,
                op: 'raise.memory_read'
              )
              nil
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: 'Memory read lowering is unsupported in CIRCT->DSL v1',
                line: nil,
                column: nil,
                op: 'raise.memory_read'
              )
              '0'
            end
          else
            if strict
              diagnostics << Diagnostic.new(
                severity: :error,
                message: "Unsupported expression type #{expr.class}; no placeholder emission allowed",
                line: nil,
                column: nil,
                op: 'raise.expr'
              )
              nil
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported expression type #{expr.class}; using 0",
                line: nil,
                column: nil,
                op: 'raise.expr'
              )
              '0'
            end
          end
        end

        def format_generated_output_dir(out_dir, diagnostics)
          return unless out_dir && Dir.exist?(out_dir)

          cmd = rubocop_format_command(out_dir: out_dir)
          ok = system(*cmd, out: File::NULL, err: File::NULL)
          return if ok

          status = $?.exitstatus
          severity = status == 1 ? :warning : :error
          diagnostics << Diagnostic.new(
            severity: severity,
            message: "RuboCop formatting reported status=#{status} for output directory #{out_dir}",
            line: nil,
            column: nil,
            op: 'raise.format'
          )
        rescue Errno::ENOENT
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: 'RuboCop executable not found; generated files were not auto-formatted',
            line: nil,
            column: nil,
            op: 'raise.format'
          )
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: "RuboCop formatting failed: #{e.class}: #{e.message}",
            line: nil,
            column: nil,
            op: 'raise.format'
          )
        end

        def rubocop_format_command(out_dir:)
          exe = begin
            Gem.bin_path('rubocop', 'rubocop')
          rescue StandardError
            'rubocop'
          end

          cmd = [
            exe,
            '--autocorrect',
            '--format', 'quiet',
            '--force-exclusion',
            '--parallel',
            '--only', 'Layout',
            '--except', 'Layout/LineLength'
          ]
          config_path = rubocop_config_path
          cmd.concat(['--config', config_path]) if config_path
          cmd << out_dir
          cmd
        end

        def rubocop_config_path
          root = File.expand_path('../../../../', __dir__)
          path = File.join(root, '.rubocop.yml')
          File.exist?(path) ? path : nil
        end

        def underscore(name)
          name.to_s
              .gsub('::', '_')
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\\\\1_\\\\2')
              .gsub(/([a-z\\d])([A-Z])/, '\\\\1_\\\\2')
              .tr('.', '_')
              .downcase
              .gsub(/[^a-z0-9_]/, '_')
        end

        def camelize(name)
          tokens = underscore(name).split('_').reject(&:empty?)
          camel = tokens.map(&:capitalize).join
          camel = 'RaisedModule' if camel.empty?
          camel = "M#{camel}" if camel.match?(/\A\d/)
          camel
        end

        def sanitize_name(name)
          value = name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          value = "_#{value}" if value.empty? || value.match?(/\A\d/)
          value = "_#{value}" if ruby_reserved_word?(value)
          value
        end

        def signal_ref(name)
          ident = sanitize_name(name)
          return ident if ident.match?(/\A[a-z_][a-z0-9_]*\z/)

          "self.send(:#{ident})"
        end

        def ruby_reserved_word?(value)
          reserved = %w[
            BEGIN END alias and begin break case class def defined? do else elsif end ensure false for if in module
            next nil not or redo rescue retry return self super then true undef unless until when while yield
            __FILE__ __LINE__ __ENCODING__
          ]
          reserved.include?(value)
        end
      end
    end
  end
end
