# frozen_string_literal: true

require "set"
require_relative "source_map"
require_relative "diagnostic_mapper"

module RHDL
  module Import
    module Frontend
      class Normalizer
        BINARY_OPERATORS = {
          "AND" => "&",
          "OR" => "|",
          "XOR" => "^",
          "ADD" => "+",
          "SUB" => "-",
          "EQ" => "==",
          "NEQ" => "!=",
          "LT" => "<",
          "LTE" => "<=",
          "LTES" => "<=",
          "GT" => ">",
          "GTE" => ">=",
          "GTES" => ">=",
          "LTS" => "<",
          "GTS" => ">",
          "SHIFTR" => ">>",
          "SHIFTL" => "<<"
        }.freeze

        class << self
          def normalize(raw_payload)
            new(raw_payload).normalize
          end
        end

        def initialize(raw_payload)
          @raw_payload = raw_payload.is_a?(Hash) ? raw_payload : {}
          @payload = extract_payload(@raw_payload)
          @frontend_meta = extract_frontend_meta(@raw_payload)
        end

        def normalize
          source_map = SourceMap.build(raw_sources)

          {
            schema_version: 1,
            adapter: normalize_adapter(value_for(@payload, :adapter)),
            invocation: normalize_invocation(value_for(@payload, :invocation)),
            source_map: source_map.to_h,
            design: {
              modules: normalize_modules(raw_modules, source_map)
            },
            diagnostics: DiagnosticMapper.map(
              diagnostics: raw_diagnostics,
              source_map: source_map
            )
          }
        end

        private

        def normalize_adapter(adapter)
          hash = adapter.is_a?(Hash) ? adapter : {}
          return {
            name: value_for(hash, :name),
            version: value_for(hash, :version)
          } if !hash.empty?

          {
            name: "verilator_json",
            version: value_for(@payload, :version)
          }
        end

        def normalize_invocation(invocation)
          hash = invocation.is_a?(Hash) ? invocation : {}
          return {
            cwd: value_for(hash, :cwd),
            command: Array(value_for(hash, :command))
          } if !hash.empty?

          command_metadata = value_for(value_for(@raw_payload, :metadata), :command)
          {
            cwd: value_for(command_metadata, :chdir),
            command: Array(value_for(command_metadata, :argv))
          }
        end

        def normalize_modules(modules, source_map)
          Array(modules).map do |module_entry|
            entry = module_entry.is_a?(Hash) ? module_entry : {}
            source = source_map.lookup_by_original_id(value_for(entry, :source_id))
            span = normalize_span(value_for(entry, :span), source)
            normalized = {
              name: value_for(entry, :name).to_s,
              source_id: source && source[:id],
              span: span
            }

            ports = normalize_module_section(entry, :ports)
            parameters = normalize_module_section(entry, :parameters)
            declarations = normalize_module_section(entry, :declarations)
            statements = normalize_module_section(entry, :statements)
            processes = normalize_module_section(entry, :processes)
            instances = normalize_module_section(entry, :instances)
            inferred_widths = infer_missing_declared_widths(
              statements: statements,
              processes: processes,
              instances: instances
            )
            declarations = add_inferred_declarations(
              ports: ports,
              parameters: parameters,
              declarations: declarations,
              statements: statements,
              processes: processes,
              inferred_widths: inferred_widths
            )
            ports = apply_inferred_widths(ports, inferred_widths)
            declarations = apply_inferred_widths(declarations, inferred_widths)

            normalized[:ports] = ports unless ports.empty?
            normalized[:parameters] = parameters unless parameters.empty?
            normalized[:declarations] = declarations unless declarations.empty?
            normalized[:statements] = statements unless statements.empty?
            normalized[:processes] = processes unless processes.empty?
            normalized[:instances] = instances unless instances.empty?
            normalized
          end.sort_by { |entry| entry[:name] }
        end

        def normalize_span(span, source)
          span_hash = span.is_a?(Hash) ? span : {}
          line = integer_or_default(value_for(span_hash, :line), 1)
          column = integer_or_default(value_for(span_hash, :column), 1)
          end_line = integer_or_default(value_for(span_hash, :end_line), line)
          end_column = integer_or_default(value_for(span_hash, :end_column), column)

          {
            source_id: source && source[:id],
            source_path: source ? source[:path] : normalize_path(value_for(span_hash, :source_path) || value_for(span_hash, :file) || value_for(span_hash, :path)),
            line: line,
            column: column,
            end_line: end_line,
            end_column: end_column
          }
        end

        def raw_sources
          canonical_sources = value_for(@payload, :sources)
          return canonical_sources if canonical_sources.is_a?(Array)

          files = value_for(@frontend_meta, :files)
          return [] unless files.is_a?(Hash)

          files.map do |id, entry|
            hash = entry.is_a?(Hash) ? entry : {}
            path = value_for(hash, :filename) || value_for(hash, :realpath)
            next unless path

            { id: id.to_s, path: path.to_s }
          end.compact
        end

        def raw_modules
          canonical_modules = value_for(@payload, :modules)
          return canonical_modules if canonical_modules.is_a?(Array)

          modulesp = value_for(@payload, :modulesp)
          return [] unless modulesp.is_a?(Array)

          extract_modules_from_modulesp(modulesp)
        end

        def normalize_module_section(entry, key)
          Array(value_for(entry, key)).map { |value| deep_normalize(value) }
        end

        def deep_normalize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, inner), memo|
              memo[key.to_sym] = deep_normalize(inner)
            end
          when Array
            value.map { |inner| deep_normalize(inner) }
          else
            value
          end
        end

        def extract_modules_from_modulesp(modulesp)
          addr_index = build_address_index(@payload)
          modulesp.filter_map do |entry|
            hash = entry.is_a?(Hash) ? entry : {}
            next unless value_for(hash, :type).to_s == "MODULE"

            name = value_for(hash, :name).to_s
            next if name.empty? || name.start_with?("@")

            normalize_modulesp_module(hash, addr_index: addr_index)
          end
        end

        def build_address_index(node, index = {})
          case node
          when Hash
            addr = value_for(node, :addr)
            index[addr.to_s] = node if addr
            node.each_value { |inner| build_address_index(inner, index) }
          when Array
            node.each { |inner| build_address_index(inner, index) }
          end
          index
        end

        def normalize_modulesp_module(module_node, addr_index:)
          loc = parse_loc(value_for(module_node, :loc))
          statements = Array(value_for(module_node, :stmtsp))
          var_nodes = statements.select { |node| value_for(node, :type).to_s == "VAR" }

          {
            name: value_for(module_node, :name).to_s,
            source_id: loc[:source_id],
            span: {
              line: loc[:line],
              column: loc[:column],
              end_line: loc[:end_line],
              end_column: loc[:end_column]
            },
            ports: var_nodes.filter_map { |node| normalize_var_port(node, addr_index: addr_index) },
            parameters: var_nodes.filter_map { |node| normalize_var_parameter(node, addr_index: addr_index) },
            declarations: var_nodes.filter_map { |node| normalize_var_declaration(node, addr_index: addr_index) },
            statements: extract_continuous_assignments(statements, addr_index: addr_index),
            processes: statements.filter_map { |node| normalize_process(node, addr_index: addr_index) },
            instances: statements.filter_map { |node| normalize_instance(node, addr_index: addr_index) }
          }
        end

        def normalize_var_port(var_node, addr_index:)
          direction = normalize_direction(value_for(var_node, :direction))
          return nil if direction.nil?

          name = value_for(var_node, :name).to_s
          return nil if name.empty?

          {
            direction: direction,
            name: name,
            width: width_from_var(var_node, addr_index: addr_index)
          }
        end

        def normalize_var_parameter(var_node, addr_index:)
          var_type = value_for(var_node, :varType).to_s
          is_param = truthy?(value_for(var_node, :isParam)) || truthy?(value_for(var_node, :isGParam))
          return nil unless var_type == "LPARAM" || is_param

          name = value_for(var_node, :name).to_s
          return nil if name.empty?

          {
            name: name,
            default: normalize_expression(first_entry(var_node, :valuep), addr_index: addr_index)
          }
        end

        def normalize_var_declaration(var_node, addr_index:)
          return nil if normalize_direction(value_for(var_node, :direction))
          return nil if normalize_var_parameter(var_node, addr_index: addr_index)

          name = value_for(var_node, :name).to_s
          return nil if name.empty?

          kind = declaration_kind(value_for(var_node, :varType), name: name)
          return nil if kind.nil?

          {
            kind: kind,
            name: name,
            width: width_from_var(var_node, addr_index: addr_index)
          }
        end

        def declaration_kind(var_type, name: nil)
          case var_type.to_s
          when "WIRE"
            "wire"
          when "VAR"
            if verilator_synthetic_logic_name?(name)
              "logic"
            elsif verilator_synthetic_wire_name?(name)
              "wire"
            else
              "reg"
            end
          when "MODULETEMP"
            "logic"
          else
            nil
          end
        end

        def verilator_synthetic_logic_name?(name)
          token = name.to_s
          return false if token.empty?

          token.start_with?("__Vdfg")
        end

        def verilator_synthetic_wire_name?(name)
          name.to_s == "_unused_ok"
        end

        def extract_continuous_assignments(statements, addr_index:)
          Array(statements).flat_map do |node|
            hash = normalize_hash(node)
            type = value_for(hash, :type).to_s

            if type == "ALWAYS" && value_for(hash, :keyword).to_s == "cont_assign"
              normalize_statement_list(value_for(hash, :stmtsp), addr_index: addr_index)
                .select { |statement| value_for(statement, :kind).to_s == "continuous_assign" }
            elsif type == "ASSIGNW"
              statement = normalize_assign_statement(hash, kind: "continuous_assign", addr_index: addr_index)
              statement ? [statement] : []
            else
              []
            end
          end
        end

        def normalize_process(node, addr_index:)
          hash = normalize_hash(node)
          type = value_for(hash, :type).to_s

          if %w[INITIAL INITIALSTATIC].include?(type)
            return {
              kind: "initial",
              domain: "initial",
              sensitivity: [],
              statements: normalize_statement_list(value_for(hash, :stmtsp), addr_index: addr_index)
            }
          end

          return nil unless type == "ALWAYS"
          return nil if value_for(hash, :keyword).to_s == "cont_assign"

          sensitivity = normalize_sensitivity(value_for(hash, :sentreep), addr_index: addr_index)
          {
            kind: "always",
            domain: sensitivity.any? { |event| %w[posedge negedge].include?(value_for(event, :edge).to_s) } ? "sequential" : "combinational",
            sensitivity: sensitivity,
            statements: normalize_statement_list(value_for(hash, :stmtsp), addr_index: addr_index)
          }
        end

        def normalize_sensitivity(sentrees, addr_index:)
          Array(sentrees).flat_map do |entry|
            hash = normalize_hash(entry)
            Array(value_for(hash, :sensesp)).filter_map do |sense|
              sense_hash = normalize_hash(sense)
              signal = normalize_expression(first_entry(sense_hash, :sensp), addr_index: addr_index)
              next if signal.nil?

              {
                edge: normalize_edge(value_for(sense_hash, :edgeType)),
                signal: signal
              }
            end
          end
        end

        def normalize_instance(node, addr_index:)
          hash = normalize_hash(node)
          return nil unless value_for(hash, :type).to_s == "CELL"

          module_name = resolve_module_name(value_for(hash, :modp), addr_index: addr_index)
          name = value_for(hash, :name).to_s
          return nil if module_name.empty? || name.empty?

          {
            name: name,
            module_name: module_name,
            parameter_overrides: normalize_instance_parameter_overrides(
              value_for(hash, :paramsp),
              addr_index: addr_index
            ),
            connections: Array(value_for(hash, :pinsp)).filter_map do |pin|
              pin_hash = normalize_hash(pin)
              port = value_for(pin_hash, :name).to_s
              signal = normalize_expression(first_entry(pin_hash, :exprp), addr_index: addr_index)
              next if port.empty?

              {
                port: port,
                signal: signal
              }
            end
          }
        end

        def normalize_instance_parameter_overrides(paramsp, addr_index:)
          Array(paramsp).filter_map do |entry|
            hash = normalize_hash(entry)
            name = value_for(hash, :name).to_s

            if name.empty?
              parameter_node = addr_index[value_for(hash, :paramp).to_s]
              name = value_for(parameter_node, :name).to_s
            end
            next if name.empty?

            value_node =
              first_entry(hash, :exprp) ||
              first_entry(hash, :valuep) ||
              first_entry(hash, :rhsp) ||
              first_entry(hash, :srcp)
            value = normalize_expression(value_node, addr_index: addr_index)
            next if value.nil?

            {
              name: name,
              value: value
            }
          end
        end

        def normalize_statement_list(nodes, addr_index:)
          statements = []
          entries = Array(nodes).map { |node| normalize_hash(node) }
          index = 0

          while index < entries.length
            hash = entries[index]
            type = value_for(hash, :type).to_s

            if type == "BEGIN"
              statements.concat(
                normalize_statement_list(value_for(hash, :stmtsp), addr_index: addr_index)
              )
              index += 1
              next
            end

            if type == "ASSIGN" &&
                value_for(entries[index + 1], :type).to_s == "LOOP"
              loop_stmt = normalize_loop_statement(
                entries[index + 1],
                addr_index: addr_index,
                init_assign_node: hash
              )
              unless loop_stmt.nil?
                statements << loop_stmt
                index += 2
                next
              end
            end

            statement = normalize_statement(hash, addr_index: addr_index)
            statements << statement unless statement.nil?
            index += 1
          end

          statements
        end

        def normalize_statement(node, addr_index:)
          type = value_for(node, :type).to_s

          case type
          when "ASSIGNW"
            normalize_assign_statement(node, kind: "continuous_assign", addr_index: addr_index)
          when "ASSIGN"
            normalize_assign_statement(node, kind: "blocking_assign", addr_index: addr_index)
          when "ASSIGNDLY"
            normalize_assign_statement(node, kind: "nonblocking_assign", addr_index: addr_index)
          when "IF"
            condition = normalize_expression(first_entry(node, :condp), addr_index: addr_index)
            return nil if condition.nil?

            {
              kind: "if",
              condition: condition,
              then: normalize_statement_list(value_for(node, :thensp), addr_index: addr_index),
              else: normalize_statement_list(value_for(node, :elsesp), addr_index: addr_index)
            }
          when "CASE"
            normalize_case_statement(node, addr_index: addr_index)
          when "LOOP"
            normalize_loop_statement(node, addr_index: addr_index)
          else
            nil
          end
        end

        def normalize_case_statement(node, addr_index:)
          selector = normalize_expression(first_entry(node, :exprp), addr_index: addr_index)
          return nil if selector.nil?

          items = Array(value_for(node, :itemsp)).map { |item| normalize_hash(item) }
          default_item = items.find { |item| Array(value_for(item, :condsp)).empty? }

          {
            kind: "case",
            selector: selector,
            items: items.filter_map do |item|
              conds = Array(value_for(item, :condsp))
              next if conds.empty?

              values = conds.filter_map { |cond| normalize_expression(cond, addr_index: addr_index) }
              next if values.empty?

              {
                values: values,
                body: normalize_statement_list(value_for(item, :stmtsp), addr_index: addr_index)
              }
            end,
            default: default_item ? normalize_statement_list(value_for(default_item, :stmtsp), addr_index: addr_index) : []
          }
        end

        def normalize_loop_statement(node, addr_index:, init_assign_node: nil)
          hash = normalize_hash(node)
          return nil unless value_for(hash, :type).to_s == "LOOP"

          init_assign = normalize_hash(init_assign_node)
          loop_statements = Array(value_for(hash, :stmtsp)).map { |entry| normalize_hash(entry) }
          loop_test = loop_statements.find { |entry| value_for(entry, :type).to_s == "LOOPTEST" }
          body_begin = loop_statements.find { |entry| value_for(entry, :type).to_s == "BEGIN" }
          increment_assign = loop_statements.reverse.find { |entry| value_for(entry, :type).to_s == "ASSIGN" }
          return nil if loop_test.nil? || body_begin.nil? || increment_assign.nil?

          init_target = normalize_expression(first_entry(init_assign, :lhsp), addr_index: addr_index)
          init_value = normalize_expression(first_entry(init_assign, :rhsp), addr_index: addr_index)
          return nil if init_target.nil? || init_value.nil?

          var_name = extract_identifier_name(init_target)
          start_value = number_literal_to_integer(init_value)
          return nil if var_name.nil? || start_value.nil?

          condition = normalize_expression(first_entry(loop_test, :condp), addr_index: addr_index)
          stop_value = loop_condition_stop_value(condition: condition, loop_var_name: var_name)
          return nil if stop_value.nil?

          return nil unless increment_matches_static_step_one?(
            assign_node: increment_assign,
            loop_var_name: var_name,
            addr_index: addr_index
          )

          {
            kind: "for",
            var: var_name,
            range: {
              from: start_value,
              to: stop_value
            },
            body: normalize_statement_list(value_for(body_begin, :stmtsp), addr_index: addr_index)
          }
        end

        def increment_matches_static_step_one?(assign_node:, loop_var_name:, addr_index:)
          target = normalize_expression(first_entry(assign_node, :lhsp), addr_index: addr_index)
          value = normalize_expression(first_entry(assign_node, :rhsp), addr_index: addr_index)
          return false if target.nil? || value.nil?
          return false unless extract_identifier_name(target) == loop_var_name

          value_hash = normalize_hash(value)
          return false unless value_for(value_hash, :kind).to_s == "binary"
          return false unless value_for(value_hash, :operator).to_s == "+"

          left_name = extract_identifier_name(value_for(value_hash, :left))
          right_name = extract_identifier_name(value_for(value_hash, :right))
          left_number = number_literal_to_integer(value_for(value_hash, :left))
          right_number = number_literal_to_integer(value_for(value_hash, :right))

          (left_name == loop_var_name && right_number == 1) ||
            (right_name == loop_var_name && left_number == 1)
        end

        def loop_condition_stop_value(condition:, loop_var_name:)
          hash = normalize_hash(condition)
          return nil unless value_for(hash, :kind).to_s == "binary"

          operator = value_for(hash, :operator).to_s
          left = value_for(hash, :left)
          right = value_for(hash, :right)
          left_name = extract_identifier_name(left)
          right_name = extract_identifier_name(right)
          left_number = number_literal_to_integer(left)
          right_number = number_literal_to_integer(right)

          if (operator == "<=" || operator == "<") &&
              left_name == loop_var_name &&
              !right_number.nil?
            return right_number if operator == "<="
            return right_number - 1
          end

          if (operator == ">=" || operator == ">") &&
              right_name == loop_var_name &&
              !left_number.nil?
            return left_number if operator == ">="
            return left_number - 1
          end

          nil
        end

        def extract_identifier_name(node)
          hash = normalize_hash(node)
          return nil unless value_for(hash, :kind).to_s == "identifier"

          name = value_for(hash, :name).to_s
          name.empty? ? nil : name
        end

        def number_literal_to_integer(node)
          hash = normalize_hash(node)
          return nil unless value_for(hash, :kind).to_s == "number"

          value = value_for(hash, :value)
          base = value_for(hash, :base).to_s.strip.downcase
          text = value.to_s
          return nil if text.empty?

          radix =
            case base
            when "2", "b", "bin", "binary" then 2
            when "8", "o", "oct", "octal" then 8
            when "16", "h", "hex", "hexadecimal" then 16
            else 10
            end
          Integer(text, radix)
        rescue ArgumentError
          nil
        end

        def normalize_assign_statement(node, kind:, addr_index:)
          target = normalize_expression(first_entry(node, :lhsp), addr_index: addr_index)
          value = normalize_expression(first_entry(node, :rhsp), addr_index: addr_index)
          return nil if target.nil? || value.nil?

          {
            kind: kind,
            target: target,
            value: value
          }
        end

        def normalize_expression(node, addr_index:, parent_type: nil)
          hash = normalize_hash(node)
          type = value_for(hash, :type).to_s

          case type
          when "VARREF"
            {
              kind: "identifier",
              name: value_for(hash, :name).to_s
            }
          when "CONST"
            parse_const(value_for(hash, :name))
          when "EXTEND"
            normalize_extend_expression(hash, addr_index: addr_index, parent_type: parent_type)
          when "NOT"
            operand = normalize_expression(first_entry(hash, :lhsp), addr_index: addr_index, parent_type: type)
            return nil if operand.nil?

            {
              kind: "unary",
              operator: "~",
              operand: operand
            }
          when "NEGATE", "REDOR", "REDAND"
            operand = normalize_expression(first_entry(hash, :lhsp), addr_index: addr_index, parent_type: type)
            return nil if operand.nil?

            {
              kind: "unary",
              operator: { "NEGATE" => "-", "REDOR" => "|", "REDAND" => "&" }.fetch(type),
              operand: operand
            }
          when *BINARY_OPERATORS.keys
            left = normalize_expression(first_entry(hash, :lhsp), addr_index: addr_index, parent_type: type)
            right = normalize_expression(first_entry(hash, :rhsp), addr_index: addr_index, parent_type: type)
            return nil if left.nil? || right.nil?

            {
              kind: "binary",
              operator: BINARY_OPERATORS.fetch(type),
              left: left,
              right: right
            }
          when "COND"
            condition = normalize_expression(first_entry(hash, :condp), addr_index: addr_index, parent_type: type)
            true_expr = normalize_expression(first_entry(hash, :thenp), addr_index: addr_index, parent_type: type)
            false_expr = normalize_expression(first_entry(hash, :elsep), addr_index: addr_index, parent_type: type)
            return nil if condition.nil? || true_expr.nil? || false_expr.nil?

            {
              kind: "ternary",
              condition: condition,
              true_expr: true_expr,
              false_expr: false_expr
            }
          when "SEL"
            normalize_sel_expression(hash, addr_index: addr_index)
          when "ARRAYSEL"
            base = normalize_expression(first_entry(hash, :fromp), addr_index: addr_index, parent_type: type)
            index = normalize_expression(first_entry(hash, :bitp), addr_index: addr_index, parent_type: type)
            return nil if base.nil? || index.nil?

            {
              kind: "index",
              base: base,
              index: index
            }
          when "CONCAT"
            parts = Array(value_for(hash, :lhsp)) + Array(value_for(hash, :rhsp))
            normalized_parts = parts.filter_map { |part| normalize_expression(part, addr_index: addr_index, parent_type: type) }
            return nil if normalized_parts.empty?

            {
              kind: "concat",
              parts: normalized_parts
            }
          when "REPLICATE"
            count = normalize_expression(first_entry(hash, :countp), addr_index: addr_index, parent_type: type)
            value = normalize_expression(first_entry(hash, :srcp), addr_index: addr_index, parent_type: type)
            return nil if count.nil? || value.nil?

            {
              kind: "replication",
              count: count,
              value: value
            }
          else
            nil
          end
        end

        def normalize_extend_expression(hash, addr_index:, parent_type:)
          source_node = first_entry(hash, :lhsp) || first_entry(hash, :srcp)
          source_expr = normalize_expression(source_node, addr_index: addr_index, parent_type: "EXTEND")
          return nil if source_expr.nil?

          target_width = node_bit_width(hash, addr_index: addr_index)
          source_width = node_bit_width(source_node, addr_index: addr_index)
          return source_expr if target_width.nil? || source_width.nil?

          truncated_source = truncate_expression_to_width(source_expr, width: source_width)
          return truncated_source if target_width <= source_width

          {
            kind: "concat",
            parts: [
              { kind: "number", value: 0, base: 10, width: target_width - source_width, signed: false },
              truncated_source
            ]
          }
        end

        def normalize_sel_expression(hash, addr_index:)
          base = normalize_expression(first_entry(hash, :fromp), addr_index: addr_index)
          lsb = normalize_expression(first_entry(hash, :lsbp), addr_index: addr_index)
          return nil if base.nil? || lsb.nil?

          width = integer_or_default(value_for(hash, :widthConst), 1)
          if width <= 1
            {
              kind: "index",
              base: base,
              index: lsb
            }
          else
            msb =
              if value_for(lsb, :kind).to_s == "number" && value_for(lsb, :value).is_a?(Integer)
                {
                  kind: "number",
                  value: value_for(lsb, :value) + width - 1,
                  base: 10,
                  width: nil,
                  signed: false
                }
              else
                {
                  kind: "binary",
                  operator: "+",
                  left: lsb,
                  right: {
                    kind: "number",
                    value: width - 1,
                    base: 10,
                    width: nil,
                    signed: false
                  }
                }
              end

            {
              kind: "slice",
              base: base,
              msb: msb,
              lsb: lsb
            }
          end
        end

        def parse_const(raw)
          text = raw.to_s.strip
          match = text.match(/\A(?:(\d+))?'([sS])?([bBoOdDhH])([0-9a-fA-F_xXzZ]+)\z/)
          if match
            {
              kind: "number",
              value: match[4],
              base: match[3].downcase,
              width: match[1] ? Integer(match[1]) : nil,
              signed: !match[2].nil?
            }
          elsif text.match?(/\A-?\d+\z/)
            {
              kind: "number",
              value: Integer(text),
              base: 10,
              width: nil,
              signed: text.start_with?("-")
            }
          else
            {
              kind: "number",
              value: text,
              base: nil,
              width: nil,
              signed: false
            }
          end
        rescue ArgumentError
          nil
        end

        def width_from_var(var_node, addr_index:)
          range_text = value_for(var_node, :range)
          if range_text.to_s.strip.empty?
            dtype_node = addr_index[value_for(var_node, :dtypep).to_s]
            range_text = value_for(dtype_node, :range)
          end

          parse_range_expression(range_text)
        end

        def parse_range_expression(range_text)
          text = range_text.to_s.strip
          return nil if text.empty?

          match = text.match(/\A(.+):(.+)\z/)
          return nil unless match

          msb = parse_simple_expression(match[1])
          lsb = parse_simple_expression(match[2])
          return nil if msb.nil? || lsb.nil?

          {
            msb: msb,
            lsb: lsb
          }
        end

        def parse_simple_expression(text)
          token = text.to_s.strip
          return nil if token.empty?

          if token.match?(/\A-?\d+\z/)
            return {
              kind: "number",
              value: Integer(token),
              base: 10,
              width: nil,
              signed: token.start_with?("-")
            }
          end

          if (match = token.match(/\A(.+)\+(.+)\z/))
            left = parse_simple_expression(match[1])
            right = parse_simple_expression(match[2])
            return nil if left.nil? || right.nil?

            return {
              kind: "binary",
              operator: "+",
              left: left,
              right: right
            }
          end

          if (match = token.match(/\A(.+)-(.+)\z/))
            left = parse_simple_expression(match[1])
            right = parse_simple_expression(match[2])
            return nil if left.nil? || right.nil?

            return {
              kind: "binary",
              operator: "-",
              left: left,
              right: right
            }
          end

          {
            kind: "identifier",
            name: token
          }
        end

        def infer_missing_declared_widths(statements:, processes:, instances:)
          max_indices = {}
          inferred_widths = {}

          scan_width_requirements(Array(statements), max_indices, inferred_widths)
          Array(processes).each do |process|
            scan_width_requirements(value_for(process, :statements), max_indices, inferred_widths)
          end
          Array(instances).each do |instance|
            Array(value_for(instance, :connections)).each do |connection|
              scan_width_requirements(value_for(connection, :signal), max_indices, inferred_widths)
            end
          end

          max_indices.each do |name, max_index|
            next unless max_index.is_a?(Integer) && max_index >= 0

            update_inferred_width(inferred_widths, name, max_index + 1)
          end

          inferred_widths
        end

        def add_inferred_declarations(ports:, parameters:, declarations:, statements:, processes:, inferred_widths:)
          known = Set.new
          Array(ports).each { |entry| known.add(value_for(entry, :name).to_s) }
          Array(parameters).each { |entry| known.add(value_for(entry, :name).to_s) }
          Array(declarations).each { |entry| known.add(value_for(entry, :name).to_s) }

          procedural_targets = Set.new
          continuous_targets = Set.new
          collect_statement_targets(
            statements,
            procedural_targets: procedural_targets,
            continuous_targets: continuous_targets
          )
          Array(processes).each do |process|
            collect_statement_targets(
              value_for(process, :statements),
              procedural_targets: procedural_targets,
              continuous_targets: continuous_targets
            )
          end

          inferred_entries = []
          (procedural_targets | continuous_targets).each do |entry|
            name = entry.to_s
            next if name.empty? || known.include?(name)

            inferred_entries << {
              kind: procedural_targets.include?(name) ? "reg" : "wire",
              name: name,
              width: inferred_width_hash(inferred_widths[name])
            }
            known.add(name)
          end

          (Array(declarations) + inferred_entries).sort_by { |entry| value_for(entry, :name).to_s }
        end

        def collect_statement_targets(statements, procedural_targets:, continuous_targets:)
          Array(statements).each do |statement|
            hash = statement.is_a?(Hash) ? statement : {}
            kind = value_for(hash, :kind).to_s

            case kind
            when "continuous_assign"
              name = target_identifier_name(value_for(hash, :target))
              continuous_targets.add(name) unless name.nil?
            when "blocking_assign", "nonblocking_assign"
              name = target_identifier_name(value_for(hash, :target))
              procedural_targets.add(name) unless name.nil?
            when "if"
              collect_statement_targets(
                value_for(hash, :then),
                procedural_targets: procedural_targets,
                continuous_targets: continuous_targets
              )
              collect_statement_targets(
                value_for(hash, :else),
                procedural_targets: procedural_targets,
                continuous_targets: continuous_targets
              )
            when "case"
              Array(value_for(hash, :items)).each do |item|
                collect_statement_targets(
                  value_for(item, :body),
                  procedural_targets: procedural_targets,
                  continuous_targets: continuous_targets
                )
              end
              collect_statement_targets(
                value_for(hash, :default),
                procedural_targets: procedural_targets,
                continuous_targets: continuous_targets
              )
            when "for"
              var_name = value_for(hash, :var).to_s
              procedural_targets.add(var_name) unless var_name.empty?
              collect_statement_targets(
                value_for(hash, :body),
                procedural_targets: procedural_targets,
                continuous_targets: continuous_targets
              )
            end
          end
        end

        def target_identifier_name(target)
          hash = target.is_a?(Hash) ? target : {}
          kind = value_for(hash, :kind).to_s
          case kind
          when "identifier"
            name = value_for(hash, :name).to_s
            name.empty? ? nil : name
          when "index", "slice"
            expression_identifier_name(value_for(hash, :base))
          else
            nil
          end
        end

        def apply_inferred_widths(entries, inferred_widths)
          Array(entries).map do |entry|
            hash = entry.is_a?(Hash) ? entry : {}
            width = value_for(hash, :width)
            name = value_for(hash, :name).to_s
            inferred_width = inferred_widths[name]
            next hash if width || inferred_width.nil?

            hash.merge(width: inferred_width_hash(inferred_width))
          end
        end

        def inferred_width_hash(width)
          upper = width.to_i - 1
          return nil if upper < 1

          {
            msb: number_literal_node(upper),
            lsb: number_literal_node(0)
          }
        end

        def number_literal_node(value)
          {
            kind: "number",
            value: value.to_i,
            base: 10,
            width: nil,
            signed: value.to_i.negative?
          }
        end

        def scan_width_requirements(node, max_indices, inferred_widths)
          case node
          when Array
            node.each { |entry| scan_width_requirements(entry, max_indices, inferred_widths) }
          when Hash
            collect_assignment_width_requirements(node, inferred_widths)

            kind = value_for(node, :kind).to_s
            if kind == "index"
              register_index_width_requirement(
                max_indices,
                base: value_for(node, :base),
                index: value_for(node, :index)
              )
            elsif kind == "slice"
              register_slice_width_requirement(
                max_indices,
                base: value_for(node, :base),
                msb: value_for(node, :msb),
                lsb: value_for(node, :lsb)
              )
            end

            node.each_value { |value| scan_width_requirements(value, max_indices, inferred_widths) }
          end
        end

        def collect_assignment_width_requirements(node, inferred_widths)
          return unless node.is_a?(Hash)

          kind = value_for(node, :kind).to_s
          return unless %w[continuous_assign blocking_assign nonblocking_assign].include?(kind)

          target_name = target_identifier_name(value_for(node, :target))
          return if target_name.nil?

          width = expression_width(value_for(node, :value), inferred_widths)
          update_inferred_width(inferred_widths, target_name, width)
        end

        def update_inferred_width(inferred_widths, name, width)
          return unless width.is_a?(Integer) && width >= 1

          token = name.to_s
          return if token.empty?

          current = inferred_widths[token].to_i
          inferred_widths[token] = [current, width].max
        end

        def expression_width(node, inferred_widths)
          hash = node.is_a?(Hash) ? node : {}
          kind = value_for(hash, :kind).to_s

          case kind
          when "number"
            explicit = integer_or_default(value_for(hash, :width), nil)
            return explicit if explicit.is_a?(Integer) && explicit >= 1

            numeric = parse_number_literal(hash)
            return nil if numeric.nil?
            return 1 if numeric.zero?

            [numeric.bit_length, 1].max
          when "identifier"
            name = value_for(hash, :name).to_s
            return nil if name.empty?

            inferred_widths[name]
          when "index"
            1
          when "slice"
            msb_value = integer_expression_value(value_for(hash, :msb))
            lsb_value = integer_expression_value(value_for(hash, :lsb))
            return nil if msb_value.nil? || lsb_value.nil?

            (msb_value - lsb_value).abs + 1
          when "concat"
            widths = Array(value_for(hash, :parts)).map { |entry| expression_width(entry, inferred_widths) }
            return nil if widths.any?(&:nil?)

            widths.sum
          when "replication"
            count = integer_expression_value(value_for(hash, :count))
            value_width = expression_width(value_for(hash, :value), inferred_widths)
            return nil if count.nil? || value_width.nil?
            return nil unless count.positive?

            count * value_width
          when "ternary"
            true_width = expression_width(value_for(hash, :true_expr), inferred_widths)
            false_width = expression_width(value_for(hash, :false_expr), inferred_widths)
            [true_width, false_width].compact.max
          when "unary"
            expression_width(value_for(hash, :operand), inferred_widths)
          when "binary"
            left_width = expression_width(value_for(hash, :left), inferred_widths)
            right_width = expression_width(value_for(hash, :right), inferred_widths)
            op = value_for(hash, :operator).to_s

            case op
            when "==", "!=", "<", "<=", ">", ">="
              1
            when "+"
              [left_width, right_width].compact.max.to_i + 1
            when "-", "&", "|", "^"
              [left_width, right_width].compact.max
            when "<<", ">>"
              left_width
            else
              [left_width, right_width].compact.max
            end
          else
            nil
          end
        end

        def register_index_width_requirement(max_indices, base:, index:)
          name = expression_identifier_name(base)
          return if name.nil?

          index_value = integer_expression_value(index)
          return if index_value.nil? || index_value.negative?

          current = max_indices[name]
          max_indices[name] = [current.to_i, index_value].max
        end

        def register_slice_width_requirement(max_indices, base:, msb:, lsb:)
          name = expression_identifier_name(base)
          return if name.nil?

          msb_value = integer_expression_value(msb)
          lsb_value = integer_expression_value(lsb)
          return if msb_value.nil? || lsb_value.nil?

          upper = [msb_value, lsb_value].max
          return if upper.negative?

          current = max_indices[name]
          max_indices[name] = [current.to_i, upper].max
        end

        def expression_identifier_name(node)
          hash = node.is_a?(Hash) ? node : {}
          return nil unless value_for(hash, :kind).to_s == "identifier"

          name = value_for(hash, :name).to_s
          name.empty? ? nil : name
        end

        def integer_expression_value(node)
          hash = node.is_a?(Hash) ? node : {}
          kind = value_for(hash, :kind).to_s

          case kind
          when "number"
            parse_number_literal(hash)
          when "unary"
            operator = value_for(hash, :operator).to_s
            operand = integer_expression_value(value_for(hash, :operand))
            return nil if operand.nil?

            operator == "-" ? -operand : nil
          when "binary"
            left = integer_expression_value(value_for(hash, :left))
            right = integer_expression_value(value_for(hash, :right))
            return nil if left.nil? || right.nil?

            case value_for(hash, :operator).to_s
            when "+" then left + right
            when "-" then left - right
            else nil
            end
          else
            nil
          end
        end

        def parse_number_literal(hash)
          value = value_for(hash, :value)
          base = value_for(hash, :base)

          if value.is_a?(Integer)
            return value
          end

          token = value.to_s.strip
          return nil if token.empty?

          radix = case base.to_s.downcase
                  when "b", "2" then 2
                  when "o", "8" then 8
                  when "h", "16" then 16
                  else 10
                  end
          Integer(token, radix)
        rescue ArgumentError
          nil
        end

        def node_bit_width(node, addr_index:)
          hash = normalize_hash(node)
          return nil if hash.empty?

          width_const = integer_or_default(value_for(hash, :widthConst), nil)
          return width_const if width_const.is_a?(Integer) && width_const > 0

          dtype_node = addr_index[value_for(hash, :dtypep).to_s]
          range = parse_range_expression(value_for(dtype_node, :range))
          width = bit_width_from_range(range)
          return width unless width.nil?

          if value_for(hash, :type).to_s == "CONST"
            literal = parse_const(value_for(hash, :name))
            literal_width = value_for(literal, :width)
            return literal_width if literal_width.is_a?(Integer) && literal_width > 0
          end

          nil
        end

        def bit_width_from_range(range_hash)
          hash = normalize_hash(range_hash)
          msb = constant_numeric_expression_value(value_for(hash, :msb))
          lsb = constant_numeric_expression_value(value_for(hash, :lsb))
          return nil if msb.nil? || lsb.nil?

          (msb - lsb).abs + 1
        end

        def constant_numeric_expression_value(node)
          hash = normalize_hash(node)
          return node if node.is_a?(Integer) && hash.empty?
          return nil if hash.empty?

          kind = value_for(hash, :kind).to_s
          case kind
          when "number"
            value = value_for(hash, :value)
            return value if value.is_a?(Integer)

            integer_or_default(value, nil)
          when "binary"
            left = constant_numeric_expression_value(value_for(hash, :left))
            right = constant_numeric_expression_value(value_for(hash, :right))
            return nil if left.nil? || right.nil?

            case value_for(hash, :operator).to_s
            when "+"
              left + right
            when "-"
              left - right
            else
              nil
            end
          else
            nil
          end
        end

        def truncate_expression_to_width(expression, width:)
          return expression unless width.is_a?(Integer) && width > 0
          return expression unless expression.is_a?(Hash)
          return expression unless needs_truncation_wrapper?(expression)

          {
            kind: "slice",
            base: expression,
            msb: { kind: "number", value: width - 1, base: 10, width: nil, signed: false },
            lsb: { kind: "number", value: 0, base: 10, width: nil, signed: false }
          }
        end

        def needs_truncation_wrapper?(expression)
          kind = value_for(expression, :kind).to_s
          %w[binary unary ternary].include?(kind)
        end

        def resolve_module_name(pointer, addr_index:)
          ref = pointer.to_s
          target = addr_index[ref]
          value_for(target, :name).to_s
        end

        def normalize_direction(direction)
          case direction.to_s
          when "INPUT"
            "input"
          when "OUTPUT"
            "output"
          when "INOUT"
            "inout"
          else
            nil
          end
        end

        def normalize_edge(edge_type)
          case edge_type.to_s
          when "POS"
            "posedge"
          when "NEG"
            "negedge"
          else
            "level"
          end
        end

        def first_entry(hash, key)
          Array(value_for(hash, key)).first
        end

        def normalize_hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def truthy?(value)
          value == true || value.to_s.downcase == "true"
        end

        def raw_diagnostics
          diagnostics = value_for(@payload, :diagnostics)
          return diagnostics if diagnostics.is_a?(Array)

          []
        end

        def parse_loc(loc)
          text = loc.to_s.strip
          match = text.match(/\A([^,]+),(\d+):(\d+),(\d+):(\d+)\z/)
          return default_loc unless match

          {
            source_id: match[1],
            line: Integer(match[2]),
            column: Integer(match[3]),
            end_line: Integer(match[4]),
            end_column: Integer(match[5])
          }
        rescue ArgumentError, TypeError
          default_loc
        end

        def default_loc
          {
            source_id: nil,
            line: 1,
            column: 1,
            end_line: 1,
            end_column: 1
          }
        end

        def extract_payload(raw_payload)
          payload = value_for(raw_payload, :payload)
          payload.is_a?(Hash) ? payload : raw_payload
        end

        def extract_frontend_meta(raw_payload)
          metadata = value_for(raw_payload, :metadata)
          frontend_meta = value_for(metadata, :frontend_meta)
          frontend_meta.is_a?(Hash) ? frontend_meta : {}
        end

        def value_for(hash, key)
          return nil unless hash.is_a?(Hash)

          return hash[key] if hash.key?(key)

          string_key = key.to_s
          return hash[string_key] if hash.key?(string_key)

          symbol_key = key.to_sym
          return hash[symbol_key] if hash.key?(symbol_key)

          nil
        end

        def normalize_path(path)
          return nil if path.nil?

          path.to_s.tr("\\", "/").sub(%r{\A\./}, "")
        end

        def integer_or_default(value, default)
          Integer(value)
        rescue ArgumentError, TypeError
          default
        end
      end
    end
  end
end
