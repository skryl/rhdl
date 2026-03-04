# frozen_string_literal: true

module RHDL
  module Codegen
    module CIRCT
      Diagnostic = Struct.new(:severity, :message, :line, :column, :op, keyword_init: true)

      class ImportResult
        attr_reader :modules, :diagnostics

        def initialize(modules:, diagnostics: [])
          @modules = modules
          @diagnostics = diagnostics
        end

        def success?
          @diagnostics.none? { |d| d.severity.to_s == 'error' }
        end
      end

      module Import
        module_function

        def from_mlir(text)
          diagnostics = []
          modules = []
          lines = text.lines
          idx = 0

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
            processes = []
            instances = []

            idx = header[:next_idx]
            while idx < lines.length
              body = lines[idx].strip
              break if body == '}'

              if body.include?('hw.instance')
                combined, consumed = collect_multiline_instance(lines, idx)
                parse_body_line(
                  combined,
                  value_map: value_map,
                  assigns: assigns,
                  regs: regs,
                  processes: processes,
                  instances: instances,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1
                )
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
                  processes: processes,
                  instances: instances,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1
                )
                idx += consumed
                next
              end

              parse_body_line(
                body,
                value_map: value_map,
                assigns: assigns,
                regs: regs,
                processes: processes,
                instances: instances,
                output_ports: output_ports,
                diagnostics: diagnostics,
                line_no: idx + 1
              )
              idx += 1
            end

            if idx >= lines.length || lines[idx].strip != '}'
              diagnostics << Diagnostic.new(
                severity: :error,
                message: "Unterminated hw.module @#{mod_name}",
                line: idx + 1,
                column: 1,
                op: 'hw.module'
              )
            end

            modules << IR::ModuleOp.new(
              name: mod_name,
              ports: input_ports + output_ports,
              nets: [],
              regs: regs,
              assigns: assigns,
              processes: processes,
              instances: instances,
              memories: [],
              write_ports: [],
              sync_read_ports: [],
              parameters: module_parameters
            )

            idx += 1
          end

          ImportResult.new(modules: modules, diagnostics: diagnostics)
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
          match = header.match(/\Ahw\.module\s+@(?<name>[A-Za-z0-9_$.]+)(?:<(?<params>.*?)>)?\s*\((?<inputs>.*?)\)\s*(?:->\s*\((?<outputs>.*?)\))?\s*\{\s*\z/)
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

        def parse_body_line(body, value_map:, assigns:, regs:, processes:, instances:, output_ports:, diagnostics:, line_no:)
          body = normalize_body_line(body)
          return if body.empty? || body.start_with?('//')

          if (m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*hw\.constant\s+(-?\d+)\s*:\s*i(\d+)\z/))
            value_map[m[1]] = IR::Literal.new(value: m[2].to_i, width: m[3].to_i)
            return
          end

          if (m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*comb\.icmp\s+(\w+)\s+(%[A-Za-z0-9_$.]+),\s*(%[A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/))
            pred_map = {
              'eq' => :==,
              'ne' => :'!=',
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

            in_width = m[5].to_i
            value_map[m[1]] = IR::BinaryOp.new(
              op: pred_map.fetch(pred, :==),
              left: lookup_value(value_map, m[3], width: in_width),
              right: lookup_value(value_map, m[4], width: in_width),
              width: 1
            )
            return
          end

          if (m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*comb\.(add|sub|mul|divu|divs|modu|mods|and|or|xor|shl|shr_u|shr_s|shru|shrs)\s+(%[A-Za-z0-9_$.]+),\s*(%[A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/))
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
            value_map[m[1]] = IR::BinaryOp.new(
              op: op_map[m[2]] || m[2].to_sym,
              left: lookup_value(value_map, m[3]),
              right: lookup_value(value_map, m[4]),
              width: m[5].to_i
            )
            return
          end

          if (m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*comb\.mux\s+(%[A-Za-z0-9_$.]+),\s*(%[A-Za-z0-9_$.]+),\s*(%[A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/))
            value_map[m[1]] = IR::Mux.new(
              condition: lookup_value(value_map, m[2], width: 1),
              when_true: lookup_value(value_map, m[3]),
              when_false: lookup_value(value_map, m[4]),
              width: m[5].to_i
            )
            return
          end

          if (m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*comb\.extract\s+(%[A-Za-z0-9_$.]+)\s+from\s+(\d+)\s*:\s*\(i(\d+)\)\s*->\s*i(\d+)\z/))
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

          if (m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*comb\.concat\s+(.+)\s*:\s*(.+)\z/))
            tokens = split_top_level_csv(m[2])
            type_tokens = split_top_level_csv(m[3])
            widths = type_tokens.map { |t| t[/\Ai(\d+)\z/, 1] }.compact.map(&:to_i)
            if widths.length != tokens.length
              diagnostics << Diagnostic.new(
                severity: :warning,
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

          if body.match?(/\A%[A-Za-z0-9_$.]+\s*=\s*seq\.compreg\b/)
            return if parse_seq_compreg_line(
              body,
              value_map: value_map,
              regs: regs,
              processes: processes,
              diagnostics: diagnostics,
              line_no: line_no
            )

            diagnostics << Diagnostic.new(
              severity: :warning,
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
            severity: :warning,
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
            /\A(?:(?<lhs>%[A-Za-z0-9_$.]+(?:\s*,\s*%[A-Za-z0-9_$.]+)*)\s*=\s*)?hw\.instance\s+"(?<inst_name>[^"]+)"\s+(?:sym\s+@[A-Za-z0-9_$.]+\s+)?@(?<module>[A-Za-z0-9_$.]+)(?:<(?<params>[^>]*)>)?\((?<inputs>.*)\)\s*->\s*\((?<outputs>.*)\)(?:\s*\{.*\})?\s*\z/
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
            if (named = e.match(/\A([A-Za-z0-9_$.]+)\s*:\s*(%[A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/))
              IR::PortConnection.new(
                port_name: named[1],
                signal: lookup_value(value_map, named[2], width: named[3].to_i),
                direction: :in
              )
            elsif (unnamed = e.match(/\A(%[A-Za-z0-9_$.]+)\s*:\s*i(\d+)\z/))
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
          m = body.match(/\A(%[A-Za-z0-9_$.]+)\s*=\s*seq\.compreg\s+(.+)\s*:\s*i(\d+)\z/)
          return false unless m

          out_token = m[1]
          args = m[2].strip
          width = m[3].to_i

          # Drop optional trailing op attributes (for example, {sv.namehint = "q"}).
          args = strip_trailing_attr_dict(args)

          parsed = if (plain = args.match(/\A(%[A-Za-z0-9_$.]+)\s*,\s*(%[A-Za-z0-9_$.]+)\s*\z/))
                     {
                       data: plain[1],
                       clock: plain[2],
                       reset: nil,
                       reset_value: nil
                     }
                   elsif (with_reset = args.match(/\A(%[A-Za-z0-9_$.]+)\s*,\s*(%[A-Za-z0-9_$.]+)\s+reset\s+(%[A-Za-z0-9_$.]+)\s*,\s*(%[A-Za-z0-9_$.]+|-?\d+)\s*\z/))
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
          return value_map[token] if value_map.key?(token)
          return IR::Signal.new(name: token.sub('%', ''), width: width) if token.start_with?('%')

          IR::Literal.new(value: token.to_i, width: width)
        end
      end
    end
  end
end
