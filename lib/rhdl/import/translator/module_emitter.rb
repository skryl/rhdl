# frozen_string_literal: true
require "set"

module RHDL
  module Import
    module Translator
      class ModuleEmitter
        class << self
          def emit(mapped_module)
            new(mapped_module).emit
          end
        end

        def initialize(mapped_module)
          @mapped_module = mapped_module.is_a?(Hash) ? mapped_module : {}
        end

        def emit
          lines = []
          lines << "# frozen_string_literal: true"
          lines << ""
          lines << "class #{class_name} < RHDL::Component"
          lines << "  self._ports = []"
          lines << "  self._signals = []"
          lines << "  self._constants = []"
          lines << "  self._processes = []"
          lines << "  self._assignments = []"
          lines << "  self._instances = []"
          lines << "  self._generics = []"
          lines << ""
          lines << "  # source_module: #{module_name}"
          lines << ""

          emit_import_metadata(lines)
          emit_parameters(lines)
          emit_ports(lines)
          emit_signals(lines)
          emit_body_shape(lines)

          lines << "end"
          lines << ""
          lines.join("\n")
        end

        private

        attr_reader :mapped_module

        ALTDPRAM_INPUT_DEFAULTS = {
          "aclr" => 0,
          "sclr" => 0,
          "inclocken" => 1,
          "outclocken" => 1,
          "rdaddressstall" => 0,
          "wraddressstall" => 0,
          "rden" => 1,
          "byteena" => :ones
        }.freeze

        ALTSYNCRAM_INPUT_DEFAULTS = {
          "aclr0" => 0,
          "aclr1" => 0,
          "addressstall_a" => 0,
          "addressstall_b" => 0,
          "byteena_a" => :ones,
          "byteena_b" => :ones,
          "clock1" => 1,
          "clocken0" => 1,
          "clocken1" => 1,
          "clocken2" => 1,
          "clocken3" => 1,
          "data_b" => 0,
          "rden_a" => 1,
          "rden_b" => 1,
          "wren_b" => 0
        }.freeze

        def module_name
          value_for(mapped_module, :name).to_s
        end

        def class_name
          tokens = module_name.gsub(/[^0-9A-Za-z]+/, "_").split("_").reject(&:empty?)
          candidate = tokens.map { |token| token[0].upcase + token[1..] }.join
          candidate = "ImportedModule" if candidate.empty?
          candidate = "M#{candidate}" if candidate.match?(/\A\d/)
          candidate = "Imported#{candidate}" if reserved_constant_name?(candidate)
          candidate
        end

        def emit_parameters(lines)
          return if parameters.empty?

          lines << "  # Parameters"
          lines << ""
          parameters.each do |parameter|
            name = value_for(parameter, :name).to_s
            default = format_parameter_default(value_for(parameter, :default))
            lines << "  generic :#{name}, default: #{default}"
          end
          lines << ""
        end

        def emit_ports(lines)
          return if ports.empty?

          lines << "  # Ports"
          lines << ""
          ports.each do |port|
            direction = normalize_port_direction(value_for(port, :direction))
            name = value_for(port, :name).to_s
            width_value = value_for(port, :width)
            if width_value.nil?
              inferred = signal_widths[name]
              width_value = inferred unless inferred.nil?
            end
            width = format_width(width_value)
            explicit_default = value_for(port, :default)
            if explicit_default.nil?
              explicit_default = known_module_port_default(
                direction: direction,
                port_name: name,
                width_value: width_value
              )
            end
            default = explicit_default.nil? ? nil : format_signal_default(explicit_default)

            line = +"  #{direction} :#{name}"
            line << ", width: #{width}" unless width.nil?
            line << ", default: #{default}" unless default.nil?
            lines << line
          end
          lines << ""
        end

        def known_module_port_default(direction:, port_name:, width_value:)
          return nil unless direction == "input"

          defaults =
            if module_name.downcase.start_with?("altdpram__")
              ALTDPRAM_INPUT_DEFAULTS
            elsif module_name.downcase.start_with?("altsyncram__")
              ALTSYNCRAM_INPUT_DEFAULTS
            end
          return nil if defaults.nil?

          token = defaults[port_name.to_s]
          return nil if token.nil?

          return token unless token == :ones

          width = infer_port_width_integer(width_value)
          return 1 if width.nil? || width <= 1
          return nil if width > 62

          (1 << width) - 1
        end

        def infer_port_width_integer(width_value)
          return width_value.to_i if width_value.is_a?(Integer)

          width_hash = normalize_hash(width_value)
          unless width_hash.empty?
            msb = numeric_expression_value(value_for(width_hash, :msb))
            lsb = numeric_expression_value(value_for(width_hash, :lsb))
            return (msb - lsb).abs + 1 if msb.is_a?(Integer) && lsb.is_a?(Integer)
          end

          token = width_value.to_s.strip
          return nil if token.empty?
          return Integer(token) if integer_string?(token)

          nil
        rescue ArgumentError, TypeError
          nil
        end

        def emit_signals(lines)
          return if declaration_signals.empty?

          lines << "  # Signals"
          lines << ""
          declaration_signals.each do |signal|
            name = value_for(signal, :name).to_s
            width_value = value_for(signal, :width)
            if width_value.nil?
              inferred = signal_widths[name]
              width_value = inferred unless inferred.nil?
            end
            width = format_width(width_value)
            explicit_default = value_for(signal, :default)
            default = explicit_default.nil? ? nil : format_signal_default(explicit_default)

            line = +"  signal :#{name}"
            line << ", width: #{width}" unless width.nil?
            line << ", default: #{default}" unless default.nil?
            lines << line
          end
          lines << ""
        end

        def emit_body_shape(lines)
          emit_assignments(lines)
          emit_processes(lines)
          emit_instances(lines)
        end

        def emit_assignments(lines)
          emitted_targets = Set.new
          assignment_lines = []

          assign_entries.each do |assign|
            target_node = value_for(assign, :target)
            value_node = value_for(assign, :value)
            value_node = value_for(assign, :expr) if value_node.nil?

            target_name = extract_identifier_name(target_node)
            value_code = expression_to_ruby(value_node)
            if !target_name.nil? && !value_code.nil?
              assignment_lines << "  assign :#{target_name}, #{value_code}"
              emitted_targets.add(target_name)
            end
          end

          return if assignment_lines.empty?

          lines << "  # Assignments"
          lines << ""
          lines.concat(assignment_lines)
          lines << ""
        end

        def emit_processes(lines)
          process_blocks = []
          used_process_names = Set.new

          processes.each_with_index do |process, index|
            sensitivity_values = Array(value_for(process, :sensitivity))
            process_name = process_symbol(
              value_for(process, :name),
              index: index,
              process: process,
              sensitivity_values: sensitivity_values,
              used_names: used_process_names
            )
            sensitivity_code = sensitivity_values.map { |entry| sensitivity_to_ruby(entry) }.compact
            initial = process_initial?(process)
            clocked = process_clocked?(process, sensitivity_values: sensitivity_values)
            block = []
            block.concat(
              process_signature_lines(
                process_name: process_name,
                sensitivity_code: sensitivity_code,
                clocked: clocked,
                initial: initial
              )
            )
            emit_process_statements(
              block,
              statements: Array(value_for(process, :statements)),
              indent: 2,
              default_kind: clocked ? :nonblocking : :blocking
            )
            block << "  end"
            process_blocks << block
          end

          return if process_blocks.empty?

          lines << "  # Processes"
          lines << ""
          process_blocks.each_with_index do |block, index|
            lines.concat(block)
            lines << "" unless index == process_blocks.length - 1
          end
          lines << ""
        end

        def emit_process_statements(lines, statements:, indent:, default_kind:)
          pad = "  " * indent
          Array(statements).each do |statement|
            hash = normalize_hash(statement)
            kind = value_for(hash, :kind).to_s

            case kind
            when "blocking_assign", "nonblocking_assign"
              target = target_expression_to_ruby(value_for(hash, :target))
              value = expression_to_ruby(value_for(hash, :value))
              next if target.nil? || value.nil?

              assignment_kind =
                case kind
                when "blocking_assign" then ":blocking"
                when "nonblocking_assign" then ":nonblocking"
                else ":#{default_kind}"
                end
              lines << "#{pad}assign(#{target}, #{value}, kind: #{assignment_kind})"
            when "if"
              emit_if_statement(
                lines,
                statement: hash,
                indent: indent,
                default_kind: default_kind
              )
            when "case"
              emit_case_statement(
                lines,
                statement: hash,
                indent: indent,
                default_kind: default_kind
              )
            when "for"
              emit_for_loop_statement(
                lines,
                statement: hash,
                indent: indent,
                default_kind: default_kind
              )
            end
          end
        end

        def emit_if_statement(lines, statement:, indent:, default_kind:)
          pad = "  " * indent
          condition = expression_to_ruby(value_for(statement, :condition))
          return if condition.nil?

          lines << "#{pad}if_stmt(#{condition}) do"
          then_body = value_for(statement, :then) || value_for(statement, :then_body)
          emit_process_statements(
            lines,
            statements: Array(then_body),
            indent: indent + 1,
            default_kind: default_kind
          )

          current_else_body = Array(value_for(statement, :else) || value_for(statement, :else_body))
          while current_else_body.length == 1
            nested_if = normalize_hash(current_else_body.first)
            break unless value_for(nested_if, :kind).to_s == "if"

            elsif_condition = expression_to_ruby(value_for(nested_if, :condition))
            break if elsif_condition.nil?

            lines << "#{pad}  elsif_block(#{elsif_condition}) do"
            nested_then_body = value_for(nested_if, :then) || value_for(nested_if, :then_body)
            emit_process_statements(
              lines,
              statements: Array(nested_then_body),
              indent: indent + 2,
              default_kind: default_kind
            )
            lines << "#{pad}  end"
            current_else_body = Array(value_for(nested_if, :else) || value_for(nested_if, :else_body))
          end

          unless current_else_body.empty?
            lines << "#{pad}  else_block do"
            emit_process_statements(
              lines,
              statements: current_else_body,
              indent: indent + 2,
              default_kind: default_kind
            )
            lines << "#{pad}  end"
          end

          lines << "#{pad}end"
        end

        def emit_import_metadata(lines)
          kind_map = import_declaration_kinds
          lines << "  def self._import_decl_kinds"
          entries = kind_map.keys.sort.map { |name| [name, kind_map.fetch(name)] }
          if entries.empty?
            lines << "    {}"
          else
            lines << "    {"
            entries.each_with_index do |(name, kind), index|
              suffix = index == entries.length - 1 ? "" : ","
              lines << "      #{name}: :#{kind}#{suffix}"
            end
            lines << "    }"
          end
          lines << "  end"
          lines << ""
        end

        def emit_case_statement(lines, statement:, indent:, default_kind:)
          pad = "  " * indent
          selector = expression_to_ruby(value_for(statement, :selector))
          return if selector.nil?

          qualifier = normalize_case_qualifier(value_for(statement, :qualifier))
          qualifier_arg = qualifier.nil? ? "" : ", qualifier: :#{qualifier}"
          lines << "#{pad}case_stmt(#{selector}#{qualifier_arg}) do"
          Array(value_for(statement, :items)).each do |item|
            item_hash = normalize_hash(item)
            values = Array(value_for(item_hash, :values))
            body = Array(value_for(item_hash, :body))
            next if values.empty?

            rendered_values = values.filter_map { |entry| expression_to_ruby(entry) }
            next if rendered_values.empty?

            rendered_values.each do |rendered_value|
              lines << "#{pad}  when_value(#{rendered_value}) do"
              emit_process_statements(
                lines,
                statements: body,
                indent: indent + 2,
                default_kind: default_kind
              )
              lines << "#{pad}  end"
            end
          end

          default_body = value_for(statement, :default) || value_for(statement, :default_body)
          unless Array(default_body).empty?
            lines << "#{pad}  default do"
            emit_process_statements(
              lines,
              statements: Array(default_body),
              indent: indent + 2,
              default_kind: default_kind
            )
            lines << "#{pad}  end"
          end
          lines << "#{pad}end"
        end

        def emit_for_loop_statement(lines, statement:, indent:, default_kind:)
          pad = "  " * indent
          variable = value_for(statement, :var) || value_for(statement, :variable)
          variable_name = variable.to_s.strip
          return if variable_name.empty?

          range = normalize_hash(value_for(statement, :range))
          range_start = loop_range_endpoint_to_ruby(value_for(range, :from))
          range_end = loop_range_endpoint_to_ruby(value_for(range, :to))
          return if range_start.nil? || range_end.nil?

          lines << "#{pad}for_loop(:#{variable_name}, #{range_start}..#{range_end}) do"
          emit_process_statements(
            lines,
            statements: Array(value_for(statement, :body)),
            indent: indent + 1,
            default_kind: default_kind
          )
          lines << "#{pad}end"
        end

        def loop_range_endpoint_to_ruby(value)
          return value.to_i.to_s if value.is_a?(Numeric)

          rendered = expression_to_ruby(value)
          return nil if rendered.nil? || rendered.empty?

          rendered
        end

        def normalize_case_qualifier(value)
          token = value.to_s.strip.downcase
          return nil if token.empty?

          return "unique" if token == "unique"
          return "priority" if token == "priority"

          nil
        end

        def emit_instances(lines)
          instance_lines = []

          instances.each do |instance|
            instance_name = value_for(instance, :name).to_s
            module_ref = value_for(instance, :module_name) || value_for(instance, :module)
            module_ref_name = module_ref.to_s
            next if instance_name.empty?

            parameter_map = normalize_hash(value_for(instance, :parameters))
            if parameter_map.empty?
              parameter_map = normalize_parameter_overrides(value_for(instance, :parameter_overrides))
            end

            connection_map = normalize_connections(value_for(instance, :connections))
            connection_map = prune_identity_instance_connections(connection_map)
            instance_lines.concat(
              instance_signature_lines(
                instance_name: instance_name,
                module_ref_name: module_ref_name,
                parameter_map: parameter_map,
                connection_map: connection_map
              )
            )
          end

          return if instance_lines.empty?

          lines << "  # Instances"
          lines << ""
          lines.concat(instance_lines)
          lines << ""
        end

        def process_signature_lines(process_name:, sensitivity_code:, clocked:, initial:)
          lines = []
          lines << "  process :#{process_name},"
          lines << "    sensitivity: ["
          sensitivity_code.each_with_index do |entry, index|
            suffix = index == sensitivity_code.length - 1 ? "" : ","
            lines << "      #{entry}#{suffix}"
          end
          lines << "    ],"
          lines << "    clocked: #{clocked},"
          lines << "    initial: #{initial} do"
          lines
        end

        def instance_signature_lines(instance_name:, module_ref_name:, parameter_map:, connection_map:)
          has_generics = !parameter_map.empty?
          has_ports = !connection_map.empty?
          return ["  instance :#{instance_name}, #{module_ref_name.inspect}"] unless has_generics || has_ports

          lines = []
          lines << "  instance :#{instance_name}, #{module_ref_name.inspect},"
          sections = []
          sections << format_instance_hash_section(name: "generics", values: parameter_map, formatter: :format_instance_generic_value) if has_generics
          sections << format_instance_hash_section(name: "ports", values: connection_map, formatter: :format_instance_port_value) if has_ports
          sections.each_with_index do |section_lines, index|
            suffix = index == sections.length - 1 ? "" : ","
            block = section_lines.dup
            block[-1] = "#{block[-1]}#{suffix}"
            lines.concat(block)
          end
          lines
        end

        def format_instance_hash_section(name:, values:, formatter:)
          lines = []
          entries = values.map do |entry_name, entry_value|
            [entry_name.to_s, send(formatter, entry_value)]
          end
          lines << "    #{name}: {"
          entries.each_with_index do |(entry_name, formatted_value), index|
            suffix = index == entries.length - 1 ? "" : ","
            lines << "      #{entry_name}: #{formatted_value}#{suffix}"
          end
          lines << "    }"
          lines
        end

        def emit_generated_verilog_method(lines)
          verilog = generated_verilog_text
          lines << "  def self.to_verilog_generated(top_name: nil)"
          lines << "    text = <<~'VERILOG'"
          verilog.each_line do |line|
            lines << "      #{line.chomp}"
          end
          lines << "    VERILOG"
          lines << "    return text if top_name.nil? || top_name.to_s.strip.empty?"
          lines << '    text.sub(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)/, "module #{top_name}")'
          lines << "  end"
          lines << ""
        end

        def generated_verilog_text
          lines = []
          lines << "`timescale 1ns/1ps"
          lines << ""

          port_names = generated_port_names
          if port_names.empty?
            lines << "module #{module_name};"
          else
            lines << "module #{module_name}("
            port_names.each_with_index do |name, index|
              suffix = index == port_names.length - 1 ? "" : ","
              lines << "  #{name}#{suffix}"
            end
            lines << ");"
          end
          lines << ""

          parameter_lines = generated_parameter_lines
          lines.concat(parameter_lines)
          lines << "" unless parameter_lines.empty?

          port_lines = generated_port_declaration_lines
          lines.concat(port_lines)
          lines << "" unless port_lines.empty?

          signal_lines = generated_signal_declaration_lines
          lines.concat(signal_lines)
          lines << "" unless signal_lines.empty?

          assign_lines = generated_continuous_assign_lines
          lines.concat(assign_lines)
          lines << "" unless assign_lines.empty?

          process_lines = generated_process_lines
          lines.concat(process_lines)
          lines << "" unless process_lines.empty?

          instance_lines = generated_instance_lines
          lines.concat(instance_lines)
          lines << "" unless instance_lines.empty?

          lines << "endmodule"
          lines << ""
          lines.join("\n")
        end

        def generated_port_names
          ports.map { |entry| value_for(entry, :name).to_s }.reject(&:empty?)
        end

        def generated_parameter_lines
          parameters.filter_map do |parameter|
            name = value_for(parameter, :name).to_s
            next if name.empty?

            "parameter #{name} = #{render_parameter_default_verilog(value_for(parameter, :default))};"
          end
        end

        def render_parameter_default_verilog(value)
          rendered = expression_to_verilog(value)
          return rendered unless rendered.nil? || rendered.empty?

          text = value.to_s.strip
          return "0" if text.empty?

          text
        end

        def generated_port_declaration_lines
          ports.filter_map do |port|
            name = value_for(port, :name).to_s
            next if name.empty?

            direction = normalize_port_direction(value_for(port, :direction))
            width = value_for(port, :width)
            inferred = inferred_signal_widths[name]
            width = inferred if width.nil? && !inferred.nil?
            "#{direction} logic #{verilog_width_decl(width)}#{name};"
          end
        end

        def generated_signal_declaration_lines
          port_name_set = generated_port_names.to_set
          entries = []

          declarations.each do |entry|
            hash = normalize_hash(entry)
            kind = value_for(hash, :kind).to_s.downcase
            next unless %w[wire reg logic integer int].include?(kind)

            name = value_for(hash, :name).to_s
            next if name.empty? || port_name_set.include?(name)

            kind = "integer" if kind == "int"
            entries << {
              kind: kind,
              name: name,
              width: value_for(hash, :width)
            }
          end

          signals.each do |entry|
            hash = normalize_hash(entry)
            name = value_for(hash, :name).to_s
            next if name.empty? || port_name_set.include?(name)
            next if entries.any? { |signal| signal[:name] == name }

            kind = value_for(hash, :kind).to_s.downcase
            kind = "logic" unless %w[wire reg logic].include?(kind)
            entries << {
              kind: kind,
              name: name,
              width: value_for(hash, :width)
            }
          end

          entries.map do |entry|
            if entry[:kind] == "integer"
              "integer #{entry[:name]};"
            else
              width = entry[:width]
              inferred = inferred_signal_widths[entry[:name]]
              width = inferred if width.nil? && !inferred.nil?
              "#{entry[:kind]} #{verilog_width_decl(width)}#{entry[:name]};"
            end
          end
        end

        def generated_continuous_assign_lines
          assign_entries.filter_map do |assign|
            target = render_verilog_lhs_expression(value_for(assign, :target))
            value = expression_to_verilog(value_for(assign, :value))
            next if target.nil? || value.nil?

            "assign #{target} = #{value};"
          end
        end

        def generated_process_lines
          lines = []

          processes.each do |process|
            domain = value_for(process, :domain).to_s
            kind = value_for(process, :kind).to_s
            if domain == "initial" || kind == "initial"
              lines << "initial begin"
            else
              sensitivity = process_sensitivity_text(process)
              lines << "always @(#{sensitivity}) begin"
            end

            statement_lines = generated_statement_lines(
              Array(value_for(process, :statements)),
              indent: 1
            )
            lines.concat(statement_lines)
            lines << "end"
          end

          lines
        end

        def process_sensitivity_text(process)
          raw = Array(value_for(process, :sensitivity))
          entries = raw.filter_map do |entry|
            case entry
            when Hash
              render_sensitivity_entry(entry)
            else
              text = entry.to_s.strip
              text.empty? ? nil : text
            end
          end

          return "*" if entries.empty?
          return "*" if entries.any? { |entry| entry == "*" }

          entries.join(" or ")
        end

        def render_sensitivity_entry(entry)
          hash = normalize_hash(entry)
          signal = expression_to_verilog(value_for(hash, :signal))
          return nil if signal.nil? || signal.empty?

          edge = value_for(hash, :edge).to_s.strip
          return signal if edge.empty? || edge == "any"

          "#{edge} #{signal}"
        end

        def generated_statement_lines(statements, indent:)
          Array(statements).flat_map do |statement|
            hash = normalize_hash(statement)
            kind = value_for(hash, :kind).to_s
            pad = "  " * indent

            case kind
            when "blocking_assign", "nonblocking_assign"
              target = render_verilog_lhs_expression(value_for(hash, :target))
              value = expression_to_verilog(value_for(hash, :value))
              next [] if target.nil? || value.nil?

              op = kind == "nonblocking_assign" ? "<=" : "="
              ["#{pad}#{target} #{op} #{value};"]
            when "if"
              generated_if_statement_lines(hash, indent: indent)
            else
              ["#{pad}// unsupported statement: #{kind}"]
            end
          end
        end

        def generated_if_statement_lines(hash, indent:)
          pad = "  " * indent
          condition = expression_to_verilog(value_for(hash, :condition))
          return ["#{pad}// unsupported if condition"] if condition.nil?

          then_body = value_for(hash, :then) || value_for(hash, :then_body)
          else_body = value_for(hash, :else) || value_for(hash, :else_body)
          then_lines = generated_statement_lines(Array(then_body), indent: indent + 1)
          else_lines = generated_statement_lines(Array(else_body), indent: indent + 1)

          lines = []
          lines << "#{pad}if (#{condition}) begin"
          lines.concat(then_lines)
          if else_lines.empty?
            lines << "#{pad}end"
          else
            lines << "#{pad}end else begin"
            lines.concat(else_lines)
            lines << "#{pad}end"
          end
          lines
        end

        def generated_instance_lines
          lines = []

          instances.each do |instance|
            instance_name = value_for(instance, :name).to_s
            module_ref = value_for(instance, :module_name) || value_for(instance, :module)
            module_ref_name = module_ref.to_s
            next if instance_name.empty? || module_ref_name.empty?

            parameter_map = normalize_hash(value_for(instance, :parameters))
            if parameter_map.empty?
              parameter_map = normalize_parameter_overrides(value_for(instance, :parameter_overrides))
            end
            connection_map = normalize_connections(value_for(instance, :connections))

            if parameter_map.empty?
              lines << "#{module_ref_name} #{instance_name} ("
            else
              parameter_entries = parameter_map
                .map do |name, value|
                  rendered = render_instance_value_verilog(value)
                  ".#{name}(#{rendered})"
                end
              lines << "#{module_ref_name} #(#{parameter_entries.join(', ')}) #{instance_name} ("
            end

            connection_entries = connection_map.map do |port_name, signal_expr|
              rendered = render_instance_value_verilog(signal_expr)
              ".#{port_name}(#{rendered})"
            end
            lines << "  #{connection_entries.join(', ')}"
            lines << ");"
          end

          lines
        end

        def render_instance_value_verilog(value)
          return "" if open_connection_signal?(value)

          text = expression_to_verilog(value)
          return text unless text.nil?

          value.to_s
        end

        def render_verilog_lhs_expression(node)
          case node
          when Symbol
            node.to_s
          when String
            text = node.strip
            return nil if text.empty?

            text
          when Hash
            hash = normalize_hash(node)
            kind = value_for(hash, :kind).to_s
            case kind
            when "identifier"
              value_for(hash, :name).to_s
            when "index"
              base = render_verilog_lhs_expression(value_for(hash, :base))
              index = expression_to_verilog(value_for(hash, :index))
              return nil if base.nil? || index.nil?

              "#{base}[#{index}]"
            when "slice"
              base = render_verilog_lhs_expression(value_for(hash, :base))
              msb = expression_to_verilog(value_for(hash, :msb))
              lsb = expression_to_verilog(value_for(hash, :lsb))
              return nil if base.nil? || msb.nil? || lsb.nil?

              "#{base}[#{msb}:#{lsb}]"
            else
              expression_to_verilog(node)
            end
          else
            expression_to_verilog(node)
          end
        end

        def verilog_width_decl(value)
          return "" if value.nil?
          return "" if value == 1 || value == "1"

          if value.is_a?(Integer)
            return "" if value <= 1

            return "[#{value - 1}:0] "
          end

          hash = normalize_hash(value)
          if !hash.empty? && (hash.key?(:msb) || hash.key?("msb"))
            msb = expression_to_verilog(value_for(hash, :msb))
            lsb = expression_to_verilog(value_for(hash, :lsb))
            return "" if msb.nil? || lsb.nil?

            return "[#{msb}:#{lsb}] "
          end

          text = value.to_s.strip
          return "" if text.empty?
          if integer_string?(text)
            width = Integer(text)
            return "" if width <= 1

            return "[#{width - 1}:0] "
          end
          return "[#{text}-1:0] " if identifier?(text)

          ""
        end

        def inferred_signal_widths
          @inferred_signal_widths ||= begin
            widths = {}

            assign_entries.each do |assign|
              infer_expression_widths(value_for(assign, :target), widths)
              infer_expression_widths(value_for(assign, :value), widths)
            end

            processes.each do |process|
              infer_statement_widths(Array(value_for(process, :statements)), widths)
            end

            instances.each do |instance|
              connection_map = normalize_connections(value_for(instance, :connections))
              connection_map.each_value do |signal_expr|
                infer_expression_widths(signal_expr, widths)
              end
            end

            widths
          end
        end

        def infer_statement_widths(statements, widths)
          Array(statements).each do |statement|
            hash = normalize_hash(statement)
            kind = value_for(hash, :kind).to_s
            case kind
            when "blocking_assign", "nonblocking_assign", "continuous_assign"
              target = value_for(hash, :target)
              value = value_for(hash, :value)
              infer_expression_widths(target, widths)
              infer_expression_widths(value, widths)
              infer_assignment_target_width(target: target, value: value, widths: widths)
            when "if"
              infer_expression_widths(value_for(hash, :condition), widths)
              then_body = value_for(hash, :then) || value_for(hash, :then_body)
              else_body = value_for(hash, :else) || value_for(hash, :else_body)
              infer_statement_widths(Array(then_body), widths)
              infer_statement_widths(Array(else_body), widths)
            when "case", "case_stmt"
              infer_expression_widths(value_for(hash, :selector), widths)
              case_items(hash).each do |item|
                item_hash = normalize_hash(item)
                Array(value_for(item_hash, :values)).each do |value|
                  infer_expression_widths(value, widths)
                end
                body = value_for(item_hash, :body) || value_for(item_hash, :statements)
                infer_statement_widths(Array(body), widths)
              end
              default_body = value_for(hash, :default_body) || value_for(hash, :default)
              infer_statement_widths(Array(default_body), widths)
            when "for", "for_loop"
              range = normalize_hash(value_for(hash, :range))
              infer_expression_widths(value_for(range, :from), widths)
              infer_expression_widths(value_for(range, :to), widths)
              body = value_for(hash, :body) || value_for(hash, :statements)
              infer_statement_widths(Array(body), widths)
            end
          end
        end

        def infer_assignment_target_width(target:, value:, widths:)
          target_name = extract_identifier_name(target)
          return if target_name.nil? || target_name.empty?
          return if declared_signal_names.include?(target_name)

          inferred_width = expression_width(value, widths)
          return if inferred_width.nil? || inferred_width <= 0
          if inferred_width == 1
            current = widths[target_name]
            return if current.nil? || current <= 1
          end

          current = widths[target_name] || 0
          widths[target_name] = [current, inferred_width].max
        end

        def declared_signal_names
          @declared_signal_names ||= begin
            names = Set.new
            ports.each do |entry|
              hash = normalize_hash(entry)
              name = value_for(hash, :name).to_s
              names.add(name) unless name.empty?
            end
            signals.each do |entry|
              hash = normalize_hash(entry)
              name = value_for(hash, :name).to_s
              names.add(name) unless name.empty?
            end
            declarations.each do |entry|
              hash = normalize_hash(entry)
              name = value_for(hash, :name).to_s
              names.add(name) unless name.empty?
            end
            names
          end
        end

        def expression_width(node, widths)
          case node
          when Integer
            return minimum_integer_width(node)
          when Symbol
            return width_for_identifier(node.to_s, widths)
          when String
            text = node.strip
            return nil if text.empty?
            return width_for_identifier(text, widths) if identifier?(text)
            return minimum_integer_width(Integer(text)) if integer_string?(text)

            return nil
          end

          hash = normalize_hash(node)
          return nil if hash.empty?

          kind = value_for(hash, :kind).to_s
          case kind
          when "number"
            explicit = value_for(hash, :width)
            if explicit.is_a?(Integer) && explicit.positive?
              explicit
            else
              minimum_integer_width(literal_integer_value(hash))
            end
          when "identifier"
            width_for_identifier(value_for(hash, :name).to_s, widths)
          when "index"
            1
          when "slice"
            msb = numeric_expression_value(value_for(hash, :msb))
            lsb = numeric_expression_value(value_for(hash, :lsb))
            return (msb - lsb).abs + 1 if msb.is_a?(Integer) && lsb.is_a?(Integer)

            nil
          when "concat"
            parts = Array(value_for(hash, :parts))
            part_widths = parts.map { |part| expression_width(part, widths) }
            return nil if part_widths.any?(&:nil?)

            part_widths.sum
          when "replicate", "replication"
            count = numeric_expression_value(value_for(hash, :count))
            value_width = expression_width(value_for(hash, :value), widths)
            return nil unless count.is_a?(Integer) && count.positive? && value_width.is_a?(Integer)

            count * value_width
          when "ternary"
            true_width = expression_width(value_for(hash, :true_expr), widths)
            false_width = expression_width(value_for(hash, :false_expr), widths)
            [true_width, false_width].compact.max
          when "unary"
            operator = value_for(hash, :operator).to_s
            return 1 if operator == "!"

            expression_width(value_for(hash, :operand), widths)
          when "binary"
            operator = value_for(hash, :operator).to_s
            return 1 if %w[== != < <= > >= && ||].include?(operator)

            left_width = expression_width(value_for(hash, :left), widths)
            right_width = expression_width(value_for(hash, :right), widths)
            if %w[<< >> <<< >>>].include?(operator)
              left_width
            else
              [left_width, right_width].compact.max
            end
          else
            nil
          end
        end

        def width_for_identifier(name, widths)
          token = name.to_s
          return nil if token.empty?

          explicit_signal_widths[token] || widths[token]
        end

        def minimum_integer_width(value)
          integer = value.to_i
          return 1 if integer.zero?

          magnitude = integer.negative? ? -integer : integer
          [magnitude.bit_length, 1].max
        end

        def case_items(hash)
          Array(value_for(hash, :items) || value_for(hash, :cases))
        end

        def infer_expression_widths(node, widths)
          hash = normalize_hash(node)
          return if hash.empty?

          kind = value_for(hash, :kind).to_s
          case kind
          when "index"
            base = value_for(hash, :base)
            index = value_for(hash, :index)
            base_name = extract_identifier_name(base)
            upper_bound = inferred_index_upper_bound(index, widths)
            if !base_name.nil? && !upper_bound.nil? && upper_bound > 1
              current = widths[base_name] || 0
              widths[base_name] = [current, upper_bound].max
            end
            infer_expression_widths(base, widths)
            infer_expression_widths(index, widths)
          when "slice"
            base = value_for(hash, :base)
            msb = value_for(hash, :msb)
            lsb = value_for(hash, :lsb)
            base_name = extract_identifier_name(base)
            msb_value = numeric_expression_value(msb)
            if !base_name.nil? && msb_value.is_a?(Integer) && msb_value >= 0
              current = widths[base_name] || 0
              widths[base_name] = [current, msb_value + 1].max
            end
            infer_expression_widths(base, widths)
            infer_expression_widths(msb, widths)
            infer_expression_widths(lsb, widths)
          when "binary"
            infer_expression_widths(value_for(hash, :left), widths)
            infer_expression_widths(value_for(hash, :right), widths)
          when "unary"
            infer_expression_widths(value_for(hash, :operand), widths)
          when "ternary"
            infer_expression_widths(value_for(hash, :condition), widths)
            infer_expression_widths(value_for(hash, :true_expr), widths)
            infer_expression_widths(value_for(hash, :false_expr), widths)
          when "concat"
            Array(value_for(hash, :parts)).each { |part| infer_expression_widths(part, widths) }
          when "replicate", "replication"
            infer_expression_widths(value_for(hash, :count), widths)
            infer_expression_widths(value_for(hash, :value), widths)
          end
        end

        def inferred_index_upper_bound(node, widths)
          numeric = numeric_expression_value(node)
          return numeric + 1 if numeric.is_a?(Integer) && numeric >= 0

          hash = normalize_hash(node)
          return nil if hash.empty?
          return nil unless value_for(hash, :kind).to_s == "identifier"

          index_name = value_for(hash, :name).to_s
          width = explicit_signal_widths[index_name]
          width = widths[index_name] if width.nil?
          return nil if width.nil? || width <= 0 || width > 16

          2**width
        end

        def emit_vendor_source_passthrough(lines)
          filename = vendor_source_filename
          return if filename.nil?

          relative_vendor_path = File.join("..", "..", "..", "vendor", "source_hdl", filename)
          lines << "  def self.to_verilog(top_name: nil)"
          lines << "    source_path = File.expand_path(#{relative_vendor_path.inspect}, __dir__)"
          lines << "    return File.read(source_path) if File.file?(source_path)"
          lines << ""
          lines << "    rendered = begin"
          lines << "      super(top_name: top_name)"
          lines << "    rescue ArgumentError"
          lines << "      super()"
          lines << "    end"
          lines << ""
          lines << "    return rendered if top_name.nil? || top_name.to_s.strip.empty?"
          lines << '    rendered.sub(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)/, "module #{top_name}")'
          lines << "  end"
          lines << ""
        end

        def normalize_port_direction(direction)
          case direction.to_s
          when "input", "in"
            "input"
          when "output", "out"
            "output"
          else
            "input"
          end
        end

        def import_declaration_kinds
          @import_declaration_kinds ||= begin
            kinds = {}
            declarations.each do |entry|
              hash = normalize_hash(entry)
              name = value_for(hash, :name).to_s
              kind = value_for(hash, :kind).to_s.downcase
              next if name.empty? || kind.empty?

              kinds[name.to_sym] = kind.to_sym
            end
            kinds
          end
        end

        def format_parameter_default(value)
          return value if value.is_a?(Integer)

          if value.is_a?(Hash)
            rendered = expression_to_verilog(value)
            return rendered.inspect unless rendered.nil?
          end

          text = value.to_s
          return Integer(text) if integer_string?(text)
          return ":#{text}" if identifier?(text)

          text.inspect
        end

        def format_signal_default(value)
          format_parameter_default(value)
        end

        def format_width(value)
          return nil if value.nil?
          return nil if value == 1 || value == "1"
          return value if value.is_a?(Integer)

          if value.is_a?(Hash)
            range_literal = range_width_literal(value)
            return range_literal unless range_literal.nil?

            width = width_from_range_hash(value)
            return width unless width.nil?
          end

          text = value.to_s
          return Integer(text) if integer_string?(text)
          return ":#{text}" if identifier?(text)

          text.inspect
        end

        def range_width_literal(value)
          msb = numeric_expression_value(value_for(value, :msb))
          lsb = numeric_expression_value(value_for(value, :lsb))
          return nil unless msb.is_a?(Integer) && lsb.is_a?(Integer)
          return "(#{msb}..#{lsb})" if msb == lsb
          return nil if lsb == 0

          "(#{msb}..#{lsb})"
        end

        def emit_output_default_assignments(emitted_targets:)
          lines = []

          ports.each do |port|
            direction = normalize_port_direction(value_for(port, :direction))
            next unless direction == "output"

            name = value_for(port, :name).to_s
            next if name.empty?
            next if emitted_targets.include?(name)
            next if continuous_assignment_targets.include?(name)
            next if non_initial_procedural_assignment_targets.include?(name)

            default_value = port_default_for(port, name: name, direction: direction)
            next if default_value.nil?

            width_tokens = default_assignment_width_tokens(value_for(port, :width))
            next if width_tokens.nil?

            value_code = default_assignment_value_to_ruby(
              default: default_value,
              width_ruby: width_tokens.fetch(:ruby),
              width_integer: width_tokens.fetch(:integer)
            )
            next if value_code.nil?

            lines << "  assign :#{name}, #{value_code}"
          end

          lines
        end

        def default_assignment_width_tokens(width)
          case width
          when NilClass
            { integer: 1, ruby: "1" }
          when Integer
            normalized = width <= 0 ? 1 : width
            { integer: normalized, ruby: normalized.to_s }
          when Symbol
            token = width.to_s
            return nil unless identifier?(token)

            { integer: nil, ruby: ":#{token}" }
          when String
            token = width.strip
            return { integer: 1, ruby: "1" } if token.empty?

            if integer_string?(token)
              normalized = Integer(token)
              normalized = 1 if normalized <= 0
              return { integer: normalized, ruby: normalized.to_s }
            end

            return nil unless identifier?(token)

            { integer: nil, ruby: ":#{token}" }
          else
            nil
          end
        end

        def default_assignment_value_to_ruby(default:, width_ruby:, width_integer:)
          if default.is_a?(Integer)
            return "lit(#{default}, width: #{width_ruby}, base: \"d\", signed: false)"
          end

          if default.is_a?(Hash)
            rendered = expression_to_ruby(default)
            return rendered unless rendered.nil?
          end

          token = default.to_s.strip
          return nil if token.empty?
          return "lit(#{token}, width: #{width_ruby}, base: \"d\", signed: false)" if integer_string?(token)
          return "sig(:#{token}, width: #{identifier_width(token) || 1})" if identifier?(token)

          nil
        end

        def parameters
          Array(value_for(mapped_module, :parameters))
        end

        def ports
          Array(value_for(mapped_module, :ports))
        end

        def signals
          Array(value_for(mapped_module, :signals))
        end

        def declarations
          Array(value_for(mapped_module, :declarations))
        end

        def declaration_signals
          combined = []
          port_name_set = generated_port_names.to_set

          signals.each do |entry|
            hash = normalize_hash(entry)
            name = value_for(hash, :name).to_s
            next if name.empty? || port_name_set.include?(name)

            combined << {
              name: name,
              width: value_for(hash, :width),
              allow_inferred_width: false
            }
          end

          declarations.each do |entry|
            hash = normalize_hash(entry)
            kind = value_for(hash, :kind).to_s.downcase
            next unless %w[wire reg logic integer int].include?(kind)

            name = value_for(hash, :name).to_s
            next if name.empty? || port_name_set.include?(name)

            combined << {
              name: name,
              width: value_for(hash, :width),
              allow_inferred_width: false
            }
          end

          existing = combined.map { |entry| value_for(entry, :name).to_s }.to_set
          procedural_assignment_targets.each do |target_name|
            token = target_name.to_s
            next if token.empty? || port_name_set.include?(token) || existing.include?(token)

            combined << {
              name: token,
              width: nil,
              allow_inferred_width: true
            }
            existing << token
          end

          dedupe_signals(combined)
        end

        def dedupe_signals(entries)
          seen = {}
          entries.each do |entry|
            name = value_for(entry, :name).to_s
            next if name.empty?
            if seen.key?(name)
              existing = seen[name]
              existing_width = value_for(existing, :width)
              new_width = value_for(entry, :width)
              seen[name] = entry if existing_width.nil? && !new_width.nil?
              next
            end

            seen[name] = entry
          end
          seen.values
        end

        def signal_default_for_declaration(signal, name:)
          explicit = value_for(signal, :default)
          return explicit unless explicit.nil?
          initializer = initial_default_for_signal(name.to_s)
          return initializer unless initializer.nil?
          if procedural_assignment_targets.include?(name.to_s) &&
              !continuous_assignment_targets.include?(name.to_s)
            return 0
          end

          nil
        end

        def port_default_for(port, name:, direction:)
          explicit = value_for(port, :default)
          return explicit unless explicit.nil?
          return nil unless direction == "output"
          initializer = initial_default_for_signal(name.to_s)
          return initializer unless initializer.nil?

          if procedural_assignment_targets.include?(name.to_s) &&
              !continuous_assignment_targets.include?(name.to_s)
            return 0
          end

          nil
        end

        def continuous_assignment_targets
          @continuous_assignment_targets ||= begin
            assign_entries.each_with_object(Set.new) do |entry, memo|
              name = target_root_identifier_name(value_for(entry, :target))
              memo.add(name) unless name.nil?
            end
          end
        end

        def procedural_assignment_targets
          @procedural_assignment_targets ||= begin
            processes.each_with_object(Set.new) do |process, memo|
              collect_procedural_assignment_targets(Array(value_for(process, :statements)), memo)
            end
          end
        end

        def non_initial_procedural_assignment_targets
          @non_initial_procedural_assignment_targets ||= begin
            processes.each_with_object(Set.new) do |process, memo|
              next if initial_default_process?(process)

              collect_procedural_assignment_targets(Array(value_for(process, :statements)), memo)
            end
          end
        end

        def collect_procedural_assignment_targets(statements, targets)
          Array(statements).each do |statement|
            hash = normalize_hash(statement)
            kind = value_for(hash, :kind).to_s
            case kind
            when "blocking_assign", "nonblocking_assign"
              name = target_root_identifier_name(value_for(hash, :target))
              targets.add(name) unless name.nil?
            when "if"
              then_body = value_for(hash, :then) || value_for(hash, :then_body)
              else_body = value_for(hash, :else) || value_for(hash, :else_body)
              collect_procedural_assignment_targets(Array(then_body), targets)
              collect_procedural_assignment_targets(Array(else_body), targets)
            when "case", "case_stmt"
              case_items(hash).each do |item|
                item_hash = normalize_hash(item)
                body = value_for(item_hash, :body) || value_for(item_hash, :statements)
                collect_procedural_assignment_targets(Array(body), targets)
              end
              default_body = value_for(hash, :default_body) || value_for(hash, :default)
              collect_procedural_assignment_targets(Array(default_body), targets)
            when "for", "for_loop"
              body = value_for(hash, :body) || value_for(hash, :statements)
              collect_procedural_assignment_targets(Array(body), targets)
            end
          end
        end

        def initial_default_for_signal(name)
          initial_default_assignments[name.to_s]
        end

        def initial_default_assignments
          @initial_default_assignments ||= begin
            processes.each_with_object({}) do |process, memo|
              next unless initial_default_process?(process)

              Array(value_for(process, :statements)).each do |statement|
                hash = normalize_hash(statement)
                target_name = target_root_identifier_name(value_for(hash, :target))
                value = value_for(hash, :value)
                next if target_name.nil? || value.nil?
                next unless constant_expression?(value)
                constant = constant_integer_expression(value)
                next if constant.nil?

                memo[target_name] = constant
              end
            end
          end
        end

        def initial_default_process?(process)
          domain = value_for(process, :domain).to_s
          kind = value_for(process, :kind).to_s
          return false unless domain == "initial" || kind == "initial"

          statements = Array(value_for(process, :statements))
          return false if statements.empty?

          statements.all? do |statement|
            hash = normalize_hash(statement)
            stmt_kind = value_for(hash, :kind).to_s
            next false unless %w[blocking_assign nonblocking_assign].include?(stmt_kind)

            target_name = target_root_identifier_name(value_for(hash, :target))
            value = value_for(hash, :value)
            !target_name.nil? && !value.nil? && constant_expression?(value)
          end
        end

        def target_root_identifier_name(node)
          case node
          when Symbol
            node.to_s
          when String
            text = node.strip
            identifier?(text) ? text : nil
          when Hash
            hash = normalize_hash(node)
            kind = value_for(hash, :kind).to_s
            case kind
            when "identifier"
              value_for(hash, :name).to_s
            when "index", "slice"
              target_root_identifier_name(value_for(hash, :base))
            else
              nil
            end
          else
            nil
          end
        end

        def statements
          Array(value_for(mapped_module, :statements))
        end

        def assign_entries
          entries = []

          Array(value_for(mapped_module, :assigns)).each do |entry|
            hash = normalize_hash(entry)
            entries << {
              target: value_for(hash, :target),
              value: value_for(hash, :expr),
              expr: value_for(hash, :expr)
            }
          end

          statements.each do |entry|
            hash = normalize_hash(entry)
            next unless value_for(hash, :kind).to_s == "continuous_assign"

            entries << {
              target: value_for(hash, :target),
              value: value_for(hash, :value),
              expr: value_for(hash, :value)
            }
          end

          entries
        end

        def processes
          Array(value_for(mapped_module, :processes))
        end

        def instances
          Array(value_for(mapped_module, :instances))
        end

        def vendor_source_filename
          span = normalize_hash(value_for(mapped_module, :span))
          source_path = value_for(span, :source_path).to_s.strip
          return nil if source_path.empty?

          basename = File.basename(source_path)
          return nil if basename.empty?

          basename
        end

        def width_from_range_hash(value)
          msb = numeric_expression_value(value_for(value, :msb))
          lsb = numeric_expression_value(value_for(value, :lsb))
          return (msb - lsb).abs + 1 if !msb.nil? && !lsb.nil?

          lsb_hash = normalize_hash(value_for(value, :lsb))
          msb_hash = normalize_hash(value_for(value, :msb))
          lsb_value = numeric_expression_value(lsb_hash)
          return nil unless lsb_value == 0

          if value_for(msb_hash, :kind).to_s == "binary" &&
              value_for(msb_hash, :operator).to_s == "-"
            left = normalize_hash(value_for(msb_hash, :left))
            right = normalize_hash(value_for(msb_hash, :right))
            if value_for(left, :kind).to_s == "identifier" &&
                numeric_expression_value(right) == 1
              name = value_for(left, :name).to_s
              return nil if name.empty?

              return ":#{name}"
            end
          end

          if value_for(msb_hash, :kind).to_s == "identifier"
            name = value_for(msb_hash, :name).to_s
            return nil if name.empty?

            return ":#{name}"
          end

          nil
        end

        def numeric_expression_value(node)
          return node if node.is_a?(Integer)
          if node.is_a?(String)
            text = node.strip
            return Integer(text) if integer_string?(text)
          end

          folded = constant_integer_expression(node)
          return folded unless folded.nil?

          nil
        end

        def normalize_parameter_overrides(overrides)
          Array(overrides).each_with_object({}) do |entry, memo|
            hash = normalize_hash(entry)
            name = value_for(hash, :name).to_s
            next if name.empty?

            memo[name] = value_for(hash, :value).to_s
          end
        end

        def normalize_connections(connections)
          case connections
          when Hash
            connections.each_with_object({}) do |(key, value), memo|
              port = key.to_s
              next if port.empty?

              memo[port] = normalize_connection_signal(value)
            end
          else
            Array(connections).each_with_object({}) do |entry, memo|
              hash = normalize_hash(entry)
              port = value_for(hash, :port).to_s
              next if port.empty?

              memo[port] = normalize_connection_signal(value_for(hash, :signal))
            end
          end
        end

        def normalize_connection_signal(signal)
          return :__rhdl_unconnected if open_connection_signal?(signal)

          signal
        end

        def open_connection_signal?(signal)
          return true if signal.nil?

          if signal.is_a?(String)
            return true if signal.strip.empty?
          end

          hash = normalize_hash(signal)
          return false if hash.empty?

          return false unless value_for(hash, :kind).to_s == "number"

          value_for(hash, :value).to_s.strip.empty?
        end

        def prune_identity_instance_connections(connections)
          return {} if connections.nil? || connections.empty?

          connections.each_with_object({}) do |(port_name, signal_expr), memo|
            memo[port_name] = signal_expr unless identity_instance_connection?(port_name, signal_expr)
          end
        end

        def identity_instance_connection?(port_name, signal_expr)
          identifier = extract_identifier_name(signal_expr)
          return false if identifier.nil?

          identifier.to_s == port_name.to_s
        end

        def format_instance_generics(generics)
          items = generics
            .map do |name, value|
              formatted = format_instance_generic_value(value)
              "#{name}: #{formatted}"
            end

          "{ #{items.join(', ')} }"
        end

        def format_instance_ports(connections)
          items = connections
            .map do |port_name, signal_expr|
              formatted = format_instance_port_value(signal_expr)
              "#{port_name}: #{formatted}"
            end

          "{ #{items.join(', ')} }"
        end

        def format_instance_generic_value(value)
          format_instance_connection_value(value)
        end

        def format_instance_port_value(value)
          identifier = extract_identifier_name(value)
          return ":#{identifier}" unless identifier.nil?

          ruby_expression = expression_to_ruby(value)
          return ruby_expression unless ruby_expression.nil?

          format_instance_connection_value(value)
        end

        def format_instance_connection_value(value)
          identifier = extract_identifier_name(value)
          return ":#{identifier}" unless identifier.nil?

          expression = expression_to_verilog(value)
          return expression.inspect unless expression.nil?

          value.to_s.inspect
        end

        def extract_identifier_name(node)
          case node
          when Symbol
            node.to_s
          when String
            text = node.strip
            return nil unless identifier?(text)

            text
          when Hash
            hash = normalize_hash(node)
            return value_for(hash, :name).to_s if value_for(hash, :kind).to_s == "identifier"

            nil
          else
            nil
          end
        end

        def process_symbol(value, index:, process:, sensitivity_values:, used_names:)
          explicit = sanitize_identifier(value.to_s)
          base_name = explicit
          if base_name.empty?
            base_name = auto_process_base_name(
              process: process,
              sensitivity_values: sensitivity_values,
              index: index
            )
          end
          base_name = "process_#{index}" unless identifier?(base_name)
          unique_identifier(base_name, used_names)
        end

        def auto_process_base_name(process:, sensitivity_values:, index:)
          domain = value_for(process, :domain).to_s
          kind = value_for(process, :kind).to_s
          intent = value_for(process, :intent).to_s.strip

          if domain == "initial"
            return "initial_block_#{index}"
          end

          if process_clocked?(process, sensitivity_values: sensitivity_values)
            clock_event = Array(sensitivity_values).find do |event|
              hash = normalize_hash(event)
              %w[posedge negedge].include?(value_for(hash, :edge).to_s)
            end

            signal_name = extract_identifier_name(value_for(normalize_hash(clock_event), :signal))
            edge = value_for(normalize_hash(clock_event), :edge).to_s
            base = if signal_name.nil? || signal_name.empty? || edge.empty?
                     "sequential"
                   else
                     "sequential_#{edge}_#{signal_name}"
                   end
            return sanitize_identifier(base)
          end

          if intent == "always_comb"
            return "combinational_logic_#{index}"
          end

          if intent == "always_latch"
            return "latch_logic_#{index}"
          end

          if domain == "combinational" || kind.include?("comb")
            return "combinational_logic_#{index}"
          end

          "process_#{index}"
        end

        def sanitize_identifier(value)
          token = value.to_s.strip
          token = token.gsub(/[^A-Za-z0-9_]/, "_")
          token = token.gsub(/_+/, "_")
          token = token.sub(/\A_+/, "")
          token = token.sub(/_+\z/, "")
          return "" if token.empty?
          return "n_#{token}" if token.match?(/\A\d/)

          token
        end

        def unique_identifier(base_name, used_names)
          candidate = base_name
          suffix = 2
          while used_names.include?(candidate)
            candidate = "#{base_name}_#{suffix}"
            suffix += 1
          end
          used_names.add(candidate)
          candidate
        end

        def process_clocked?(process, sensitivity_values:)
          return false if value_for(process, :domain).to_s == "initial"

          return true if value_for(process, :intent).to_s.strip == "always_ff"

          return true if value_for(process, :domain).to_s == "clocked"

          Array(sensitivity_values).any? do |event|
            hash = normalize_hash(event)
            edge = value_for(hash, :edge).to_s.strip
            %w[posedge negedge].include?(edge)
          end
        end

        def process_initial?(process)
          domain = value_for(process, :domain).to_s
          kind = value_for(process, :kind).to_s
          domain == "initial" || kind == "initial"
        end

        def sensitivity_to_ruby(node)
          hash = normalize_hash(node)
          unless hash.empty?
            signal = expression_to_ruby(value_for(hash, :signal))
            return nil if signal.nil?

            edge = value_for(hash, :edge).to_s.strip
            edge_value = edge.empty? ? "any" : edge
            return "{ edge: #{edge_value.inspect}, signal: #{signal} }"
          end

          expression_to_ruby(node)
        end

        def target_expression_to_ruby(node)
          case node
          when Symbol
            ":#{node}"
          when String
            text = node.strip
            return nil if text.empty?
            return ":#{text}" if identifier?(text)

            nil
          when Hash
            hash = normalize_hash(node)
            kind = value_for(hash, :kind).to_s
            case kind
            when "identifier"
              name = value_for(hash, :name).to_s
              return nil if name.empty?

              ":#{name}"
            when "index"
              base = expression_to_ruby(value_for(hash, :base))
              index = expression_to_ruby(value_for(hash, :index))
              return nil if base.nil? || index.nil?

              "#{base}[#{index}]"
            when "slice"
              base = expression_to_ruby(value_for(hash, :base))
              msb_node = value_for(hash, :msb)
              lsb_node = value_for(hash, :lsb)
              msb = expression_to_ruby(msb_node)
              lsb = expression_to_ruby(lsb_node)
              return nil if base.nil? || msb.nil? || lsb.nil?

              static_msb = constant_integer_expression(msb_node)
              static_lsb = constant_integer_expression(lsb_node)
              if !static_msb.nil? && !static_lsb.nil?
                "#{base}[#{static_msb}..#{static_lsb}]"
              else
                "#{base}[#{msb}..#{lsb}]"
              end
            else
              nil
            end
          else
            nil
          end
        end

        def expression_to_ruby(node)
          case node
          when NilClass
            nil
          when Symbol
            signal_ref_ruby(node.to_s)
          when String
            text = node.strip
            return nil if text.empty?
            return signal_ref_ruby(text) if identifier?(text)
            return Integer(text).to_s if integer_string?(text)

            text.inspect
          when Numeric
            node.to_i.to_s
          when Hash
            expression_hash_to_ruby(normalize_hash(node))
          else
            node.to_s.inspect
          end
        end

        def expression_hash_to_ruby(hash)
          kind = value_for(hash, :kind).to_s
          case kind
          when "identifier"
            signal_ref_ruby(value_for(hash, :name).to_s)
          when "number"
            number_to_ruby(hash)
          when "binary"
            binary_to_ruby(hash)
          when "unary"
            unary_to_ruby(hash)
          when "ternary"
            ternary_to_ruby(hash)
          when "concat"
            concat_to_ruby(hash)
          when "replicate", "replication"
            replication_to_ruby(hash)
          when "index"
            index_to_ruby(hash)
          when "slice"
            slice_to_ruby(hash)
          else
            nil
          end
        end

        def signal_ref_ruby(name)
          text = name.to_s.strip
          return nil if text.empty?

          width = identifier_width(text) || 1
          "sig(:#{text}, width: #{width})"
        end

        def number_to_ruby(hash)
          value = literal_integer_value(hash)
          width = value_for(hash, :width)
          base = normalize_number_base(value_for(hash, :base))
          signed = value_for(hash, :signed) ? true : false
          width_code = width.nil? ? "nil" : width.to_i.to_s
          base_code = base.nil? ? "nil" : base.inspect
          "lit(#{value}, width: #{width_code}, base: #{base_code}, signed: #{signed})"
        end

        def binary_to_ruby(hash)
          left = expression_to_ruby(value_for(hash, :left))
          right = expression_to_ruby(value_for(hash, :right))
          op = value_for(hash, :operator).to_s
          return nil if left.nil? || right.nil? || op.empty?

          "(#{left} #{op} #{right})"
        end

        def unary_to_ruby(hash)
          operand = expression_to_ruby(value_for(hash, :operand))
          op = value_for(hash, :operator).to_s
          return nil if operand.nil? || op.empty?

          if %w[~ ! + -].include?(op)
            "(#{op}#{operand})"
          else
            "u(#{op.to_sym.inspect}, #{operand})"
          end
        end

        def ternary_to_ruby(hash)
          case_select = ternary_chain_to_case_select_ruby(hash)
          return case_select unless case_select.nil?

          condition = expression_to_ruby(value_for(hash, :condition))
          when_true = expression_to_ruby(value_for(hash, :true_expr))
          when_false = expression_to_ruby(value_for(hash, :false_expr))
          return nil if condition.nil? || when_true.nil? || when_false.nil?

          "mux(#{condition}, #{when_true}, #{when_false})"
        end

        def ternary_chain_to_case_select_ruby(root_hash)
          chain = extract_case_select_chain(root_hash)
          return nil if chain.nil?

          selector_code = expression_to_ruby(chain.fetch(:selector))
          default_code = expression_to_ruby(chain.fetch(:default))
          return nil if selector_code.nil? || default_code.nil?

          case_entries = chain.fetch(:entries)
          return nil if case_entries.length < 2

          rendered_entries = case_entries.map do |entry|
            expr_code = expression_to_ruby(entry.fetch(:expr))
            return nil if expr_code.nil?

            "#{entry.fetch(:value)} => #{expr_code}"
          end

          "case_select(#{selector_code}, cases: { #{rendered_entries.join(', ')} }, default: #{default_code})"
        end

        def extract_case_select_chain(root_hash)
          current = root_hash
          selector_key = nil
          selector_node = nil
          entries = []
          seen_values = Set.new
          default_node = nil
          max_depth = 128
          depth = 0

          while depth < max_depth
            depth += 1
            hash = normalize_hash(current)
            return nil unless value_for(hash, :kind).to_s == "ternary"

            condition_info = extract_case_condition(value_for(hash, :condition))
            return nil if condition_info.nil?

            candidate_selector = condition_info.fetch(:selector)
            candidate_key = expression_to_verilog(candidate_selector)
            return nil if candidate_key.nil? || candidate_key.empty?

            if selector_key.nil?
              selector_key = candidate_key
              selector_node = candidate_selector
            elsif selector_key != candidate_key
              return nil
            end

            branch_expr = value_for(hash, :true_expr)
            condition_info.fetch(:values).each do |value|
              next if seen_values.include?(value)

              seen_values.add(value)
              entries << { value: value, expr: branch_expr }
            end

            false_expr = value_for(hash, :false_expr)
            false_hash = normalize_hash(false_expr)
            if value_for(false_hash, :kind).to_s == "ternary"
              current = false_hash
              next
            end

            default_node = false_expr
            break
          end

          return nil if default_node.nil?
          return nil if entries.empty?

          {
            selector: selector_node,
            entries: entries,
            default: default_node
          }
        rescue StandardError
          nil
        end

        def extract_case_condition(node)
          hash = normalize_hash(node)
          kind = value_for(hash, :kind).to_s

          if kind == "binary"
            operator = value_for(hash, :operator).to_s
            if operator == "||" || operator == "|"
              left_info = extract_case_condition(value_for(hash, :left))
              right_info = extract_case_condition(value_for(hash, :right))
              return nil if left_info.nil? || right_info.nil?

              left_selector = expression_to_verilog(left_info.fetch(:selector))
              right_selector = expression_to_verilog(right_info.fetch(:selector))
              return nil if left_selector.nil? || right_selector.nil?
              return nil unless left_selector == right_selector

              merged_values = left_info.fetch(:values) + right_info.fetch(:values)
              return {
                selector: left_info.fetch(:selector),
                values: merged_values.uniq
              }
            end

            return nil unless operator == "==" || operator == "==="

            left = value_for(hash, :left)
            right = value_for(hash, :right)
            left_value = constant_integer_expression(left)
            right_value = constant_integer_expression(right)

            if !left_value.nil? && right_value.nil?
              return { selector: right, values: [left_value] }
            end
            if !right_value.nil? && left_value.nil?
              return { selector: left, values: [right_value] }
            end
          end

          nil
        end

        def concat_to_ruby(hash)
          parts = Array(value_for(hash, :parts)).map { |entry| expression_to_ruby(entry) }
          return nil if parts.any?(&:nil?)

          return nil if parts.empty?
          return parts.first if parts.length == 1

          head = parts.first
          tail = parts[1..]
          "#{head}.concat(#{tail.join(', ')})"
        end

        def replication_to_ruby(hash)
          value = expression_to_ruby(value_for(hash, :value))
          count = expression_to_ruby(value_for(hash, :count))
          return nil if value.nil? || count.nil?

          "#{value}.replicate(#{count})"
        end

        def index_to_ruby(hash)
          base_node = value_for(hash, :base)
          base = expression_to_ruby(base_node)
          index_node = value_for(hash, :index)
          static_index = constant_integer_expression(index_node)
          index = static_index.nil? ? expression_to_ruby(index_node) : static_index.to_s
          return nil if base.nil? || index.nil?

          if direct_select_base?(base_node)
            "#{base}[#{index}]"
          else
            shifted = "(#{base} >> #{index})"
            "(#{shifted} & lit(1, width: 1, base: \"b\"))"
          end
        end

        def slice_to_ruby(hash)
          base_node = value_for(hash, :base)
          base = expression_to_ruby(base_node)
          msb_node = value_for(hash, :msb)
          lsb_node = value_for(hash, :lsb)
          msb = expression_to_ruby(msb_node)
          lsb = expression_to_ruby(lsb_node)
          return nil if base.nil? || msb.nil? || lsb.nil?

          static_msb = constant_integer_expression(msb_node)
          static_lsb = constant_integer_expression(lsb_node)
          if direct_select_base?(base_node)
            rendered_msb = static_msb.nil? ? msb : static_msb.to_s
            rendered_lsb = static_lsb.nil? ? lsb : static_lsb.to_s
            "#{base}[#{rendered_msb}..#{rendered_lsb}]"
          else
            width_expr = "((#{msb}) - (#{lsb}) + lit(1, width: 32, base: \"d\"))"
            mask_expr = "((lit(1, width: 32, base: \"d\") << #{width_expr}) - lit(1, width: 32, base: \"d\"))"
            shifted = "(#{base} >> #{lsb})"
            "(#{shifted} & #{mask_expr})"
          end
        end

        def literal_integer_value(hash)
          value = value_for(hash, :value)
          return value if value.is_a?(Integer)

          base = normalize_number_base(value_for(hash, :base))
          text = value.to_s
          return 0 if text.empty?

          if base.nil? || base == "d"
            return Integer(text) if integer_string?(text)
          end

          radix =
            case base
            when "b" then 2
            when "o" then 8
            when "d", nil then 10
            when "h" then 16
            else 10
            end
          Integer(text, radix)
        rescue ArgumentError
          0
        end

        def expression_to_verilog(node)
          case node
          when NilClass
            nil
          when Symbol
            node.to_s
          when String
            node
          when Numeric
            node.to_s
          when Hash
            expression_hash_to_verilog(normalize_hash(node))
          else
            node.to_s
          end
        end

        def expression_hash_to_verilog(hash)
          kind = value_for(hash, :kind).to_s
          case kind
          when "identifier"
            value_for(hash, :name).to_s
          when "number"
            number_to_verilog(hash)
          when "binary"
            binary_expression_to_verilog(hash)
          when "unary"
            unary_expression_to_verilog(hash)
          when "ternary"
            ternary_expression_to_verilog(hash)
          when "concat"
            concat_expression_to_verilog(hash)
          when "replicate", "replication"
            replicate_expression_to_verilog(hash)
          when "index"
            index_expression_to_verilog(hash)
          when "slice"
            slice_expression_to_verilog(hash)
          else
            nil
          end
        end

        def number_to_verilog(hash)
          value = value_for(hash, :value)
          base = value_for(hash, :base)
          width = value_for(hash, :width)
          signed = value_for(hash, :signed)

          text = value.to_s
          return text if base.nil?
          base_token = normalize_number_base(base)
          return text if base_token.nil?
          return text if base_token == "d" && width.nil?

          prefix = width.nil? ? "" : "#{width}"
          signed_token = signed ? "s" : ""
          "#{prefix}'#{signed_token}#{base_token}#{text}"
        end

        def normalize_number_base(base)
          token = base.to_s.strip.downcase
          return nil if token.empty?

          case token
          when "2", "b", "bin", "binary"
            "b"
          when "8", "o", "oct", "octal"
            "o"
          when "10", "d", "dec", "decimal"
            "d"
          when "16", "h", "hex", "hexadecimal"
            "h"
          else
            token
          end
        end

        def binary_expression_to_verilog(hash)
          left = expression_to_verilog(value_for(hash, :left))
          right = expression_to_verilog(value_for(hash, :right))
          op = value_for(hash, :operator).to_s
          return nil if left.nil? || right.nil? || op.empty?

          "(#{left} #{op} #{right})"
        end

        def unary_expression_to_verilog(hash)
          operand = expression_to_verilog(value_for(hash, :operand))
          op = value_for(hash, :operator).to_s
          return nil if operand.nil? || op.empty?

          "(#{op}#{operand})"
        end

        def ternary_expression_to_verilog(hash)
          condition = expression_to_verilog(value_for(hash, :condition))
          true_expr = expression_to_verilog(value_for(hash, :true_expr))
          false_expr = expression_to_verilog(value_for(hash, :false_expr))
          return nil if condition.nil? || true_expr.nil? || false_expr.nil?

          "(#{condition} ? #{true_expr} : #{false_expr})"
        end

        def concat_expression_to_verilog(hash)
          parts = Array(value_for(hash, :parts)).map { |entry| expression_to_verilog(entry) }
          return nil if parts.any?(&:nil?)

          "{#{parts.join(', ')}}"
        end

        def replicate_expression_to_verilog(hash)
          count = expression_to_verilog(value_for(hash, :count))
          value = expression_to_verilog(value_for(hash, :value))
          return nil if count.nil? || value.nil?

          "{#{count}{#{value}}}"
        end

        def index_expression_to_verilog(hash)
          base_node = value_for(hash, :base)
          base = expression_to_verilog(base_node)
          index = expression_to_verilog(value_for(hash, :index))
          return nil if base.nil? || index.nil?

          static_index = constant_integer_expression(value_for(hash, :index))
          if direct_select_base?(base_node)
            "#{base}[#{index}]"
          else
            "((#{base} >> #{index}) & 1'b1)"
          end
        end

        def slice_expression_to_verilog(hash)
          base_node = value_for(hash, :base)
          base = expression_to_verilog(base_node)
          msb_node = value_for(hash, :msb)
          lsb_node = value_for(hash, :lsb)
          msb = expression_to_verilog(msb_node)
          lsb = expression_to_verilog(lsb_node)
          return nil if base.nil? || msb.nil? || lsb.nil?

          static_msb = constant_integer_expression(msb_node)
          static_lsb = constant_integer_expression(lsb_node)
          if direct_select_base?(base_node)
            rendered_msb = static_msb.nil? ? msb : static_msb.to_s
            rendered_lsb = static_lsb.nil? ? lsb : static_lsb.to_s
            "#{base}[#{rendered_msb}:#{rendered_lsb}]"
          else
            width_expr = "((#{msb}) - (#{lsb}) + 1)"
            mask_expr = "((1 << #{width_expr}) - 1)"
            "((#{base} >> #{lsb}) & #{mask_expr})"
          end
        end

        def constant_expression?(node)
          hash = normalize_hash(node)
          return node.is_a?(Numeric) if hash.empty?

          kind = value_for(hash, :kind).to_s
          case kind
          when "number"
            true
          when "unary"
            constant_expression?(value_for(hash, :operand))
          when "binary"
            constant_expression?(value_for(hash, :left)) && constant_expression?(value_for(hash, :right))
          else
            false
          end
        end

        def constant_integer_expression(node)
          hash = normalize_hash(node)
          return node if node.is_a?(Integer) && hash.empty?
          return nil if hash.empty?

          kind = value_for(hash, :kind).to_s
          case kind
          when "number"
            literal_integer_value(hash)
          when "unary"
            unary_constant_expression(value_for(hash, :operator).to_s, constant_integer_expression(value_for(hash, :operand)))
          when "binary"
            left = constant_integer_expression(value_for(hash, :left))
            right = constant_integer_expression(value_for(hash, :right))
            binary_constant_expression(value_for(hash, :operator).to_s, left, right)
          else
            nil
          end
        rescue StandardError
          nil
        end

        def unary_constant_expression(operator, operand)
          return nil if operand.nil?

          case operator
          when "+"
            operand
          when "-"
            -operand
          when "~"
            ~operand
          else
            nil
          end
        end

        def binary_constant_expression(operator, left, right)
          return nil if left.nil? || right.nil?

          case operator
          when "+"
            left + right
          when "-"
            left - right
          when "*"
            left * right
          when "/"
            return nil if right.zero?

            left / right
          when "%"
            return nil if right.zero?

            left % right
          when "<<"
            left << right
          when ">>"
            left >> right
          when "&"
            left & right
          when "|"
            left | right
          when "^"
            left ^ right
          else
            nil
          end
        end

        def direct_select_base?(node)
          case node
          when Symbol
            identifier?(node.to_s)
          when String
            text = node.strip
            return false unless identifier?(text)
            true
          when Hash
            hash = normalize_hash(node)
            kind = value_for(hash, :kind).to_s
            if kind == "identifier"
              name = value_for(hash, :name).to_s
              return identifier?(name)
            end

            %w[index slice].include?(kind)
          else
            false
          end
        end

        def can_emit_direct_select?(base_node, static_msb:, static_lsb:)
          return false unless direct_select_base?(base_node)

          identifier_name = extract_identifier_name(base_node)
          return true if identifier_name.nil?

          width = identifier_width(identifier_name)
          return false if width.nil? || width <= 1

          return true if static_msb.nil? || static_lsb.nil?

          upper = [static_msb, static_lsb].max
          lower = [static_msb, static_lsb].min
          return false if lower.negative?

          upper < width
        end

        def known_wide_identifier?(name)
          width = identifier_width(name)
          !width.nil? && width > 1
        end

        def identifier_width(name)
          signal_widths[name.to_s]
        end

        def signal_widths
          @signal_widths ||= begin
            widths = explicit_signal_widths.dup
            inferred_signal_widths.each do |name, inferred_width|
              next if inferred_width.nil?

              existing = widths[name]
              widths[name] = existing.nil? ? inferred_width : [existing, inferred_width].max
            end

            widths
          end
        end

        def explicit_signal_widths
          @explicit_signal_widths ||= begin
            widths = {}

            ports.each do |entry|
              hash = normalize_hash(entry)
              name = value_for(hash, :name).to_s
              width = numeric_width(value_for(hash, :width))
              widths[name] = width unless name.empty? || width.nil?
            end

            declaration_signals.each do |entry|
              hash = normalize_hash(entry)
              name = value_for(hash, :name).to_s
              width = numeric_width(value_for(hash, :width))
              widths[name] = width unless name.empty? || width.nil?
            end

            widths
          end
        end

        def numeric_width(value)
          return nil if value.nil?
          return value if value.is_a?(Integer)
          return width_from_range_hash(value) if value.is_a?(Hash)

          text = value.to_s.strip
          return nil if text.empty?
          return Integer(text) if integer_string?(text)

          nil
        end

        def class_name_for_module(module_name)
          tokens = module_name.to_s.gsub(/[^0-9A-Za-z]+/, "_").split("_").reject(&:empty?)
          candidate = tokens.map { |token| token[0].upcase + token[1..] }.join
          candidate = "ImportedModule" if candidate.empty?
          candidate = "M#{candidate}" if candidate.match?(/\A\d/)
          candidate = "Imported#{candidate}" if reserved_constant_name?(candidate)
          candidate
        end

        def normalize_hash(value)
          value.is_a?(Hash) ? value : {}
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

        def identifier?(value)
          value.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        end

        def integer_string?(value)
          value.match?(/\A-?\d+\z/)
        end

        def reserved_constant_name?(name)
          Object.const_defined?(name)
        rescue NameError
          false
        end
      end
    end
  end
end
