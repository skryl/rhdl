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
        MAX_ARRAY_SELECT_ELEMENTS = 512

        SSA_TOKEN_PATTERN = '%[A-Za-z0-9_$.\\-]+'
        LLHD_VALUE_TOKEN_PATTERN = '%[A-Za-z0-9_$.\\-]+(?:#\\d+)?'
        ARRAY_TYPE_PATTERN = /!hw\.array<(?<len>\d+)xi(?<width>\d+)>/
        LLHD_ARRAY_TYPE_PATTERN = /<\s*!hw\.array<(?<len>\d+)xi(?<width>\d+)>\s*>/
        FIRMEM_TYPE_PATTERN = /<\s*(?<depth>\d+)\s*x\s*(?<width>\d+)\s*>/

        ArrayValue = Struct.new(:elements, :length, :element_width, keyword_init: true) do
          def width
            length.to_i * element_width.to_i
          end
        end
        ArrayMeta = Struct.new(:token, :name, :length, :element_width, keyword_init: true)
        ArrayElementRef = Struct.new(:array_token, :array_name, :length, :element_width, :index_expr, keyword_init: true)
        ArrayForwardRef = Struct.new(:token, :name, :length, :element_width, keyword_init: true) do
          def width
            length.to_i * element_width.to_i
          end
        end
        ArrayWriteCandidate = Struct.new(
          :base_value,
          :base_token,
          :base_name,
          :index_expr,
          :new_element,
          :length,
          :element_width,
          :enable_expr,
          keyword_init: true
        ) do
          def width
            length.to_i * element_width.to_i
          end
        end
        class DeferredArrayRead < IR::Expr
          attr_reader :base_token, :base_name, :addr, :length, :element_width

          def initialize(base_token:, base_name:, addr:, length:, element_width:)
            @base_token = base_token
            @base_name = base_name
            @addr = addr
            @length = length
            @element_width = element_width
            super(width: element_width.to_i)
          end
        end

        def from_mlir(text, strict: false, top: nil, extern_modules: [], resolve_forward_refs: true)
          previous_array_elements_cache = Thread.current[:rhdl_circt_import_array_elements_cache]
          previous_literal_cache = Thread.current[:rhdl_circt_import_literal_cache]
          previous_signal_cache = Thread.current[:rhdl_circt_import_signal_cache]
          previous_forward_refs_seen = Thread.current[:rhdl_circt_import_forward_refs_seen]
          Thread.current[:rhdl_circt_import_array_elements_cache] = {}
          Thread.current[:rhdl_circt_import_literal_cache] = {}
          Thread.current[:rhdl_circt_import_signal_cache] = {}
          Thread.current[:rhdl_circt_import_forward_refs_seen] = false

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
            array_meta = {}
            array_element_refs = {}
            assigns = []
            regs = []
            nets = []
            processes = []
            instances = []
            memories = []
            write_ports = []
            sync_read_ports = []
            module_start_line = header[:line_no]

            idx = header[:next_idx]
            body_depth = 1
            Thread.current[:rhdl_circt_import_forward_refs_seen] = false
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
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
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

              if (resultful_process = parse_resultful_llhd_process_header(body))
                process_lines, consumed = collect_braced_block(lines, idx)
                drive_lines, drive_consumed = collect_resultful_llhd_drive_lines(
                  lines,
                  start_idx: idx + consumed,
                  process_token: resultful_process[:token]
                )
                handled = parse_resultful_llhd_process_block(
                  process_token: resultful_process[:token],
                  process_lines: process_lines,
                  drive_lines: drive_lines,
                  value_map: value_map,
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  processes: processes,
                  input_ports: input_ports,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1,
                  strict: strict
                )

                if handled
                  body_depth += brace_delta(lines, idx, consumed + drive_consumed)
                  idx += consumed + drive_consumed
                  next
                end
              end

              if llhd_process_opener?(body)
                process_lines, consumed = collect_braced_block(lines, idx)
                handled = parse_llhd_process_block(
                  process_lines,
                  value_map: value_map,
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  processes: processes,
                  input_ports: input_ports,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1,
                  strict: strict
                )

                unless handled
                  handled = parse_llhd_combinational_block(
                    process_lines,
                    value_map: value_map,
                    array_meta: array_meta,
                    array_element_refs: array_element_refs,
                    assigns: assigns,
                    regs: regs,
                    nets: nets,
                    input_ports: input_ports,
                    output_ports: output_ports,
                    diagnostics: diagnostics,
                    line_no: idx + 1,
                    strict: strict
                  )
                end

                unless handled
                  process_lines.each_with_index do |process_line, offset|
                    parse_body_line(
                      process_line.to_s.strip,
                      value_map: value_map,
                      array_meta: array_meta,
                      array_element_refs: array_element_refs,
                      assigns: assigns,
                      regs: regs,
                      nets: nets,
                      memories: memories,
                      write_ports: write_ports,
                      sync_read_ports: sync_read_ports,
                      processes: processes,
                      instances: instances,
                      output_ports: output_ports,
                      diagnostics: diagnostics,
                      line_no: idx + offset + 1,
                      strict: strict
                    )
                  end
                end

                body_depth += brace_delta(lines, idx, consumed)
                idx += consumed
                next
              end

              if body.match?(/\Allhd\.combinational\s*\{\z/)
                process_lines, consumed = collect_braced_block(lines, idx)
                handled = parse_llhd_combinational_block(
                  process_lines,
                  value_map: value_map,
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  input_ports: input_ports,
                  output_ports: output_ports,
                  diagnostics: diagnostics,
                  line_no: idx + 1,
                  strict: strict
                )

                unless handled
                  process_lines.each_with_index do |process_line, offset|
                    parse_body_line(
                      process_line.to_s.strip,
                      value_map: value_map,
                      array_meta: array_meta,
                      array_element_refs: array_element_refs,
                      assigns: assigns,
                      regs: regs,
                      nets: nets,
                      memories: memories,
                      write_ports: write_ports,
                      sync_read_ports: sync_read_ports,
                      processes: processes,
                      instances: instances,
                      output_ports: output_ports,
                      diagnostics: diagnostics,
                      line_no: idx + offset + 1,
                      strict: strict
                    )
                  end
                end

                body_depth += brace_delta(lines, idx, consumed)
                idx += consumed
                next
              end

              if body.include?('hw.instance')
                combined, consumed = collect_multiline_instance(lines, idx)
                parse_body_line(
                  combined,
                  value_map: value_map,
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  memories: memories,
                  write_ports: write_ports,
                  sync_read_ports: sync_read_ports,
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
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
                  assigns: assigns,
                  regs: regs,
                  nets: nets,
                  memories: memories,
                  write_ports: write_ports,
                  sync_read_ports: sync_read_ports,
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
                array_meta: array_meta,
                array_element_refs: array_element_refs,
                assigns: assigns,
                regs: regs,
                nets: nets,
                memories: memories,
                write_ports: write_ports,
                sync_read_ports: sync_read_ports,
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

            if resolve_forward_refs && Thread.current[:rhdl_circt_import_forward_refs_seen]
              resolution_state = {
                declared_names: declared_signal_names(input_ports, output_ports, nets, regs, memories),
                memory_names: Array(memories).map { |memory| memory.name.to_s }.to_set,
                signal_memo: {},
                expr_memo: {}
              }

              assigns = resolve_forward_refs_in_assigns(
                assigns,
                value_map: value_map,
                **resolution_state
              )
              processes = resolve_forward_refs_in_processes(
                processes,
                value_map: value_map,
                **resolution_state
              )
              write_ports = resolve_forward_refs_in_write_ports(
                write_ports,
                value_map: value_map,
                **resolution_state
              )
              sync_read_ports = resolve_forward_refs_in_sync_read_ports(
                sync_read_ports,
                value_map: value_map,
                **resolution_state
              )
              assigns = prune_literal_assigns_for_clocked_targets(assigns, processes)
              instances = resolve_forward_refs_in_instances(
                instances,
                value_map: value_map,
                **resolution_state
              )
            end

            modules << IR::ModuleOp.new(
              name: mod_name,
              ports: input_ports + output_ports,
              nets: nets,
              regs: regs,
              assigns: assigns,
              processes: processes,
              instances: instances,
              memories: memories,
              write_ports: write_ports,
              sync_read_ports: sync_read_ports,
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

          modules = normalize_instance_port_connections(modules)
          modules = recover_memory_like_registers(modules)

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
        ensure
          Thread.current[:rhdl_circt_import_array_elements_cache] = previous_array_elements_cache
          Thread.current[:rhdl_circt_import_literal_cache] = previous_literal_cache
          Thread.current[:rhdl_circt_import_signal_cache] = previous_signal_cache
          Thread.current[:rhdl_circt_import_forward_refs_seen] = previous_forward_refs_seen
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
            map["%#{port.name}"] = import_signal(name: port.name.to_s, width: port.width.to_i)
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

        def collect_braced_block(lines, start_idx)
          collected = []
          idx = start_idx
          depth = 0

          while idx < lines.length
            raw = lines[idx].to_s
            collected << raw
            depth += raw.count('{')
            depth -= raw.count('}')
            idx += 1
            break if depth <= 0 && !collected.empty?
          end

          [collected, [idx - start_idx, 1].max]
        end

        def llhd_process_opener?(line)
          line.to_s.strip.match?(/\A(?:#{SSA_TOKEN_PATTERN}(?::\d+)?\s*=\s*)?llhd\.(?:process|combinational)(?:\s*->\s*.+)?\s*\{\z/)
        end

        def parse_resultful_llhd_process_header(line)
          match = line.to_s.strip.match(/\A(#{SSA_TOKEN_PATTERN})(?::\d+)?\s*=\s*llhd\.process\s*->\s*.+\{\z/)
          return nil unless match

          { token: match[1] }
        end

        def collect_resultful_llhd_drive_lines(lines, start_idx:, process_token:)
          collected = []
          idx = start_idx

          while idx < lines.length
            line = normalize_body_line(lines[idx].to_s)
            if line.empty?
              idx += 1
              next
            end

            parsed = parse_llhd_drive(line)
            break unless parsed
            break unless parsed[:process_token] == process_token

            collected << line
            idx += 1
          end

          [collected, idx - start_idx]
        end

        def parse_llhd_process_block(process_lines, value_map:, array_meta:, array_element_refs:, assigns:, regs:, nets:,
                                     processes:, input_ports:,
                                     output_ports:, diagnostics:, line_no:, strict:)
          return true if one_shot_llhd_init_process?(process_lines)

          blocks, entry_target = parse_llhd_blocks(process_lines)
          return false if blocks.empty? || entry_target.nil?

          wait_block = blocks[entry_target]
          return false unless wait_block

          wait_term = parse_llhd_wait(wait_block[:terminator])
          return false unless wait_term

          check_block = blocks[wait_term[:target]]
          return false unless check_block

          edge_term = parse_cf_cond_br(check_block[:terminator])
          return false unless edge_term
          return false unless edge_term[:false_target] == entry_target
          return false if edge_term[:true_target] == entry_target

          clock_name = infer_llhd_clock_signal(
            wait_term: wait_term,
            wait_block: wait_block,
            check_block: check_block,
            value_map: value_map
          )
          clock_name = resolve_existing_seq_clock(clock_name, processes)
          return false unless clock_name

          seq_statements = lower_llhd_clocked_process_statements(
            blocks: blocks,
            start_label: edge_term[:true_target],
            stop_label: entry_target,
            value_map: value_map,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict
          )
          return false if seq_statements.empty?

          target_widths = {}
          collect_seq_targets(seq_statements).each do |target_name, expr|
            width = process_signal_width(
              target: target_name,
              expr: expr,
              input_ports: input_ports,
              output_ports: output_ports,
              nets: nets,
              regs: regs
            )
            target_widths[target_name] = [target_widths[target_name].to_i, width].max
          end

          target_widths.each do |target, width|
            next if process_target_declared?(target, input_ports: input_ports, output_ports: output_ports, regs: regs)

            regs << IR::Reg.new(name: target, width: width)
          end

          processes << IR::Process.new(
            name: :"llhd_proc_#{processes.length}",
            statements: seq_statements,
            clocked: true,
            clock: clock_name,
            sensitivity_list: []
          )
          true
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: strict ? :error : :warning,
            message: "Failed parsing llhd.process at line #{line_no}: #{e.class}: #{e.message}",
            line: line_no,
            column: 1,
            op: 'llhd.process'
          )
          false
        end

        def parse_resultful_llhd_process_block(process_token:, process_lines:, drive_lines:, value_map:, array_meta:,
                                               array_element_refs:, assigns:, regs:, nets:, processes:, input_ports:,
                                               output_ports:, diagnostics:, line_no:, strict:)
          return false if Array(drive_lines).empty?

          blocks, entry_target = parse_llhd_blocks(process_lines)
          return false if blocks.empty? || entry_target.nil?

          wait_block = blocks[entry_target]
          return false unless wait_block

          wait_term = parse_llhd_wait(wait_block[:terminator])
          return false unless wait_term

          check_block = blocks[wait_term[:target]]
          return false unless check_block

          edge_term = parse_cf_cond_br(check_block[:terminator])
          clock_name =
            if edge_term && edge_term[:false_target] == entry_target && edge_term[:true_target] != entry_target
              inferred_clock = infer_llhd_clock_signal(
                wait_term: wait_term,
                wait_block: wait_block,
                check_block: check_block,
                value_map: value_map
              )
              resolve_existing_seq_clock(inferred_clock, processes)
            end

          stop_env = resolve_llhd_stop_env(
            blocks: blocks,
            current_label: wait_term[:target],
            stop_label: entry_target,
            stop_block: wait_block,
            value_map: value_map.dup,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            stack: []
          )
          return false if stop_env.empty?

          if clock_name
            seq_statements = build_resultful_llhd_drive_statements(
              process_token: process_token,
              drive_lines: drive_lines,
              stop_block: wait_block,
              stop_env: stop_env,
              yield_tokens: wait_term[:yield_tokens],
              value_map: value_map,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict
            )
            return false if seq_statements.empty?

            target_widths = {}
            collect_seq_targets(seq_statements).each do |target_name, expr|
              width = process_signal_width(
                target: target_name,
                expr: expr,
                input_ports: input_ports,
                output_ports: output_ports,
                nets: nets,
                regs: regs
              )
              target_widths[target_name] = [target_widths[target_name].to_i, width].max
            end

            target_widths.each do |target, width|
              next if process_target_declared?(target, input_ports: input_ports, output_ports: output_ports, regs: regs)

              regs << IR::Reg.new(name: target, width: width)
            end

            processes << IR::Process.new(
              name: :"llhd_proc_#{processes.length}",
              statements: seq_statements,
              clocked: true,
              clock: clock_name,
              sensitivity_list: []
            )
            return true
          end

          result_assigns = build_resultful_llhd_assigns(
            process_token: process_token,
            drive_lines: drive_lines,
            stop_block: wait_block,
            stop_env: stop_env,
            yield_tokens: wait_term[:yield_tokens],
            value_map: value_map,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict
          )
          return false if result_assigns.empty?

          assigns.concat(result_assigns)
          true
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: strict ? :error : :warning,
            message: "Failed parsing llhd.process results at line #{line_no}: #{e.class}: #{e.message}",
            line: line_no,
            column: 1,
            op: 'llhd.process'
          )
          false
        end

        def resolve_llhd_stop_env(blocks:, current_label:, stop_label:, stop_block:, value_map:, array_meta:,
                                  array_element_refs:, diagnostics:, line_no:, strict:, stack:)
          block = blocks[current_label]
          return {} unless block
          state_key = llhd_block_state_key(current_label: current_label, block: block, value_map: value_map)
          return {} if stack.include?(state_key)

          local_map = value_map.dup
          next_stack = stack + [state_key]

          Array(block[:instructions]).each do |instruction|
            parse_non_drive_process_instruction(
              instruction,
              value_map: local_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict
            )
          end

          terminator = block[:terminator].to_s.strip
          return {} if terminator == 'llhd.yield' || terminator == 'llhd.halt'

          if (cond_br = parse_cf_cond_br(terminator))
            cond_expr = lookup_value(local_map, cond_br[:cond_token], width: 1)
            true_env = resolve_llhd_branch_stop_env(
              blocks: blocks,
              target_label: cond_br[:true_target],
              branch_args: cond_br[:true_args],
              stop_label: stop_label,
              stop_block: stop_block,
              local_map: local_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict,
              stack: next_stack
            )
            false_env = resolve_llhd_branch_stop_env(
              blocks: blocks,
              target_label: cond_br[:false_target],
              branch_args: cond_br[:false_args],
              stop_label: stop_label,
              stop_block: stop_block,
              local_map: local_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict,
              stack: next_stack
            )
            return merge_expr_envs(cond_expr, true_env, false_env)
          end

          if (br = parse_cf_br(terminator))
            return resolve_llhd_branch_stop_env(
              blocks: blocks,
              target_label: br[:target],
              branch_args: br[:args],
              stop_label: stop_label,
              stop_block: stop_block,
              local_map: local_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict,
              stack: next_stack
            )
          end

          {}
        end

        def resolve_llhd_branch_stop_env(blocks:, target_label:, branch_args:, stop_label:, stop_block:, local_map:,
                                         array_meta:, array_element_refs:, diagnostics:, line_no:, strict:, stack:)
          if target_label == stop_label
            return stop_env_from_branch_args(
              value_map: local_map,
              stop_block: stop_block,
              branch_args: branch_args
            )
          end

          next_map = apply_llhd_block_args(
            value_map: local_map,
            target_block: blocks[target_label],
            branch_args: branch_args
          )
          resolve_llhd_stop_env(
            blocks: blocks,
            current_label: target_label,
            stop_label: stop_label,
            stop_block: stop_block,
            value_map: next_map,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            stack: stack
          )
        end

        def stop_env_from_branch_args(value_map:, stop_block:, branch_args:)
          mapped = apply_llhd_block_args(
            value_map: value_map,
            target_block: stop_block,
            branch_args: branch_args
          )

          Array(stop_block[:args]).each_with_object({}) do |arg_spec, env|
            env[arg_spec[:name]] = mapped[arg_spec[:name]]
          end
        end

        def merge_expr_envs(condition, true_env, false_env)
          keys = (Array(true_env).map(&:first) + Array(false_env).map(&:first)).uniq
          keys.each_with_object({}) do |key, merged|
            lhs = true_env[key]
            rhs = false_env[key]
            if expr_equivalent?(lhs, rhs)
              merged[key] = lhs || rhs
              next
            end

            next if lhs.nil? && rhs.nil?

            width = [lhs&.width.to_i, rhs&.width.to_i, 1].max
            merged[key] = IR::Mux.new(
              condition: condition,
              when_true: ensure_expr_with_width(lhs, width: width),
              when_false: ensure_expr_with_width(rhs, width: width),
              width: width
            )
          end
        end

        def build_resultful_llhd_drive_statements(process_token:, drive_lines:, stop_block:, stop_env:, yield_tokens:,
                                                  value_map:, diagnostics:, line_no:, strict:)
          result_token_map = resultful_llhd_result_token_map(
            process_token: process_token,
            stop_block: stop_block,
            yield_tokens: yield_tokens
          )

          Array(drive_lines).flat_map do |line|
            parsed_drive = parse_llhd_drive(line)
            next [] unless parsed_drive

            value_name = result_token_map[parsed_drive[:value_token]]
            enable_name = parsed_drive[:enable_token] ? result_token_map[parsed_drive[:enable_token]] : nil
            next [] unless value_name

            value_expr = stop_env[value_name]
            next [] if value_expr.nil?

            enable_expr =
              if enable_name
                stop_env[enable_name] || IR::Literal.new(value: 0, width: 1)
              else
                IR::Literal.new(value: 1, width: 1)
              end

            build_llhd_drive_statements(
              parsed_drive: parsed_drive,
              value_map: value_map,
              value_expr: pack_array_value(value_expr),
              enable_expr: enable_expr
            )
          rescue StandardError => e
            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Failed lowering llhd.drv result at line #{line_no}: #{e.class}: #{e.message}",
              line: line_no,
              column: 1,
              op: 'llhd.drv'
            )
            []
          end
        end

        def build_resultful_llhd_assigns(process_token:, drive_lines:, stop_block:, stop_env:, yield_tokens:,
                                         value_map:,
                                         diagnostics:, line_no:, strict:)
          result_token_map = resultful_llhd_result_token_map(
            process_token: process_token,
            stop_block: stop_block,
            yield_tokens: yield_tokens
          )

          Array(drive_lines).filter_map do |line|
            parsed_drive = parse_llhd_drive(line)
            next unless parsed_drive

            value_name = result_token_map[parsed_drive[:value_token]]
            enable_name = parsed_drive[:enable_token] ? result_token_map[parsed_drive[:enable_token]] : nil
            next unless value_name

            value_expr = stop_env[value_name]
            next if value_expr.nil?

            target_expr = lookup_value(value_map, parsed_drive[:target_token], width: parsed_drive[:width])
            target_name = if target_expr.is_a?(IR::Signal)
                            target_expr.name.to_s
                          else
                            parsed_drive[:target_token].to_s.delete_prefix('%')
                          end

            expr = ensure_expr_with_width(pack_array_value(value_expr), width: parsed_drive[:width])
            if enable_name
              enable_expr = ensure_expr_with_width(stop_env[enable_name] || IR::Literal.new(value: 0, width: 1), width: 1)
              if enable_expr.is_a?(IR::Literal)
                next if enable_expr.value.to_i.zero?
              else
                expr = IR::Mux.new(
                  condition: enable_expr,
                  when_true: expr,
                  when_false: ensure_expr_with_width(target_expr, width: parsed_drive[:width]),
                  width: parsed_drive[:width]
                )
              end
            end

            IR::Assign.new(target: target_name, expr: expr)
          rescue StandardError => e
            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Failed lowering llhd.drv result assign at line #{line_no}: #{e.class}: #{e.message}",
              line: line_no,
              column: 1,
              op: 'llhd.drv'
            )
            nil
          end
        end

        def resultful_llhd_result_token_map(process_token:, stop_block:, yield_tokens:)
          stop_arg_names = Array(stop_block[:args]).map { |arg_spec| arg_spec[:name] }
          yielded_names = Array(yield_tokens).map { |token| normalize_value_token(token) }

          result_names =
            if yielded_names.any? && yielded_names.all? { |name| stop_arg_names.include?(name) }
              yielded_names
            else
              stop_arg_names
            end

          result_names.each_with_index.each_with_object({}) do |(name, idx), map|
            map["#{process_token}##{idx}"] = name
          end
        end

        def parse_llhd_combinational_block(process_lines, value_map:, array_meta:, array_element_refs:, assigns:, regs:,
                                           nets:, input_ports:, output_ports:,
                                           diagnostics:, line_no:, strict:)
          blocks, entry_target = parse_llhd_blocks(process_lines)
          return false if blocks.empty? || entry_target.nil?

          statements = build_llhd_statement_block(
            blocks: blocks,
            current_label: entry_target,
            stop_label: nil,
            value_map: value_map.dup,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            stack: []
          )
          return false if statements.empty?

          env = evaluate_combinational_statements(statements)
          return true if env.empty?

          env.each do |target_name, expr|
            next if target_name.to_s.empty?
            next if expr.nil?
            next if expr.is_a?(IR::Signal) && expr.name.to_s == target_name.to_s

            width = process_signal_width(
              target: target_name,
              expr: expr,
              input_ports: input_ports,
              output_ports: output_ports,
              nets: nets,
              regs: regs
            )
            unless process_target_declared?(target_name, input_ports: input_ports, output_ports: output_ports, regs: regs) ||
                   nets.any? { |net| net.name.to_s == target_name.to_s }
              nets << IR::Net.new(name: target_name, width: width)
            end

            assigns << IR::Assign.new(target: target_name, expr: expr)
          end
          true
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: strict ? :error : :warning,
            message: "Failed parsing llhd.combinational at line #{line_no}: #{e.class}: #{e.message}",
            line: line_no,
            column: 1,
            op: 'llhd.combinational'
          )
          false
        end

        def parse_llhd_blocks(process_lines)
          lines = Array(process_lines).map { |line| normalize_body_line(line) }
          return [{}, nil] if lines.empty?
          return [{}, nil] unless llhd_process_opener?(lines.first)

          blocks = {}
          current_label = nil
          entry_target = nil

          lines[1...-1].each do |line|
            next if line.empty?

            if (label_match = line.match(/\A(\^bb\d+)(?:\(([^)]*)\))?:/))
              current_label = label_match[1]
              blocks[current_label] ||= {
                instructions: [],
                terminator: nil,
                args: []
              }
              parsed_args = parse_block_arguments(label_match[2])
              blocks[current_label][:args] = parsed_args unless parsed_args.empty?
              next
            end

            if current_label.nil?
              br = parse_cf_br(line)
              if br
                entry_target = br[:target] if entry_target.nil?
                current_label = br[:target]
                blocks[current_label] ||= { instructions: [], terminator: nil, args: [] }
                next
              end

              current_label = '^bb0'
              entry_target ||= current_label
              blocks[current_label] ||= { instructions: [], terminator: nil, args: [] }
            end

            if parse_cf_cond_br(line) || parse_cf_br(line) || parse_llhd_wait(line) || line == 'llhd.yield' || line == 'llhd.halt'
              blocks[current_label][:terminator] = line
            else
              blocks[current_label][:instructions] << line
            end
          end

          entry_target ||= blocks.keys.first
          [blocks, entry_target]
        end

        def parse_cf_br(line)
          m = line.to_s.strip.match(/\Acf\.br\s+(.+)\z/)
          return nil unless m

          target = parse_cf_target(m[1])
          return nil unless target

          {
            target: target[:label],
            args: target[:args]
          }
        end

        def parse_cf_cond_br(line)
          m = line.to_s.strip.match(/\Acf\.cond_br\s+(#{SSA_TOKEN_PATTERN})\s*,\s*(.+)\z/)
          return nil unless m

          targets = split_top_level_csv(m[2])
          return nil unless targets.length == 2

          true_target = parse_cf_target(targets[0])
          false_target = parse_cf_target(targets[1])
          return nil unless true_target && false_target

          {
            cond_token: m[1],
            true_target: true_target[:label],
            true_args: true_target[:args],
            false_target: false_target[:label],
            false_args: false_target[:args]
          }
        end

        def parse_llhd_wait(line)
          yielded = line.to_s.strip.match(/\Allhd\.wait\s+yield\s+\((.+)\)\s*,\s*\((.+)\)\s*,\s*(\^bb\d+(?:\([^)]*\))?)\z/)
          if yielded
            target = parse_cf_target(yielded[3])
            return nil unless target

            value_tokens = split_top_level_csv(yielded[2].split(':', 2).first.to_s)
                             .map { |token| normalize_value_token(token) }
                             .reject(&:empty?)
            yield_tokens = split_top_level_csv(yielded[1].split(':', 2).first.to_s)
                             .map { |token| normalize_value_token(token) }
                             .reject(&:empty?)
            return {
              value_tokens: value_tokens,
              yield_tokens: yield_tokens,
              target: target[:label],
              target_args: target[:args]
            }
          end

          m = line.to_s.strip.match(/\Allhd\.wait\s+\((.+)\)\s*,\s*(\^bb\d+)\z/)
          return nil unless m

          value_tokens = split_top_level_csv(m[1].split(':', 2).first.to_s)
                           .map { |token| normalize_value_token(token) }
                           .reject(&:empty?)
          {
            value_tokens: value_tokens,
            yield_tokens: [],
            target: m[2],
            target_args: []
          }
        end

        def infer_llhd_clock_signal(wait_term:, wait_block:, check_block:, value_map:)
          probe_token = wait_term[:value_tokens].first
          if probe_token
            probe_expr = lookup_value(value_map, probe_token, width: 1)
            return probe_expr.name.to_s if probe_expr.is_a?(IR::Signal)
          end

          [wait_block, check_block].each do |block|
            Array(block[:instructions]).each do |instruction|
              m = instruction.match(/\A#{SSA_TOKEN_PATTERN}\s*=\s*llhd\.prb\s+(#{SSA_TOKEN_PATTERN})\s*:\s*i1\z/)
              next unless m

              signal_expr = lookup_value(value_map, m[1], width: 1)
              return signal_expr.name.to_s if signal_expr.is_a?(IR::Signal)
            end
          end

          nil
        end

        def resolve_existing_seq_clock(clock_name, processes)
          resolved = clock_name.to_s
          seen = Set.new

          while !resolved.empty? && !seen.include?(resolved)
            seen << resolved
            source_process = Array(processes).find do |process|
              process.clocked && Array(process.statements).any? do |statement|
                statement.is_a?(IR::SeqAssign) && statement.target.to_s == resolved
              end
            end
            break unless source_process&.clock

            resolved = source_process.clock.to_s
          end

          resolved
        end

        def lower_llhd_clocked_process_statements(blocks:, start_label:, stop_label:, value_map:, array_meta:,
                                                  array_element_refs:, diagnostics:, line_no:, strict:)
          build_llhd_statement_block(
            blocks: blocks,
            current_label: start_label,
            stop_label: stop_label,
            value_map: value_map.dup,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            stack: []
          )
        end

        def build_llhd_statement_block(blocks:, current_label:, stop_label:, value_map:, array_meta:, array_element_refs:,
                                       diagnostics:, line_no:, strict:, stack:)
          return [] if !stop_label.nil? && current_label == stop_label
          block = blocks[current_label]
          return [] unless block
          state_key = llhd_block_state_key(current_label: current_label, block: block, value_map: value_map)
          return [] if stack.include?(state_key)

          local_map = value_map.dup
          statements = []
          next_stack = stack + [state_key]

          Array(block[:instructions]).each do |instruction|
            parsed_drive = parse_llhd_drive(instruction)
            if parsed_drive
              statements.concat(
                build_llhd_drive_statements(
                  parsed_drive: parsed_drive,
                  value_map: local_map,
                  array_element_refs: array_element_refs
                )
              )
              next
            end

            parse_non_drive_process_instruction(
              instruction,
              value_map: local_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict
            )
          end

          terminator = block[:terminator].to_s.strip
          return statements if terminator == 'llhd.yield' || terminator == 'llhd.halt'

          if (cond_br = parse_cf_cond_br(terminator))
            cond_expr = lookup_value(local_map, cond_br[:cond_token], width: 1)
            true_map = apply_llhd_block_args(
              value_map: local_map,
              target_block: blocks[cond_br[:true_target]],
              branch_args: cond_br[:true_args]
            )
            false_map = apply_llhd_block_args(
              value_map: local_map,
              target_block: blocks[cond_br[:false_target]],
              branch_args: cond_br[:false_args]
            )
            then_statements = build_llhd_statement_block(
              blocks: blocks,
              current_label: cond_br[:true_target],
              stop_label: stop_label,
              value_map: true_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict,
              stack: next_stack
            )
            else_statements = build_llhd_statement_block(
              blocks: blocks,
              current_label: cond_br[:false_target],
              stop_label: stop_label,
              value_map: false_map,
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              diagnostics: diagnostics,
              line_no: line_no,
              strict: strict,
              stack: next_stack
            )
            statements << IR::If.new(
              condition: cond_expr,
              then_statements: then_statements,
              else_statements: else_statements
            )
            return statements
          end

          if (br = parse_cf_br(terminator))
            unless !stop_label.nil? && br[:target] == stop_label
              next_map = apply_llhd_block_args(
                value_map: local_map,
                target_block: blocks[br[:target]],
                branch_args: br[:args]
              )
              statements.concat(
                build_llhd_statement_block(
                  blocks: blocks,
                  current_label: br[:target],
                  stop_label: stop_label,
                  value_map: next_map,
                  array_meta: array_meta,
                  array_element_refs: array_element_refs,
                  diagnostics: diagnostics,
                  line_no: line_no,
                  strict: strict,
                  stack: next_stack
                )
              )
            end
            return statements
          end

          statements
        end

        def parse_block_arguments(raw_args)
          return [] if raw_args.nil? || raw_args.strip.empty?

          split_top_level_csv(raw_args).filter_map do |entry|
            token = entry.to_s.strip
            m = token.match(/\A(#{SSA_TOKEN_PATTERN})\s*:\s*(.+)\z/)
            next unless m

            type = m[2].to_s.strip
            array_type = array_type_from_string(type)
            width =
              array_type&.dig(:total_width) ||
              integer_type_width(type) ||
              type.match(/!llhd\.ref<i(\d+)>/)&.captures&.first&.to_i ||
              type.match(/<i(\d+)>/)&.captures&.first&.to_i ||
              1

            { name: m[1], width: width, array_type: array_type }
          end
        end

        def parse_cf_target(target_text)
          m = target_text.to_s.strip.match(/\A(\^bb\d+)(?:\((.*)\))?\z/)
          return nil unless m

          args = if m[2]
                   split_top_level_csv(m[2]).map do |entry|
                     normalize_value_token(entry.to_s.split(':', 2).first.to_s)
                   end
                 else
                   []
                 end
          { label: m[1], args: args }
        end

        def apply_llhd_block_args(value_map:, target_block:, branch_args:)
          return value_map.dup if target_block.nil?

          mapped = value_map.dup
          block_args = Array(target_block[:args])
          Array(branch_args).each_with_index do |arg_token, idx|
            arg_spec = block_args[idx]
            next unless arg_spec

            if arg_spec[:array_type]
              mapped[arg_spec[:name]] = lookup_array_value(value_map, arg_token, arg_spec[:array_type])
            else
              width = [arg_spec[:width].to_i, 1].max
              mapped[arg_spec[:name]] = lookup_value(value_map, arg_token, width: width)
            end
          end
          mapped
        end

        def llhd_block_state_key(current_label:, block:, value_map:)
          arg_state = Array(block[:args]).map do |arg_spec|
            [arg_spec[:name], expr_signature(value_map[arg_spec[:name]])]
          end
          [current_label, arg_state]
        end

        def one_shot_llhd_init_process?(process_lines)
          lines = Array(process_lines).map { |line| line.to_s.strip }.reject(&:empty?)
          return false if lines.empty?
          return false unless llhd_process_opener?(lines.first)
          return false unless lines.last == '}'
          body = lines[1...-1]
          return false if body.nil? || body.empty?
          return false if body.any? { |line| line.start_with?('llhd.wait ') || line.start_with?('cf.') }
          body.any? { |line| line == 'llhd.halt' } &&
            body.all? { |line| line == 'llhd.halt' || parse_llhd_drive(line) || line.match?(/\A\^bb\d+:/) }
        end

        def evaluate_combinational_statements(statements, env = {})
          result = env.dup
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              result[stmt.target.to_s] = stmt.expr
            when IR::If
              base = result.dup
              then_env = evaluate_combinational_statements(stmt.then_statements, base)
              else_env = evaluate_combinational_statements(stmt.else_statements, base)
              keys = (then_env.keys + else_env.keys + base.keys).uniq
              keys.each do |key|
                then_expr = then_env[key] || base[key]
                else_expr = else_env[key] || base[key]
                next if then_expr.nil? && else_expr.nil?

                if expr_equivalent?(then_expr, else_expr)
                  result[key] = then_expr || else_expr
                  next
                end

                width = [then_expr&.width.to_i, else_expr&.width.to_i, 1].max
                result[key] = IR::Mux.new(
                  condition: stmt.condition,
                  when_true: ensure_expr_with_width(then_expr, width: width),
                  when_false: ensure_expr_with_width(else_expr, width: width),
                  width: width
                )
              end
            end
          end
          result
        end

        def expr_equivalent?(lhs, rhs)
          return true if lhs.equal?(rhs)
          return false if lhs.nil? || rhs.nil?

          expr_signature(lhs) == expr_signature(rhs)
        end

        def expr_signature(expr)
          case expr
          when IR::Signal
            [:signal, expr.name.to_s, expr.width.to_i]
          when IR::Literal
            [:literal, expr.value, expr.width.to_i]
          when IR::UnaryOp
            [:unary, expr.op, expr_signature(expr.operand), expr.width.to_i]
          when IR::BinaryOp
            [:binary, expr.op, expr_signature(expr.left), expr_signature(expr.right), expr.width.to_i]
          when IR::Mux
            [:mux, expr_signature(expr.condition), expr_signature(expr.when_true), expr_signature(expr.when_false), expr.width.to_i]
          when IR::Concat
            [:concat, Array(expr.parts).map { |part| expr_signature(part) }, expr.width.to_i]
          when IR::Slice
            [:slice, expr_signature(expr.base), expr.range&.first, expr.range&.last, expr.width.to_i]
          when IR::Resize
            [:resize, expr_signature(expr.expr), expr.width.to_i]
          when IR::Case
            [
              :case,
              expr_signature(expr.selector),
              expr.cases.to_h { |k, v| [k, expr_signature(v)] },
              expr_signature(expr.default),
              expr.width.to_i
            ]
          when IR::MemoryRead
            [:memory_read, expr.memory.to_s, expr_signature(expr.addr), expr.width.to_i]
          else
            [:unknown, expr.class.name, expr.to_s]
          end
        end

        def collect_seq_targets(statements, acc = {})
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              acc[stmt.target.to_s] = stmt.expr
            when IR::If
              collect_seq_targets(stmt.then_statements, acc)
              collect_seq_targets(stmt.else_statements, acc)
            end
          end
          acc
        end

        def prune_literal_assigns_for_clocked_targets(assigns, processes)
          seq_targets = Set.new
          Array(processes).each do |process|
            next unless process.clocked

            collect_seq_targets(process.statements).keys.each { |target| seq_targets << target.to_s }
          end
          return assigns if seq_targets.empty?

          Array(assigns).reject do |assign|
            target = assign.target.to_s
            next false unless seq_targets.include?(target)
            assign.expr.is_a?(IR::Literal)
          end
        end

        def parse_non_drive_process_instruction(instruction, value_map:, array_meta:, array_element_refs:, diagnostics:,
                                                line_no:, strict:)
          temp_assigns = []
          temp_regs = []
          temp_nets = []
          temp_memories = []
          temp_write_ports = []
          temp_sync_read_ports = []
          temp_processes = []
          temp_instances = []
          parse_body_line(
            instruction,
            value_map: value_map,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            assigns: temp_assigns,
            regs: temp_regs,
            nets: temp_nets,
            memories: temp_memories,
            write_ports: temp_write_ports,
            sync_read_ports: temp_sync_read_ports,
            processes: temp_processes,
            instances: temp_instances,
            output_ports: [],
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict
          )
        end

        def build_llhd_drive_statements(parsed_drive:, value_map:, array_element_refs: {}, value_expr: nil, enable_expr: nil)
          target_expr = lookup_value(value_map, parsed_drive[:target_token], width: parsed_drive[:width])
          target_name = if target_expr.is_a?(IR::Signal)
                          target_expr.name.to_s
                        else
                          parsed_drive[:target_token].to_s.delete_prefix('%')
                        end
          return [] if target_name.nil? || target_name.empty?

          drive_expr = value_expr || lookup_value(value_map, parsed_drive[:value_token], width: parsed_drive[:width])
          drive_expr = pack_array_value(drive_expr)
          base_statements = [
            IR::SeqAssign.new(
              target: target_name,
              expr: ensure_expr_with_width(drive_expr, width: parsed_drive[:width])
            )
          ]

          condition = enable_expr
          if condition.nil? && parsed_drive[:enable_token]
            condition = lookup_value(value_map, parsed_drive[:enable_token], width: 1)
          end
          return base_statements if condition.nil?

          condition = ensure_expr_with_width(condition, width: 1)
          return [] if condition.is_a?(IR::Literal) && condition.value.to_i.zero?
          return base_statements if condition.is_a?(IR::Literal) && condition.value.to_i != 0

          [
            IR::If.new(
              condition: condition,
              then_statements: base_statements,
              else_statements: []
            )
          ]
        end

        def parse_llhd_drive(line)
          m = line.to_s.strip.match(
            /\Allhd\.drv\s+(#{SSA_TOKEN_PATTERN})\s*,\s*(#{LLHD_VALUE_TOKEN_PATTERN})\s+after\s+#{SSA_TOKEN_PATTERN}(?:\s+if\s+(#{LLHD_VALUE_TOKEN_PATTERN}))?\s*:\s*(.+)\z/
          )
          return nil unless m
          width = mlir_type_width(m[4])
          return nil unless width

          {
            target_token: m[1],
            value_token: normalize_value_token(m[2]),
            enable_token: m[3] ? normalize_value_token(m[3]) : nil,
            width: width,
            process_token: m[2][/^%[^#]+/]
          }
        end

        def update_array_from_element_drive!(value_map:, target_ref:, value_token:, assigns: nil, statements: nil)
          return if target_ref.nil?

          array_token = target_ref.array_token.to_s
          array_name = target_ref.array_name.to_s
          length = [target_ref.length.to_i, 1].max
          element_width = [target_ref.element_width.to_i, 1].max
          total_width = length * element_width

          current_array = lookup_value(value_map, array_token, width: total_width)
          # For array signals, updates must be based on the live signal state,
          # not the declaration initializer literal snapshot.
          if current_array.is_a?(ArrayValue)
            current_array = IR::Signal.new(name: array_name, width: total_width)
          end
          index_width = [[Math.log2(length).ceil, 1].max, 1].max
          index_expr = ensure_expr_with_width(target_ref.index_expr, width: index_width)
          new_element = lookup_value(value_map, value_token, width: element_width)

          old_elements = array_elements_from_value(current_array, length: length, element_width: element_width)
          updated_elements = write_array_elements(
            elements: old_elements,
            index_expr: index_expr,
            new_element: new_element,
            element_width: element_width
          )
          updated_array = ArrayValue.new(
            elements: updated_elements,
            length: length,
            element_width: element_width
          )
          value_map[array_token] = updated_array

          assign_expr = pack_array_value(updated_array)
          if statements
            statements << IR::SeqAssign.new(target: array_name, expr: assign_expr)
          elsif assigns
            assigns << IR::Assign.new(target: array_name, expr: assign_expr)
          end
        end

        def lookup_array_value(value_map, token, array_type)
          normalized = normalize_value_token(token)
          return value_map[normalized] if value_map.key?(normalized)

          if normalized.start_with?('%')
            Thread.current[:rhdl_circt_import_forward_refs_seen] = true
            return ArrayForwardRef.new(
              token: normalized,
              name: normalized.sub('%', ''),
              length: array_type[:len],
              element_width: array_type[:element_width]
            )
          end

          lookup_value(value_map, normalized, width: array_type[:total_width])
        end

        def parse_firmem_type(text)
          match = text.to_s.match(FIRMEM_TYPE_PATTERN)
          raise ArgumentError, "Invalid seq.firmem type: #{text}" unless match

          {
            depth: match[:depth].to_i,
            width: match[:width].to_i
          }
        end

        def array_base_matches?(value, base_token:, base_name:, total_width:)
          case value
          when ArrayForwardRef
            value.token.to_s == base_token.to_s
          when IR::Signal
            value.name.to_s == base_name.to_s && value.width.to_i == total_width.to_i
          else
            false
          end
        end

        def write_array_elements(elements:, index_expr:, new_element:, element_width:)
          entries = Array(elements)
          return entries if entries.empty?

          width = [index_expr.width.to_i, 1].max
          if index_expr.is_a?(IR::Literal)
            idx = [[index_expr.value.to_i, 0].max, entries.length - 1].min
            out = entries.dup
            out[idx] = ensure_expr_with_width(new_element, width: element_width)
            return out
          end

          entries.each_with_index.map do |element, idx|
            cond = IR::BinaryOp.new(
              op: :==,
              left: index_expr,
              right: IR::Literal.new(value: idx, width: width),
              width: 1
            )
            IR::Mux.new(
              condition: cond,
              when_true: ensure_expr_with_width(new_element, width: element_width),
              when_false: ensure_expr_with_width(element, width: element_width),
              width: element_width
            )
          end
        end

        def pack_array_value(value)
          case value
          when ArrayValue
            IR::Concat.new(parts: Array(value.elements).reverse, width: value.length.to_i * value.element_width.to_i)
          when ArrayForwardRef
            import_signal(name: value.name, width: value.width)
          when ArrayWriteCandidate
            IR::Concat.new(
              parts: Array(
                array_elements_from_value(value, length: value.length.to_i, element_width: value.element_width.to_i)
              ).reverse,
              width: value.width
            )
          else
            value
          end
        end

        def lookup_expr_value(value_map, token, width:)
          pack_array_value(lookup_value(value_map, token, width: width))
        end

        def process_signal_width(target:, expr:, input_ports:, output_ports:, nets:, regs:)
          width = expr.respond_to?(:width) ? expr.width.to_i : 0
          return width if width.positive?

          port = Array(input_ports).find { |p| p.name.to_s == target.to_s } ||
                 Array(output_ports).find { |p| p.name.to_s == target.to_s }
          return port.width.to_i if port

          reg = Array(regs).find { |r| r.name.to_s == target.to_s }
          return reg.width.to_i if reg

          net = Array(nets).find { |n| n.name.to_s == target.to_s }
          return net.width.to_i if net

          1
        end

        def process_target_declared?(target, input_ports:, output_ports:, regs:)
          return true if Array(input_ports).any? { |p| p.name.to_s == target.to_s }
          return true if Array(output_ports).any? { |p| p.name.to_s == target.to_s }
          return true if Array(regs).any? { |r| r.name.to_s == target.to_s }

          false
        end

        def parse_scf_if_block(lines, start_idx, value_map:, array_meta:, array_element_refs:, diagnostics:, line_no:,
                               strict:)
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
            array_meta: array_meta,
            array_element_refs: array_element_refs,
            diagnostics: diagnostics,
            line_no: line_no,
            strict: strict,
            expected_width: result_width
          )
          else_expr = evaluate_scf_branch_value(
            else_lines,
            value_map: value_map,
            array_meta: array_meta,
            array_element_refs: array_element_refs,
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

        def evaluate_scf_branch_value(lines, value_map:, array_meta:, array_element_refs:, diagnostics:, line_no:,
                                      strict:, expected_width:)
          yield_token = nil
          temp_assigns = []
          temp_regs = []
          temp_nets = []
          temp_memories = []
          temp_write_ports = []
          temp_sync_read_ports = []
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
              array_meta: array_meta,
              array_element_refs: array_element_refs,
              assigns: temp_assigns,
              regs: temp_regs,
              nets: temp_nets,
              memories: temp_memories,
              write_ports: temp_write_ports,
              sync_read_ports: temp_sync_read_ports,
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

        def parse_body_line(body, value_map:, array_meta:, array_element_refs:, assigns:, regs:, nets:,
                            memories:, write_ports:, sync_read_ports:, processes:, instances:, output_ports:,
                            diagnostics:, line_no:, strict: false)
          body = normalize_body_line(body)
          return if body.empty? || body.start_with?('//')
          return if body.start_with?('dbg.variable ')
          return if body.match?(/\A\^bb\d+(?:\([^)]*\))?:/)
          return if body == '{' || body == '}'
          return if body.start_with?('cf.br ') || body.start_with?('cf.cond_br ')
          return if llhd_process_opener?(body)
          return if body.start_with?('llhd.wait ')
          return if body == 'llhd.halt'
          return if body == 'llhd.yield'

          if (op = fast_body_op(body))
            case op
            when 'hw.constant'
              return if fast_parse_hw_constant_line(body, value_map: value_map, diagnostics: diagnostics, line_no: line_no, strict: strict)
            when 'comb.extract'
              return if fast_parse_comb_extract_line(body, value_map: value_map)
            when 'comb.icmp'
              return if fast_parse_comb_icmp_line(body, value_map: value_map, diagnostics: diagnostics, line_no: line_no, strict: strict)
            when 'comb.mux'
              return if fast_parse_comb_mux_line(body, value_map: value_map)
            when 'comb.and', 'comb.or', 'comb.xor', 'comb.add', 'comb.sub', 'comb.mul', 'comb.shru', 'comb.shl'
              return if fast_parse_comb_binary_line(body, value_map: value_map, diagnostics: diagnostics, line_no: line_no, strict: strict)
            when 'comb.concat'
              return if fast_parse_comb_concat_line(body, value_map: value_map, diagnostics: diagnostics, line_no: line_no, strict: strict)
            when 'hw.output'
              return if fast_parse_hw_output_line(body, value_map: value_map, assigns: assigns, output_ports: output_ports)
            end
          end

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

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*arith\.constant\s+(-?\d+|true|false)(?:\s*:\s*(.+))?\z/))
            literal_value = case m[2]
                            when 'true' then 1
                            when 'false' then 0
                            else m[2].to_i
                            end

            width = if m[3]
                      mlir_type_width(m[3]) || 1
                    elsif %w[true false].include?(m[2])
                      1
                    else
                      [literal_value.to_i.bit_length, 1].max
                    end

            value_map[m[1]] = IR::Literal.new(value: literal_value, width: width)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*arith\.select\s+(#{SSA_TOKEN_PATTERN})\s*,\s*(.+)\s*:\s*(.+)\z/))
            operands = split_top_level_csv(m[3])
            return if operands.length != 2

            width = mlir_type_width(m[4]) || 1
            value_map[m[1]] = IR::Mux.new(
              condition: lookup_value(value_map, m[2], width: 1),
              when_true: lookup_value(value_map, operands[0], width: width),
              when_false: lookup_value(value_map, operands[1], width: width),
              width: width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*arith\.xori\s+(.+)\s*,\s*(.+)\s*:\s*(.+)\z/))
            width = mlir_type_width(m[4]) || 1
            value_map[m[1]] = IR::BinaryOp.new(
              op: :^,
              left: lookup_value(value_map, m[2], width: width),
              right: lookup_value(value_map, m[3], width: width),
              width: width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*arith\.extui\s+(.+)\s*:\s*(.+)\s+to\s+(.+)\z/))
            in_width = mlir_type_width(m[3]) || 1
            out_width = mlir_type_width(m[4]) || in_width
            value_map[m[1]] = IR::Resize.new(
              expr: lookup_value(value_map, m[2], width: in_width),
              width: out_width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.constant_time\s+<.*>\z/))
            value_map[m[1]] = IR::Literal.new(value: 0, width: 1)
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.array_create\s+(.+)\s*:\s*i(\d+)\z/))
            element_width = m[3].to_i
            # CIRCT prints array literals in packed/high-to-low order, while
            # hw.array_get index 0 addresses the least-significant element.
            elements = split_top_level_csv(m[2]).map { |token| lookup_value(value_map, token, width: element_width) }.reverse
            value_map[m[1]] = ArrayValue.new(
              elements: elements,
              length: elements.length,
              element_width: element_width
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.aggregate_constant\s+\[(.+)\]\s*:\s*(!hw\.array<\d+xi\d+>)\z/))
            array_type = parse_array_type(m[3])
            elements = split_top_level_csv(m[2]).map do |token|
              lookup_value(value_map, token, width: array_type[:element_width])
            end.reverse
            value_map[m[1]] = ArrayValue.new(
              elements: elements,
              length: array_type[:len],
              element_width: array_type[:element_width]
            )
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.array_get\s+(#{SSA_TOKEN_PATTERN})\[(#{SSA_TOKEN_PATTERN})\]\s*:\s*(!hw\.array<\d+xi\d+>)\s*,\s*i(\d+)\z/))
            array_type = parse_array_type(m[4])
            index_width = m[5].to_i
            array_value = lookup_array_value(value_map, m[2], array_type)
            index_expr = lookup_value(value_map, m[3], width: index_width)
            value_map[m[1]] = if array_value.is_a?(ArrayForwardRef)
                                DeferredArrayRead.new(
                                  base_token: array_value.token,
                                  base_name: array_value.name,
                                  addr: ensure_expr_with_width(index_expr, width: index_width),
                                  length: array_type[:len],
                                  element_width: array_type[:element_width]
                                )
                              else
                                elements = array_elements_from_value(
                                  array_value,
                                  length: array_type[:len],
                                  element_width: array_type[:element_width]
                                )
                                select_array_element(
                                  elements: elements,
                                  index_expr: index_expr,
                                  element_width: array_type[:element_width]
                                )
                              end
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.array_inject\s+(#{SSA_TOKEN_PATTERN})\[(#{SSA_TOKEN_PATTERN})\],\s*(.+)\s*:\s*(!hw\.array<\d+xi\d+>)\s*,\s*i(\d+)\z/))
            array_type = parse_array_type(m[5])
            array_value = lookup_array_value(value_map, m[2], array_type)
            index_expr = lookup_value(value_map, m[3], width: m[6].to_i)
            new_element = lookup_value(value_map, m[4], width: array_type[:element_width])
            value_map[m[1]] = if array_value.is_a?(ArrayForwardRef)
                                ArrayWriteCandidate.new(
                                  base_value: array_value,
                                  base_token: array_value.token,
                                  base_name: array_value.name,
                                  index_expr: ensure_expr_with_width(index_expr, width: m[6].to_i),
                                  new_element: ensure_expr_with_width(new_element, width: array_type[:element_width]),
                                  length: array_type[:len],
                                  element_width: array_type[:element_width],
                                  enable_expr: nil
                                )
                              else
                                old_elements = array_elements_from_value(
                                  array_value,
                                  length: array_type[:len],
                                  element_width: array_type[:element_width]
                                )
                                updated_elements = write_array_elements(
                                  elements: old_elements,
                                  index_expr: index_expr,
                                  new_element: new_element,
                                  element_width: array_type[:element_width]
                                )
                                ArrayValue.new(
                                  elements: updated_elements,
                                  length: array_type[:len],
                                  element_width: array_type[:element_width]
                                )
                              end
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
            # Parse initializer for side effects/value-map seeding, but model the
            # signal as a live array-backed signal so later array_get reads do
            # not collapse to declaration-time literals.
            lookup_value(value_map, m[3].strip, width: array_type[:total_width])
            value_map[m[1]] = IR::Signal.new(
              name: signal_name,
              width: array_type[:total_width]
            )
            array_meta[m[1]] = ArrayMeta.new(
              token: m[1],
              name: signal_name.to_s,
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
            if (meta = array_meta[m[2]])
              array_element_refs[m[1]] = ArrayElementRef.new(
                array_token: meta.token,
                array_name: meta.name,
                length: length,
                element_width: element_width,
                index_expr: index_expr
              )
            end
            return
          end

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*llhd\.sig\.extract\s+(#{SSA_TOKEN_PATTERN})\s+from\s+(#{SSA_TOKEN_PATTERN})\s*:\s*<i(\d+)>\s*->\s*<i(\d+)>\z/))
            base = lookup_value(value_map, m[2], width: m[4].to_i)
            index_expr = lookup_value(value_map, m[3], width: m[4].to_i)
            if index_expr.is_a?(IR::Literal)
              idx = index_expr.value.to_i
              value_map[m[1]] = IR::Slice.new(base: base, range: (idx..idx), width: m[5].to_i)
            else
              base_width = m[4].to_i
              out_width = m[5].to_i
              shifted = IR::BinaryOp.new(
                op: :>>,
                left: ensure_expr_with_width(base, width: base_width),
                right: ensure_expr_with_width(index_expr, width: [index_expr.width.to_i, 1].max),
                width: base_width
              )
              value_map[m[1]] = if out_width >= base_width
                                  shifted
                                else
                                  IR::Slice.new(
                                    base: shifted,
                                    range: (0..(out_width - 1)),
                                    width: out_width
                                  )
                                end
            end
            return
          end

          if (m = body.match(/\Allhd\.drv\s+(#{SSA_TOKEN_PATTERN}),\s*(.+)\s+after\s+#{SSA_TOKEN_PATTERN}\s*:\s*(.+)\z/))
            width = mlir_type_width(m[3])
            return unless width

            if (element_ref = array_element_refs[m[1]])
              update_array_from_element_drive!(
                value_map: value_map,
                target_ref: element_ref,
                value_token: m[2].strip,
                assigns: assigns
              )
              return
            end

            target_expr = lookup_value(value_map, m[1], width: width)
            target_name = target_expr.is_a?(IR::Signal) ? target_expr.name.to_s : m[1].sub('%', '')
            expr = lookup_expr_value(value_map, m[2].strip, width: width)
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

          if (m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.mux(?:\s+bin)?\s+(#{SSA_TOKEN_PATTERN}),\s*(#{SSA_TOKEN_PATTERN}),\s*(#{SSA_TOKEN_PATTERN})\s*:\s*(.+)\z/))
            condition = lookup_value(value_map, m[2], width: 1)
            if (array_type = array_type_from_string(m[5]))
              when_true = lookup_array_value(value_map, m[3], array_type)
              when_false = lookup_array_value(value_map, m[4], array_type)
              candidate =
                if when_true.is_a?(ArrayWriteCandidate) &&
                   array_base_matches?(
                     when_false,
                     base_token: when_true.base_token,
                     base_name: when_true.base_name,
                     total_width: array_type[:total_width]
                   )
                  ArrayWriteCandidate.new(
                    base_value: when_true.base_value,
                    base_token: when_true.base_token,
                    base_name: when_true.base_name,
                    index_expr: when_true.index_expr,
                    new_element: when_true.new_element,
                    length: when_true.length,
                    element_width: when_true.element_width,
                    enable_expr: condition
                  )
                end

              value_map[m[1]] = candidate || IR::Mux.new(
                condition: condition,
                when_true: pack_array_value(when_true),
                when_false: pack_array_value(when_false),
                width: array_type[:total_width]
              )
              return
            end

            width = mlir_type_width(m[5])
            return unless width

            value_map[m[1]] = IR::Mux.new(
              condition: condition,
              when_true: lookup_expr_value(value_map, m[3], width: width),
              when_false: lookup_expr_value(value_map, m[4], width: width),
              width: width
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

          if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*seq\.to_clock\b/)
            return if parse_seq_to_clock_line(body, value_map: value_map, nets: nets, assigns: assigns)

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.to_clock syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.to_clock'
            )
            return
          end

          if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*seq\.clock_inv\b/)
            return if parse_seq_clock_inv_line(
              body,
              value_map: value_map,
              nets: nets,
              assigns: assigns
            )

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.clock_inv syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.clock_inv'
            )
            return
          end

          if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*seq\.firmem\.read_port\b/)
            return if parse_seq_firmem_read_port_line(
              body,
              value_map: value_map
            )

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.firmem.read_port syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.firmem.read_port'
            )
            return
          end

          if body.match?(/\Aseq\.firmem\.write_port\b/)
            return if parse_seq_firmem_write_port_line(
              body,
              value_map: value_map,
              memories: memories,
              write_ports: write_ports
            )

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.firmem.write_port syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.firmem.write_port'
            )
            return
          end

          if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*seq\.firmem\b/)
            return if parse_seq_firmem_line(
              body,
              value_map: value_map,
              memories: memories
            )

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.firmem syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.firmem'
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

          if body.match?(/\A#{SSA_TOKEN_PATTERN}\s*=\s*seq\.firreg\b/)
            return if parse_seq_firreg_line(
              body,
              value_map: value_map,
              regs: regs,
              memories: memories,
              write_ports: write_ports,
              processes: processes,
              diagnostics: diagnostics,
              line_no: line_no
            )

            diagnostics << Diagnostic.new(
              severity: strict ? :error : :warning,
              message: "Unsupported seq.firreg syntax, skipped: #{body}",
              line: line_no,
              column: 1,
              op: 'seq.firreg'
            )
            return
          end

          if body.include?('hw.instance')
            return if parse_hw_instance_line(
              body,
              value_map: value_map,
              nets: nets,
              regs: regs,
              output_ports: output_ports,
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

        def fast_body_op(body)
          if body.start_with?('%')
            eq_idx = body.index('=')
            return nil unless eq_idx

            rhs = body[(eq_idx + 1)..].lstrip
            op_end = rhs.index(/[ \t]/) || rhs.length
            return rhs[0...op_end]
          end

          return 'hw.output' if body.start_with?('hw.output')

          nil
        end

        def fast_parse_hw_constant_line(body, value_map:, diagnostics:, line_no:, strict:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*hw\.constant\s+(-?\d+|true|false)(?:\s*:\s*i(\d+))?\z/)
          return false unless m

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
                    return true
                  end

          value_map[m[1]] = import_literal(value: literal_value, width: width)
          true
        end

        def fast_parse_comb_extract_line(body, value_map:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.extract\s+(#{SSA_TOKEN_PATTERN})\s+from\s+(\d+)\s*:\s*\(i(\d+)\)\s*->\s*i(\d+)\z/)
          return false unless m

          low = m[3].to_i
          in_width = m[4].to_i
          out_width = m[5].to_i
          value_map[m[1]] = IR::Slice.new(
            base: lookup_value(value_map, m[2], width: in_width),
            range: (low..(low + out_width - 1)),
            width: out_width
          )
          true
        end

        def fast_parse_comb_icmp_line(body, value_map:, diagnostics:, line_no:, strict:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.icmp\s+(\w+)\s+(.+)\s*:\s*i(\d+)\z/)
          return false unless m

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
            return true
          end

          in_width = m[4].to_i
          value_map[m[1]] = IR::BinaryOp.new(
            op: pred_map.fetch(pred, :==),
            left: lookup_value(value_map, operands[0], width: in_width),
            right: lookup_value(value_map, operands[1], width: in_width),
            width: 1
          )
          true
        end

        def fast_parse_comb_mux_line(body, value_map:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.mux(?:\s+bin)?\s+(#{SSA_TOKEN_PATTERN}),\s*(#{SSA_TOKEN_PATTERN}),\s*(#{SSA_TOKEN_PATTERN})\s*:\s*(.+)\z/)
          return false unless m
          return false if array_type_from_string(m[5])

          width = mlir_type_width(m[5])
          return true unless width

          value_map[m[1]] = IR::Mux.new(
            condition: lookup_value(value_map, m[2], width: 1),
            when_true: lookup_expr_value(value_map, m[3], width: width),
            when_false: lookup_expr_value(value_map, m[4], width: width),
            width: width
          )
          true
        end

        def fast_parse_comb_binary_line(body, value_map:, diagnostics:, line_no:, strict:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.(add|sub|mul|divu|divs|modu|mods|and|or|xor|shl|shr_u|shr_s|shru|shrs)\s+(?:bin\s+)?(.+)\s*:\s*i(\d+)\z/)
          return false unless m

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
            return true
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
            return true
          end

          op_symbol = op_map[op_name] || op_name.to_sym
          exprs = operands.map { |token| lookup_value(value_map, token, width: width) }
          value_map[m[1]] = exprs.drop(1).reduce(exprs.first) do |lhs, rhs|
            IR::BinaryOp.new(op: op_symbol, left: lhs, right: rhs, width: width)
          end
          true
        end

        def fast_parse_comb_concat_line(body, value_map:, diagnostics:, line_no:, strict:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*comb\.concat\s+(.+)\s*:\s*(.+)\z/)
          return false unless m

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
            return true
          end

          parts = tokens.each_with_index.map { |tok, i| lookup_value(value_map, tok, width: widths[i]) }
          value_map[m[1]] = IR::Concat.new(parts: parts, width: widths.sum)
          true
        end

        def fast_parse_hw_output_line(body, value_map:, assigns:, output_ports:)
          return true if body == 'hw.output'

          m = body.match(/\Ahw\.output\s+(.+)\s*:\s*(.+)\z/)
          return false unless m

          values = split_top_level_csv(m[1])
          output_ports.each_with_index do |port, out_idx|
            next if values[out_idx].nil?

            assigns << IR::Assign.new(target: port.name.to_s, expr: lookup_value(value_map, values[out_idx], width: port.width))
          end
          true
        end

        def normalize_body_line(body)
          text = body.to_s.strip
          return text if text.empty?
          text = text.sub(/\s*\/\/.*\z/, '').strip
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

        def parse_hw_instance_line(body, value_map:, nets:, regs:, output_ports:, instances:, diagnostics:, line_no:)
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
            width = infer_width_from_connection(conn, m[:outputs], idx)
            signal_name = conn.signal.to_s
            value_map[token] = IR::Signal.new(name: signal_name, width: width)
            declare_instance_result_net!(
              nets: nets,
              regs: regs,
              output_ports: output_ports,
              name: signal_name,
              width: width
            )
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
                direction: :in,
                width: named[3].to_i
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
                direction: :in,
                width: unnamed[2].to_i
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
                direction: :out,
                width: named[2].to_i
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
                direction: :out,
                width: token.delete_prefix('i').to_i
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

        def declare_instance_result_net!(nets:, regs:, output_ports:, name:, width:)
          target = name.to_s
          return if target.empty?
          return if Array(output_ports).any? { |port| port.name.to_s == target }
          return if Array(nets).any? { |net| net.name.to_s == target }
          return if Array(regs).any? { |reg| reg.name.to_s == target }

          nets << IR::Net.new(name: target, width: width.to_i)
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
                   elsif (with_reset = args.match(/\A(#{SSA_TOKEN_PATTERN})\s*,\s*(#{SSA_TOKEN_PATTERN})\s+reset(?:\s+async)?\s+(#{SSA_TOKEN_PATTERN})\s*,\s*(#{SSA_TOKEN_PATTERN}|-?\d+|true|false)\s*\z/))
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
            clock: clock_name_for_token(value_map, parsed[:clock])
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

        def parse_seq_to_clock_line(body, value_map:, nets:, assigns:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*seq\.to_clock\s+(#{SSA_TOKEN_PATTERN})\z/)
          return false unless m

          clock_expr = lookup_value(value_map, m[2], width: 1)
          if clock_expr.is_a?(IR::Signal)
            value_map[m[1]] = IR::Signal.new(name: clock_expr.name.to_s, width: 1)
            return true
          end

          clock_name = m[1].sub('%', '')
          nets << IR::Net.new(name: clock_name, width: 1) unless nets.any? { |net| net.name.to_s == clock_name }
          assigns << IR::Assign.new(
            target: clock_name,
            expr: ensure_expr_with_width(clock_expr, width: 1)
          )
          value_map[m[1]] = IR::Signal.new(name: clock_name, width: 1)
          true
        end

        def parse_seq_clock_inv_line(body, value_map:, nets:, assigns:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*seq\.clock_inv\s+(#{SSA_TOKEN_PATTERN})\z/)
          return false unless m

          clock_name = clock_name_for_token(value_map, m[2])
          inverted_name = m[1].sub('%', '')
          nets << IR::Net.new(name: inverted_name, width: 1) unless nets.any? { |net| net.name.to_s == inverted_name }
          assigns << IR::Assign.new(
            target: inverted_name,
            expr: IR::UnaryOp.new(
              op: :'~',
              operand: IR::Signal.new(name: clock_name, width: 1),
              width: 1
            )
          )
          value_map[m[1]] = IR::Signal.new(name: inverted_name, width: 1)
          true
        end

        def parse_seq_firmem_line(body, value_map:, memories:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*seq\.firmem\s+.+\s*:\s*(<\s*\d+\s*x\s*\d+\s*>)\z/)
          return false unless m

          mem_type = parse_firmem_type(m[2])
          mem_name = m[1].sub('%', '')
          unless Array(memories).any? { |memory| memory.name.to_s == mem_name }
            memories << IR::Memory.new(
              name: mem_name,
              depth: mem_type[:depth],
              width: mem_type[:width],
              initial_data: []
            )
          end
          value_map[m[1]] = ArrayForwardRef.new(
            token: m[1],
            name: mem_name,
            length: mem_type[:depth],
            element_width: mem_type[:width]
          )
          true
        end

        def parse_seq_firmem_read_port_line(body, value_map:)
          m = body.match(
            /\A(#{SSA_TOKEN_PATTERN})\s*=\s*seq\.firmem\.read_port\s+(#{SSA_TOKEN_PATTERN})\[(#{SSA_TOKEN_PATTERN})\],\s*clock\s+(#{SSA_TOKEN_PATTERN})(?:\s+enable\s+(#{SSA_TOKEN_PATTERN}))?\s*:\s*(<\s*\d+\s*x\s*\d+\s*>)\z/
          )
          return false unless m

          mem_type = parse_firmem_type(m[6])
          memory_name = m[2].sub('%', '')
          addr_width = [Math.log2(mem_type[:depth]).ceil, 1].max
          read_expr = IR::MemoryRead.new(
            memory: memory_name,
            addr: lookup_value(value_map, m[3], width: addr_width),
            width: mem_type[:width]
          )
          if m[5]
            enable = lookup_value(value_map, m[5], width: 1)
            read_expr = IR::Mux.new(
              condition: enable,
              when_true: read_expr,
              when_false: IR::Literal.new(value: 0, width: mem_type[:width]),
              width: mem_type[:width]
            )
          end
          value_map[m[1]] = read_expr
          true
        end

        def parse_seq_firmem_write_port_line(body, value_map:, memories:, write_ports:)
          m = body.match(
            /\Aseq\.firmem\.write_port\s+(#{SSA_TOKEN_PATTERN})\[(#{SSA_TOKEN_PATTERN})\]\s*=\s*(#{SSA_TOKEN_PATTERN}),\s*clock\s+(#{SSA_TOKEN_PATTERN})\s+enable\s+(#{SSA_TOKEN_PATTERN})\s*:\s*(<\s*\d+\s*x\s*\d+\s*>)\z/
          )
          return false unless m

          mem_type = parse_firmem_type(m[6])
          memory_name = m[1].sub('%', '')
          unless Array(memories).any? { |memory| memory.name.to_s == memory_name }
            memories << IR::Memory.new(
              name: memory_name,
              depth: mem_type[:depth],
              width: mem_type[:width],
              initial_data: []
            )
          end
          addr_width = [Math.log2(mem_type[:depth]).ceil, 1].max
          write_ports << IR::MemoryWritePort.new(
            memory: memory_name,
            clock: clock_name_for_token(value_map, m[4]),
            addr: lookup_value(value_map, m[2], width: addr_width),
            data: lookup_value(value_map, m[3], width: mem_type[:width]),
            enable: lookup_value(value_map, m[5], width: 1)
          )
          true
        end

        def parse_seq_firreg_line(body, value_map:, regs:, memories:, write_ports:, processes:, diagnostics:, line_no:)
          m = body.match(/\A(#{SSA_TOKEN_PATTERN})\s*=\s*seq\.firreg\s+(.+)\s*:\s*(.+)\z/)
          return false unless m

          out_token = m[1]
          args = strip_trailing_attr_dict(m[2].strip)
          type = m[3].strip
          array_type = array_type_from_string(type)
          width = mlir_type_width(type)
          return false unless width

          parsed = if (plain = args.match(/\A(.+?)\s+clock\s+(#{SSA_TOKEN_PATTERN})\s*\z/))
                     {
                       data: plain[1],
                       clock: plain[2],
                       reset: nil,
                       reset_value: nil
                     }
                   elsif (with_reset = args.match(/\A(.+?)\s+clock\s+(#{SSA_TOKEN_PATTERN})\s+reset(?:\s+async)?\s+(#{SSA_TOKEN_PATTERN})\s*,\s*(#{SSA_TOKEN_PATTERN}|-?\d+|true|false)\s*\z/))
                     {
                       data: with_reset[1],
                       clock: with_reset[2],
                       reset: with_reset[3],
                       reset_value: with_reset[4]
                     }
                   end
          return false unless parsed

          reg_name = out_token.sub('%', '')
          if array_type
            return false if parsed[:reset]

            array_value = lookup_array_value(value_map, parsed[:data], array_type)
            if array_value.is_a?(ArrayWriteCandidate) && array_value.base_name.to_s == reg_name
              memories << IR::Memory.new(
                name: reg_name,
                depth: array_type[:len],
                width: array_type[:element_width],
                initial_data: []
              )
              write_ports << IR::MemoryWritePort.new(
                memory: reg_name,
                clock: clock_name_for_token(value_map, parsed[:clock]),
                addr: ensure_expr_with_width(
                  array_value.index_expr,
                  width: [[Math.log2(array_type[:len]).ceil, 1].max, 1].max
                ),
                data: ensure_expr_with_width(array_value.new_element, width: array_type[:element_width]),
                enable: ensure_expr_with_width(array_value.enable_expr || import_literal(value: 1, width: 1), width: 1)
              )
              value_map[out_token] = ArrayForwardRef.new(
                token: out_token,
                name: reg_name,
                length: array_type[:len],
                element_width: array_type[:element_width]
              )
              return true
            end
          end

          data_expr = lookup_expr_value(value_map, parsed[:data], width: width)
          reset_expr = parsed[:reset_value] ? lookup_value(value_map, parsed[:reset_value], width: width) : nil
          reg_reset = case reset_expr
                      when IR::Literal then reset_expr.value
                      else nil
                      end
          regs << IR::Reg.new(name: reg_name, width: width, reset_value: reg_reset)

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
            clock: clock_name_for_token(value_map, parsed[:clock])
          )
          value_map[out_token] = IR::Signal.new(name: reg_name, width: width)
          true
        rescue StandardError => e
          diagnostics << Diagnostic.new(
            severity: :warning,
            message: "Failed parsing seq.firreg at line #{line_no}: #{e.class}: #{e.message}",
            line: line_no,
            column: 1,
            op: 'seq.firreg'
          )
          false
        end

        def clock_name_for_token(value_map, token)
          clock_expr = lookup_value(value_map, token, width: 1)
          return clock_expr.name.to_s if clock_expr.respond_to?(:name) && clock_expr.name

          normalize_value_token(token).sub('%', '')
        end

        def lookup_value(value_map, token, width: 1)
          token = normalize_value_token(token)
          return value_map[token] if value_map.key?(token)
          return import_literal(value: 1, width: width) if token == 'true'
          return import_literal(value: 0, width: width) if token == 'false'
          if token.start_with?('%')
            Thread.current[:rhdl_circt_import_forward_refs_seen] = true
            return import_signal(name: token.sub('%', ''), width: width)
          end

          import_literal(value: token.to_i, width: width)
        end

        def import_literal(value:, width:)
          cache = Thread.current[:rhdl_circt_import_literal_cache]
          literal_value = value.to_i
          literal_width = width.to_i
          return IR::Literal.new(value: literal_value, width: literal_width) unless cache

          cache[[literal_value, literal_width]] ||= IR::Literal.new(value: literal_value, width: literal_width)
        end

        def import_signal(name:, width:)
          cache = Thread.current[:rhdl_circt_import_signal_cache]
          signal_name = name.to_s
          signal_width = width.to_i
          return IR::Signal.new(name: signal_name, width: signal_width) unless cache

          cache[[signal_name, signal_width]] ||= IR::Signal.new(name: signal_name, width: signal_width)
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

        def mlir_type_width(text)
          token = text.to_s.strip
          return integer_type_width(token) if integer_type_width(token)
          if (array_type = array_type_from_string(token))
            return array_type[:total_width]
          end

          if (m = token.match(/\A!llhd\.ref<i(\d+)>\z/))
            return m[1].to_i
          end
          if (m = token.match(/\A<\s*i(\d+)\s*>\z/))
            return m[1].to_i
          end

          nil
        end

        def array_elements_from_value(value, length:, element_width:)
          cache = Thread.current[:rhdl_circt_import_array_elements_cache]
          cache_key = [value.object_id, length.to_i, element_width.to_i]
          if cache && (cached = cache[cache_key])
            return cached
          end

          elements = case value
                     when ArrayValue
                       elems = value.elements.first(length)
                       if elems.length < length
                         elems + Array.new(length - elems.length) { import_literal(value: 0, width: element_width) }
                       else
                         elems
                       end
                     when ArrayWriteCandidate
                       base_elements = array_elements_from_value(
                         value.base_value,
                         length: length,
                         element_width: element_width
                       )
                       write_array_elements(
                         elements: base_elements,
                         index_expr: ensure_expr_with_width(
                           value.index_expr,
                           width: [[Math.log2(length.to_i).ceil, 1].max, 1].max
                         ),
                         new_element: ensure_expr_with_width(value.new_element, width: element_width),
                         element_width: element_width
                       )
                     when ArrayForwardRef
                       base = import_signal(name: value.name, width: value.width)
                       Array.new(length) do |idx|
                         low = idx * element_width
                         IR::Slice.new(base: base, range: (low..(low + element_width - 1)), width: element_width)
                       end
                     else
                       base = ensure_expr_with_width(value, width: length * element_width)
                       Array.new(length) do |idx|
                         low = idx * element_width
                         IR::Slice.new(base: base, range: (low..(low + element_width - 1)), width: element_width)
                       end
                     end

          cache[cache_key] = elements if cache
          elements
        end

        def ensure_expr_with_width(value, width:)
          return value if value.is_a?(IR::Expr)

          case value
          when String, Symbol
            import_signal(name: value.to_s, width: width)
          else
            import_literal(value: 0, width: width)
          end
        end

        def select_array_element(elements:, index_expr:, element_width:)
          return import_literal(value: 0, width: element_width) if elements.empty?
          # Large dynamic array selects (for inferred RAMs) can explode into
          # extremely large mux trees that are not loadable by Ruby parsers.
          # Keep import stable by capping expansion size.
          if elements.length > MAX_ARRAY_SELECT_ELEMENTS && !index_expr.is_a?(IR::Literal)
            return import_literal(value: 0, width: element_width)
          end

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

        def declared_signal_names(input_ports, output_ports, nets, regs, memories = [])
          names = Set.new
          Array(input_ports).each { |port| names << port.name.to_s }
          Array(output_ports).each { |port| names << port.name.to_s }
          Array(nets).each { |net| names << net.name.to_s }
          Array(regs).each { |reg| names << reg.name.to_s }
          Array(memories).each { |memory| names << memory.name.to_s }
          names
        end

        def resolve_forward_refs_in_assigns(assigns, value_map:, declared_names:, memory_names:, signal_memo:, expr_memo:)
          Array(assigns).map do |assign|
            IR::Assign.new(
              target: assign.target,
              expr: resolve_forward_expr(
                assign.expr,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              )
            )
          end
        end

        def resolve_forward_refs_in_processes(processes, value_map:, declared_names:, memory_names:, signal_memo:, expr_memo:)
          Array(processes).map do |process|
            statements = Array(process.statements).map do |stmt|
              resolve_forward_statement(
                stmt,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
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

        def resolve_forward_refs_in_write_ports(write_ports, value_map:, declared_names:, memory_names:, signal_memo:, expr_memo:)
          Array(write_ports).map do |write_port|
            IR::MemoryWritePort.new(
              memory: write_port.memory,
              clock: write_port.clock,
              addr: resolve_forward_expr(
                write_port.addr,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              ),
              data: resolve_forward_expr(
                write_port.data,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              ),
              enable: resolve_forward_expr(
                write_port.enable,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              )
            )
          end
        end

        def resolve_forward_refs_in_sync_read_ports(sync_read_ports, value_map:, declared_names:, memory_names:,
                                                    signal_memo:, expr_memo:)
          Array(sync_read_ports).map do |read_port|
            IR::MemorySyncReadPort.new(
              memory: read_port.memory,
              clock: read_port.clock,
              addr: resolve_forward_expr(
                read_port.addr,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              ),
              data: read_port.data,
              enable: read_port.enable && resolve_forward_expr(
                read_port.enable,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              )
            )
          end
        end

        def resolve_forward_refs_in_instances(instances, value_map:, declared_names:, memory_names:, signal_memo:,
                                              expr_memo:)
          Array(instances).map do |inst|
            connections = Array(inst.connections).map do |conn|
              signal = conn.signal
              resolved_signal = if signal.is_a?(IR::Expr)
                                  resolve_forward_expr(
                                    signal,
                                    value_map: value_map,
                                    declared_names: declared_names,
                                    memory_names: memory_names,
                                    signal_memo: signal_memo,
                                    expr_memo: expr_memo
                                  )
                                else
                                  signal
                                end
              IR::PortConnection.new(
                port_name: conn.port_name,
                signal: resolved_signal,
                direction: conn.direction,
                width: conn.width
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

        def resolve_forward_statement(stmt, value_map:, declared_names:, memory_names:, signal_memo:, expr_memo:)
          case stmt
          when IR::SeqAssign
            IR::SeqAssign.new(
              target: stmt.target,
              expr: resolve_forward_expr(
                stmt.expr,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              )
            )
          when IR::If
            IR::If.new(
              condition: resolve_forward_expr(
                stmt.condition,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo
              ),
              then_statements: Array(stmt.then_statements).map do |inner|
                resolve_forward_statement(
                  inner,
                  value_map: value_map,
                  declared_names: declared_names,
                  memory_names: memory_names,
                  signal_memo: signal_memo,
                  expr_memo: expr_memo
                )
              end,
              else_statements: Array(stmt.else_statements).map do |inner|
                resolve_forward_statement(
                  inner,
                  value_map: value_map,
                  declared_names: declared_names,
                  memory_names: memory_names,
                  signal_memo: signal_memo,
                  expr_memo: expr_memo
                )
              end
            )
          else
            stmt
          end
        end

        def resolve_forward_expr(expr, value_map:, declared_names:, memory_names:, signal_memo:, expr_memo:,
                                 visiting: Set.new)
          expr_key = expr.object_id
          return expr_memo[expr_key] if expr_memo.key?(expr_key)
          return expr if visiting.include?(expr_key)

          visiting << expr_key

          case expr
          when IR::Signal
            name = expr.name.to_s
            resolved = if declared_names.include?(name)
                         expr
                       else
                         key = "%#{name}"
                         candidate = value_map[key]
                         if !candidate || candidate.equal?(expr) || visiting.include?(key)
                           expr
                         elsif signal_memo.key?(key)
                           signal_memo[key]
                         else
                           visiting << key
                           resolved_signal = resolve_forward_expr(
                             candidate,
                             value_map: value_map,
                             declared_names: declared_names,
                             memory_names: memory_names,
                             signal_memo: signal_memo,
                             expr_memo: expr_memo,
                             visiting: visiting
                           )
                           visiting.delete(key)
                           signal_memo[key] = resolved_signal
                         end
                       end
          when IR::Literal
            resolved = expr
          when IR::UnaryOp
            resolved = IR::UnaryOp.new(
              op: expr.op,
              operand: resolve_forward_expr(
                expr.operand,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::BinaryOp
            resolved = IR::BinaryOp.new(
              op: expr.op,
              left: resolve_forward_expr(
                expr.left,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              right: resolve_forward_expr(
                expr.right,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::Mux
            resolved = IR::Mux.new(
              condition: resolve_forward_expr(
                expr.condition,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              when_true: resolve_forward_expr(
                expr.when_true,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              when_false: resolve_forward_expr(
                expr.when_false,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::Slice
            resolved = IR::Slice.new(
              base: resolve_forward_expr(
                expr.base,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              range: expr.range,
              width: expr.width
            )
          when IR::Concat
            resolved = IR::Concat.new(
              parts: Array(expr.parts).map do |part|
                resolve_forward_expr(
                  part,
                  value_map: value_map,
                  declared_names: declared_names,
                  memory_names: memory_names,
                  signal_memo: signal_memo,
                  expr_memo: expr_memo,
                  visiting: visiting
                )
              end,
              width: expr.width
            )
          when IR::Resize
            resolved = IR::Resize.new(
              expr: resolve_forward_expr(
                expr.expr,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when IR::Case
            resolved = IR::Case.new(
              selector: resolve_forward_expr(
                expr.selector,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              cases: Array(expr.cases).map do |key, value|
                [
                  key,
                  resolve_forward_expr(
                    value,
                    value_map: value_map,
                    declared_names: declared_names,
                    memory_names: memory_names,
                    signal_memo: signal_memo,
                    expr_memo: expr_memo,
                    visiting: visiting
                  )
                ]
              end.to_h,
              default: resolve_forward_expr(
                expr.default,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              width: expr.width
            )
          when DeferredArrayRead
            resolved_addr = resolve_forward_expr(
              expr.addr,
              value_map: value_map,
              declared_names: declared_names,
              memory_names: memory_names,
              signal_memo: signal_memo,
              expr_memo: expr_memo,
              visiting: visiting
            )
            if memory_names.include?(expr.base_name.to_s)
              resolved = IR::MemoryRead.new(
                memory: expr.base_name,
                addr: resolved_addr,
                width: expr.width
              )
            else
              base_signal = import_signal(name: expr.base_name, width: expr.length.to_i * expr.element_width.to_i)
              elements = Array.new(expr.length.to_i) do |idx|
                low = idx * expr.element_width.to_i
                IR::Slice.new(
                  base: base_signal,
                  range: (low..(low + expr.element_width.to_i - 1)),
                  width: expr.element_width.to_i
                )
              end
              resolved = select_array_element(
                elements: elements,
                index_expr: resolved_addr,
                element_width: expr.element_width.to_i
              )
            end
          when IR::MemoryRead
            resolved = IR::MemoryRead.new(
              memory: expr.memory,
              addr: resolve_forward_expr(
                expr.addr,
                value_map: value_map,
                declared_names: declared_names,
                memory_names: memory_names,
                signal_memo: signal_memo,
                expr_memo: expr_memo,
                visiting: visiting
              ),
              width: expr.width
            )
          else
            resolved = expr
          end

          expr_memo[expr_key] = resolved
          resolved
        rescue SystemStackError
          expr
        ensure
          visiting.delete(expr_key) if expr_key
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

        def normalize_instance_port_connections(modules)
          module_index = modules.each_with_object({}) { |mod, acc| acc[mod.name.to_s] = mod }

          modules.map do |mod|
            next mod if mod.instances.nil? || mod.instances.empty?

            changed = false
            normalized_instances = mod.instances.map do |inst|
              target_mod = module_index[inst.module_name.to_s]
              next inst unless target_mod

              exact_ports = {}
              downcase_ports = {}
              target_mod.ports.each do |port|
                port_name = port.name.to_s
                exact_ports[port_name] = port_name
                downcase_ports[port_name.downcase] ||= port_name
              end

              inst_changed = false
              normalized_connections = Array(inst.connections).map do |conn|
                original_name = conn.port_name.to_s
                normalized_name = exact_ports[original_name] || downcase_ports[original_name.downcase] || original_name
                inst_changed ||= normalized_name != original_name
                IR::PortConnection.new(
                  port_name: normalized_name,
                  signal: conn.signal,
                  direction: conn.direction,
                  width: conn.width
                )
              end

              unless inst_changed
                next inst
              end

              changed = true
              IR::Instance.new(
                name: inst.name,
                module_name: inst.module_name,
                connections: normalized_connections,
                parameters: inst.parameters || {}
              )
            end

            next mod unless changed

            IR::ModuleOp.new(
              name: mod.name,
              ports: mod.ports,
              nets: mod.nets,
              regs: mod.regs,
              assigns: mod.assigns,
              processes: mod.processes,
              instances: normalized_instances,
              memories: mod.memories,
              write_ports: mod.write_ports,
              sync_read_ports: mod.sync_read_ports,
              parameters: mod.parameters
            )
          end
        end

        def recover_memory_like_registers(modules)
          current = Array(modules)

          loop do
            changed = false
            current = current.map do |mod|
              next_mod, mod_changed = recover_memory_like_registers_in_module(mod)
              changed ||= mod_changed
              next_mod
            end
            break current unless changed
          end
        end

        def recover_memory_like_registers_in_module(mod)
          recovered = {}
          remaining_processes = []

          Array(mod.processes).each do |process|
            candidate = nil
            if process.clocked && Array(process.statements).length == 1
              stmt = process.statements.first
              if stmt.is_a?(IR::SeqAssign)
                candidate = extract_packed_vector_memory_write(stmt.target.to_s, stmt.expr)
                candidate ||= extract_packed_vector_memory_copy(stmt.target.to_s, stmt.expr)
                if candidate
                  recovered[stmt.target.to_s] = candidate.merge(memory: stmt.target.to_s, clock: process.clock.to_s)
                end
              end
            end

            remaining_processes << process unless candidate
          end

          return [mod, false] if recovered.empty?

          memories = Array(mod.memories).dup
          write_ports = Array(mod.write_ports).dup

          recovered.each_value do |info|
            memories << IR::Memory.new(
              name: info[:memory],
              depth: info[:depth],
              width: info[:element_width],
              initial_data: []
            )

            if info[:copy_from_memory]
              addr_width = [Math.log2(info[:depth]).ceil, 1].max
              info[:depth].times do |slot|
                addr = IR::Literal.new(value: slot, width: addr_width)
                write_ports << IR::MemoryWritePort.new(
                  memory: info[:memory],
                  clock: info[:clock],
                  addr: addr,
                  data: IR::MemoryRead.new(
                    memory: info[:copy_from_memory],
                    addr: addr,
                    width: info[:element_width]
                  ),
                  enable: info[:enable]
                )
              end
            else
              write_ports << IR::MemoryWritePort.new(
                memory: info[:memory],
                clock: info[:clock],
                addr: info[:addr],
                data: info[:data],
                enable: info[:enable]
              )
            end
          end

          [
            IR::ModuleOp.new(
              name: mod.name,
              ports: mod.ports,
              nets: mod.nets,
              regs: Array(mod.regs).reject { |reg| recovered.key?(reg.name.to_s) },
              assigns: Array(mod.assigns).map do |assign|
                IR::Assign.new(
                  target: assign.target,
                  expr: rewrite_memory_like_register_reads(assign.expr, recovered)
                )
              end,
              processes: Array(remaining_processes).map do |process|
                IR::Process.new(
                  name: process.name,
                  statements: rewrite_memory_like_register_statements(process.statements, recovered),
                  clocked: process.clocked,
                  clock: process.clock,
                  sensitivity_list: process.sensitivity_list
                )
              end,
              instances: mod.instances,
              memories: memories,
              write_ports: write_ports,
              sync_read_ports: mod.sync_read_ports,
              parameters: mod.parameters
            ),
            true
          ]
        end

        def extract_packed_vector_memory_write(target_name, expr)
          packed_write, write_enable_expr = extract_packed_vector_update(target_name, expr)
          return nil unless packed_write

          parts = Array(packed_write.parts)
          return nil if parts.empty?

          element_width = parts.first.width.to_i
          return nil unless element_width.positive? && parts.all? { |part| part.width.to_i == element_width }

          addr_expr = nil
          data_expr = nil

          parts.each_with_index do |part, part_index|
            slot_index = parts.length - 1 - part_index
            current = extract_packed_vector_memory_part(
              part,
              target_name: target_name,
              slot_index: slot_index,
              element_width: element_width
            )
            return nil unless current

            addr_expr ||= current[:addr]
            data_expr ||= current[:data]
            return nil unless expr_equivalent?(addr_expr, current[:addr])
            return nil unless expr_equivalent?(data_expr, current[:data])
          end

          {
            depth: parts.length,
            element_width: element_width,
            addr: ensure_expr_with_width(addr_expr, width: [addr_expr.width.to_i, 1].max),
            data: ensure_expr_with_width(data_expr, width: element_width),
            enable: ensure_expr_with_width(write_enable_expr, width: 1)
          }
        end

        def extract_packed_vector_memory_copy(target_name, expr)
          packed_write, write_enable_expr = extract_packed_vector_update(target_name, expr)
          return nil unless packed_write

          parts = Array(packed_write.parts)
          return nil if parts.empty?

          element_width = parts.first.width.to_i
          return nil unless element_width.positive? && parts.all? { |part| part.width.to_i == element_width }

          source_memory = nil

          parts.each_with_index do |part, part_index|
            slot_index = parts.length - 1 - part_index
            current = extract_packed_vector_memory_copy_part(
              part,
              slot_index: slot_index,
              element_width: element_width
            )
            return nil unless current

            source_memory ||= current[:memory]
            return nil unless source_memory == current[:memory]
          end

          {
            depth: parts.length,
            element_width: element_width,
            copy_from_memory: source_memory,
            enable: ensure_expr_with_width(write_enable_expr, width: 1)
          }
        end

        def extract_packed_vector_update(target_name, expr)
          case expr
          when IR::Mux
            if signal_ref_to_target?(expr.when_true, target_name) && expr.when_false.is_a?(IR::Concat)
              [expr.when_false, invert_boolean_expr(expr.condition)]
            elsif signal_ref_to_target?(expr.when_false, target_name) && expr.when_true.is_a?(IR::Concat)
              [expr.when_true, expr.condition]
            else
              nil
            end
          when IR::Concat
            [expr, import_literal(value: 1, width: 1)]
          else
            nil
          end
        end

        def extract_packed_vector_memory_part(part, target_name:, slot_index:, element_width:)
          case part
          when IR::Mux
            return nil unless slice_matches_packed_memory_slot?(part.when_false, target_name, slot_index, element_width)

            addr, literal = equality_selector_for_expr(part.condition)
            return nil unless literal == slot_index

            { addr: addr, data: part.when_true }
          when IR::Slice
            return nil unless slice_matches_packed_memory_slot?(part, target_name, slot_index, element_width)

            {
              addr: import_literal(value: slot_index, width: [Math.log2(slot_index + 1).ceil, 1].max),
              data: part
            }
          else
            nil
          end
        end

        def extract_packed_vector_memory_copy_part(part, slot_index:, element_width:)
          return nil unless part.is_a?(IR::MemoryRead)
          return nil unless part.width.to_i == element_width.to_i
          return nil unless part.addr.is_a?(IR::Literal)
          return nil unless part.addr.value.to_i == slot_index.to_i

          { memory: part.memory.to_s }
        end

        def equality_selector_for_expr(expr)
          return nil unless expr.is_a?(IR::BinaryOp) && expr.op.to_sym == :==

          if expr.left.is_a?(IR::Literal)
            [expr.right, expr.left.value.to_i]
          elsif expr.right.is_a?(IR::Literal)
            [expr.left, expr.right.value.to_i]
          end
        end

        def signal_ref_to_target?(expr, target_name)
          expr.is_a?(IR::Signal) && expr.name.to_s == target_name.to_s
        end

        def slice_matches_packed_memory_slot?(expr, target_name, slot_index, element_width)
          return false unless expr.is_a?(IR::Slice)
          return false unless signal_ref_to_target?(expr.base, target_name)

          low = expr.range.begin.to_i
          high = expr.range.end.to_i
          low == slot_index.to_i * element_width.to_i &&
            high == low + element_width.to_i - 1 &&
            expr.width.to_i == element_width.to_i
        end

        def invert_boolean_expr(expr)
          IR::BinaryOp.new(
            op: :^,
            left: ensure_expr_with_width(expr, width: 1),
            right: IR::Literal.new(value: 1, width: 1),
            width: 1
          )
        end

        def rewrite_memory_like_register_statements(statements, recovered)
          Array(statements).map do |stmt|
            case stmt
            when IR::SeqAssign
              IR::SeqAssign.new(
                target: stmt.target,
                expr: rewrite_memory_like_register_reads(stmt.expr, recovered)
              )
            when IR::If
              IR::If.new(
                condition: rewrite_memory_like_register_reads(stmt.condition, recovered),
                then_statements: rewrite_memory_like_register_statements(stmt.then_statements, recovered),
                else_statements: rewrite_memory_like_register_statements(stmt.else_statements, recovered)
              )
            else
              stmt
            end
          end
        end

        def rewrite_memory_like_register_reads(expr, recovered)
          return expr if expr.nil?

          if expr.is_a?(IR::Slice) && (info = recovered[expr.base.name.to_s] if expr.base.is_a?(IR::Signal))
            if slice_matches_packed_memory_slot?(expr, expr.base.name.to_s, expr.range.begin.to_i / info[:element_width].to_i, info[:element_width].to_i)
              return IR::MemoryRead.new(
                memory: expr.base.name.to_s,
                addr: IR::Literal.new(
                  value: expr.range.begin.to_i / info[:element_width].to_i,
                  width: [Math.log2(info[:depth]).ceil, 1].max
                ),
                width: info[:element_width].to_i
              )
            end
          end

          case expr
          when IR::UnaryOp
            IR::UnaryOp.new(
              op: expr.op,
              operand: rewrite_memory_like_register_reads(expr.operand, recovered),
              width: expr.width.to_i
            )
          when IR::BinaryOp
            IR::BinaryOp.new(
              op: expr.op,
              left: rewrite_memory_like_register_reads(expr.left, recovered),
              right: rewrite_memory_like_register_reads(expr.right, recovered),
              width: expr.width.to_i
            )
          when IR::Mux
            IR::Mux.new(
              condition: rewrite_memory_like_register_reads(expr.condition, recovered),
              when_true: rewrite_memory_like_register_reads(expr.when_true, recovered),
              when_false: rewrite_memory_like_register_reads(expr.when_false, recovered),
              width: expr.width.to_i
            )
          when IR::Concat
            IR::Concat.new(
              parts: Array(expr.parts).map { |part| rewrite_memory_like_register_reads(part, recovered) },
              width: expr.width.to_i
            )
          when IR::Slice
            IR::Slice.new(
              base: rewrite_memory_like_register_reads(expr.base, recovered),
              range: expr.range,
              width: expr.width.to_i
            )
          when IR::Resize
            IR::Resize.new(
              expr: rewrite_memory_like_register_reads(expr.expr, recovered),
              width: expr.width.to_i
            )
          when IR::Case
            IR::Case.new(
              selector: rewrite_memory_like_register_reads(expr.selector, recovered),
              cases: expr.cases.transform_values { |value| rewrite_memory_like_register_reads(value, recovered) },
              default: rewrite_memory_like_register_reads(expr.default, recovered),
              width: expr.width.to_i
            )
          else
            expr
          end
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
