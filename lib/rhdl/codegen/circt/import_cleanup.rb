# frozen_string_literal: true

require_relative '../../codegen'
require_relative 'mlir'

module RHDL
  module Codegen
    module CIRCT
      module ImportCleanup
        module_function

        CleanupResult = Struct.new(:success, :cleaned_text, :import_result, keyword_init: true) do
          def success?
            !!success
          end
        end

        # Normalize imported CIRCT MLIR into pure core dialects by parsing it
        # through the existing CIRCT importer and re-emitting structural MLIR.
        # This strips surviving LLHD signal/time overlays from circt-verilog
        # imports before downstream tools such as firtool consume the artifact.
        def parse_imported_core_mlir(text, strict: true, top: nil, extern_modules: [], resolve_forward_refs: false)
          RHDL::Codegen.import_circt_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            resolve_forward_refs: resolve_forward_refs
          )
        end

        def emit_cleaned_core_mlir(modules)
          RHDL::Codegen::CIRCT::MLIR.generate(modules)
        end

        def cleanup_imported_core_mlir(text, strict: true, top: nil, extern_modules: [])
          needs_cleanup = cleanup_markers?(text)
          return success_result(text) unless needs_cleanup

          package = split_top_level_package(text)
          return cleanup_whole_text(text, strict: strict, top: top, extern_modules: extern_modules) unless package

          wrapped = package.fetch(:wrapped)
          entries = package.fetch(:entries)
          module_names = entries.filter_map { |entry| module_name_for_entry(entry) }
          diagnostics = []
          cleaned_entries = entries.map do |entry|
            unless cleanup_markers?(entry)
              next normalize_entry_text(entry)
            end

            entry_name = module_name_for_entry(entry)
            entry_externs = Array(extern_modules).map(&:to_s) | (module_names - Array(entry_name))
            import_result = parse_imported_core_mlir(
              entry,
              strict: strict,
              top: entry_name || top,
              extern_modules: entry_externs,
              resolve_forward_refs: true
            )
            return failure_result(import_result.diagnostics) unless import_result.success?

            diagnostics.concat(Array(import_result.diagnostics))
            normalize_entry_text(emit_cleaned_core_mlir(import_result.modules))
          end

          cleaned_text = rebuild_top_level_package(entries: cleaned_entries, wrapped: wrapped)

          CleanupResult.new(
            success: !cleaned_text.to_s.include?('llhd.'),
            cleaned_text: cleaned_text,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: diagnostics)
          )
        end

        def success_result(text)
          CleanupResult.new(
            success: true,
            cleaned_text: text,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: [])
          )
        end

        def failure_result(diagnostics)
          CleanupResult.new(
            success: false,
            cleaned_text: nil,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: diagnostics)
          )
        end

        def cleanup_markers?(text)
          text.include?('llhd.')
        end

        def cleanup_whole_text(text, strict:, top:, extern_modules:)
          import_result = parse_imported_core_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            resolve_forward_refs: true
          )
          return failure_result(import_result.diagnostics) unless import_result.success?

          cleaned_text = emit_cleaned_core_mlir(import_result.modules)
          CleanupResult.new(
            success: !cleaned_text.to_s.include?('llhd.'),
            cleaned_text: cleaned_text,
            import_result: import_result
          )
        end

        def split_top_level_package(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          lines = if wrapped_package_text?(text)
                    unwrap_builtin_module_lines(text)
                  else
                    text.lines
                  end
          entries = split_top_level_entries(lines)
          return nil if entries.empty?

          {
            wrapped: wrapped_package_text?(text),
            entries: entries
          }
        end

        def wrapped_package_text?(text)
          significant = text.to_s.lines.map(&:strip).reject(&:empty?)
          significant.length >= 2 &&
            significant.first == 'module {' &&
            significant.last == '}'
        end

        def unwrap_builtin_module_lines(text)
          lines = text.lines
          first = lines.index { |line| !line.strip.empty? }
          last = lines.rindex { |line| !line.strip.empty? }
          return [] unless first && last
          return [] if lines[first].strip != 'module {'
          return [] if lines[last].strip != '}'

          lines[(first + 1)...last] || []
        end

        def split_top_level_entries(lines)
          entries = []
          current = []
          depth = 0

          Array(lines).each do |line|
            next if current.empty? && line.strip.empty?

            current << line
            depth += brace_delta(line)
            next unless depth <= 0

            entries << current.join
            current = []
            depth = 0
          end

          entries << current.join unless current.empty?
          entries.reject { |entry| entry.to_s.strip.empty? }
        end

        def brace_delta(line)
          delta = 0
          in_string = false
          escape = false

          line.to_s.each_char do |char|
            if in_string
              if escape
                escape = false
              elsif char == '\\'
                escape = true
              elsif char == '"'
                in_string = false
              end
              next
            end

            if char == '"'
              in_string = true
            elsif char == '{'
              delta += 1
            elsif char == '}'
              delta -= 1
            end
          end

          delta
        end

        def module_name_for_entry(entry)
          entry.to_s[/^\s*(?:hw|sv)\.module(?:\s+\w+)*\s+@([A-Za-z_$][A-Za-z0-9_$.]*)/, 1]
        end

        def normalize_entry_text(entry)
          entry.to_s.strip
        end

        def rebuild_top_level_package(entries:, wrapped:)
          body = Array(entries).map { |entry| normalize_entry_text(entry) }.reject(&:empty?)
          return "#{body.join("\n\n")}\n" unless wrapped

          indented = body.map do |entry|
            entry.lines.map { |line| line.strip.empty? ? line : "  #{line}" }.join
          end
          "module {\n#{indented.join("\n\n")}\n}\n"
        end

      end
    end
  end
end
