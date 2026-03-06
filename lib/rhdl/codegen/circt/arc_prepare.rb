# frozen_string_literal: true

module RHDL
  module Codegen
    module CIRCT
      module ArcPrepare
        module_function

        def transform_normalized_llhd(text)
          modules = extract_hw_modules(text)
          return empty_transform_result(text) if modules.empty?

          transformed_modules = []
          unsupported_modules = []
          rendered_modules = modules.map do |mod_text|
            result = transform_module(mod_text)
            transformed_modules << result.fetch(:module_name) if result[:transformed]
            unsupported_modules << result.fetch(:unsupported) if result[:unsupported]
            result.fetch(:text)
          end

          {
            success: unsupported_modules.empty?,
            output_text: wrap_modules(rendered_modules),
            transformed_modules: transformed_modules,
            unsupported_modules: unsupported_modules
          }
        end

        def extract_hw_modules(text)
          lines = text.to_s.lines
          modules = []
          idx = 0
          while idx < lines.length
            unless lines[idx].lstrip.start_with?('hw.module ')
              idx += 1
              next
            end

            start_idx = idx
            depth = brace_delta(lines[idx])
            idx += 1
            while idx < lines.length && depth.positive?
              depth += brace_delta(lines[idx])
              idx += 1
            end

            modules << lines[start_idx...idx].join
          end
          modules
        end

        def wrap_modules(modules)
          rendered = +"module {\n"
          modules.each do |mod_text|
            rendered << mod_text
            rendered << "\n" unless mod_text.end_with?("\n")
          end
          rendered << "}\n"
          rendered
        end

        def transform_module(mod_text)
          module_name = module_name_from_text(mod_text)
          return { text: mod_text, module_name: module_name, transformed: false } unless mod_text.include?('llhd.')

          lowered = lower_simple_edge_register_module(mod_text)
          return { text: lowered, module_name: module_name, transformed: true } if lowered

          {
            text: mod_text,
            module_name: module_name,
            transformed: false,
            unsupported: {
              'module' => module_name,
              'reason' => 'unsupported normalized LLHD process shape'
            }
          }
        end

        def lower_simple_edge_register_module(mod_text)
          lines = mod_text.lines
          return nil unless lines.count { |line| code_for(line) == 'llhd.process {' } == 1
          return nil if lines.any? { |line| code_for(line).start_with?('llhd.combinational') }

          header_line = lines.find { |line| line.lstrip.start_with?('hw.module ') }
          return nil unless header_line

          output_line = lines.find { |line| code_for(line).start_with?('hw.output ') }
          return nil unless output_line
          output_match = code_for(output_line).match(/\Ahw\.output\s+(%[A-Za-z0-9_$.\\-]+)\s*:\s*([A-Za-z0-9_!<>,.]+)\z/)
          return nil unless output_match

          output_probe = output_match[1]
          output_type = output_match[2]
          output_probe_match = lines.find { |line| code_for(line).include?("#{output_probe} = llhd.prb ") }&.then { |line| code_for(line) }&.match(
            /\A(#{Regexp.escape(output_probe)})\s*=\s*llhd\.prb\s+(%[A-Za-z0-9_$.\\-]+)\s*:\s*([A-Za-z0-9_!<>,.]+)\z/
          )
          return nil unless output_probe_match

          reg_signal = output_probe_match[2]
          signal_to_port = extract_signal_to_port_map(lines)
          process_lines = extract_first_process(lines)
          return nil unless process_lines

          drive_idx = process_lines.index do |line|
            code_for(line).match?(/\Allhd\.drv\s+#{Regexp.escape(reg_signal)}\s*,\s+%[A-Za-z0-9_$.\\-]+\s+after\s+%[A-Za-z0-9_$.\\-]+\s+if\s+%[A-Za-z0-9_$.\\-]+\s*:\s*#{Regexp.escape(output_type)}\z/)
          end
          return nil unless drive_idx

          drive_match = code_for(process_lines[drive_idx]).match(
            /\Allhd\.drv\s+#{Regexp.escape(reg_signal)}\s*,\s+(%[A-Za-z0-9_$.\\-]+)\s+after\s+(%[A-Za-z0-9_$.\\-]+)\s+if\s+(%[A-Za-z0-9_$.\\-]+)\s*:\s*(#{Regexp.escape(output_type)})\z/
          )
          return nil unless drive_match

          data_arg = drive_match[1]
          pred_arg = drive_match[3]

          block_label_line = process_lines[0..drive_idx].reverse.find { |line| code_for(line).start_with?('^bb') }
          return nil unless block_label_line
          block_label_match = code_for(block_label_line).match(/\A(\^bb\d+)\(([^)]*)\):\z/)
          return nil unless block_label_match

          block_label = block_label_match[1]
          block_args = parse_block_args(block_label_match[2])
          data_index = block_args.index(data_arg)
          pred_index = block_args.index(pred_arg)
          return nil unless data_index && pred_index

          cond_br_line = process_lines.find do |line|
            code_for(line).start_with?('cf.cond_br ') &&
              code_for(line).include?("#{block_label}(") &&
              code_for(line).scan(block_label).length >= 2
          end
          return nil unless cond_br_line

          cond_match = code_for(cond_br_line).match(
            /\Acf\.cond_br\s+%[A-Za-z0-9_$.\\-]+,\s*#{Regexp.escape(block_label)}\(([^:]+)\s*:\s*[^)]*\),\s*#{Regexp.escape(block_label)}\(([^:]+)\s*:\s*[^)]*\)\z/
          )
          return nil unless cond_match

          true_args = cond_match[1].split(',').map(&:strip)
          false_args = cond_match[2].split(',').map(&:strip)
          return nil unless true_args.length == block_args.length && false_args.length == block_args.length

          next_value_token = true_args[data_index]
          return nil if next_value_token == data_arg

          next_value_match = process_lines.find { |line| code_for(line).include?("#{next_value_token} = llhd.prb ") }&.then { |line| code_for(line) }&.match(
            /\A#{Regexp.escape(next_value_token)}\s*=\s*llhd\.prb\s+(%[A-Za-z0-9_$.\\-]+)\s*:\s*(#{Regexp.escape(output_type)})\z/
          )
          return nil unless next_value_match

          data_signal = next_value_match[1]
          data_port = signal_to_port[data_signal]
          return nil unless data_port

          wait_line = process_lines.find { |line| code_for(line).start_with?('llhd.wait (') }
          return nil unless wait_line
          wait_match = code_for(wait_line).match(/\Allhd\.wait\s+\((%[A-Za-z0-9_$.\\-]+)\s*:\s*i1\)\s*,/)
          return nil unless wait_match

          wait_probe = wait_match[1]
          wait_probe_match = lines.find { |line| code_for(line).include?("#{wait_probe} = llhd.prb ") }&.then { |line| code_for(line) }&.match(
            /\A#{Regexp.escape(wait_probe)}\s*=\s*llhd\.prb\s+(%[A-Za-z0-9_$.\\-]+)\s*:\s*i1\z/
          )
          return nil unless wait_probe_match

          clock_signal = wait_probe_match[1]
          clock_port = signal_to_port[clock_signal]
          return nil unless clock_port

          module_indent = header_line[/\A\s*/] || ''
          body_indent = "#{module_indent}  "
          clock_value = "%#{sanitize_token(clock_port)}_clock"
          reg_value = "%#{sanitize_token(reg_signal)}_reg"

          [
            header_line,
            "#{body_indent}#{clock_value} = seq.to_clock #{clock_port}\n",
            "#{body_indent}#{reg_value} = seq.compreg #{data_port}, #{clock_value} : #{output_type}\n",
            "#{body_indent}hw.output #{reg_value} : #{output_type}\n",
            "#{module_indent}}\n"
          ].join
        end

        def extract_first_process(lines)
          start_idx = lines.index { |line| code_for(line) == 'llhd.process {' }
          return nil unless start_idx

          idx = start_idx
          depth = brace_delta(lines[idx])
          idx += 1
          while idx < lines.length && depth.positive?
            depth += brace_delta(lines[idx])
            idx += 1
          end
          lines[start_idx...idx]
        end

        def extract_signal_to_port_map(lines)
          lines.each_with_object({}) do |line, acc|
            match = code_for(line).match(
              /\Allhd\.drv\s+(%[A-Za-z0-9_$.\\-]+)\s*,\s+(%[A-Za-z0-9_$.\\-]+)\s+after\s+%[A-Za-z0-9_$.\\-]+\s*:\s*([A-Za-z0-9_!<>,.]+)\z/
            )
            next unless match

            acc[match[1]] = match[2]
          end
        end

        def parse_block_args(arg_string)
          arg_string.split(',').map do |entry|
            token = entry.strip.split(':').first.to_s.strip
            token unless token.empty?
          end.compact
        end

        def module_name_from_text(mod_text)
          mod_text[/hw\.module(?:\s+\w+)*\s+@([^\(\s]+)/, 1] || '<unknown>'
        end

        def brace_delta(line)
          line.count('{') - line.count('}')
        end

        def sanitize_token(token)
          token.to_s.delete_prefix('%').gsub(/[^A-Za-z0-9_]/, '_')
        end

        def code_for(line)
          line.to_s.sub(%r{//.*$}, '').strip
        end

        def empty_transform_result(text)
          {
            success: true,
            output_text: text,
            transformed_modules: [],
            unsupported_modules: []
          }
        end
      end
    end
  end
end
