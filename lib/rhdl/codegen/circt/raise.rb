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
        attr_reader :sources, :diagnostics, :modules

        def initialize(sources:, diagnostics: [], modules: [])
          @sources = sources
          @diagnostics = diagnostics
          @modules = modules
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
          SourceResult.new(sources: sources, diagnostics: diagnostics, modules: modules)
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
          source_module_texts = nodes_or_mlir.is_a?(String) ? module_texts_by_name(nodes_or_mlir) : {}
          source_result = to_sources(nodes_or_mlir, top: top, strict: strict)
          diagnostics = source_result.diagnostics.dup
          components = {}
          module_by_name = source_result.modules.each_with_object({}) { |mod, memo| memo[mod.name.to_s] = mod }

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

                component = namespace.const_get(class_name, false)
                attach_imported_circt_module!(
                  component,
                  module_by_name[module_name],
                  module_text: source_module_texts[module_name]
                )
                components[module_name] = component
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

        def attach_imported_circt_module!(component_class, mod, module_text: nil)
          return unless component_class && mod

          component_class.instance_variable_set(:@_imported_circt_module, mod)
          component_class.instance_variable_set(:@_imported_circt_module_by_name, { mod.name.to_s => mod })
          component_class.instance_variable_set(:@_imported_circt_module_text, module_text&.strip)
          component_class.instance_variable_set(
            :@_imported_circt_module_text_by_name,
            module_text ? { mod.name.to_s => module_text.strip } : {}
          )
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
          structure_plan = build_structure_plan(mod, diagnostics)
          dsl_features = dsl_features_for_module(mod, structure_plan: structure_plan)
          base = dsl_features[:sequential] ? 'RHDL::Sim::SequentialComponent' : 'RHDL::Sim::Component'

          lines = []
          lines << '# frozen_string_literal: true'
          lines << ''
          lines << "class #{class_name} < #{base}"
          lines << '  include RHDL::DSL::Behavior' if dsl_features[:behavior]
          lines << '  include RHDL::DSL::Sequential' if dsl_features[:sequential]
          lines << '  include RHDL::DSL::Memory' if dsl_features[:memory]
          lines << '  def self.verilog_module_name'
          lines << "    #{mod.name.to_s.inspect}"
          lines << '  end'
          lines << ''

          emit_module_parameters(lines, mod, diagnostics)

          mod.ports.each do |port|
            width_arg = port.width.to_i == 1 ? '' : ", width: #{port.width.to_i}"
            lines << "  #{port.direction == :out ? 'output' : 'input'} :#{sanitize_name(port.name)}#{width_arg}"
          end
          lines << ''

          extra_wires = structure_plan[:bridge_wires]
          inferred_wires = infer_referenced_internal_wires(mod, extra_wires: extra_wires)
          emit_internal_wires(lines, mod, extra_wires: extra_wires + inferred_wires)
          emit_structure(lines, structure_plan)

          if dsl_features[:sequential]
            emit_sequential(lines, mod, diagnostics, strict: strict)
          end

          emit_behavior(
            lines,
            mod,
            diagnostics,
            strict: strict,
            bridge_assignments: structure_plan[:bridge_assignments],
            structural_output_targets: structure_plan[:structural_output_targets],
            behavior_plan: dsl_features[:behavior_plan]
          )

          lines << 'end'
          lines << ''
          lines.join("\n")
        end

        def dsl_features_for_module(mod, structure_plan: nil)
          structure_plan ||= build_structure_plan(mod, [])
          behavior_plan = behavior_plan_for_module(
            mod,
            bridge_assignments: structure_plan[:bridge_assignments],
            structural_output_targets: structure_plan[:structural_output_targets]
          )
          sequential = Array(mod.processes).any?(&:clocked)
          memory = memory_feature_for_module?(mod)

          {
            behavior: sequential || behavior_plan[:emit],
            sequential: sequential,
            memory: memory,
            behavior_plan: behavior_plan
          }
        end

        def behavior_plan_for_module(mod, bridge_assignments:, structural_output_targets:)
          driven_outputs = Set.new(Array(structural_output_targets).map { |name| sanitize_name(name) })
          assign_counts = Hash.new(0)
          Array(mod.assigns).each { |assign| assign_counts[sanitize_name(assign.target)] += 1 }

          emitted_assignments = []
          Array(bridge_assignments).each { |assign| emitted_assignments << assign }

          Array(mod.assigns).each do |assign|
            original_target = sanitize_name(assign.target)
            next if redundant_self_assign?(assign, original_target, assign_counts)

            emitted_assignments << assign
            driven_outputs << original_target if output_port?(mod, original_target)
          end

          output_targets = Array(mod.ports).select { |p| p.direction == :out }.map { |p| sanitize_name(p.name) }.to_set
          missing_outputs = (output_targets - driven_outputs).to_a.sort

          {
            assignments: emitted_assignments,
            missing_outputs: missing_outputs,
            emit: emitted_assignments.any? || missing_outputs.any?
          }
        end

        def memory_feature_for_module?(mod)
          return true if Array(mod.memories).any? || Array(mod.write_ports).any? || Array(mod.sync_read_ports).any?
          return true if memory_like_module_name?(mod.name)
          return true if Array(mod.instances).any? { |inst| memory_like_module_name?(inst.module_name) }

          seen_exprs = Set.new
          Array(mod.assigns).any? { |assign| expr_contains_memory_feature?(assign.expr, seen_exprs: seen_exprs) } ||
            Array(mod.processes).any? { |process| statements_contain_memory_feature?(process.statements, seen_exprs: seen_exprs) }
        end

        def memory_like_module_name?(name)
          value = name.to_s
          value == 'spram' ||
            value.start_with?('altsyncram_', 'dpram__vhdl_', 'dpram_dif__vhdl_')
        end

        def statements_contain_memory_feature?(statements, seen_exprs: Set.new)
          Array(statements).any? do |stmt|
            case stmt
            when IR::SeqAssign
              expr_contains_memory_feature?(stmt.expr, seen_exprs: seen_exprs)
            when IR::If
              expr_contains_memory_feature?(stmt.condition, seen_exprs: seen_exprs) ||
                statements_contain_memory_feature?(stmt.then_statements, seen_exprs: seen_exprs) ||
                statements_contain_memory_feature?(stmt.else_statements, seen_exprs: seen_exprs)
            else
              false
            end
          end
        end

        def expr_contains_memory_feature?(expr, seen_exprs: Set.new)
          return false if expr.nil?

          oid = expr.object_id
          return false if seen_exprs.include?(oid)

          seen_exprs << oid
          return true if expr.is_a?(IR::MemoryRead)

          expr_children(expr).any? { |child| expr_contains_memory_feature?(child, seen_exprs: seen_exprs) }
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
          seen_exprs = Set.new

          mod.assigns.each do |assign|
            target = sanitize_name(assign.target)
            next if declared.include?(target)

            width = if assign.expr.respond_to?(:width)
                      assign.expr.width.to_i
                    else
                      1
                    end
            referenced[target] = [referenced[target].to_i, width].max
          end

          mod.assigns.each { |assign| collect_signals_from_expr(assign.expr, referenced, seen_exprs: seen_exprs) }
          mod.processes.each do |process|
            collect_signals_from_statements(Array(process.statements), referenced, seen_exprs: seen_exprs)
          end

          Array(mod.instances).each do |inst|
            Array(inst.connections).each do |conn|
              collect_signals_from_connection(conn.signal, referenced, seen_exprs: seen_exprs)
            end
          end

          referenced.each_with_object([]) do |(name, width), wires|
            next if declared.include?(name)

            wires << { name: name, width: width.to_i.positive? ? width.to_i : 1 }
          end
        end

        def collect_signals_from_statements(statements, referenced, seen_exprs: Set.new)
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              collect_signals_from_expr(stmt.expr, referenced, seen_exprs: seen_exprs)
            when IR::If
              collect_signals_from_expr(stmt.condition, referenced, seen_exprs: seen_exprs)
              collect_signals_from_statements(stmt.then_statements, referenced, seen_exprs: seen_exprs)
              collect_signals_from_statements(stmt.else_statements, referenced, seen_exprs: seen_exprs)
            end
          end
        end

        def collect_signals_from_connection(signal, referenced, seen_exprs: Set.new)
          case signal
          when String, Symbol
            name = sanitize_name(signal)
            referenced[name] = [referenced[name].to_i, 1].max
          when IR::Signal
            name = sanitize_name(signal.name)
            referenced[name] = [referenced[name].to_i, signal.width.to_i].max
          when IR::Expr
            collect_signals_from_expr(signal, referenced, seen_exprs: seen_exprs)
          end
        end

        def collect_signals_from_expr(expr, referenced, seen_exprs: Set.new)
          return if expr.nil?

          expr_id = expr.object_id
          return if seen_exprs.include?(expr_id)

          seen_exprs << expr_id

          case expr
          when IR::Signal
            name = sanitize_name(expr.name)
            referenced[name] = [referenced[name].to_i, expr.width.to_i].max
          when IR::UnaryOp
            collect_signals_from_expr(expr.operand, referenced, seen_exprs: seen_exprs)
          when IR::BinaryOp
            collect_signals_from_expr(expr.left, referenced, seen_exprs: seen_exprs)
            collect_signals_from_expr(expr.right, referenced, seen_exprs: seen_exprs)
          when IR::Mux
            collect_signals_from_expr(expr.condition, referenced, seen_exprs: seen_exprs)
            collect_signals_from_expr(expr.when_true, referenced, seen_exprs: seen_exprs)
            collect_signals_from_expr(expr.when_false, referenced, seen_exprs: seen_exprs)
          when IR::Concat
            Array(expr.parts).each { |part| collect_signals_from_expr(part, referenced, seen_exprs: seen_exprs) }
          when IR::Slice
            collect_signals_from_expr(expr.base, referenced, seen_exprs: seen_exprs)
          when IR::Resize
            collect_signals_from_expr(expr.expr, referenced, seen_exprs: seen_exprs)
          when IR::Case
            collect_signals_from_expr(expr.selector, referenced, seen_exprs: seen_exprs)
            expr.cases.each_value do |value|
              collect_signals_from_expr(value, referenced, seen_exprs: seen_exprs)
            end
            collect_signals_from_expr(expr.default, referenced, seen_exprs: seen_exprs)
          when IR::MemoryRead
            collect_signals_from_expr(expr.addr, referenced, seen_exprs: seen_exprs)
          end
        end

        def expr_children(expr)
          case expr
          when IR::UnaryOp
            [expr.operand]
          when IR::BinaryOp
            [expr.left, expr.right]
          when IR::Mux
            [expr.condition, expr.when_true, expr.when_false]
          when IR::Concat
            Array(expr.parts)
          when IR::Slice
            [expr.base]
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

        def shared_expr_parent_counts(root)
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

        def hoist_shared_behavior_expr(expr, prefix:)
          counts = shared_expr_parent_counts(expr)
          hoisted = {}
          locals = []
          rewritten = rewrite_expr_with_behavior_locals(
            expr,
            counts: counts,
            hoisted: hoisted,
            locals: locals,
            prefix: sanitize_name(prefix)
          )
          [rewritten, locals]
        end

        def rewrite_expr_with_behavior_locals(expr, counts:, hoisted:, locals:, prefix:)
          return expr if expr.nil? || expr.is_a?(IR::Literal) || expr.is_a?(IR::Signal)

          oid = expr.object_id
          if hoisted.key?(oid)
            return IR::Signal.new(name: hoisted.fetch(oid), width: expr.width.to_i)
          end

          rewritten_children = expr_children(expr).map do |child|
            rewrite_expr_with_behavior_locals(
              child,
              counts: counts,
              hoisted: hoisted,
              locals: locals,
              prefix: prefix
            )
          end
          rewritten = rebuild_expr_with_children(expr, rewritten_children)

          if hoistable_behavior_expr?(expr, counts)
            name = sanitize_name("#{prefix}_local_#{locals.length}")
            locals << { name: name, expr: rewritten, width: rewritten.width.to_i }
            hoisted[oid] = name
            IR::Signal.new(name: name, width: rewritten.width.to_i)
          else
            rewritten
          end
        end

        def hoistable_behavior_expr?(expr, counts)
          counts[expr.object_id].to_i > 1 &&
            !expr.is_a?(IR::Literal) &&
            !expr.is_a?(IR::Signal)
        end

        def rebuild_expr_with_children(expr, children)
          case expr
          when IR::UnaryOp
            IR::UnaryOp.new(op: expr.op, operand: children.fetch(0), width: expr.width.to_i)
          when IR::BinaryOp
            IR::BinaryOp.new(
              op: expr.op,
              left: children.fetch(0),
              right: children.fetch(1),
              width: expr.width.to_i
            )
          when IR::Mux
            IR::Mux.new(
              condition: children.fetch(0),
              when_true: children.fetch(1),
              when_false: children.fetch(2),
              width: expr.width.to_i
            )
          when IR::Concat
            IR::Concat.new(parts: children, width: expr.width.to_i)
          when IR::Slice
            IR::Slice.new(base: children.fetch(0), range: expr.range, width: expr.width.to_i)
          when IR::Resize
            IR::Resize.new(expr: children.fetch(0), width: expr.width.to_i)
          when IR::Case
            case_values = expr.cases.keys.zip(children.drop(2)).to_h
            IR::Case.new(
              selector: children.fetch(0),
              cases: case_values,
              default: children.fetch(1),
              width: expr.width.to_i
            )
          when IR::MemoryRead
            IR::MemoryRead.new(memory: expr.memory, addr: children.fetch(0), width: expr.width.to_i)
          else
            expr
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

          mod.processes.each_with_index do |process, process_idx|
            next unless process.clocked

            seq_state = {}
            target_order = []
            lower_seq_statements_to_mux(
              Array(process.statements),
              seq_state: seq_state,
              target_order: target_order,
              mod: mod,
              diagnostics: diagnostics,
              strict: strict,
              mod_name: mod.name
            )

            target_order.each do |target|
              expr = seq_state[target.to_s]
              next unless expr

              rewritten_expr, locals = hoist_shared_behavior_expr(
                expr,
                prefix: "#{sanitize_name(target)}_seq_#{process_idx}"
              )
              Array(locals).each do |local|
                emit_local_binding(
                  lines,
                  name: local[:name],
                  expr: local[:expr],
                  width: local[:width],
                  diagnostics: diagnostics,
                  strict: strict,
                  indent: 4
                )
              end

              emit_assignment(
                lines,
                target: signal_ref(target),
                expr: rewritten_expr,
                diagnostics: diagnostics,
                strict: strict,
                indent: 4
              )
            end
          end

          lines << '  end'
          lines << ''
        end

        def lower_seq_statements_to_mux(statements, seq_state:, target_order:, mod:, diagnostics:, strict:, mod_name:)
          touched = Set.new

          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              target = sanitize_name(stmt.target)
              seq_state[target] = stmt.expr
              target_order << target unless target_order.include?(target)
              touched << target
            when IR::If
              condition = stmt.condition
              if condition.nil?
                diagnostics << Diagnostic.new(
                  severity: strict ? :error : :warning,
                  message: "Unsupported sequential if condition in #{mod_name}",
                  line: nil,
                  column: nil,
                  op: 'raise.sequential'
                )
                next
              end

              then_state = seq_state.dup
              else_state = seq_state.dup

              then_touched = lower_seq_statements_to_mux(
                Array(stmt.then_statements),
                seq_state: then_state,
                target_order: target_order,
                mod: mod,
                diagnostics: diagnostics,
                strict: strict,
                mod_name: mod_name
              )
              else_touched = lower_seq_statements_to_mux(
                Array(stmt.else_statements),
                seq_state: else_state,
                target_order: target_order,
                mod: mod,
                diagnostics: diagnostics,
                strict: strict,
                mod_name: mod_name
              )

              branch_targets = (then_touched + else_touched).uniq
              branch_targets.each do |target|
                width = seq_target_width(mod, target, then_state[target], else_state[target], seq_state[target])
                prior = seq_state[target] || IR::Signal.new(name: target, width: width)
                when_true = ensure_expr_width(then_state[target] || prior, width)
                when_false = ensure_expr_width(else_state[target] || prior, width)

                seq_state[target] = IR::Mux.new(
                  condition: condition,
                  when_true: when_true,
                  when_false: when_false,
                  width: width
                )
                target_order << target unless target_order.include?(target)
                touched << target
              end
            else
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Unsupported sequential statement #{stmt.class} in #{mod_name}",
                line: nil,
                column: nil,
                op: 'raise.sequential'
              )
            end
          end

          touched.to_a
        end

        def seq_target_width(mod, target, *exprs)
          widths = Array(exprs).compact.map { |expr| expr.respond_to?(:width) ? expr.width.to_i : 0 }

          port = mod.ports.find { |p| sanitize_name(p.name) == target.to_s }
          widths << port.width.to_i if port

          reg = mod.regs.find { |r| sanitize_name(r.name) == target.to_s }
          widths << reg.width.to_i if reg

          net = mod.nets.find { |n| sanitize_name(n.name) == target.to_s }
          widths << net.width.to_i if net

          [widths.max.to_i, 1].max
        end

        def ensure_expr_width(expr, width)
          return IR::Literal.new(value: 0, width: width) if expr.nil?
          return expr if !expr.respond_to?(:width) || expr.width.to_i == width

          IR::Resize.new(expr: expr, width: width)
        end

        def emit_seq_statements(lines, statements, diagnostics:, strict:, indent:, mod_name:)
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              emit_assignment(
                lines,
                target: signal_ref(stmt.target),
                expr: stmt.expr,
                diagnostics: diagnostics,
                strict: strict,
                indent: indent
              )
            when IR::If
              condition = expr_to_ruby(stmt.condition, diagnostics, strict: strict)
              if condition.nil?
                diagnostics << Diagnostic.new(
                  severity: :warning,
                  message: "Unsupported sequential if condition in #{mod_name}",
                  line: nil,
                  column: nil,
                  op: 'raise.sequential'
                )
                next
              end

              lines << "#{' ' * indent}if #{condition}"
              emit_seq_statements(
                lines,
                Array(stmt.then_statements),
                diagnostics: diagnostics,
                strict: strict,
                indent: indent + 2,
                mod_name: mod_name
              )
              unless Array(stmt.else_statements).empty?
                lines << "#{' ' * indent}else"
                emit_seq_statements(
                  lines,
                  Array(stmt.else_statements),
                  diagnostics: diagnostics,
                  strict: strict,
                  indent: indent + 2,
                  mod_name: mod_name
                )
              end
              lines << "#{' ' * indent}end"
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported sequential statement #{stmt.class} in #{mod_name}",
                line: nil,
                column: nil,
                op: 'raise.sequential'
              )
            end
          end
        end

        def emit_behavior(lines, mod, diagnostics, strict: false, bridge_assignments: [], structural_output_targets: [], behavior_plan: nil)
          behavior_plan ||= behavior_plan_for_module(
            mod,
            bridge_assignments: bridge_assignments,
            structural_output_targets: structural_output_targets
          )
          return unless behavior_plan[:emit]

          lines << '  behavior do'
          bridge_count = Array(bridge_assignments).length

          Array(bridge_assignments).each_with_index do |assign, idx|
            target = sanitize_name(assign.target)
            emit_behavior_assignment(
              lines,
              target: signal_ref(target),
              expr: assign.expr,
              diagnostics: diagnostics,
              strict: strict,
              indent: 4,
              local_prefix: "#{target}_bridge_#{idx}"
            )
          end

          assign_counts = Hash.new(0)
          Array(mod.assigns).each { |assign| assign_counts[sanitize_name(assign.target)] += 1 }

          Array(mod.assigns).each_with_index do |assign, idx|
            original_target = sanitize_name(assign.target)
            next if redundant_self_assign?(assign, original_target, assign_counts)

            emit_behavior_assignment(
              lines,
              target: signal_ref(original_target),
              expr: assign.expr,
              diagnostics: diagnostics,
              strict: strict,
              indent: 4,
              local_prefix: "#{original_target}_expr_#{idx + bridge_count}"
            )
          end

          missing_outputs = Array(behavior_plan[:missing_outputs])
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

        def emit_behavior_assignment(lines, target:, expr:, diagnostics:, strict:, indent:, local_prefix:)
          rewritten_expr, locals = hoist_shared_behavior_expr(expr, prefix: local_prefix)
          Array(locals).each do |local|
            emit_local_binding(
              lines,
              name: local[:name],
              expr: local[:expr],
              width: local[:width],
              diagnostics: diagnostics,
              strict: strict,
              indent: indent
            )
          end

          emit_assignment(
            lines,
            target: target,
            expr: rewritten_expr,
            diagnostics: diagnostics,
            strict: strict,
            indent: indent
          )
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

        def emit_local_binding(lines, name:, expr:, width:, diagnostics:, strict:, indent:)
          cache = {}
          expr_text = expr_to_ruby_cached(expr, diagnostics, strict: strict, cache: cache)
          return if expr_text.nil? || expr_text.empty?

          prefix = ' ' * indent
          inline = "#{name} = local(:#{name}, #{expr_text}, width: #{width.to_i})"
          if prefix.length + inline.length <= MAX_EMITTED_LINE_LENGTH
            lines << "#{prefix}#{inline}"
            return
          end

          expr_lines = render_expr_lines(
            expr,
            diagnostics,
            strict: strict,
            indent: indent + 2,
            cache: cache
          )
          append_suffix_to_last_line(expr_lines, ',')

          lines << "#{prefix}#{name} = local("
          lines << "#{prefix}  :#{name},"
          lines.concat(expr_lines)
          lines << "#{prefix}  width: #{width.to_i}"
          lines << "#{prefix})"
        end

        def render_expr_lines(expr, diagnostics, strict:, indent:, cache:)
          inline = expr_to_ruby_cached(expr, diagnostics, strict: strict, cache: cache)
          return [] if inline.nil? || inline.empty?

          if indent + inline.length <= MAX_EMITTED_LINE_LENGTH || !pretty_breakable_expr?(expr) || expr.is_a?(IR::Mux)
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
              indent: indent + 2,
              cache: cache
            )
            false_lines = render_expr_lines(
              expr.when_false,
              diagnostics,
              strict: strict,
              indent: indent + 2,
              cache: cache
            )
            append_suffix_to_last_line(condition_lines, ',')
            append_suffix_to_last_line(true_lines, ',')

            lines = ["#{' ' * indent}mux("]
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
          return nil if expr.nil?

          key = [expr.object_id, strict]
          return cache[key] if cache.key?(key)

          cache[key] = expr_to_ruby(expr, diagnostics, strict: strict, cache: cache)
        end

        def pretty_breakable_expr?(expr)
          return false if expr.is_a?(IR::BinaryOp) && comparison_op_conflicts_with_assignment?(expr.op)

          expr.is_a?(IR::BinaryOp) || expr.is_a?(IR::Mux) || expr.is_a?(IR::Concat)
        end

        def append_suffix_to_last_line(lines, suffix)
          return lines if lines.empty?

          lines[-1] = "#{lines[-1]}#{suffix}"
          lines
        end

        def redundant_self_assign?(assign, target, assign_counts)
          return false unless assign_counts[target].to_i > 1
          return false unless assign.expr.is_a?(IR::Signal)

          sanitize_name(assign.expr.name) == target
        end

        def input_port?(mod, name)
          mod.ports.any? { |p| p.direction == :in && sanitize_name(p.name) == name.to_s }
        end

        def output_port?(mod, name)
          mod.ports.any? { |p| p.direction == :out && sanitize_name(p.name) == name.to_s }
        end

        def comparison_op_conflicts_with_assignment?(op)
          %i[<= >=].include?(op.to_sym)
        rescue StandardError
          false
        end

        def expr_to_ruby(expr, diagnostics, strict: false, cache: nil)
          cache ||= {}

          case expr
          when IR::Literal
            "lit(#{expr.value.inspect}, width: #{expr.width.to_i})"
          when IR::Signal
            signal_ref(expr.name)
          when IR::BinaryOp
            left = expr_to_ruby_cached(expr.left, diagnostics, strict: strict, cache: cache)
            right = expr_to_ruby_cached(expr.right, diagnostics, strict: strict, cache: cache)
            return nil if left.nil? || right.nil?

            if comparison_op_conflicts_with_assignment?(expr.op)
              case expr.op.to_sym
              when :<=
                "((#{left} < #{right}) | (#{left} == #{right}))"
              when :>=
                "((#{left} > #{right}) | (#{left} == #{right}))"
              else
                "(#{left} #{expr.op} #{right})"
              end
            else
              "(#{left} #{expr.op} #{right})"
            end
          when IR::UnaryOp
            operand = expr_to_ruby_cached(expr.operand, diagnostics, strict: strict, cache: cache)
            return nil if operand.nil?

            "(#{expr.op}#{operand})"
          when IR::Mux
            expr_to_ruby_mux(expr, diagnostics, strict: strict, cache: cache)
          when IR::Slice
            range = expr.range
            if range.begin == range.end
              base = expr_to_ruby_cached(expr.base, diagnostics, strict: strict, cache: cache)
              return nil if base.nil?

              "#{base}[#{range.begin}]"
            else
              base = expr_to_ruby_cached(expr.base, diagnostics, strict: strict, cache: cache)
              return nil if base.nil?

              "#{base}[#{range.end}..#{range.begin}]"
            end
          when IR::Concat
            parts = expr.parts.map { |p| expr_to_ruby_cached(p, diagnostics, strict: strict, cache: cache) }
            return nil if parts.any?(&:nil?)

            "cat(#{parts.join(', ')})"
          when IR::Resize
            expr_to_ruby_cached(expr.expr, diagnostics, strict: strict, cache: cache)
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
              expr.default ? expr_to_ruby_cached(expr.default, diagnostics, strict: strict, cache: cache) : '0'
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

        def expr_to_ruby_mux(expr, diagnostics, strict:, cache:)
          chain = []
          seen = Set.new
          current = expr

          while current.is_a?(IR::Mux)
            key = current.object_id
            if seen.include?(key)
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: 'Detected cyclic mux chain while raising expression',
                line: nil,
                column: nil,
                op: 'raise.expr'
              )
              return nil if strict
              return '0'
            end

            seen << key
            chain << [current.condition, current.when_true]
            current = current.when_false
          end

          tail = expr_to_ruby_cached(current, diagnostics, strict: strict, cache: cache)
          return nil if tail.nil?

          rendered_pairs = []
          chain.each do |condition_expr, true_expr|
            condition = expr_to_ruby_cached(condition_expr, diagnostics, strict: strict, cache: cache)
            when_true = expr_to_ruby_cached(true_expr, diagnostics, strict: strict, cache: cache)
            return nil if condition.nil? || when_true.nil?

            rendered_pairs << [condition, when_true]
          end

          return tail if rendered_pairs.empty?

          rendered = +''
          rendered_pairs.each do |condition, when_true|
            rendered << 'mux('
            rendered << condition
            rendered << ', '
            rendered << when_true
            rendered << ', '
          end
          rendered << tail
          rendered << (')' * rendered_pairs.length)
          rendered
        end

        def format_generated_output_dir(out_dir, diagnostics)
          return unless out_dir && Dir.exist?(out_dir)

          return unless syntax_tree_available?(diagnostics)

          ruby_files = Dir.glob(File.join(out_dir, '**', '*.rb')).sort
          ruby_files.each do |path|
            format_ruby_file_with_syntax_tree(path, diagnostics)
          end
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: "SyntaxTree formatting failed: #{e.class}: #{e.message}",
            line: nil,
            column: nil,
            op: 'raise.format'
          )
        end

        def syntax_tree_available?(diagnostics)
          return @syntax_tree_loaded if defined?(@syntax_tree_loaded)

          begin
            require 'syntax_tree'
            @syntax_tree_loaded = true
          rescue LoadError
            diagnostics << Diagnostic.new(
              severity: :warning,
              message: 'SyntaxTree gem not available; generated files were not auto-formatted',
              line: nil,
              column: nil,
              op: 'raise.format'
            )
            @syntax_tree_loaded = false
          end
          @syntax_tree_loaded
        end

        def format_ruby_file_with_syntax_tree(path, diagnostics)
          source = File.read(path)
          formatted = if SyntaxTree.respond_to?(:format)
                        SyntaxTree.format(source)
                      else
                        SyntaxTree::Formatter.format(source)
                      end
          return if formatted == source

          File.write(path, formatted)
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: "SyntaxTree formatting failed for #{path}: #{e.class}: #{e.message}",
            line: nil,
            column: nil,
            op: 'raise.format'
          )
        end

        def underscore(name)
          name.to_s
              .gsub('::', '_')
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
              .gsub(/([a-z\\d])([A-Z])/, '\\1_\\2')
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
          reserved.include?(value) || numbered_parameter_identifier?(value)
        end

        def numbered_parameter_identifier?(value)
          value.to_s.match?(/\A_[1-9]\d*\z/)
        end

        def module_texts_by_name(mlir_text)
          package = RHDL::Codegen::CIRCT::ImportCleanup.split_top_level_package(mlir_text)
          return {} unless package

          package.fetch(:entries).each_with_object({}) do |entry, acc|
            name = RHDL::Codegen::CIRCT::ImportCleanup.module_name_for_entry(entry)
            acc[name] = entry.strip if name
          end
        end
      end
    end
  end
end
