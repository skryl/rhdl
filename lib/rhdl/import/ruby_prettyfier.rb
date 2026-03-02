# frozen_string_literal: true

module RHDL
  module Import
    class RubyPrettyfier
      class << self
        MAX_EXPRESSION_FORMAT_DEPTH = 96

        INFIX_OPERATOR_GROUPS = [
          %w[||],
          %w[&&],
          %w[|],
          %w[^],
          %w[&],
          %w[== != <= >= < >],
          ["<<", "< <", ">>", "> >"],
          ["+", "-"],
          ["*", "/", "%"]
        ].freeze

        def format(source)
          text = normalize_newlines(source.to_s)
          text = format_inline_keyword_hash_arguments(text)
          text = format_assign_statements(text)
          text = strip_trailing_whitespace(text)
          text = collapse_blank_runs(text)
          text = ensure_terminal_newline(text)
          text
        end

        private

        def normalize_newlines(text)
          text.gsub("\r\n", "\n")
        end

        def format_inline_keyword_hash_arguments(text)
          lines = text.split("\n", -1)
          formatted = lines.map { |line| format_inline_keyword_hash_line(line) }
          formatted.join("\n")
        end

        def format_assign_statements(text)
          lines = text.split("\n", -1)
          output = []
          index = 0

          while index < lines.length
            line = lines[index]
            multiline = format_multiline_continuous_assign(lines, index: index)
            unless multiline.nil?
              output.concat(multiline.fetch(:lines))
              index = multiline.fetch(:next_index)
              next
            end

            rewritten = format_assign_statement_line(line)
            if rewritten.nil?
              output << line
            else
              output.concat(rewritten)
            end
            index += 1
          end

          output.join("\n")
        end

        def format_multiline_continuous_assign(lines, index:)
          line = lines[index]
          stripped = line.strip
          match = stripped.match(/\Aassign\s+:([A-Za-z_]\w*),\s*(.*)\z/)
          return nil if match.nil?

          indent = line[/\A\s*/] || ""
          target = match[1]
          expression_fragments = []
          first_fragment = match[2].to_s.strip
          expression_fragments << first_fragment unless first_fragment.empty?

          cursor = index + 1
          while cursor < lines.length
            candidate = lines[cursor]
            break if candidate.strip.empty?
            break if top_level_statement_line?(candidate, indent: indent)

            expression_fragments << candidate.strip
            cursor += 1
          end

          return nil if expression_fragments.empty?

          expression = expression_fragments.join(" ").strip
          return nil if expression.empty?

          {
            lines: format_continuous_assign_lines(
              indent: indent,
              target: target,
              expression: expression
            ),
            next_index: cursor
          }
        rescue StandardError
          nil
        end

        def top_level_statement_line?(line, indent:)
          line_indent = line[/\A\s*/] || ""
          return true if line_indent.length < indent.length
          return false unless line_indent.length == indent.length

          stripped = line[indent.length..].to_s.strip
          return false if stripped.empty?

          stripped.start_with?(
            "assign ",
            "assign(",
            "signal ",
            "input ",
            "output ",
            "process ",
            "instance ",
            "for_loop ",
            "if_stmt",
            "case_stmt",
            "else_block",
            "elsif_block",
            "end",
            "#"
          )
        end

        def format_assign_statement_line(line)
          stripped = line.strip
          return nil unless stripped.start_with?("assign")

          indent = line[/\A\s*/] || ""

          if (match = stripped.match(/\Aassign\s+:([A-Za-z_]\w*),\s*(.+)\z/))
            target = match[1]
            expression = match[2].to_s.strip
            return nil if expression.empty?

            return format_continuous_assign_lines(
              indent: indent,
              target: target,
              expression: expression
            )
          end

          return nil unless stripped.start_with?("assign(") && stripped.end_with?(")")

          inner = stripped[7...-1].to_s.strip
          return nil if inner.empty?

          args = split_top_level_commas(inner)
          return nil if args.length < 2

          target = args[0].to_s.strip
          value = args[1].to_s.strip
          trailing = args[2..] || []
          return nil if target.empty? || value.empty?

          format_process_assign_lines(
            indent: indent,
            target: target,
            value: value,
            trailing: trailing
          )
        rescue StandardError
          nil
        end

        def format_continuous_assign_lines(indent:, target:, expression:)
          lines = []
          lines << "#{indent}assign :#{target},"
          expression_lines = format_expression_lines(expression)
          expression_lines.each do |entry|
            lines << "#{indent}  #{entry}"
          end
          lines
        end

        def format_process_assign_lines(indent:, target:, value:, trailing:)
          lines = []
          lines << "#{indent}assign("
          lines << "#{indent}  #{target},"

          value_lines = format_expression_lines(value)
          value_lines.each_with_index do |entry, index|
            suffix = if trailing.empty?
                       ""
                     elsif index == value_lines.length - 1
                       ","
                     else
                       ""
                     end
            lines << "#{indent}  #{entry}#{suffix}"
          end

          trailing.each_with_index do |entry, index|
            suffix = index == trailing.length - 1 ? "" : ","
            lines << "#{indent}  #{entry.to_s.strip}#{suffix}"
          end

          lines << "#{indent})"
          lines
        end

        def format_expression_lines(expression, depth: 0)
          text = expression.to_s.strip
          return [text] if text.empty?
          return format_expression_lines_at_depth_limit(text) if depth >= MAX_EXPRESSION_FORMAT_DEPTH

          call = decompose_terminal_call(text)
          unless call.nil?
            callee = call.fetch(:callee)
            args = call.fetch(:args)

            multiline = text.length > 96 || args.any? { |arg| arg.length > 48 || complex_expression_fragment?(arg) }
            if multiline
              lines = format_call_callee_lines(callee, depth: depth)
              args.each_with_index do |arg, arg_index|
                nested =
                  format_keyword_hash_argument_lines(arg) ||
                  format_expression_lines(arg, depth: depth + 1)
                nested.each_with_index do |nested_line, nested_index|
                  suffix = if arg_index == args.length - 1 || nested_index != nested.length - 1
                             ""
                           else
                             ","
                           end
                  lines << "  #{nested_line}#{suffix}"
                end
              end
              lines << ")"
              return lines
            end
          end

          parenthesized_lines = format_parenthesized_expression_lines(text, depth: depth)
          return parenthesized_lines unless parenthesized_lines.nil?

          unary_lines = format_unary_expression_lines(text, depth: depth)
          return unary_lines unless unary_lines.nil?

          infix_lines = format_infix_expression_lines(text, depth: depth)
          return infix_lines unless infix_lines.nil?

          [text]
        end

        def format_parenthesized_expression_lines(text, depth:)
          inner = unwrap_outer_parentheses(text)
          return nil if inner.nil?

          inner_lines = format_expression_lines(inner, depth: depth + 1)
          multiline = text.length > 80 || inner_lines.length > 1 || complex_expression_fragment?(inner)
          return nil unless multiline

          lines = []
          lines << "("
          inner_lines.each do |line|
            lines << "  #{line}"
          end
          lines << ")"
          lines
        end

        def format_expression_lines_at_depth_limit(text)
          call = decompose_terminal_call(text)
          unless call.nil?
            callee = call.fetch(:callee)
            args = call.fetch(:args)

            if text.length > 96 || args.length > 1 || args.any? { |arg| arg.length > 64 }
              lines = format_call_callee_lines(callee, depth: MAX_EXPRESSION_FORMAT_DEPTH)
              args.each_with_index do |arg, index|
                suffix = index == args.length - 1 ? "" : ","
                lines << "  #{arg.to_s.strip}#{suffix}"
              end
              lines << ")"
              return lines
            end
          end

          inner = unwrap_outer_parentheses(text)
          unless inner.nil?
            split = split_top_level_infix(inner)
            unless split.nil?
              return [
                "(",
                "  #{split.fetch(:left)} #{split.fetch(:op)}",
                "  #{split.fetch(:right)}",
                ")"
              ]
            end
          end

          [text]
        end

        def format_unary_expression_lines(text, depth:)
          original = text.to_s.strip
          token = original
          if token.start_with?("(") && token.end_with?(")") && matching_open_paren_for_terminal_close(token) == 0
            token = token[1...-1].to_s.strip
          end
          return nil if token.length < 3

          operator = token[0]
          return nil unless %w[~ ! + -].include?(operator)

          operand = token[1..].to_s.strip
          return nil unless operand.start_with?("(") && operand.end_with?(")")
          return nil unless matching_open_paren_for_terminal_close(operand) == 0

          inner = operand[1...-1].to_s.strip
          inner_lines = format_expression_lines(inner, depth: depth + 1)
          multiline = original.length > 80 || inner_lines.length > 1 || complex_expression_fragment?(inner)
          return nil unless multiline

          lines = []
          lines << "#{operator}("
          inner_lines.each do |line|
            lines << "  #{line}"
          end
          lines << ")"
          lines
        end

        def format_call_callee_lines(callee, depth:)
          receiver_call = split_terminal_receiver_method(callee)
          return ["#{callee}("] if receiver_call.nil?

          receiver_lines = format_expression_lines(receiver_call.fetch(:receiver), depth: depth + 1)
          lines = receiver_lines.dup
          lines[-1] = "#{lines[-1]}.#{receiver_call.fetch(:method)}("
          lines
        end

        def split_terminal_receiver_method(callee)
          token = callee.to_s.strip
          return nil if token.empty?

          state = scanner_initial_state
          last_dot = nil
          index = 0

          while index < token.length
            char = token[index]
            scanner_update_state_before(char, state)
            if char == "." && top_level_token_context?(state) && state[:brace].zero? && state[:bracket].zero? && state[:paren].zero?
              last_dot = index
            end
            scanner_update_state_after(char, state)
            index += 1
          end

          return nil if last_dot.nil?

          receiver = token[0...last_dot].to_s.strip
          method = token[(last_dot + 1)..].to_s.strip
          return nil if receiver.empty? || method.empty?
          return nil unless method.match?(/\A[a-zA-Z_]\w*[!?]?\z/)

          {
            receiver: receiver,
            method: method
          }
        end

        def format_infix_expression_lines(text, depth:)
          token = text.to_s.strip
          wrapped = false
          inner = unwrap_outer_parentheses(token)
          if inner.nil?
            inner = token
          else
            wrapped = true
          end

          split = split_top_level_infix(inner)
          return nil if split.nil?

          left = split.fetch(:left)
          op = split.fetch(:op)
          right = split.fetch(:right)

          left_lines = format_expression_lines(left, depth: depth + 1)
          right_lines = format_expression_lines(right, depth: depth + 1)
          multiline = text.length > 80 ||
            left_lines.length > 1 ||
            right_lines.length > 1 ||
            complex_expression_fragment?(left) ||
            complex_expression_fragment?(right)
          return nil unless multiline

          lines = []
          lines << "(" if wrapped
          left_lines.each_with_index do |line, index|
            suffix = index == left_lines.length - 1 ? " #{op}" : ""
            lines << "  #{line}#{suffix}"
          end
          right_lines.each do |line|
            lines << "  #{line}"
          end
          lines << ")" if wrapped
          lines
        end

        def unwrap_outer_parentheses(text)
          token = text.to_s.strip
          return nil unless token.start_with?("(") && token.end_with?(")")
          return nil unless matching_open_paren_for_terminal_close(token) == 0

          token[1...-1].to_s.strip
        end

        def split_top_level_infix(text)
          INFIX_OPERATOR_GROUPS.each do |operators|
            found = find_top_level_operator(text, operators)
            next if found.nil?

            index = found.fetch(:index)
            op = found.fetch(:op)
            left = text[0...index].to_s.strip
            right = text[(index + op.length)..].to_s.strip
            next if left.empty? || right.empty?

            return {
              left: left,
              op: op,
              right: right
            }
          end

          nil
        end

        def find_top_level_operator(text, operators)
          token = text.to_s
          return nil if token.empty?

          state = scanner_initial_state
          last_match = nil
          index = 0
          sorted_ops = Array(operators).sort_by { |op| -op.length }

          while index < token.length
            char = token[index]
            scanner_update_state_before(char, state)
            if top_level_token_context?(state) && state[:brace].zero? && state[:bracket].zero? && state[:paren].zero?
              sorted_ops.each do |op|
                next unless token[index, op.length] == op
                next if unary_operator_at?(token, index: index, op: op)
                next if relational_arrow_at?(token, index: index, op: op)
                next if shift_operator_at?(token, index: index, op: op)

                last_match = { index: index, op: op }
                break
              end
            end
            scanner_update_state_after(char, state)
            index += 1
          end

          last_match
        end

        def unary_operator_at?(text, index:, op:)
          return false unless op == "+" || op == "-"

          previous = previous_non_space_char(text, index: index)
          return true if previous.nil?

          ["(", "[", "{", ",", "?", ":", "=", "!", "~", "+", "-", "*", "/", "%", "^", "&", "|", "<", ">"]
            .include?(previous)
        end

        def relational_arrow_at?(text, index:, op:)
          return false unless op == ">"
          return false if index.zero?

          text[index - 1] == "="
        end

        def shift_operator_at?(text, index:, op:)
          return false unless op == ">" || op == "<"

          previous = previous_non_space_char(text, index: index)
          return true if previous == op

          following = next_non_space_char(text, index: index + op.length)
          following == op
        end

        def previous_non_space_char(text, index:)
          cursor = index - 1
          while cursor >= 0
            char = text[cursor]
            return char unless char.match?(/\s/)

            cursor -= 1
          end
          nil
        end

        def next_non_space_char(text, index:)
          cursor = index
          while cursor < text.length
            char = text[cursor]
            return char unless char.match?(/\s/)

            cursor += 1
          end
          nil
        end

        def format_keyword_hash_argument_lines(argument)
          key, value = split_keyword_argument(argument)
          return nil if key.nil? || value.nil?
          return nil unless brace_wrapped?(value)

          body = value[1...-1].to_s.strip
          return ["#{key}: {}"] if body.empty?

          entries = split_top_level_commas(body)
          lines = []
          lines << "#{key}: {"
          entries.each_with_index do |entry, index|
            suffix = index == entries.length - 1 ? "" : ","
            lines << "  #{entry}#{suffix}"
          end
          lines << "}"
          lines
        end

        def complex_expression_fragment?(text)
          token = text.to_s
          token.include?(",") ||
            token.include?(" && ") ||
            token.include?(" || ") ||
            token.include?(" & ") ||
            token.include?(" | ") ||
            token.include?(" ? ") ||
            token.length > 64
        end

        def decompose_terminal_call(text)
          token = text.to_s.strip
          return nil unless token.end_with?(")")

          open_index = matching_open_paren_for_terminal_close(token)
          return nil if open_index.nil?

          callee = token[0...open_index].to_s.strip
          return nil if callee.empty?
          return nil if callee.end_with?(":")
          return nil unless terminal_call_callee?(callee)

          args_text = token[(open_index + 1)...-1].to_s
          args = split_top_level_commas(args_text)
          return nil if args.empty?

          {
            callee: callee,
            args: args
          }
        end

        def terminal_call_callee?(callee)
          token = callee.to_s.strip
          return true if token.match?(/\A[a-zA-Z_]\w*\z/)
          return true if token.match?(/\.[a-zA-Z_]\w*[!?]?\z/)

          false
        end

        def matching_open_paren_for_terminal_close(text)
          target_close = text.length - 1
          return nil unless text[target_close] == ")"

          state = scanner_initial_state
          stack = []

          text.each_char.with_index do |char, index|
            scanner_update_state_before(char, state)
            if top_level_token_context?(state)
              case char
              when "("
                stack << index
              when ")"
                open_index = stack.pop
                return nil if open_index.nil?
                return open_index if index == target_close && stack.empty?
              end
            end
            scanner_update_state_after(char, state)
          end

          nil
        end

        def scanner_initial_state
          {
            single_quote: false,
            double_quote: false,
            escape: false,
            brace: 0,
            bracket: 0,
            paren: 0
          }
        end

        def top_level_token_context?(state)
          !state[:single_quote] && !state[:double_quote]
        end

        def scanner_update_state_before(char, state)
          if state[:escape]
            state[:escape] = false
            return
          end

          if state[:single_quote]
            state[:single_quote] = false if char == "'"
            state[:escape] = true if char == "\\"
            return
          end

          if state[:double_quote]
            state[:double_quote] = false if char == "\""
            state[:escape] = true if char == "\\"
            return
          end

          case char
          when "'"
            state[:single_quote] = true
          when "\""
            state[:double_quote] = true
          end
        end

        def scanner_update_state_after(char, state)
          return if state[:single_quote] || state[:double_quote]

          case char
          when "{"
            state[:brace] += 1
          when "}"
            state[:brace] -= 1 if state[:brace].positive?
          when "["
            state[:bracket] += 1
          when "]"
            state[:bracket] -= 1 if state[:bracket].positive?
          when "("
            state[:paren] += 1
          when ")"
            state[:paren] -= 1 if state[:paren].positive?
          end
        end

        def format_inline_keyword_hash_line(line)
          stripped = line.strip
          return line unless stripped.match?(/\A[a-z_]\w*\s+/)

          method_name, args = stripped.split(/\s+/, 2)
          return line if args.nil? || args.empty?

          segments = split_top_level_commas(args)
          return line if segments.length < 2

          hash_index = segments.index { |segment| keyword_hash_literal_argument?(segment) }
          return line if hash_index.nil? || hash_index.zero?

          indent = line[/\A\s*/] || ""
          positional = segments[0...hash_index]
          keyword_segments = segments[hash_index..]
          return line unless keyword_segments.any? { |segment| keyword_hash_literal_argument?(segment) }

          output = []
          output << "#{indent}#{method_name} #{positional.join(', ')},"
          keyword_segments.each_with_index do |segment, index|
            trailing = index == keyword_segments.length - 1 ? "" : ","
            if keyword_hash_literal_argument?(segment)
              key, hash_literal = split_keyword_hash_argument(segment)
              formatted_hash = format_hash_literal_lines(
                key: key,
                hash_literal: hash_literal,
                indent: "#{indent}  "
              )
              formatted_hash[-1] = "#{formatted_hash[-1]}#{trailing}"
              output.concat(formatted_hash)
            else
              output << "#{indent}  #{segment}#{trailing}"
            end
          end

          output.join("\n")
        rescue StandardError
          line
        end

        def keyword_hash_literal_argument?(segment)
          key, value = split_keyword_argument(segment)
          !key.nil? && !value.nil? && brace_wrapped?(value)
        end

        def split_keyword_hash_argument(segment)
          key, value = split_keyword_argument(segment)
          [key, value]
        end

        def split_keyword_argument(segment)
          scanner = TopLevelScanner.new(segment.to_s)
          separator = scanner.index_of(":")
          return [nil, nil] if separator.nil?

          key = segment[0...separator].strip
          value = segment[(separator + 1)..].to_s.strip
          return [nil, nil] if key.empty? || value.empty?
          return [nil, nil] unless key.match?(/\A[a-z_]\w*\z/)

          [key, value]
        end

        def brace_wrapped?(value)
          text = value.strip
          return false unless text.start_with?("{") && text.end_with?("}")

          scanner = TopLevelScanner.new(text)
          scanner.balanced_braces?
        end

        def format_hash_literal_lines(key:, hash_literal:, indent:)
          literal = hash_literal.strip
          body = literal[1...-1].to_s.strip
          return ["#{indent}#{key}: {}"] if body.empty?

          entries = split_top_level_commas(body)
          lines = []
          lines << "#{indent}#{key}: {"
          entries.each_with_index do |entry, index|
            suffix = index == entries.length - 1 ? "" : ","
            lines << "#{indent}  #{entry}#{suffix}"
          end
          lines << "#{indent}}"
          lines
        end

        def split_top_level_commas(text)
          scanner = TopLevelScanner.new(text.to_s)
          scanner.split_commas.map(&:strip).reject(&:empty?)
        end

        def strip_trailing_whitespace(text)
          text.each_line.map { |line| line.rstrip }.join("\n")
        end

        def collapse_blank_runs(text)
          lines = text.split("\n", -1)
          collapsed = []
          blank_count = 0

          lines.each do |line|
            if line.strip.empty?
              blank_count += 1
              next if blank_count > 2
            else
              blank_count = 0
            end

            collapsed << line
          end

          collapsed.join("\n")
        end

        def ensure_terminal_newline(text)
          text.end_with?("\n") ? text : "#{text}\n"
        end
      end

      class TopLevelScanner
        attr_reader :text

        def initialize(text)
          @text = text.to_s
        end

        def split_commas
          segments = []
          start_index = 0
          each_char_with_state do |index, char, state|
            next unless char == ","
            next unless top_level?(state)

            segments << text[start_index...index]
            start_index = index + 1
          end
          segments << text[start_index..]
          segments.compact
        end

        def index_of(target_char)
          each_char_with_state do |index, char, state|
            next unless char == target_char
            next unless top_level?(state)

            return index
          end
          nil
        end

        def balanced_braces?
          state = initial_state
          text.each_char do |char|
            update_state_before(char, state)
            update_state_after(char, state)
          end

          state[:brace].zero? &&
            state[:bracket].zero? &&
            state[:paren].zero? &&
            !state[:single_quote] &&
            !state[:double_quote] &&
            !state[:escape]
        end

        private

        def each_char_with_state
          state = initial_state
          text.each_char.with_index do |char, index|
            update_state_before(char, state)
            yield(index, char, state.dup)
            update_state_after(char, state)
          end
        end

        def initial_state
          {
            single_quote: false,
            double_quote: false,
            escape: false,
            brace: 0,
            bracket: 0,
            paren: 0
          }
        end

        def update_state_before(char, state)
          if state[:escape]
            state[:escape] = false
            return
          end

          if state[:single_quote]
            state[:single_quote] = false if char == "'"
            state[:escape] = true if char == "\\"
            return
          end

          if state[:double_quote]
            state[:double_quote] = false if char == "\""
            state[:escape] = true if char == "\\"
            return
          end

          case char
          when "'"
            state[:single_quote] = true
          when "\""
            state[:double_quote] = true
          end
        end

        def update_state_after(char, state)
          return if state[:single_quote] || state[:double_quote]

          case char
          when "{"
            state[:brace] += 1
          when "}"
            state[:brace] -= 1 if state[:brace].positive?
          when "["
            state[:bracket] += 1
          when "]"
            state[:bracket] -= 1 if state[:bracket].positive?
          when "("
            state[:paren] += 1
          when ")"
            state[:paren] -= 1 if state[:paren].positive?
          end
        end

        def top_level?(state)
          state[:brace].zero? &&
            state[:bracket].zero? &&
            state[:paren].zero? &&
            !state[:single_quote] &&
            !state[:double_quote] &&
            !state[:escape]
        end
      end
    end
  end
end
