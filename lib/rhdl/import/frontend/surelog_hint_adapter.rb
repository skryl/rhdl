# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "set"

module RHDL
  module Import
    module Frontend
      class SurelogHintAdapter
        class BackendUnavailable < StandardError
          attr_reader :backend, :command, :stderr, :exit_code, :metadata

          def initialize(message, backend:, command:, stderr:, exit_code:, metadata:)
            super(message)
            @backend = backend
            @command = command
            @stderr = stderr
            @exit_code = exit_code
            @metadata = metadata
          end
        end

        def initialize(surelog_bin: "surelog", uhdm_dump_bin: "uhdm-dump", runner: nil)
          @surelog_bin = surelog_bin
          @uhdm_dump_bin = uhdm_dump_bin
          @runner = runner || method(:default_runner)
        end

        def call(resolved_input:, work_dir:, env: {})
          expanded_work_dir = File.expand_path(work_dir)
          FileUtils.mkdir_p(expanded_work_dir)

          command = [@surelog_bin, "--version"]
          normalized_env = normalize_env(env)
          stdout, stderr, status = @runner.call(command, chdir: expanded_work_dir, env: normalized_env)
          exit_code = extract_exit_code(status)

          if !exit_code.zero?
            raise BackendUnavailable.new(
              "surelog hint backend failed (exit #{exit_code})",
              backend: "surelog",
              command: command,
              stderr: stderr.to_s,
              exit_code: exit_code,
              metadata: {
                command: command,
                stdout: stdout.to_s,
                stderr: stderr.to_s,
                resolved_input: resolved_input
              }
            )
          end

          raw_hints = extract_raw_hints(resolved_input)
          if raw_hints.empty? && !explicit_hint_input?(resolved_input)
            raw_hints = extract_raw_hints_from_surelog(
              resolved_input: resolved_input,
              work_dir: expanded_work_dir,
              env: normalized_env
            )
          end
          hints, discarded_diagnostics = normalize_hints(raw_hints)
          diagnostics = discarded_diagnostics.sort_by do |entry|
            [
              value_for(entry, :code).to_s,
              value_for(entry, :module).to_s,
              value_for(entry, :message).to_s
            ]
          end

          {
            backend: "surelog",
            available: true,
            hints: hints,
            diagnostics: diagnostics,
            summary: {
              extracted_count: raw_hints.length,
              applied_count: hints.length,
              discarded_count: diagnostics.count { |entry| value_for(entry, :code).to_s == "hint_discarded" },
              conflict_count: diagnostics.count { |entry| value_for(entry, :code).to_s == "hint_conflict" }
            }
          }
        rescue Errno::ENOENT => e
          raise BackendUnavailable.new(
            "surelog hint backend unavailable: #{e.message}",
            backend: "surelog",
            command: [@surelog_bin, "--version"],
            stderr: e.message,
            exit_code: 127,
            metadata: { resolved_input: resolved_input, work_dir: expanded_work_dir, env: env }
          )
        end

        private

        def default_runner(command, chdir:, env:)
          Open3.capture3(env, *command, chdir: chdir)
        end

        def extract_raw_hints(resolved_input)
          input = normalize_hash(resolved_input)
          inline = value_for(input, :surelog_hints)
          return Array(inline) if inline.is_a?(Array)

          path = value_for(input, :surelog_hints_path).to_s.strip
          return [] if path.empty? || !File.exist?(path)

          parsed = JSON.parse(File.read(path), symbolize_names: false)
          payload = parsed.is_a?(Hash) ? (value_for(parsed, :hints) || value_for(parsed, :surelog_hints)) : parsed
          Array(payload)
        rescue JSON::ParserError
          []
        end

        def extract_raw_hints_from_surelog(resolved_input:, work_dir:, env:)
          input = normalize_hash(resolved_input)
          source_files = array_value(input, :source_files)
          return [] if source_files.empty?

          extraction_dir = File.join(work_dir, "surelog_extract")

          FileUtils.mkdir_p(extraction_dir)
          surelog_command = build_extraction_command(
            resolved_input: input,
            source_files: source_files,
            extraction_dir: extraction_dir
          )
          stdout, stderr, status = @runner.call(surelog_command, chdir: extraction_dir, env: env)
          exit_code = extract_exit_code(status)
          unless exit_code.zero?
            raise BackendUnavailable.new(
              "surelog hint extraction failed (exit #{exit_code})",
              backend: "surelog",
              command: surelog_command,
              stderr: stderr.to_s,
              exit_code: exit_code,
              metadata: {
                command: surelog_command,
                stdout: stdout.to_s,
                stderr: stderr.to_s,
                resolved_input: resolved_input
              }
            )
          end

          uhdm_path = File.join(extraction_dir, "slpp_all", "surelog.uhdm")
          return [] unless File.exist?(uhdm_path)

          dump_command = [@uhdm_dump_bin, uhdm_path]
          dump_stdout, dump_stderr, dump_status = @runner.call(dump_command, chdir: extraction_dir, env: env)
          dump_exit_code = extract_exit_code(dump_status)
          unless dump_exit_code.zero?
            raise BackendUnavailable.new(
              "uhdm dump failed during surelog hint extraction (exit #{dump_exit_code})",
              backend: "surelog",
              command: dump_command,
              stderr: dump_stderr.to_s,
              exit_code: dump_exit_code,
              metadata: {
                command: dump_command,
                stdout: dump_stdout.to_s,
                stderr: dump_stderr.to_s,
                resolved_input: resolved_input
              }
            )
          end

          parse_uhdm_dump_hints(dump_stdout.to_s)
        rescue JSON::ParserError, Errno::ENOENT
          []
        end

        def build_extraction_command(resolved_input:, source_files:, extraction_dir:)
          command = [
            @surelog_bin,
            "-parse",
            "-sverilog",
            "-odir",
            extraction_dir
          ]
          top_modules(resolved_input).each do |module_name|
            command.concat(["--top-module", module_name])
          end
          array_value(resolved_input, :include_dirs).each { |incdir| command << "-I#{File.expand_path(incdir)}" }
          normalized_defines(value_for(resolved_input, :defines)).each { |define| command << "+define+#{define}" }
          source_files.each { |source| command << File.expand_path(source) }
          command
        end

        def top_modules(resolved_input)
          explicit = array_value(resolved_input, :top_modules)
          fallback = value_for(resolved_input, :top_module).to_s.strip
          explicit << fallback unless fallback.empty?
          explicit.uniq
        end

        def normalized_defines(defines)
          case defines
          when nil
            []
          when Hash
            defines.keys.map(&:to_s).sort.map do |name|
              value = value_for(defines, name)
              value.nil? ? name : "#{name}=#{value}"
            end
          else
            Array(defines).compact.map(&:to_s)
          end
        end

        def explicit_hint_input?(resolved_input)
          input = normalize_hash(resolved_input)
          has_key?(input, :surelog_hints) || has_key?(input, :surelog_hints_path)
        end

        def parse_uhdm_dump_hints(dump_text)
          module_stack = []
          pending_always = []
          pending_case = []
          always_candidates = []
          case_candidates = []

          Array(dump_text.to_s.lines).each do |line|
            indent = leading_spaces(line)

            while module_stack.any? && indent <= module_stack.last[:indent]
              module_stack.pop
            end
            while pending_always.any? && indent <= pending_always.last[:indent]
              always_candidates << pending_always.pop
            end
            while pending_case.any? && indent <= pending_case.last[:indent]
              case_candidates << pending_case.pop
            end

            module_data = parse_module_inst_line(line)
            if module_data
              module_name =
                module_name_from_module_inst_tokens(
                  primary_token: module_data[:primary_token],
                  paren_token: module_data[:paren_token]
                )
              module_stack << {
                indent: indent,
                module: module_name,
                source_path: module_data[:source_path]
              }
              next
            end

            current_module = module_stack.last
            next unless current_module

            always_match = line.match(/_always:.*line:(\d+):(\d+)/)
            if always_match
              pending_always << {
                indent: indent,
                module: current_module[:module],
                source_path: current_module[:source_path],
                line: Integer(always_match[1]),
                column: Integer(always_match[2]),
                always_type: nil
              }
              next
            end

            always_type_match = line.match(/\|vpiAlwaysType:(\d+)/)
            if always_type_match && pending_always.any?
              pending_always.last[:always_type] = Integer(always_type_match[1])
              next
            end

            case_match = line.match(/_case_stmt:.*line:(\d+):(\d+)/)
            if case_match
              pending_case << {
                indent: indent,
                module: current_module[:module],
                source_path: current_module[:source_path],
                line: Integer(case_match[1]),
                column: Integer(case_match[2]),
                qualifier: nil
              }
              next
            end

            qualifier_match = line.match(/\|vpiQualifier:(\d+)/)
            if qualifier_match && pending_case.any?
              pending_case.last[:qualifier] = Integer(qualifier_match[1])
            end
          end

          always_candidates.concat(pending_always)
          case_candidates.concat(pending_case)

          always_hints_from_candidates(always_candidates) +
            case_hints_from_candidates(case_candidates)
        end

        def always_hints_from_candidates(candidates)
          grouped = Array(candidates)
            .select { |entry| present_string?(entry[:module]) && present_string?(entry[:source_path]) }
            .group_by { |entry| [entry[:module], entry[:source_path], entry[:line], entry[:column]] }

          deduped = grouped.values
            .map { |entries| entries.max_by { |entry| always_type_rank(entry[:always_type]) } }
            .sort_by { |entry| [entry[:module], entry[:source_path], entry[:line], entry[:column]] }

          process_index_by_module = Hash.new(0)
          deduped.map do |entry|
            module_name = entry[:module].to_s
            process_index = process_index_by_module[module_name]
            process_index_by_module[module_name] += 1

            {
              module: module_name,
              construct_family: "process",
              construct_kind: always_construct_kind(entry[:always_type]),
              confidence: "high",
              span: {
                source_path: entry[:source_path],
                line: entry[:line],
                column: entry[:column]
              },
              data: {
                process_index: process_index
              }
            }
          end
        end

        def case_hints_from_candidates(candidates)
          Array(candidates)
            .select { |entry| present_string?(entry[:module]) && present_string?(entry[:source_path]) }
            .map do |entry|
              construct_kind = case_qualifier_construct_kind(entry[:qualifier])
              next if construct_kind.nil?

              {
                module: entry[:module].to_s,
                construct_family: "statement",
                construct_kind: construct_kind,
                confidence: "medium",
                span: {
                  source_path: entry[:source_path],
                  line: entry[:line],
                  column: entry[:column]
                }
              }
            end
            .compact
            .uniq { |entry| [entry[:module], value_for(entry[:span], :source_path), value_for(entry[:span], :line), value_for(entry[:span], :column), entry[:construct_kind]] }
            .sort_by { |entry| [entry[:module], value_for(entry[:span], :source_path), value_for(entry[:span], :line), value_for(entry[:span], :column), entry[:construct_kind]] }
        end

        def always_construct_kind(always_type)
          case Integer(always_type)
          when 2
            "always_comb"
          when 3
            "always_ff"
          when 4
            "always_latch"
          else
            "always"
          end
        rescue ArgumentError, TypeError
          "always"
        end

        def always_type_rank(always_type)
          case Integer(always_type)
          when 2, 3, 4
            2
          when 1
            1
          else
            0
          end
        rescue ArgumentError, TypeError
          0
        end

        def case_qualifier_construct_kind(qualifier)
          case Integer(qualifier)
          when 1
            "case_unique"
          when 2
            "case_priority"
          else
            nil
          end
        rescue ArgumentError, TypeError
          nil
        end

        def leading_spaces(value)
          value.to_s[/\A */].to_s.length
        end

        def present_string?(value)
          !value.to_s.strip.empty?
        end

        def module_name_from_module_inst_tokens(primary_token:, paren_token:)
          primary = canonical_module_token(primary_token)
          paren = canonical_module_token(paren_token)

          raw_primary = primary_token.to_s
          raw_paren = paren_token.to_s

          return primary if raw_primary.include?("::")
          return paren if present_string?(paren) && !raw_paren.include?(".")
          return primary if present_string?(primary)

          paren
        end

        def parse_module_inst_line(line)
          match =
            line.match(
              /_module_inst:\s+([^\s,()]+)\s+\(([^)]+)\),\s+file:([^,]+),\s+line:(\d+):(\d+)/
            )
          if match
            return {
              primary_token: match[1],
              paren_token: match[2],
              source_path: match[3].to_s.strip
            }
          end

          match = line.match(/_module_inst:\s+\(([^)]+)\),\s+file:([^,]+),\s+line:(\d+):(\d+)/)
          if match
            return {
              primary_token: nil,
              paren_token: match[1],
              source_path: match[2].to_s.strip
            }
          end

          match = line.match(/_module_inst:\s+([^\s,()]+),\s+file:([^,]+),\s+line:(\d+):(\d+)/)
          return nil unless match

          {
            primary_token: match[1],
            paren_token: nil,
            source_path: match[2].to_s.strip
          }
        end

        def canonical_module_token(token)
          text = token.to_s.strip
          return "" if text.empty?

          text = text.sub(/\A[^@]*@/, "")
          text = text.split("::").last.to_s
          text = text.split(".").last.to_s
          text.strip
        end

        def normalize_hints(raw_hints)
          seen = Set.new
          diagnostics = []
          normalized = Array(raw_hints).filter_map do |entry|
            hint = normalize_hint_entry(entry)
            if hint.nil?
              diagnostics << {
                severity: "warning",
                code: "hint_discarded",
                message: "discarded invalid hint entry"
              }
              next
            end

            key = JSON.generate(hint)
            next if seen.include?(key)

            seen << key
            hint
          end

          [sort_hints(normalized), diagnostics]
        end

        def sort_hints(hints)
          Array(hints).sort_by do |entry|
            span = normalize_hash(value_for(entry, :span))
            [
              value_for(entry, :module).to_s,
              value_for(span, :source_path).to_s,
              integer_or_default(value_for(span, :line), 0),
              integer_or_default(value_for(span, :column), 0),
              integer_or_default(value_for(span, :end_line), 0),
              integer_or_default(value_for(span, :end_column), 0),
              value_for(entry, :construct_family).to_s,
              value_for(entry, :construct_kind).to_s,
              value_for(entry, :confidence).to_s
            ]
          end
        end

        def normalize_hint_entry(entry)
          hash = normalize_hash(entry)
          module_name = value_for(hash, :module) || value_for(hash, :module_name)
          construct_family = value_for(hash, :construct_family) || value_for(hash, :family)
          construct_kind = value_for(hash, :construct_kind) || value_for(hash, :kind) || value_for(hash, :construct)

          module_name = module_name.to_s.strip
          construct_family = construct_family.to_s.strip
          construct_kind = construct_kind.to_s.strip
          return nil if module_name.empty? || construct_family.empty? || construct_kind.empty?

          {
            module: module_name,
            construct_family: construct_family,
            construct_kind: construct_kind,
            confidence: normalize_confidence(value_for(hash, :confidence)),
            span: normalize_span(value_for(hash, :span), hash),
            data: normalize_data(value_for(hash, :data))
          }.compact
        end

        def normalize_confidence(value)
          normalized = value.to_s.strip.downcase
          return normalized if %w[high medium low].include?(normalized)

          "medium"
        end

        def normalize_span(span, fallback_hash)
          hash = normalize_hash(span)
          hash = fallback_hash if hash.empty?

          source_path = value_for(hash, :source_path) || value_for(hash, :path) || value_for(hash, :file)
          line = integer_or_default(value_for(hash, :line), nil)
          column = integer_or_default(value_for(hash, :column), nil)
          end_line = integer_or_default(value_for(hash, :end_line), nil)
          end_column = integer_or_default(value_for(hash, :end_column), nil)

          normalized = {
            source_path: source_path&.to_s,
            line: line,
            column: column,
            end_line: end_line,
            end_column: end_column
          }.compact

          normalized.empty? ? nil : normalized
        end

        def normalize_data(value)
          case value
          when Hash
            value.keys.map(&:to_s).sort.each_with_object({}) do |key, memo|
              memo[key.to_sym] = normalize_data(value_for(value, key))
            end
          when Array
            value.map { |inner| normalize_data(inner) }
          when String, Numeric, TrueClass, FalseClass, NilClass
            value
          else
            value.to_s
          end
        end

        def extract_exit_code(status)
          return status if status.is_a?(Integer)
          return status.exitstatus if status.respond_to?(:exitstatus)

          1
        end

        def normalize_hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def normalize_env(env)
          hash = normalize_hash(env)
          hash.each_with_object({}) do |(key, value), memo|
            next if key.nil?

            memo[key.to_s] = value.to_s
          end
        end

        def array_value(hash, key)
          Array(value_for(hash, key)).compact.map(&:to_s)
        end

        def has_key?(hash, key)
          return false unless hash.is_a?(Hash)

          hash.key?(key) || hash.key?(key.to_s) || hash.key?(key.to_sym)
        end

        def integer_or_default(value, default)
          Integer(value)
        rescue ArgumentError, TypeError
          default
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
      end
    end
  end
end
