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

      module Raise
        module_function

        # Raise CIRCT nodes/MLIR into in-memory Ruby DSL source strings.
        # Returns {module_name => ruby_source}.
        def to_sources(nodes_or_mlir, top: nil)
          modules, diagnostics = resolve_modules_and_diagnostics(nodes_or_mlir)
          sources = {}

          modules.each do |mod|
            class_name = camelize(mod.name)
            sources[mod.name.to_s] = emit_component(mod, class_name, diagnostics)
          end

          append_missing_top_error(modules, diagnostics, top)
          SourceResult.new(sources: sources, diagnostics: diagnostics)
        end

        def to_dsl(nodes_or_mlir, out_dir:, top: nil)
          source_result = to_sources(nodes_or_mlir, top: top)

          FileUtils.mkdir_p(out_dir)
          files_written = []

          source_result.sources.each do |module_name, ruby|
            out_path = File.join(out_dir, "#{underscore(module_name)}.rb")
            File.write(out_path, ruby)
            files_written << out_path
          end

          RaiseResult.new(files_written: files_written, diagnostics: source_result.diagnostics.dup)
        end

        # Raise CIRCT nodes/MLIR into loaded Ruby DSL component classes.
        # Returns {module_name => component_class}.
        def to_components(nodes_or_mlir, namespace: Module.new, top: nil)
          source_result = to_sources(nodes_or_mlir, top: top)
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

        def resolve_modules_and_diagnostics(nodes_or_mlir)
          if nodes_or_mlir.is_a?(String)
            import_result = Import.from_mlir(nodes_or_mlir)
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

        def emit_component(mod, class_name, diagnostics)
          sequential = mod.processes.any?(&:clocked)
          base = sequential ? 'RHDL::Sim::SequentialComponent' : 'RHDL::Sim::Component'

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

          emit_internal_wires(lines, mod)
          emit_structure(lines, mod, diagnostics)

          if sequential
            emit_sequential(lines, mod, diagnostics)
          end

          emit_behavior(lines, mod, diagnostics)

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

        def emit_internal_wires(lines, mod)
          port_names = mod.ports.map { |p| sanitize_name(p.name) }.to_set
          seen = Set.new
          internal = (Array(mod.nets) + Array(mod.regs)).map { |n| [sanitize_name(n.name), n.width.to_i] }

          internal.each do |name, width|
            next if port_names.include?(name)
            next if seen.include?(name)

            width_arg = width == 1 ? '' : ", width: #{width}"
            lines << "  wire :#{name}#{width_arg}"
            seen << name
          end
          lines << '' unless seen.empty?
        end

        def emit_structure(lines, mod, diagnostics)
          return if mod.instances.empty?

          mod.instances.each do |inst|
            params = format_instance_params(inst.parameters || {})
            lines << "  instance :#{sanitize_name(inst.name)}, #{camelize(inst.module_name)}#{params}"
          end
          mod.instances.each do |inst|
            inst_name = sanitize_name(inst.name)
            Array(inst.connections).each do |conn|
              port_name = sanitize_name(conn.port_name)
              case conn.direction.to_s
              when 'out'
                dest = connection_ref(conn.signal)
                if dest
                  lines << "  port [:#{inst_name}, :#{port_name}] => #{dest}"
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
                  lines << "  port #{src} => [:#{inst_name}, :#{port_name}]"
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
          lines << ''
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

        def emit_sequential(lines, mod, diagnostics)
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
              expr_text = expr_to_ruby(seq_state[target], diagnostics)
              lines << "    #{sanitize_name(target)} <= #{expr_text}"
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

        def emit_behavior(lines, mod, diagnostics)
          lines << '  behavior do'
          emitted_any = false

          mod.assigns.each do |assign|
            target = sanitize_name(assign.target)
            next unless output_port?(mod, target)

            expr_text = expr_to_ruby(assign.expr, diagnostics)
            lines << "    #{target} <= #{expr_text}"
            emitted_any = true
          end

          unless emitted_any
            diagnostics << Diagnostic.new(
              severity: :warning,
              message: "No direct output assignments were recovered for #{mod.name}; emitted placeholders",
              line: nil,
              column: nil,
              op: 'raise.behavior'
            )

            mod.ports.each do |port|
              next unless port.direction == :out
              lines << "    #{sanitize_name(port.name)} <= 0"
            end
          end

          lines << '  end'
        end

        def output_port?(mod, name)
          mod.ports.any? { |p| p.direction == :out && sanitize_name(p.name) == name.to_s }
        end

        def expr_to_ruby(expr, diagnostics)
          case expr
          when IR::Literal
            expr.value.to_s
          when IR::Signal
            sanitize_name(expr.name)
          when IR::BinaryOp
            "(#{expr_to_ruby(expr.left, diagnostics)} #{expr.op} #{expr_to_ruby(expr.right, diagnostics)})"
          when IR::UnaryOp
            "(#{expr.op}#{expr_to_ruby(expr.operand, diagnostics)})"
          when IR::Mux
            "(#{expr_to_ruby(expr.condition, diagnostics)} ? #{expr_to_ruby(expr.when_true, diagnostics)} : #{expr_to_ruby(expr.when_false, diagnostics)})"
          when IR::Slice
            range = expr.range
            if range.begin == range.end
              "#{expr_to_ruby(expr.base, diagnostics)}[#{range.begin}]"
            else
              "#{expr_to_ruby(expr.base, diagnostics)}[#{range.end}..#{range.begin}]"
            end
          when IR::Concat
            "concat(#{expr.parts.map { |p| expr_to_ruby(p, diagnostics) }.join(', ')})"
          when IR::Resize
            "#{expr_to_ruby(expr.expr, diagnostics)}"
          when IR::Case
            diagnostics << Diagnostic.new(
              severity: :warning,
              message: 'Case expression emitted as default branch only',
              line: nil,
              column: nil,
              op: 'raise.case'
            )
            expr.default ? expr_to_ruby(expr.default, diagnostics) : '0'
          when IR::MemoryRead
            diagnostics << Diagnostic.new(
              severity: :warning,
              message: 'Memory read lowering is unsupported in CIRCT->DSL v1',
              line: nil,
              column: nil,
              op: 'raise.memory_read'
            )
            '0'
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
