# frozen_string_literal: true
require 'set'

module RHDL
  module Codegen
    module CIRCT
      Diagnostic = Struct.new(:severity, :message, :line, :column, :op, keyword_init: true)

      class ImportResult
        attr_reader :modules, :diagnostics, :module_spans, :op_census, :module_diagnostics

        def initialize(modules:, diagnostics: [], module_spans: {}, op_census: {}, module_diagnostics: {})
          @modules = modules
          @diagnostics = diagnostics
          @module_spans = module_spans
          @op_census = op_census
          @module_diagnostics = module_diagnostics
        end

        def success?
          @diagnostics.none? { |d| d.severity.to_s == 'error' }
        end
      end

      module Import
        module_function

        SSA_TOKEN_PATTERN = '%[A-Za-z0-9_$.\\-]+'
        ARRAY_TYPE_PATTERN = /!hw\.array<(?<len>\d+)xi(?<width>\d+)>/
        LLHD_ARRAY_TYPE_PATTERN = /<\s*!hw\.array<(?<len>\d+)xi(?<width>\d+)>\s*>/

        ArrayValue = Struct.new(:elements, :length, :element_width, keyword_init: true)

        def from_mlir(text, strict: false, top: nil, extern_modules: [])
          diagnostics = []
          modules = []
          module_spans = {}
          lines = text.lines
          idx = 0
          census = op_census(text)

          while idx < lines.length
            header = parse_module_header(lines, idx, diagnostics)
            unless header
              idx += 1
              next
            end
            unless header[:valid]
              idx = header[:next_idx]
              next
            end

            mod_name = header[:name]
            module_parameters = parse_module_parameters(header[:params], diagnostics, header[:line_no])
            if header[:directional_ports]
              input_ports = parse_input_ports(header[:inputs], diagnostics, header[:line_no], directional: true)
              output_ports = parse_output_ports(header[:inputs], diagnostics, header[:line_no], directional: true)
            else
              input_ports = parse_input_ports(header[:inputs], diagnostics, header[:line_no])
              output_ports = parse_output_ports(header[:outputs], diagnostics, header[:line_no])
            end
            value_map = seed_value_map(input_ports)
            assigns = []
            regs = []
            nets = []
            processes = []
            instances = []
            module_start_line = header[:line_no]

            idx = header[:next_idx]
            body_depth = 1
            while idx < lines.length && body_depth.positive?
              body_raw = lines[idx]
              body = body_raw.strip

              if body == '}'
                body_depth -= 1
                idx += 1
                next
              end

              if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*scf\.if\b/)
                consumed = parse_scf_if_block(
                  lines,
                  idx,
                  value_map: value_map,
                  diagnostics: diagnostics,
                  line_no: idx + 1,
                  strict: strict
                )
                if consumed
                  body_depth += brace_delta(lines, idx, consumed)
                  idx += consumed
                  next
                end
              end

              if body.include?('hw.instance')
                combined, consumed = collect_multiline_instance(lines, idx)
                parse_body_line(
                  combined,
                  value_map: value_map,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  processes: processes,
                  instances: instances,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1,
                  strict: strict
                )
                body_depth += brace_delta(lines, idx, consumed)
                idx += consumed
                next
              end

              if body.start_with?('hw.output') && !body.include?(':')
                combined, consumed = collect_multiline_output(lines, idx)
                parse_body_line(
                  combined,
                  value_map: value_map,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  processes: processes,
                  instances: instances,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1,
                  strict: strict
                )
                body_depth += brace_delta(lines, idx, consumed)
                idx += consumed
                next
              end

              parse_body_line(
                body,
                value_map: value_map,
                assigns: assigns,
                regs: regs,
                nets: nets,
                processes: processes,
                instances: instances,
                output_ports: output_ports,
                diagnostics: diagnostics,
                line_no: idx + 1,
                strict: strict
              )
              body_depth += brace_delta(lines, idx, 1)
              idx += 1
            end

            if body_depth.positive?
              diagnostics << Diagnostic.new(
                severity: :error,
                message: "Unterminated hw.module @#{mod_name}",
                line: idx + 1,
                column: 1,
                op: 'hw.module'
              )
            end
            module_spans[mod_name] = {
              start_line: module_start_line,
              end_line: idx
            }

            assigns = resolve_forward_refs_in_assigns(
              assigns,
              value_map: value_map,
              declared_names: declared_signal_names(input_ports, output_ports, nets, regs)
            )
            processes = resolve_forward_refs_in_processes(
              processes,
              value_map: value_map,
              declared_names: declared_signal_names(input_ports, output_ports, nets, regs)
            )
            instances = resolve_forward_refs_in_instances(
              instances,
              value_map: value_map,
              declared_names: declared_signal_names(input_ports, output_ports, nets, regs)
            )

            modules << IR::ModuleOp.new(
              name: mod_name,
              ports: input_ports + output_ports,
              nets: nets,
              regs: regs,
              assigns: assigns,
              processes: processes,
              instances: instances,
              memories: [],
              write_ports: [],
              sync_read_ports: [],
              parameters: module_parameters
            )
          end

          enforce_dependency_closure(
            modules: modules,
            module_spans: module_spans,
            diagnostics: diagnostics,
            strict: strict,
            top: top,
            extern_modules: extern_modules
          )

          ImportResult.new(
            modules: modules,
            diagnostics: diagnostics,
            module_spans: module_spans,
            op_census: census,
            module_diagnostics: build_module_diagnostics(
              modules: modules,
              diagnostics: diagnostics,
              module_spans: module_spans
            )
          )
        end

        def op_census(text)
          counts = Hash.new(0)
          text.to_s.lines.each do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?('//')

            match = stripped.match(/\A(?:%[^\s]+\s*=\s*)?([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\b/)
            next unless match

            counts[match[1]] += 1
          end
          counts
        end

        def brace_delta(lines, start_idx, consumed)
          Array(lines[start_idx, consumed]).sum { |line| line.count('{') - line.count('}') }
        end

        def parse_module_header(lines, start_idx, diagnostics)
          first = lines[start_idx]
          return nil unless first&.lstrip&.match?(/\Ahw\.module\b/)

          header_lines = []
          idx = start_idx
          found_body_open = false
          attribute_depth = 0
          paren_depth = 0

          while idx < lines.length
            line = lines[idx].strip
            header_lines << line
            body_open, attribute_depth, paren_depth = scan_line_for_module_body_open(line, attribute_depth, paren_depth)
            if body_open
              found_body_open = true
              break
            end
            idx += 1
          end

          unless found_body_open
            diagnostics << Diagnostic.new(
              severity: :error,
              message: 'Unterminated hw.module header',
              line: start_idx + 1,
              column: 1,
              op: 'hw.module'
            )
            return { valid: false, next_idx: lines.length }
          end

          header = header_lines.join(' ').gsub(/\s+/, ' ').strip
          header = strip_module_attributes(header)
          match = header.match(/\Ahw\.module(?:\s+private)?\s+@(?<name>[A-Za-z0-9_$.]+)(?:<(?<params>.*?)>)?\s*\((?<inputs>.*?)\)\s*(?:->\s*\((?<outputs>.*?)\))?\s*\{\s*\z/)
          unless match
            diagnostics << Diagnostic.new(
              severity: :error,
              message: "Invalid hw.module header syntax: #{header}",
              line: start_idx + 1,
              column: 1,
              op: 'hw.module'
            )
            return { valid: false, next_idx: idx + 1 }
          end

          {
            valid: true,
            name: match[:name],
            params: match[:params],
            inputs: match[:inputs],
            outputs: match[:outputs],
            directional_ports: match[:outputs].nil? && directional_port_list?(match[:inputs]),
            line_no: start_idx + 1,
            next_idx: idx + 1
          }
        end

        def directional_port_list?(raw)
          split_top_level_csv(raw).any? { |entry| entry.strip.match?(/\A(?:in|out)\b/) }
        end

        def seed_value_map(input_ports)
          input_ports.each_with_object({}) do |port, map|
            map["%#{port.name}"] = IR::Signal.new(name: port.name.to_s, width: port.width.to_i)
          end
        end

        def strip_module_attributes(header)
          text = header.to_s
          out = +''
          idx = 0

          while idx < text.length
            if (skip_to = consume_attributes_block(text, idx))
              idx = skip_to
              next
            end

            out << text[idx]
            idx += 1
          end

          out.gsub(/\s+/, ' ').strip
        end

        def consume_attributes_block(text, idx)
          keyword = 'attributes'
          return nil unless text[idx, keyword.length] == keyword

          prev = idx.zero? ? nil : text[idx - 1]
          return nil if prev&.match?(/[A-Za-z0-9_]/)

          j = idx + keyword.length
          j += 1 while j < text.length && text[j].match?(/\s/)
          return nil unless j < text.length && text[j] == '{'

          depth = 0
          in_quote = false
          escaped = false

          while j < text.length
            ch = text[j]
            if in_quote
              if escaped
                escaped = false
              elsif ch == '\\'
                escaped = true
              elsif ch == '"'
                in_quote = false
              end
              j += 1
              next
            end

            case ch
            when '"'
              in_quote = true
            when '{'
              depth += 1
            when '}'
              depth -= 1
              return (j + 1) if depth.zero?
            end

            j += 1
          end

          text.length
        end

        def scan_line_for_module_body_open(line, attribute_depth, paren_depth)
          i = 0
          in_quote = false
          escaped = false

          while i < line.length
            ch = line[i]

            if in_quote
              if escaped
                escaped = false
              elsif ch == '\\'
                escaped = true
              elsif ch == '"'
                in_quote = false
              end
              i += 1
              next
            end

            if attribute_depth.positive?
              in_quote = true if ch == '"'
              attribute_depth += 1 if ch == '{'
              attribute_depth -= 1 if ch == '}'
              i += 1
              next
            end

            if ch == '"'
              in_quote = true
              i += 1
              next
            end

            if paren_depth.zero? && (m = line[i..].match(/\Aattributes\s*\{/))
              attribute_depth = 1
              i += m[0].length
              next
            end

            if ch == '('
              paren_depth += 1
              i += 1
              next
            end

            if ch == ')'
              paren_depth = [paren_depth - 1, 0].max
              i += 1
              next
            end

            if ch == '{'
              return [true, attribute_depth, paren_depth] if paren_depth.zero?
              i += 1
              next
            end

            i += 1
          end

          [false, attribute_depth, paren_depth]
        end

        def collect_multiline_instance(lines, start_idx)
          collect_multiline_until(
            lines,
            start_idx,
            complete: ->(text, balance) { text.include?('->') && balance <= 0 }
          )
        end

        def collect_multiline_output(lines, start_idx)
          collect_multiline_until(
            lines,
            start_idx,
            complete: ->(text, _balance) { text.include?(':') }
          )
        end

        def collect_multiline_until(lines, start_idx, complete:)
          text = ''
          idx = start_idx
          balance = 0

          while idx < lines.length
            part = lines[idx].strip
            break if idx > start_idx && part == '}'

            text = text.empty? ? part : "#{text} #{part}"
            balance += part.count('(') - part.count(')')
            return [text, (idx - start_idx + 1)] if complete.call(text, balance)
            idx += 1
          end

          consumed = [idx - start_idx, 1].max
          [text, consumed]
        end

        def parse_scf_if_block(lines, start_idx, value_map:, diagnostics:, line_no:, strict:)
          header = normalize_body_line(lines[start_idx].to_s.strip)
          match = header.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*scf\.if\s+(#{SSA_TOKEN_PATTERN})\s*->\s*\(i(\d+)\)\s*\{\z/)
          return nil unless match

          result_ssa = match[1]
          condition_ssa = match[2]
          result_width = match[3].to_i

          then_lines = []
          else_lines = []
          branch = :then

          idx = start_idx + 1
          depth = 1

          while idx < lines.length && depth.positive?
            line = lines[idx].to_s.strip

            if depth == 1 && line == '} else {'
              branch = :else
              idx += 1
              next
            end

            if line.end_with?('{')
              depth += 1
            elsif line == '}'
              depth -= 1
              break if depth.zero?
            end

            if depth.positive?
              if branch == :then
                then_lines << line
              else
                else_lines << line
              end
            end

            idx += 1
          end

          consumed = idx - start_idx + 1
          then_expr = evaluate_scf_branch_value(
            then_lines,
            value_map: value_map,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            expected_width: result_width
          )
          else_expr = evaluate_scf_branch_value(
            else_lines,
            value_map: value_map,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            expected_width: result_width
          )
          condition = lookup_value(value_map, condition_ssa, width: 1)

          if then_expr && else_expr
            value_map[result_ssa] = IR::Mux.new(
              condition: condition,
              when_true: then_expr,
              when_false: else_expr,
              width: result_width
            )
          else
            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported scf.if branch syntax, skipped: #{header}",
              line: line_no,
              column: 1,
              op: 'scf.if'
            )
          end

          consumed
        end

        def evaluate_scf_branch_value(lines, value_map:, diagnostics:, line_no:, strict:, expected_width:)
          yield_token = nil
          temp_assigns = []
          temp_regs = []
          temp_nets = []
          temp_processes = []
          temp_instances = []

          lines.each do |line|
            body = normalize_body_line(line)
            next if body.empty? || body.start_with?('//')

            if (m = body.match(/\Ascf\.yield\s+(.+)\s*:\s*i\d+\z/))
              yield_token = normalize_value_token(m[1])
              next
            end

            parse_body_line(
              body,
              value_map: value_map,
              assigns: temp_assigns,
              regs: temp_regs,
              nets: temp_nets,
              processes: temp_processes,
              instances: temp_instances,
              output_ports: [],
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict
            )
          end

          return nil if yield_token.nil? || yield_token.empty?

          lookup_value(value_map, yield_token, width: expected_width)
        end

        def parse_input_ports(raw, diagnostics, line_no, directional: false)
          return [] if raw.nil? || raw.strip.empty?

          split_top_level_csv(raw).filter_map do |entry|
            token = strip_trailing_attr_dict(entry.to_s.strip)
            m = token.match(/\A(?:in\s+)?%?([A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/)
            if !m && directional && token.match?(/\Aout\s+%?[A-Za-z0-9_$.]+\s*:\s*i\d+\z/)
              next
            end
            unless m
              diagnostics << Diagnostic.new(
                severity: :error,
                message: "Invalid input port syntax: #{entry.strip}",
                line: line_no,
                column: 1,
                op: 'hw.module'
              )
              next
            end

            IR::Port.new(name: m[1], direction: :in, width: m[2].to_i)
          end
        end

        def parse_module_parameters(raw, diagnostics, line_no)
          return {} if raw.nil? || raw.strip.empty?

          params = {}
          split_top_level_csv(raw).each do |entry|
            token = entry.to_s.strip
            if (m = token.match(/\A([A-Za-z0-9_$.]+)\s*:\s*i\d+\s*=\s*(-?\d+)\z/))
              params[m[1]] = m[2].to_i
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported hw.module parameter syntax: #{token}",
                line: line_no,
                column: 1,
                op: 'hw.module'
              )
            end
          end

          params
        end

        def parse_output_ports(raw, diagnostics, line_no, directional: false)
          return [] if raw.nil? || raw.strip.empty?

          split_top_level_csv(raw).filter_map do |entry|
            token = strip_trailing_attr_dict(entry.to_s.strip)
            m = token.match(/\A(?:out\s+)?%?([A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/)
            if !m && directional && token.match?(/\Ain\s+%?[A-Za-z0-9_$.]+\s*:\s*i\d+\z/)
              next
            end
            unless m
              diagnostics << Diagnostic.new(
                severity: :error,
                message: "Invalid output port syntax: #{entry.strip}",
                line: line_no,
                column: 1,
                op: 'hw.module'
              )
              next
            end

            IR::Port.new(name: m[1], direction: :out, width: m[2].to_i)
          end
        end

        def parse_body_line(body, value_map:, assigns:, regs:, nets:, processes:, instances:, output_ports:, diagnostics:, line_no:,
                            strict: false)
          body = normalize_body_line(body)
          return if body.empty? || body.start_with?('//')
          return if body.start_with?('dbg.variable ')
          return if body.match?(/\A\^bb\d+:/)
          return if body == '{' || body == '}'
          return if body.start_with?('cf.br ') || body.start_with?('cf.cond_br ')
          return if body.match?(/\Allhd\.process\s*\{\z/)
          return if body.start_with?('llhd.wait ')
          return if body == 'llhd.halt'

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.constant\s+(-?\d+|true|false)(?:\s*:\s*i(\d+))?\z/))
            literal_value = case m[2]
                            when 'true' then 1
                            when 'false' then 0
                            else m[2].to_i
                            end

            width = if m[3]
                      m[3].to_i
                    elsif %w[true false].include?(m[2])
                      1
                    else
                      diagnostics << Diagnostic.new(
                        severity: strict ? :error : :warning,
                        message: "Unsupported hw.constant without explicit width, skipped: #{body}",
                        line: line_no,
                        column: 1,
                        op: 'hw.constant'
                      )
                      return
                    end

            value_map[m[1]] = IR::Literal.new(value: literal_value, width: width)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.constant_time\s+<.*>\z/))
            value_map[m[1]] = IR::Literal.new(value: 0, width: 1)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.array_create\s+(.+)\s*:\s*i(\d+)\z/))
            element_width = m[3].to_i
            elements = split_top_level_csv(m[2]).map { |token| lookup_value(value_map, token, width: element_width) }
            value_map[m[1]] = ArrayValue.new(
              elements: elements,
              length: elements.length,
              element_width: element_width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.array_get\s+(#{SSA_TOKEN_PATTERN})\[(#{SSA_TOKEN_PATTERN})\]\s*:\s*(!hw\.array<\d+xi\d+>)\s*,\s*i(\d+)\z/))
            array_type = parse_array_type(m[4])
            index_width = m[5].to_i
            array_value = lookup_value(value_map, m[2], width: array_type[:total_width])
            index_expr = lookup_value(value_map, m[3], width: index_width)
            elements = array_elements_from_value(array_value, length: array_type[:len], element_width: array_type[:element_width])
            value_map[m[1]] = select_array_element(
              elements: elements,
              index_expr: index_expr,
              element_width: array_type[:element_width]
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.bitcast\s+(.+)\s*:\s*\((.+)\)\s*->\s*(.+)\z/))
            source_token = normalize_value_token(m[2])
            from_type = m[3].strip
            to_type = m[4].strip

            if (array_type = array_type_from_string(to_type))
              source_width = integer_type_width(from_type) || array_type[:total_width]
              source_value = lookup_value(value_map, source_token, width: source_width)
              elements = array_elements_from_value(
                source_value,
                length: array_type[:len],
                element_width: array_type[:element_width]
              )
              value_map[m[1]] = ArrayValue.new(
                elements: elements,
                length: array_type[:len],
                element_width: array_type[:element_width]
              )
              return
            end

            if (array_type = array_type_from_string(from_type))
              array_value = lookup_value(value_map, source_token, width: array_type[:total_width])
              elements = array_elements_from_value(
                array_value,
                length: array_type[:len],
                element_width: array_type[:element_width]
              )
              value_map[m[1]] = IR::Concat.new(parts: elements.reverse, width: array_type[:total_width])
              return
            end
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.sig(?:\s+name\s+"([^"]+)")?\s+(.+)\s*:\s*(!hw\.array<\d+xi\d+>)\z/))
            signal_name = (m[2] && !m[2].empty?) ? m[2] : m[1].sub('%', '')
            array_type = parse_array_type(m[4])
            init_value = lookup_value(value_map, m[3].strip, width: array_type[:total_width])
            elements = array_elements_from_value(
              init_value,
              length: array_type[:len],
              element_width: array_type[:element_width]
            )
            value_map[m[1]] = ArrayValue.new(
              elements: elements,
              length: array_type[:len],
              element_width: array_type[:element_width]
            )
            nets << IR::Net.new(name: signal_name, width: array_type[:total_width]) unless nets.any? { |n| n.name.to_s == signal_name.to_s }
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.sig(?:\s+name\s+"([^"]+)")?\s+(.+)\s*:\s*i(\d+)\z/))
            width = m[4].to_i
            signal_name = (m[2] && !m[2].empty?) ? m[2] : m[1].sub('%', '')
            value_map[m[1]] = IR::Signal.new(name: signal_name, width: width)
            nets << IR::Net.new(name: signal_name, width: width) unless nets.any? { |n| n.name.to_s == signal_name.to_s }
            # Force parsing of initializers to populate map when the initializer is literal/SSA.
            lookup_value(value_map, m[3].strip, width: width)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.prb\s+(#{SSA_TOKEN_PATTERN})\s*:\s*(.+)\z/))
            type = m[3].strip
            width = integer_type_width(type) || array_type_from_string(type)&.dig(:total_width) || 1
            value_map[m[1]] = lookup_value(value_map, m[2], width: width)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.sig\.array_get\s+(#{SSA_TOKEN_PATTERN})\[(#{SSA_TOKEN_PATTERN})\]\s*:\s*<\s*!hw\.array<(\d+)xi(\d+)>\s*>\z/))
            length = m[4].to_i
            element_width = m[5].to_i
            array_value = lookup_value(value_map, m[2], width: length * element_width)
            index_expr = lookup_value(value_map, m[3], width: [(Math.log2(length).ceil), 1].max)
            elements = array_elements_from_value(array_value, length: length, element_width: element_width)
            value_map[m[1]] = select_array_element(
              elements: elements,
              index_expr: index_expr,
              element_width: element_width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.sig\.extract\s+(#{SSA_TOKEN_PATTERN})\s+from\s+(#{SSA_TOKEN_PATTERN})\s*:\s*<i(\d+)>\s*->\s*<i(\d+)>\z/))
            base = lookup_value(value_map, m[2], width: m[4].to_i)
            index_expr = lookup_value(value_map, m[3], width: m[4].to_i)
            if index_expr.is_a?(IR::Literal)
              idx = index_expr.value.to_i
              value_map[m[1]] = IR::Slice.new(base: base, range: (idx..idx), width: m[5].to_i)
            else
              # Dynamic index support is deferred; preserve a symbolic reference for now.
              value_map[m[1]] = IR::Signal.new(name: m[1].sub('%', ''), width: m[5].to_i)
            end
            return
          end

          if (m = body.match(/\Allhd\.drv\s+(#{SSA_TOKEN_PATTERN}),\s*(.+)\s+after\s+#{SSA_TOKEN_PATTERN}\s*:\s*i(\d+)\z/))
            target_expr = lookup_value(value_map, m[1], width: m[3].to_i)
            target_name = target_expr.is_a?(IR::Signal) ? target_expr.name.to_s : m[1].sub('%', '')
            expr = lookup_value(value_map, m[2].strip, width: m[3].to_i)
            assigns << IR::Assign.new(target: target_name, expr: expr)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.icmp\s+(\w+)\s+(.+)\s*:\s*i(\d+)\z/))
            pred_map = {
              'eq' => :==,
              'ne' => :'!=',
              'ceq' => :==,
              'cne' => :'!=',
              'ult' => :<,
              'ule' => :<=,
              'ugt' => :>,
              'uge' => :>=,
              'slt' => :<,
              'sle' => :<=,
              'sgt' => :>,
              'sge' => :>=
            }

            pred = m[2]
            unless pred_map.key?(pred)
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported comb.icmp predicate '#{pred}', defaulting to eq",
                line: line_no,
                column: 1,
                op: 'comb.icmp'
              )
            end

            operands = split_top_level_csv(m[3])
            if operands.length != 2
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Invalid comb.icmp operand arity, skipped: #{body}",
                line: line_no,
                column: 1,
                op: 'comb.icmp'
              )
              return
            end

            in_width = m[4].to_i
            value_map[m[1]] = IR::BinaryOp.new(
              op: pred_map.fetch(pred, :==),
              left: lookup_value(value_map, operands[0], width: in_width),
              right: lookup_value(value_map, operands[1], width: in_width),
              width: 1
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.(add|sub|mul|divu|divs|modu|mods|and|or|xor|shl|shr_u|shr_s|shru|shrs)\s+(?:bin\s+)?(.+)\s*:\s*i(\d+)\z/))
            op_map = {
              'add' => :+,
              'sub' => :-,
              'mul' => :*,
              'divu' => :/,
              'divs' => :/,
              'modu' => :%,
              'mods' => :%,
              'and' => :&,
              'or' => :|,
              'xor' => :^,
              'shl' => :'<<',
              'shr_u' => :'>>',
              'shr_s' => :'>>',
              'shru' => :'>>',
              'shrs' => :'>>'
            }

            op_name = m[2]
            width = m[4].to_i
            operands = split_top_level_csv(m[3]).map { |token| normalize_value_token(token) }.reject(&:empty?)
            if operands.length < 2
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Invalid comb.#{op_name} operand arity, skipped: #{body}",
                line: line_no,
                column: 1,
                op: "comb.#{op_name}"
              )
              return
            end

            variadic_ok = %w[and or xor add].include?(op_name)
            if operands.length > 2 && !variadic_ok
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Unsupported variadic comb.#{op_name}, skipped: #{body}",
                line: line_no,
                column: 1,
                op: "comb.#{op_name}"
              )
              return
            end

            op_symbol = op_map[op_name] || op_name.to_sym
            exprs = operands.map { |token| lookup_value(value_map, token, width: width) }
            folded = exprs.drop(1).reduce(exprs.first) do |lhs, rhs|
              IR::BinaryOp.new(op: op_symbol, left: lhs, right: rhs, width: width)
            end

            value_map[m[1]] = folded
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.replicate\s+(#{SSA_TOKEN_PATTERN})\s*:\s*\(i(\d+)\)\s*->\s*i(\d+)\z/))
            in_width = m[3].to_i
            out_width = m[4].to_i
            if in_width <= 0 || out_width <= 0 || (out_width % in_width) != 0
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Invalid comb.replicate width relation, skipped: #{body}",
                line: line_no,
                column: 1,
                op: 'comb.replicate'
              )
              return
            end

            part = lookup_value(value_map, m[2], width: in_width)
            repeat = out_width / in_width
            parts = Array.new(repeat) { part }
            value_map[m[1]] = IR::Concat.new(parts: parts, width: out_width)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.mux\s+(#{SSA_TOKEN_PATTERN}),\s*(#{SSA_TOKEN_PATTERN}),\s*(#{SSA_TOKEN_PATTERN})\s*:\s*i(\d+)\z/))
            value_map[m[1]] = IR::Mux.new(
              condition: lookup_value(value_map, m[2], width: 1),
              when_true: lookup_value(value_map, m[3]),
              when_false: lookup_value(value_map, m[4]),
              width: m[5].to_i
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.extract\s+(#{SSA_TOKEN_PATTERN})\s+from\s+(\d+)\s*:\s*\(i(\d+)\)\s*->\s*i(\d+)\z/))
            low = m[3].to_i
            in_width = m[4].to_i
            out_width = m[5].to_i
            value_map[m[1]] = IR::Slice.new(
              base: lookup_value(value_map, m[2], width: in_width),
              range: (low..(low + out_width - 1)),
              width: out_width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.parity\s+(#{SSA_TOKEN_PATTERN})\s*:\s*i(\d+)\z/))
            in_width = m[3].to_i
            if in_width <= 0
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Invalid comb.parity width, skipped: #{body}",
                line: line_no,
                column: 1,
                op: 'comb.parity'
              )
              return
            end

            source = lookup_value(value_map, m[2], width: in_width)
            value_map[m[1]] = build_parity_reduce(source: source, in_width: in_width)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.concat\s+(.+)\s*:\s*(.+)\z/))
            tokens = split_top_level_csv(m[2])
            type_tokens = split_top_level_csv(m[3])
            widths = type_tokens.map { |t| t[/\Ai(\d+)\z/, 1] }.compact.map(&:to_i)
            if widths.length != tokens.length
              diagnostics << Diagnostic.new(
                severity: strict ? :error : :warning,
                message: "Invalid comb.concat arity/types, skipped: #{body}",
                line: line_no,
                column: 1,
                op: 'comb.concat'
              )
              return
            end

            parts = tokens.each_with_index.map { |tok, i| lookup_value(value_map, tok, width: widths[i]) }
            value_map[m[1]] = IR::Concat.new(parts: parts, width: widths.sum)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*func\.call\s+@([A-Za-z0-9_$.]+)\(([^)]*)\)\s*:\s*\(([^)]*)\)\s*->\s*i(\d+)\z/))
            result_ssa = m[1]
            callee = m[2]
            args = split_top_level_csv(m[3]).map { |token| normalize_value_token(token) }.reject(&:empty?)
            input_types = split_top_level_csv(m[4]).map(&:strip)
            output_width = m[5].to_i

            if callee == 'bit_reverse' && args.length == 1
              input_width = integer_type_width(input_types.first) || output_width
              arg_expr = lookup_value(value_map, args.first, width: input_width)
              parts = (0...output_width).map do |bit|
                IR::Slice.new(base: arg_expr, range: (bit..bit), width: 1)
              end
              value_map[result_ssa] = IR::Concat.new(parts: parts, width: output_width)
              return
            end

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported func.call target '#{callee}', skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'func.call'
            )
            return
          end

          if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*seq\.compreg\b/)
            return if parse_seq_compreg_line(
              body,
              value_map: value_map,
              regs: regs,
              processes: processes,
              diagnostics: diagnostics,
              line_no: line_no
            )

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.compreg syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.compreg'
            )
            return
          end

          if body.include?('hw.instance')
            return if parse_hw_instance_line(
              body,
              value_map: value_map,
              instances: instances,
              diagnostics: diagnostics,
              line_no: line_no
            )
          end

          return if body == 'hw.output'

          if (m = body.match(/\Ahw\.output\s+(.+)\s*:\s*(.+)\z/))
            values = split_top_level_csv(m[1])
            output_ports.each_with_index do |port, out_idx|
              next if values[out_idx].nil?
              assigns << IR::Assign.new(target: port.name.to_s, expr: lookup_value(value_map, values[out_idx], width: port.width))
            end
            return
          end

          diagnostics << Diagnostic.new(
            severity: strict ? :error : :warning,
            message: "Unsupported MLIR line, skipped: #{body}",
            line: line_no,
            column: 1,
            op: 'parser'
          )
        end

        def normalize_body_line(body)
          text = body.to_s.strip
          return text if text.empty?

          loop do
            updated = strip_trailing_loc(text)
            updated = strip_trailing_attr_dict(updated)
            updated = strip_attr_dict_before_type(updated)
            break text if updated == text

            text = updated
          end
        end

        def strip_trailing_loc(text)
          text.sub(/\s+loc\([^()]*\)\s*\z/, '')
        end

        def strip_trailing_attr_dict(text)
          stripped = text.rstrip
          return stripped unless stripped.end_with?('}')

          close_idx = stripped.length - 1
          open_idx = matching_open_brace_index(stripped, close_idx)
          return stripped unless open_idx
          return stripped unless open_idx.positive? && stripped[open_idx - 1].match?(/\s/)

          stripped[0...open_idx].rstrip
        end

        def strip_attr_dict_before_type(text)
          stripped = text.rstrip
          colon_idx = stripped.rindex(':')
          return stripped unless colon_idx

          close_idx = stripped.rindex('}', colon_idx)
          return stripped unless close_idx

          open_idx = matching_open_brace_index(stripped, close_idx)
          return stripped unless open_idx
          return stripped unless open_idx.positive? && stripped[open_idx - 1].match?(/\s/)

          between = stripped[(close_idx + 1)...colon_idx]
          return stripped unless between && between.strip.empty?

          "#{stripped[0...open_idx].rstrip} #{stripped[colon_idx..].lstrip}".strip
        end

        def matching_open_brace_index(text, close_idx)
          stack = []
          in_quote = false
          escaped = false

          text.each_char.with_index do |ch, idx|
            break if idx > close_idx

            if in_quote
              if escaped
                escaped = false
              elsif ch == '\\'
                escaped = true
              elsif ch == '"'
                in_quote = false
              end
              next
            end

            case ch
            when '"'
              in_quote = true
            when '{'
              stack << idx
            when '}'
              open = stack.pop
              return open if idx == close_idx
            end
          end

          nil
        end

        def parse_hw_instance_line(body, value_map:, instances:, diagnostics:, line_no:)
          m = body.match(
            /\A(?:(?<lhs>#{SSA_TOKEN_PATTERN}(?:\s*,\s*#{SSA_TOKEN_PATTERN})*)\s*=\s*)?hw\.instance\s+"(?<inst_name>[^"]+)"\s+(?:sym\s+@[A-Za-z0-9_$.]+\s+)?@(?<module>[A-Za-z0-9_$.]+)(?:<(?<params>[^>]*)>)?\((?<inputs>.*)\)\s*->\s*\((?<outputs>.*)\)(?:\s*\{.*\})?\s*\z/
          )
          return false unless m

          lhs_values = parse_value_list(m[:lhs])
          input_conns = parse_instance_inputs(m[:inputs], value_map, diagnostics, line_no)
          output_conns, out_tokens = parse_instance_outputs(m[:outputs], lhs_values, diagnostics, line_no)
          return false if input_conns.nil? || output_conns.nil?
          parameters = parse_instance_parameters(m[:params], diagnostics, line_no)

          output_conns.each_with_index do |conn, idx|
            token = out_tokens[idx]
            value_map[token] = IR::Signal.new(name: conn.signal.to_s, width: infer_width_from_connection(conn, m[:outputs], idx))
          end

          instances << IR::Instance.new(
            name: m[:inst_name],
            module_name: m[:module],
            connections: input_conns + output_conns,
            parameters: parameters
          )
          true
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: "Failed parsing hw.instance at line #{line_no}: #{e.class}: #{e.message}",
            line: line_no,
            column: 1,
            op: 'hw.instance'
          )
          false
        end

        def parse_value_list(lhs)
          return [] if lhs.nil? || lhs.strip.empty?
          split_top_level_csv(lhs)
        end

        def parse_instance_parameters(raw_params, diagnostics, line_no)
          return {} if raw_params.nil? || raw_params.strip.empty?

          params = {}
          split_top_level_csv(raw_params).each do |entry|
            e = entry.strip
            if (m = e.match(/\A([A-Za-z0-9_$.]+)\s*:\s*i\d+\s*=\s*(-?\d+)\z/))
              params[m[1]] = m[2].to_i
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported hw.instance parameter syntax: #{e}",
                line: line_no,
                column: 1,
                op: 'hw.instance'
              )
            end
          end

          params
        end

        def parse_instance_inputs(raw_inputs, value_map, diagnostics, line_no)
          return [] if raw_inputs.nil? || raw_inputs.strip.empty?

          split_top_level_csv(raw_inputs).map.with_index do |entry, index|
            e = strip_trailing_attr_dict(entry.to_s.strip)
            if (named = e.match(/\A([A-Za-z0-9_$.]+)\s*:\s*(#{SSA_TOKEN_PATTERN})\s*:\s*i(\d+)\z/))
              IR::PortConnection.new(
                port_name: named[1],
                signal: lookup_value(value_map, named[2], width: named[3].to_i),
                direction: :in
              )
            elsif (unnamed = e.match(/\A(#{SSA_TOKEN_PATTERN})\s*:\s*i(\d+)\z/))
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unnamed hw.instance input port at argument #{index + 1}; using arg#{index}",
                line: line_no,
                column: 1,
                op: 'hw.instance'
              )
              IR::PortConnection.new(
                port_name: "arg#{index}",
                signal: lookup_value(value_map, unnamed[1], width: unnamed[2].to_i),
                direction: :in
              )
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported hw.instance input syntax: #{e}",
                line: line_no,
                column: 1,
                op: 'hw.instance'
              )
              return nil
            end
          end
        end

        def parse_instance_outputs(raw_outputs, lhs_values, diagnostics, line_no)
          return [[], []] if raw_outputs.nil? || raw_outputs.strip.empty?

          entries = split_top_level_csv(raw_outputs).reject(&:empty?)
          lhs_tokens = if lhs_values.empty?
                         entries.each_index.map { |i| "%inst_out#{i}" }
                       else
                         lhs_values
                       end

          if lhs_tokens.length != entries.length
            diagnostics << Diagnostic.new(
              severity: :warning,
              message: "hw.instance output/result count mismatch: #{lhs_tokens.length} values for #{entries.length} outputs",
              line: line_no,
              column: 1,
              op: 'hw.instance'
            )
            return nil
          end

          conns = entries.map.with_index do |entry, index|
            token = strip_trailing_attr_dict(entry.to_s.strip)
            if (named = token.match(/\A([A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/))
              IR::PortConnection.new(
                port_name: named[1],
                signal: lhs_tokens[index].sub('%', ''),
                direction: :out
              )
            elsif token.match?(/\Ai\d+\z/)
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unnamed hw.instance output port at result #{index + 1}; using out#{index}",
                line: line_no,
                column: 1,
                op: 'hw.instance'
              )
              IR::PortConnection.new(
                port_name: "out#{index}",
                signal: lhs_tokens[index].sub('%', ''),
                direction: :out
              )
            else
              diagnostics << Diagnostic.new(
                severity: :warning,
                message: "Unsupported hw.instance output syntax: #{entry}",
                line: line_no,
                column: 1,
                op: 'hw.instance'
              )
              return nil
            end
          end

          [conns, lhs_tokens]
        end

        def infer_width_from_connection(conn, raw_outputs, idx)
          entries = split_top_level_csv(raw_outputs.to_s).reject(&:empty?)
          entry = strip_trailing_attr_dict(entries[idx].to_s.strip)
          if (m = entry.match(/\A(?:[A-Za-z0-9_$.]+\s*:\s*)?i(\d+)\z/))
            m[1].to_i
          else
            1
          end
        end

        def split_top_level_csv(raw)
          text = raw.to_s
          return [] if text.strip.empty?

          parts = []
          token = +''
          brace_depth = 0
          paren_depth = 0
          angle_depth = 0
          bracket_depth = 0
          in_quote = false
          escaped = false

          text.each_char do |ch|
            if in_quote
              token << ch
              if escaped
                escaped = false
              elsif ch == '\\'
                escaped = true
              elsif ch == '"'
                in_quote = false
              end
              next
            end

            case ch
            when '"'
              in_quote = true
              token << ch
            when '{'
              brace_depth += 1
              token << ch
            when '}'
              brace_depth = [brace_depth - 1, 0].max
              token << ch
            when '('
              paren_depth += 1
              token << ch
            when ')'
              paren_depth = [paren_depth - 1, 0].max
              token << ch
            when '<'
              angle_depth += 1
              token << ch
            when '>'
              angle_depth = [angle_depth - 1, 0].max
              token << ch
            when '['
              bracket_depth += 1
              token << ch
            when ']'
              bracket_depth = [bracket_depth - 1, 0].max
              token << ch
            when ','
              if brace_depth.zero? && paren_depth.zero? && angle_depth.zero? && bracket_depth.zero?
                parts << token.strip
                token = +''
              else
                token << ch
              end
            else
              token << ch
            end
          end

          stripped = token.strip
          parts << stripped unless stripped.empty?
          parts
        end

        def parse_seq_compreg_line(body, value_map:, regs:, processes:, diagnostics:, line_no:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*seq\.compreg\s+(.+)\s*:\s*i(\d+)\z/)
          return false unless m

          out_token = m[1]
          args = m[2].strip
          width = m[3].to_i

          # Drop optional trailing op attributes (for example, {sv.namehint = "q"}).
          args = strip_trailing_attr_dict(args)

          parsed = if (plain = args.match(/\A(#{SSA_TOKEN_PATTERN})\s*,\s*(#{SSA_TOKEN_PATTERN})\s*\z/))
                     {
                       data: plain[1],
                       clock: plain[2],
                       reset: nil,
                       reset_value: nil
                     }
                   elsif (with_reset = args.match(/\A(#{SSA_TOKEN_PATTERN})\s*,\s*(#{SSA_TOKEN_PATTERN})\s+reset\s+(#{SSA_TOKEN_PATTERN})\s*,\s*(#{SSA_TOKEN_PATTERN}|-?\d+|true|false)\s*\z/))
                     {
                       data: with_reset[1],
                       clock: with_reset[2],
                       reset: with_reset[3],
                       reset_value: with_reset[4]
                     }
                   end

          return false unless parsed

          reg_name = out_token.sub('%', '')
          reset_expr = parsed[:reset_value] ? lookup_value(value_map, parsed[:reset_value], width: width) : nil

          reg_reset = case reset_expr
                      when IR::Literal then reset_expr.value
                      else nil
                      end

          regs << IR::Reg.new(name: reg_name, width: width, reset_value: reg_reset)

          data_expr = lookup_value(value_map, parsed[:data], width: width)
          seq_expr = if parsed[:reset]
                       IR::Mux.new(
                         condition: lookup_value(value_map, parsed[:reset], width: 1),
                         when_true: reset_expr || IR::Literal.new(value: 0, width: width),
                         when_false: data_expr,
                         width: width
                       )
                     else
                       data_expr
                     end

          seq_stmt = IR::SeqAssign.new(target: reg_name, expr: seq_expr)
          processes << IR::Process.new(
            name: :seq_logic,
            statements: [seq_stmt],
            clocked: true,
            clock: parsed[:clock].sub('%', '')
          )
          value_map[out_token] = IR::Signal.new(name: reg_name, width: width)
          true
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: "Failed parsing seq.compreg at line #{line_no}: #{e.class}: #{e.message}",
            line: line_no,
            column: 1,
            op: 'seq.compreg'
          )
          false
        end

        def lookup_value(value_map, token, width: 1)
          token = normalize_value_token(token)
          return value_map[token] if value_map.key?(token)
          return IR::Literal.new(value: 1, width: width) if token == 'true'
          return IR::Literal.new(value: 0, width: width) if token == 'false'
          return IR::Signal.new(name: token.sub('%', ''), width: width) if token.start_with?('%')

          IR::Literal.new(value: token.to_i, width: width)
        end

        def parse_array_type(text)
          match = text.to_s.match(ARRAY_TYPE_PATTERN)
          raise ArgumentError, "Invalid hw.array type: #{text}" unless match

          len = match[:len].to_i
          element_width = match[:width].to_i
          { len: len, element_width: element_width, total_width: len * element_width }
        end

        def array_type_from_string(text)
          return parse_array_type(text) if text.to_s.match?(ARRAY_TYPE_PATTERN)

          match = text.to_s.match(LLHD_ARRAY_TYPE_PATTERN)
          return nil unless match

          len = match[:len].to_i
          element_width = match[:width].to_i
          { len: len, element_width: element_width, total_width: len * element_width }
        end

        def integer_type_width(text)
          match = text.to_s.strip.match(/\Ai(\d+)\z/)
          return nil unless match

          match[1].to_i
        end

        def array_elements_from_value(value, length:, element_width:)
          case value
          when ArrayValue
            elems = value.elements.first(length)
            if elems.length < length
              elems + Array.new(length - elems.length) { IR::Literal.new(value: 0, width: element_width) }
            else
              elems
            end
          else
            base = ensure_expr_with_width(value, width: length * element_width)
            Array.new(length) do |idx|
              low = idx * element_width
              IR::Slice.new(base: base, range: (low..(low + element_width - 1)), width: element_width)
            end
          end
        end

        def ensure_expr_with_width(value, width:)
          return value if value.is_a?(IR::Expr)

          case value
          when String, Symbol
            IR::Signal.new(name: value.to_s, width: width)
          else
            IR::Literal.new(value: 0, width: width)
          end
        end

        def select_array_element(elements:, index_expr:, element_width:)
          return IR::Literal.new(value: 0, width: element_width) if elements.empty?

          if index_expr.is_a?(IR::Literal)
            idx = [[index_expr.value.to_i, 0].max, elements.length - 1].min
            return elements[idx]
          end

          default_expr = elements[0]
          entries = elements.each_with_index.map { |element, idx| [idx, element] }
          index_width = [index_expr.width.to_i, 1].max
          build_index_select_tree(
            entries: entries,
            index_expr: index_expr,
            index_width: index_width,
            default_expr: default_expr,
            element_width: element_width
          )
        end

        def build_index_select_tree(entries:, index_expr:, index_width:, default_expr:, element_width:)
          return default_expr if entries.empty?

          if entries.length == 1
            idx, element_expr = entries.first
            cond = IR::BinaryOp.new(
              op: :==,
              left: index_expr,
              right: IR::Literal.new(value: idx, width: index_width),
              width: 1
            )
            return IR::Mux.new(
              condition: cond,
              when_true: element_expr,
              when_false: default_expr,
              width: element_width
            )
          end

          mid = entries.length / 2
          left_entries = entries[0...mid]
          right_entries = entries[mid..]
          pivot = right_entries.first.first

          left_expr = build_index_select_tree(
            entries: left_entries,
            index_expr: index_expr,
            index_width: index_width,
            default_expr: default_expr,
            element_width: element_width
          )
          right_expr = build_index_select_tree(
            entries: right_entries,
            index_expr: index_expr,
            index_width: index_width,
            default_expr: default_expr,
            element_width: element_width
          )
          cond = IR::BinaryOp.new(
            op: :<,
            left: index_expr,
            right: IR::Literal.new(value: pivot, width: index_width),
            width: 1
          )
          IR::Mux.new(
            condition: cond,
            when_true: left_expr,
            when_false: right_expr,
            width: element_width
          )
        end

        def build_parity_reduce(source:, in_width:)
          return source if in_width == 1

          bits = Array.new(in_width) do |idx|
            IR::Slice.new(base: source, range: (idx..idx), width: 1)
          end
          fold_balanced_binary(bits, op: :^, width: 1)
        end

        def fold_balanced_binary(exprs, op:, width:)
          layer = Array(exprs)
          return IR::Literal.new(value: 0, width: width) if layer.empty?

          while layer.length > 1
            next_layer = []
            layer.each_slice(2) do |lhs, rhs|
              next_layer << if rhs
                              IR::BinaryOp.new(op: op, left: lhs, right: rhs, width: width)
                            else
                              lhs
                            end
            end
            layer = next_layer
          end
          layer.first
        end

        def normalize_value_token(token)
          text = token.to_s.strip
          return text if text.empty?

          loop do
            updated = strip_trailing_loc(text)
            updated = strip_trailing_attr_dict(updated)
            break text if updated == text

            text = updated.strip
          end
        end

        def declared_signal_names(input_ports, output_ports, nets, regs)
          names = Set.new
          Array(input_ports).each { |port| names << port.name.to_s }
          Array(output_ports).each { |port| names << port.name.to_s }
          Array(nets).each { |net| names << net.name.to_s }
          Array(regs).each { |reg| names << reg.name.to_s }
          names
        end

        def resolve_forward_refs_in_assigns(assigns, value_map:, declared_names:)
          Array(assigns).map do |assign|
            IR::Assign.new(
              target: assign.target,
              expr: resolve_forward_expr(
                assign.expr,
                value_map: value_map,
                declared_names: declared_names
              )
            )
          end
        end

        def resolve_forward_refs_in_processes(processes, value_map:, declared_names:)
          Array(processes).map do |process|
            statements = Array(process.statements).map do |stmt|
              resolve_forward_statement(
                stmt,
                value_map: value_map,
                declared_names: declared_names
              )
            end

            IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: process.clocked,
              clock: process.clock,
              sensitivity_list: process.sensitivity_list
            )
          end
        end

        def resolve_forward_refs_in_instances(instances, value_map:, declared_names:)
          Array(instances).map do |inst|
            connections = Array(inst.connections).map do |conn|
              signal = conn.signal
              resolved_signal = if signal.is_a?(IR::Expr)
                                  resolve_forward_expr(signal, value_map: value_map, declared_names: declared_names)
                                else
                                  signal
                                end
              IR::PortConnection.new(
                port_name: conn.port_name,
                signal: resolved_signal,
                direction: conn.direction
              )
            end

            IR::Instance.new(
              name: inst.name,
              module_name: inst.module_name,
              connections: connections,
              parameters: inst.parameters
            )
          end
        end

        def resolve_forward_statement(stmt, value_map:, declared_names:)
          case stmt
          when IR::SeqAssign
            IR::SeqAssign.new(
              target: stmt.target,
              expr: resolve_forward_expr(stmt.expr, value_map: value_map, declared_names: declared_names)
            )
          when IR::If
            IR::If.new(
              condition: resolve_forward_expr(stmt.condition, value_map: value_map, declared_names: declared_names),
              then_statements: Array(stmt.then_statements).map do |inner|
                resolve_forward_statement(inner, value_map: value_map, declared_names: declared_names)
              end,
              else_statements: Array(stmt.else_statements).map do |inner|
                resolve_forward_statement(inner, value_map: value_map, declared_names: declared_names)
              end
            )
          else
            stmt
          end
        end

        def resolve_forward_expr(expr, value_map:, declared_names:, memo: {}, visiting: Set.new)
          case expr
          when IR::Signal
            name = expr.name.to_s
            return expr if declared_names.include?(name)

            key = "%#{name}"
            candidate = value_map[key]
            return expr unless candidate
            return expr if candidate.equal?(expr)
            return expr if visiting.include?(key)
            return memo[key] if memo.key?(key)

            visiting << key
            resolved = resolve_forward_expr(
              candidate,
              value_map: value_map,
              declared_names: declared_names,
              memo: memo,
              visiting: visiting
            )
            visiting.delete(key)
            memo[key] = resolved
            resolved
          when IR::Literal
            expr
          when IR::UnaryOp
            IR::UnaryOp.new(
              op: expr.op,
              operand: resolve_forward_expr(
                expr.operand,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::BinaryOp
            IR::BinaryOp.new(
              op: expr.op,
              left: resolve_forward_expr(
                expr.left,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              right: resolve_forward_expr(
                expr.right,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::Mux
            IR::Mux.new(
              condition: resolve_forward_expr(
                expr.condition,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              when_true: resolve_forward_expr(
                expr.when_true,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              when_false: resolve_forward_expr(
                expr.when_false,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::Slice
            IR::Slice.new(
              base: resolve_forward_expr(
                expr.base,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              range: expr.range,
              width: expr.width
            )
          when IR::Concat
            IR::Concat.new(
              parts: Array(expr.parts).map do |part|
                resolve_forward_expr(
                  part,
                  value_map: value_map,
                  declared_names: declared_names,
                  memo: memo,
                  visiting: visiting
                )
              end,
              width: expr.width
            )
          when IR::Resize
            IR::Resize.new(
              expr: resolve_forward_expr(
                expr.expr,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::Case
            IR::Case.new(
              selector: resolve_forward_expr(
                expr.selector,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              cases: Array(expr.cases).map do |key, value|
                [
                  key,
                  resolve_forward_expr(
                    value,
                    value_map: value_map,
                    declared_names: declared_names,
                    memo: memo,
                    visiting: visiting
                  )
                ]
              end.to_h,
              default: resolve_forward_expr(
                expr.default,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::MemoryRead
            IR::MemoryRead.new(
              memory: expr.memory,
              addr: resolve_forward_expr(
                expr.addr,
                value_map: value_map,
                declared_names: declared_names,
                memo: memo,
                visiting: visiting
              ),
              width: expr.width
            )
          else
            expr
          end
        rescue SystemStackError
          expr
        end

        def enforce_dependency_closure(modules:, module_spans:, diagnostics:, strict:, top:, extern_modules:)
          module_index = modules.each_with_object({}) { |mod, acc| acc[mod.name.to_s] = mod }
          imported_names = module_index.keys.to_set
          extern_names = Set.new(Array(extern_modules).map(&:to_s))

          roots = if top.to_s.strip.empty?
                    module_index.keys
                  else
                    [top.to_s]
                  end

          roots.each do |root|
            next if module_index.key?(root)

            diagnostics << Diagnostic.new(
              severity: :error,
              message: "Top module '#{root}' not found in CIRCT package",
              line: nil,
              column: nil,
              op: 'import.closure'
            )
          end

          roots.each do |root|
            next unless module_index.key?(root)

            reachable_module_names(root, module_index).each do |mod_name|
              mod = module_index[mod_name]
              Array(mod.instances).each do |inst|
                target = inst.module_name.to_s
                next if imported_names.include?(target)
                next if extern_names.include?(target)

                diagnostics << Diagnostic.new(
                  severity: strict ? :error : :warning,
                  message: "Unresolved instance target @#{target} referenced by @#{mod_name}",
                  line: module_spans[mod_name]&.dig(:start_line),
                  column: 1,
                  op: 'import.closure'
                )
              end
            end
          end
        end

        def reachable_module_names(root_name, module_index)
          seen = Set.new
          queue = [root_name.to_s]

          until queue.empty?
            current = queue.shift
            next if seen.include?(current)
            next unless module_index.key?(current)

            seen << current
            Array(module_index[current].instances).each do |inst|
              queue << inst.module_name.to_s
            end
          end

          seen.to_a
        end

        def build_module_diagnostics(modules:, diagnostics:, module_spans:)
          by_module = modules.each_with_object({}) { |mod, acc| acc[mod.name.to_s] = [] }
          diagnostics.each do |diag|
            module_name = module_for_line(diag.line, module_spans)
            next unless module_name

            by_module[module_name] << diag
          end
          by_module
        end

        def module_for_line(line, module_spans)
          return nil unless line

          module_spans.each do |name, span|
            next if span.nil?
            start_line = span[:start_line].to_i
            end_line = span[:end_line].to_i
            return name if line >= start_line && line <= end_line
          end

          nil
        end
      end
    end
  end
end
